#define _DEFAULT_SOURCE
#define GDK_WINDOWING_X11

#include <gtk/gtk.h>
#include <gtk/gtkx.h>
#include <gdk/gdkx.h>

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XInput2.h>

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_WRAPPER_WIDTH 720
#define DEFAULT_WRAPPER_HEIGHT 600
#define DEFAULT_SCROLL_STEP 50
#define MIN_WRAPPER_SIZE 320
#define MIN_SCROLL_STEP 1
#define MAX_SCROLL_STEP 1000
#define MAX_WRAPPER_SIZE 16384
/* The launcher replaces this internal status with scrcpy's exact status. */
#define SCRCPY_EXIT_REPORT_STATUS 125

static Display *dpy;
static GdkDisplay *gdk_display;
static Window foreign_window = None;
static GtkWidget *window_widget;
static GtkWidget *scrolled_window_widget;
static GtkWidget *viewport_widget;
static GtkWidget *socket_widget;
static GtkAdjustment *horizontal_adjustment;
static GtkAdjustment *vertical_adjustment;

static int wrapper_width = DEFAULT_WRAPPER_WIDTH;
static int wrapper_height = DEFAULT_WRAPPER_HEIGHT;
static int foreign_width;
static int foreign_height;
static int scroll_step = DEFAULT_SCROLL_STEP;

static bool child_embedded;
static bool child_destroyed;
static bool wrapper_destroyed;
static bool wrapper_close_requested;
static bool wrapper_destroy_intentional;
static bool wrapper_error;
static bool main_loop_running;
static bool scrcpy_exited;

static pid_t scrcpy_pid;
static int scrcpy_pidfd = -1;
static unsigned long long expected_scrcpy_start_time;
static unsigned long long scrcpy_start_time;
static bool scrcpy_identity_captured;
static pid_t launcher_pid = -1;
static volatile sig_atomic_t running = 1;
static volatile sig_atomic_t caught_signal = 0;

static void handle_signal(int signal_number) {
	caught_signal = signal_number;
	running = 0;
}

static void install_signal_handlers(void) {
	struct sigaction action;

	memset(&action, 0, sizeof(action));
	action.sa_handler = handle_signal;
	sigemptyset(&action.sa_mask);

	sigaction(SIGINT, &action, NULL);
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGHUP, &action, NULL);
}

static void usage(const char *program) {
	fprintf(stderr,
		"Usage: %s <window-id> <scrcpy-pid> <start-time> "
		"[width] [height] [step]\n"
		"       %s --watch-parent <launcher-pid> <scrcpy-pid> <start-time>\n",
		program,
		program);
}

#ifdef __linux__
static void set_process_name(const char *name) {
	(void) prctl(PR_SET_NAME, name, 0L, 0L, 0L);
}
#else
static void set_process_name(const char *name) {
	(void) name;
}
#endif

static bool parse_window_id(const char *text, Window *window) {
	char *end = NULL;
	unsigned long long value;

	if (text[0] == '\0' || text[0] == '-' || text[0] == '+'
			|| isspace((unsigned char) text[0])) {
		return false;
	}

	errno = 0;
	value = strtoull(text, &end, 0);
	if (errno == ERANGE || end == text || *end != '\0' || value == 0
			|| value > UINT32_MAX) {
		return false;
	}

	*window = (Window) value;
	return true;
}

static bool parse_pid(const char *text, pid_t *pid) {
	char *end = NULL;
	long value;

	errno = 0;
	value = strtol(text, &end, 10);
	if (errno == ERANGE || end == text || *end != '\0' || value <= 0
			|| value > INT32_MAX) {
		return false;
	}

	*pid = (pid_t) value;
	return true;
}

static bool parse_start_time(const char *text, unsigned long long *value) {
	char *end = NULL;
	unsigned long long parsed;
	const char *cursor;

	if (text[0] == '\0') {
		return false;
	}
	for (cursor = text; *cursor != '\0'; cursor++) {
		if (!isdigit((unsigned char) *cursor)) {
			return false;
		}
	}

	errno = 0;
	parsed = strtoull(text, &end, 10);
	if (errno == ERANGE || end == text || *end != '\0') {
		return false;
	}

	*value = parsed;
	return true;
}

static bool parse_positive_int(const char *text, int minimum, int maximum,
		int *value) {
	char *end = NULL;
	long parsed;

	errno = 0;
	parsed = strtol(text, &end, 10);
	if (errno == ERANGE || end == text || *end != '\0' || parsed < minimum
			|| parsed > maximum) {
		return false;
	}

	*value = (int) parsed;
	return true;
}

static bool read_process_identity(pid_t pid, char *state,
		unsigned long long *start_time) {
	char path[64];
	char status_line[1024];
	char *closing_parenthesis;
	char *cursor;
	char *token;
	unsigned int field;
	FILE *status_file;

	snprintf(path, sizeof(path), "/proc/%ld/stat", (long) pid);
	status_file = fopen(path, "r");
	if (!status_file) {
		return false;
	}

	if (!fgets(status_line, sizeof(status_line), status_file)) {
		fclose(status_file);
		return false;
	}
	fclose(status_file);

	closing_parenthesis = strrchr(status_line, ')');
	if (!closing_parenthesis || closing_parenthesis[1] != ' ') {
		return false;
	}

	cursor = closing_parenthesis + 2;
	for (field = 3; field <= 22; field++) {
		while (*cursor == ' ') {
			cursor++;
		}

		token = cursor;
		while (*cursor != '\0' && *cursor != ' ') {
			cursor++;
		}

		if (field == 3) {
			*state = token[0];
		} else if (field == 22) {
			char *end = NULL;

			errno = 0;
			*start_time = strtoull(token, &end, 10);
			if (errno == ERANGE || end == token
					|| (*end != '\0' && *end != ' ' && *end != '\n')) {
				return false;
			}
		}
	}

	return *state != '\0';
}

static bool capture_scrcpy_identity(void) {
#ifdef SYS_pidfd_open
	{
		int pidfd = (int) syscall(SYS_pidfd_open, scrcpy_pid, 0U);

		if (pidfd >= 0) {
			char state = '\0';
			unsigned long long start_time = 0;

			/* The pidfd pins the exact process selected above. */
			scrcpy_pidfd = pidfd;
			if (!read_process_identity(scrcpy_pid, &state, &start_time)
					|| state == 'Z' || state == 'X'
					|| start_time != expected_scrcpy_start_time) {
				close(scrcpy_pidfd);
				scrcpy_pidfd = -1;
				return false;
			}

			scrcpy_start_time = start_time;
			scrcpy_identity_captured = true;
			return true;
		}

		if (errno == ESRCH) {
			return false;
		}
	}
#endif

	{
		char state = '\0';
		unsigned long long start_time = 0;

		if (!read_process_identity(scrcpy_pid, &state, &start_time)
				|| state == 'Z' || state == 'X'
				|| start_time != expected_scrcpy_start_time) {
			return false;
		}

		scrcpy_start_time = start_time;
		scrcpy_identity_captured = true;
		return true;
	}
}

static bool scrcpy_identity_matches(void) {
	char state = '\0';
	unsigned long long start_time = 0;

	if (!scrcpy_identity_captured
			|| !read_process_identity(scrcpy_pid, &state, &start_time)) {
		return false;
	}

	return state != 'Z' && state != 'X'
			&& start_time == scrcpy_start_time;
}

static bool scrcpy_is_running(void) {
	if (scrcpy_pidfd >= 0) {
		struct pollfd pidfd_poll = {
			.fd = scrcpy_pidfd,
			.events = POLLIN,
		};
		int poll_result;

		do {
			poll_result = poll(&pidfd_poll, 1, 0);
		} while (poll_result < 0 && errno == EINTR);

		if (poll_result == 0) {
			return true;
		}
		if (poll_result > 0) {
			return false;
		}

		/* A transient poll failure must not be treated as process exit. */
		return true;
	}

	return scrcpy_identity_matches();
}

static int signal_scrcpy(int signal_number) {
	if (scrcpy_pidfd >= 0) {
#ifdef SYS_pidfd_send_signal
		int signal_result;

		do {
			signal_result = (int) syscall(SYS_pidfd_send_signal,
					scrcpy_pidfd, signal_number, NULL, 0U);
		} while (signal_result < 0 && errno == EINTR);

		if (signal_result == 0) {
			return 0;
		}
		if (errno == ESRCH) {
			return 1;
		}

		return -1;
#else
		errno = ENOSYS;
		return -1;
#endif
	}

	if (!scrcpy_identity_matches()) {
		return 1;
	}

	if (kill(scrcpy_pid, signal_number) == 0) {
		return 0;
	}

	return errno == ESRCH ? 1 : -1;
}

static bool wait_for_process_to_exit(int attempts) {
	struct timespec delay = {
		.tv_sec = 0,
		.tv_nsec = 20000000,
	};

	while (attempts-- > 0) {
		if (!scrcpy_is_running()) {
			return true;
		}

		nanosleep(&delay, NULL);
	}

	return !scrcpy_is_running();
}

static bool stop_scrcpy(void) {
	int signal_result;

	if (!scrcpy_is_running()) {
		return true;
	}

	signal_result = signal_scrcpy(SIGTERM);
	if (signal_result < 0) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not stop scrcpy process %ld: %s\n",
			(long) scrcpy_pid,
			strerror(errno));
		return false;
	}
	if (signal_result > 0 || wait_for_process_to_exit(100)) {
		return true;
	}

	signal_result = signal_scrcpy(SIGKILL);
	if (signal_result < 0) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not force scrcpy process %ld to stop: %s\n",
			(long) scrcpy_pid,
			strerror(errno));
		return false;
	}

	if (!wait_for_process_to_exit(50)) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] scrcpy process %ld did not stop after SIGKILL\n",
			(long) scrcpy_pid);
		return false;
	}

	return true;
}

static bool window_belongs_to_process(Window window, pid_t expected_pid) {
	Atom net_wm_pid;
	Atom actual_type = None;
	int actual_format = 0;
	unsigned long item_count = 0;
	unsigned long bytes_after = 0;
	unsigned char *property = NULL;
	pid_t actual_pid;
	int error;
	bool success = false;

	net_wm_pid = XInternAtom(dpy, "_NET_WM_PID", False);
	gdk_x11_display_error_trap_push(gdk_display);
	if (XGetWindowProperty(dpy, window, net_wm_pid, 0, 1, False,
			XA_CARDINAL, &actual_type, &actual_format, &item_count,
			&bytes_after, &property) != Success) {
		gdk_x11_display_error_trap_pop_ignored(gdk_display);
		return false;
	}
	XSync(dpy, False);
	error = gdk_x11_display_error_trap_pop(gdk_display);

	if (property && actual_type == XA_CARDINAL && actual_format == 32
			&& item_count == 1 && bytes_after == 0) {
		actual_pid = (pid_t) ((const unsigned long *) property)[0];
		success = actual_pid == expected_pid;
	} else if (error != 0) {
		success = false;
	}

	if (property) {
		XFree(property);
	}

	return success;
}

static bool target_window_matches_scrcpy(void) {
	if (!window_belongs_to_process(foreign_window, scrcpy_pid)) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] target window does not belong to scrcpy process %ld\n",
			(long) scrcpy_pid);
		return false;
	}
	if (!scrcpy_is_running()) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] scrcpy process %ld exited before wrapping its window\n",
			(long) scrcpy_pid);
		return false;
	}

	return true;
}

static bool query_geometry(Window window, int *width, int *height) {
	Window geometry_root;
	int geometry_x;
	int geometry_y;
	unsigned int geometry_width;
	unsigned int geometry_height;
	unsigned int border_width;
	unsigned int depth;
	int error;
	bool success;

	gdk_x11_display_error_trap_push(gdk_display);
	success = XGetGeometry(dpy, window, &geometry_root, &geometry_x, &geometry_y,
			&geometry_width, &geometry_height, &border_width, &depth) != 0;
	XSync(dpy, False);
	error = gdk_x11_display_error_trap_pop(gdk_display);

	if (!success || error != 0 || geometry_width > INT_MAX
			|| geometry_height > INT_MAX) {
		return false;
	}

	*width = (int) geometry_width;
	*height = (int) geometry_height;
	return true;
}

static void update_socket_size(void) {
	gtk_widget_set_size_request(socket_widget, foreign_width, foreign_height);
	gtk_widget_queue_resize(socket_widget);
	gtk_widget_queue_resize(scrolled_window_widget);
}

static bool select_xi_button_events(void) {
	unsigned char event_mask_bytes[XIMaskLen(XI_LASTEVENT)] = { 0 };
	XIEventMask event_mask;
	int status;
	int error;

	XISetMask(event_mask_bytes, XI_ButtonPress);
	event_mask.deviceid = XIAllMasterDevices;
	event_mask.mask_len = (int) sizeof(event_mask_bytes);
	event_mask.mask = event_mask_bytes;

	gdk_x11_display_error_trap_push(gdk_display);
	status = XISelectEvents(dpy, foreign_window, &event_mask, 1);
	XSync(dpy, False);
	error = gdk_x11_display_error_trap_pop(gdk_display);

	if (status != Success || error != 0) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not select XInput2 button events\n");
		return false;
	}

	return true;
}

static void scroll_adjustment(GtkAdjustment *adjustment, double delta) {
	double value = gtk_adjustment_get_value(adjustment);

	gtk_adjustment_set_value(adjustment, value + delta);
}

static bool pointer_is_over_visible_foreign(double root_x, double root_y) {
	GtkAllocation allocation;
	GdkWindow *toplevel_window;
	int origin_x;
	int origin_y;
	int viewport_x;
	int viewport_y;

	gtk_widget_get_allocation(viewport_widget, &allocation);
	if (!gtk_widget_translate_coordinates(viewport_widget,
				window_widget, 0, 0, &viewport_x, &viewport_y)) {
		return false;
	}

	toplevel_window = gtk_widget_get_window(window_widget);
	if (!toplevel_window
			|| !gdk_window_get_origin(toplevel_window, &origin_x, &origin_y)) {
		return false;
	}

	viewport_x += origin_x;
	viewport_y += origin_y;

	return root_x >= viewport_x && root_x < viewport_x + allocation.width
			&& root_y >= viewport_y && root_y < viewport_y + allocation.height;
}

static GdkFilterReturn on_xevent(GdkXEvent *gdk_xevent, GdkEvent *event,
		gpointer data) {
	XEvent *xevent = (XEvent *) gdk_xevent;
	XGenericEventCookie *cookie;
	XIDeviceEvent *button_event;
	XIEvent *xi_event;

	(void) event;
	(void) data;

	if (xevent->type == ConfigureNotify
			&& xevent->xconfigure.window == foreign_window) {
		int width = foreign_width;
		int height = foreign_height;

		if (query_geometry(foreign_window, &width, &height)
				&& (width != foreign_width || height != foreign_height)) {
			foreign_width = width;
			foreign_height = height;
			update_socket_size();
		}
		return GDK_FILTER_CONTINUE;
	}

	/* Prevent GDK from processing the core event as a second wheel step. */
	if (xevent->type == ButtonPress) {
		if (xevent->xbutton.window == foreign_window) {
			return GDK_FILTER_REMOVE;
		}
		/* Wheel input over a native scrollbar must not scroll the content. */
		if (xevent->xbutton.button >= 4 && xevent->xbutton.button <= 7) {
			return GDK_FILTER_REMOVE;
		}
	}

	if (xevent->type != GenericEvent) {
		return GDK_FILTER_CONTINUE;
	}

	cookie = &xevent->xcookie;
	if (cookie->data == NULL) {
		return GDK_FILTER_CONTINUE;
	}

	xi_event = cookie->data;
	if (xi_event->evtype != XI_ButtonPress) {
		return GDK_FILTER_CONTINUE;
	}

	button_event = (XIDeviceEvent *) xi_event;
	if (button_event->event != foreign_window) {
		if (button_event->detail >= 4 && button_event->detail <= 7) {
			return GDK_FILTER_REMOVE;
		}
		return GDK_FILTER_CONTINUE;
	}

	switch (button_event->detail) {
	case 4:
		if (pointer_is_over_visible_foreign(button_event->root_x,
				button_event->root_y)) {
			scroll_adjustment(vertical_adjustment, -(double) scroll_step);
		}
		break;
	case 5:
		if (pointer_is_over_visible_foreign(button_event->root_x,
				button_event->root_y)) {
			scroll_adjustment(vertical_adjustment, (double) scroll_step);
		}
		break;
	case 6:
		if (pointer_is_over_visible_foreign(button_event->root_x,
				button_event->root_y)) {
			scroll_adjustment(horizontal_adjustment, -(double) scroll_step);
		}
		break;
	case 7:
		if (pointer_is_over_visible_foreign(button_event->root_x,
				button_event->root_y)) {
			scroll_adjustment(horizontal_adjustment, (double) scroll_step);
		}
		break;
	default:
		break;
	}

	return GDK_FILTER_REMOVE;
}

static void configure_adjustment(GtkAdjustment *adjustment) {
	double page_size = gtk_adjustment_get_page_size(adjustment);

	if (page_size > 0
			&& gtk_adjustment_get_page_increment(adjustment) != page_size) {
		gtk_adjustment_set_page_increment(adjustment, page_size);
	}
	if (gtk_adjustment_get_step_increment(adjustment) != (double) scroll_step) {
		gtk_adjustment_set_step_increment(adjustment, (double) scroll_step);
	}
}

static void on_adjustment_changed(GtkAdjustment *adjustment, gpointer data) {
	(void) adjustment;
	(void) data;
	configure_adjustment(horizontal_adjustment);
	configure_adjustment(vertical_adjustment);
}

static bool create_layout(void) {
	GtkWidget *alignment;

	horizontal_adjustment = gtk_adjustment_new(0.0, 0.0,
			(double) foreign_width, (double) scroll_step, 100.0,
			(double) foreign_width);
	vertical_adjustment = gtk_adjustment_new(0.0, 0.0,
			(double) foreign_height, (double) scroll_step, 100.0,
			(double) foreign_height);
	if (!horizontal_adjustment || !vertical_adjustment) {
		return false;
	}

	window_widget = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_title(GTK_WINDOW(window_widget), "GTK Scrcpy Wrapper");
	gtk_window_set_role(GTK_WINDOW(window_widget), "gtk-scrcpy-wrapper");
	gtk_window_set_default_size(GTK_WINDOW(window_widget), wrapper_width,
			wrapper_height);
	gtk_widget_set_size_request(window_widget, MIN_WRAPPER_SIZE,
			MIN_WRAPPER_SIZE);
	gtk_window_set_resizable(GTK_WINDOW(window_widget), TRUE);

	scrolled_window_widget = gtk_scrolled_window_new(horizontal_adjustment,
			vertical_adjustment);
	gtk_scrolled_window_set_policy(
			GTK_SCROLLED_WINDOW(scrolled_window_widget),
			GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
	gtk_scrolled_window_set_overlay_scrolling(
			GTK_SCROLLED_WINDOW(scrolled_window_widget), FALSE);
	gtk_scrolled_window_set_propagate_natural_width(
			GTK_SCROLLED_WINDOW(scrolled_window_widget), FALSE);
	gtk_scrolled_window_set_propagate_natural_height(
			GTK_SCROLLED_WINDOW(scrolled_window_widget), FALSE);

	viewport_widget = gtk_viewport_new(horizontal_adjustment,
			vertical_adjustment);
	gtk_scrollable_set_hscroll_policy(GTK_SCROLLABLE(viewport_widget),
			GTK_SCROLL_MINIMUM);
	gtk_scrollable_set_vscroll_policy(GTK_SCROLLABLE(viewport_widget),
			GTK_SCROLL_MINIMUM);

	G_GNUC_BEGIN_IGNORE_DEPRECATIONS
	alignment = gtk_alignment_new(0.5, 0.5, 0.0, 0.0);
	G_GNUC_END_IGNORE_DEPRECATIONS

	socket_widget = gtk_socket_new();
	gtk_widget_set_size_request(socket_widget, foreign_width, foreign_height);
	gtk_container_add(GTK_CONTAINER(alignment), socket_widget);
	gtk_container_add(GTK_CONTAINER(viewport_widget), alignment);
	gtk_container_add(GTK_CONTAINER(scrolled_window_widget), viewport_widget);
	gtk_container_add(GTK_CONTAINER(window_widget), scrolled_window_widget);

	g_signal_connect(horizontal_adjustment, "changed",
			G_CALLBACK(on_adjustment_changed), NULL);
	g_signal_connect(vertical_adjustment, "changed",
			G_CALLBACK(on_adjustment_changed), NULL);
	configure_adjustment(horizontal_adjustment);
	configure_adjustment(vertical_adjustment);

	return true;
}

static bool foreign_window_has_socket_parent(void) {
	Window query_root;
	Window query_parent;
	Window *children = NULL;
	unsigned int child_count = 0;
	int error;
	bool success;

	gdk_x11_display_error_trap_push(gdk_display);
	success = XQueryTree(dpy, foreign_window, &query_root, &query_parent,
			&children, &child_count) != 0;
	if (children) {
		XFree(children);
	}
	XSync(dpy, False);
	error = gdk_x11_display_error_trap_pop(gdk_display);

	if (!success || error != 0 || query_parent
			!= GDK_WINDOW_XID(gtk_widget_get_window(socket_widget))) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] socket parent check failed (success=%d error=%d parent=0x%lx expected=0x%lx)\n",
			success ? 1 : 0,
			error,
			(unsigned long) query_parent,
			(unsigned long) GDK_WINDOW_XID(gtk_widget_get_window(socket_widget)));
		return false;
	}

	return true;
}

static gboolean poll_foreign_geometry(gpointer data) {
	int width;
	int height;

	(void) data;
	if (!running || child_destroyed || !scrcpy_is_running()) {
		return G_SOURCE_CONTINUE;
	}
	if (!query_geometry(foreign_window, &width, &height)) {
		return G_SOURCE_CONTINUE;
	}
	if (width != foreign_width || height != foreign_height) {
		foreign_width = width;
		foreign_height = height;
		update_socket_size();
	}

	return G_SOURCE_CONTINUE;
}

static gboolean on_plug_removed(GtkWidget *widget, gpointer data) {
	(void) widget;
	(void) data;
	child_destroyed = true;
	return TRUE;
}

static gboolean on_delete_event(GtkWidget *widget, GdkEvent *event,
		gpointer data) {
	(void) widget;
	(void) event;
	(void) data;
	wrapper_close_requested = true;
	return FALSE;
}

static void on_window_destroy(GtkWidget *widget, gpointer data) {
	(void) widget;
	(void) data;
	wrapper_destroyed = true;
	if (!wrapper_close_requested && !wrapper_destroy_intentional) {
		wrapper_error = true;
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] wrapper window was destroyed unexpectedly\n");
	}
	running = 0;
	if (main_loop_running) {
		gtk_main_quit();
	}
}

static gboolean runtime_tick(gpointer data) {
	(void) data;

	if (!running) {
		if (main_loop_running) {
			gtk_main_quit();
		}
		return G_SOURCE_REMOVE;
	}

	if (!scrcpy_is_running()) {
		scrcpy_exited = true;
		running = 0;
		if (main_loop_running) {
			gtk_main_quit();
		}
		return G_SOURCE_REMOVE;
	}

	if (launcher_pid > 1 && getppid() != launcher_pid) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] launcher exited; stopping the wrapper\n");
		running = 0;
		if (main_loop_running) {
			gtk_main_quit();
		}
		return G_SOURCE_REMOVE;
	}

	if (child_destroyed) {
		if (wait_for_process_to_exit(100)) {
			scrcpy_exited = true;
		} else {
			wrapper_error = true;
			fprintf(stderr,
				"[gtk-scrcpy-wrapper] target window was removed while scrcpy was still running\n");
		}
		running = 0;
		if (main_loop_running) {
			gtk_main_quit();
		}
		return G_SOURCE_REMOVE;
	}

	return G_SOURCE_CONTINUE;
}

static bool hide_foreign_window(void) {
	int error;

	if (!child_embedded || foreign_window == None) {
		return true;
	}

	gdk_x11_display_error_trap_push(gdk_display);
	XUnmapWindow(dpy, foreign_window);
	XSync(dpy, False);
	error = gdk_x11_display_error_trap_pop(gdk_display);
	return error == 0 || error == BadWindow;
}

static bool cleanup_resources(void) {
	bool success = true;

	if (!hide_foreign_window()) {
		success = false;
	}
	if (!stop_scrcpy()) {
		success = false;
	}

	wrapper_destroy_intentional = true;
	if (window_widget && !wrapper_destroyed) {
		gtk_widget_destroy(window_widget);
	}

	return success;
}

static int watch_parent_process(pid_t parent_pid, pid_t target_pid) {
	char parent_state = '\0';
	unsigned long long parent_start_time = 0;
	struct timespec delay = {
		.tv_sec = 0,
		.tv_nsec = 20000000,
	};
	bool parent_exited = false;

	install_signal_handlers();
	set_process_name("gtk-scrcpy-watch");
	scrcpy_pid = target_pid;

	if (!read_process_identity(parent_pid, &parent_state, &parent_start_time)
			|| parent_state == 'Z' || parent_state == 'X') {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not identify launcher process %ld\n",
			(long) parent_pid);
		return 1;
	}
	if (!capture_scrcpy_identity()) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not identify monitored process %ld\n",
			(long) target_pid);
		return 1;
	}

	while (running) {
		char current_state = '\0';
		unsigned long long current_start_time = 0;

		if (!scrcpy_is_running()) {
			break;
		}

		if (getppid() != parent_pid
				|| !read_process_identity(parent_pid, &current_state,
					&current_start_time)
				|| current_state == 'Z' || current_state == 'X'
				|| current_start_time != parent_start_time) {
			parent_exited = true;
			break;
		}

		nanosleep(&delay, NULL);
	}

	if (parent_exited) {
		if (!stop_scrcpy()) {
			return 1;
		}
		return 0;
	}
	if (caught_signal > 0) {
		return 128 + caught_signal;
	}
	return 0;
}

int main(int argc, char *argv[]) {
	Window target_window;
	pid_t parent_pid;
	pid_t target_pid;
	int exit_status = 1;

	if (argc == 5 && strcmp(argv[1], "--watch-parent") == 0) {
		if (!parse_pid(argv[2], &parent_pid)
				|| !parse_pid(argv[3], &target_pid)
				|| !parse_start_time(argv[4],
					&expected_scrcpy_start_time)) {
			usage(argv[0]);
			return 2;
		}
		return watch_parent_process(parent_pid, target_pid);
	}

	if (argc < 4 || argc > 7) {
		usage(argv[0]);
		return 2;
	}

	if (!parse_window_id(argv[1], &target_window)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] invalid window ID: %s\n", argv[1]);
		return 2;
	}
	foreign_window = target_window;

	if (!parse_pid(argv[2], &scrcpy_pid)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] invalid scrcpy PID: %s\n", argv[2]);
		return 2;
	}

	if (!parse_start_time(argv[3], &expected_scrcpy_start_time)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] invalid scrcpy start time: %s\n",
			argv[3]);
		return 2;
	}

	if (argc >= 5
			&& !parse_positive_int(argv[4], MIN_WRAPPER_SIZE,
				MAX_WRAPPER_SIZE, &wrapper_width)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] invalid wrapper width: %s\n",
			argv[4]);
		return 2;
	}

	if (argc >= 6
			&& !parse_positive_int(argv[5], MIN_WRAPPER_SIZE,
				MAX_WRAPPER_SIZE, &wrapper_height)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] invalid wrapper height: %s\n",
			argv[5]);
		return 2;
	}

	if (argc >= 7
			&& !parse_positive_int(argv[6], MIN_SCROLL_STEP,
				MAX_SCROLL_STEP, &scroll_step)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] invalid scroll step: %s\n",
			argv[6]);
		return 2;
	}

	if (!capture_scrcpy_identity()) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not identify scrcpy process %ld\n",
			(long) scrcpy_pid);
		return 1;
	}

	install_signal_handlers();
	launcher_pid = getppid();

	g_set_prgname("gtk-scrcpy-wrapper");
	if (!gtk_init_check(&argc, &argv)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] could not initialize GTK\n");
		goto setup_failure;
	}
	g_object_set(gtk_settings_get_default(), "gtk-primary-button-warps-slider",
			FALSE, NULL);

	gdk_display = gdk_display_get_default();
	if (!gdk_display || !GDK_IS_X11_DISPLAY(gdk_display)) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] requires an X11 display\n");
		goto setup_failure;
	}
	dpy = GDK_DISPLAY_XDISPLAY(gdk_display);

	if (!target_window_matches_scrcpy()) {
		if (scrcpy_pidfd >= 0) {
			close(scrcpy_pidfd);
			scrcpy_pidfd = -1;
		}
		return 1;
	}

	if (!query_geometry(foreign_window, &foreign_width, &foreign_height)) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not inspect target size\n");
		goto setup_failure;
	}

	if (!create_layout()) {
		fprintf(stderr, "[gtk-scrcpy-wrapper] could not create the GTK layout\n");
		goto setup_failure;
	}

	if (!select_xi_button_events()) {
		goto setup_failure;
	}
	gdk_window_add_filter(NULL, on_xevent, NULL);

	g_signal_connect(window_widget, "delete-event",
			G_CALLBACK(on_delete_event), NULL);
	g_signal_connect(window_widget, "destroy",
			G_CALLBACK(on_window_destroy), NULL);
	g_signal_connect(socket_widget, "plug-removed",
			G_CALLBACK(on_plug_removed), NULL);

	gtk_widget_show_all(window_widget);
	gtk_socket_add_id(GTK_SOCKET(socket_widget), foreign_window);
	child_embedded = gtk_socket_get_plug_window(GTK_SOCKET(socket_widget))
			!= NULL;

	if (!child_embedded || !foreign_window_has_socket_parent()
			|| !target_window_matches_scrcpy()) {
		fprintf(stderr,
			"[gtk-scrcpy-wrapper] could not embed the target window\n");
		goto setup_failure;
	}

	fprintf(stderr,
		"[gtk-scrcpy-wrapper] wrapped window 0x%lx in a %dx%d viewport\n",
		(unsigned long) foreign_window,
		wrapper_width,
		wrapper_height);

	g_timeout_add(50, poll_foreign_geometry, NULL);
	g_timeout_add(100, runtime_tick, NULL);
	main_loop_running = true;
	gtk_main();
	main_loop_running = false;

	if (!scrcpy_exited && !scrcpy_is_running()) {
		scrcpy_exited = true;
	}

	if (wrapper_error) {
		exit_status = 1;
	} else if (scrcpy_exited) {
		exit_status = SCRCPY_EXIT_REPORT_STATUS;
	} else {
		exit_status = 0;
	}
	if (caught_signal > 0) {
		exit_status = 128 + caught_signal;
	}

	if (!cleanup_resources() && caught_signal == 0) {
		exit_status = 1;
	}
	if (caught_signal > 0) {
		exit_status = 128 + caught_signal;
	}

	if (scrcpy_pidfd >= 0) {
		close(scrcpy_pidfd);
		scrcpy_pidfd = -1;
	}

	return exit_status;

setup_failure:
	wrapper_error = true;
	if (!cleanup_resources() && caught_signal == 0) {
		exit_status = 1;
	}
	if (caught_signal > 0) {
		exit_status = 128 + caught_signal;
	}
	if (scrcpy_pidfd >= 0) {
		close(scrcpy_pidfd);
		scrcpy_pidfd = -1;
	}
	return exit_status;
}
