#define _DEFAULT_SOURCE

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
#define SCROLLBAR_THICKNESS 16
#define SCROLLBAR_THUMB_MARGIN 2
#define SCROLLBAR_MIN_THUMB_LENGTH 24
/* The launcher replaces this internal status with scrcpy's exact status. */
#define SCRCPY_EXIT_REPORT_STATUS 125

static Display *dpy;
static Window root = None;
static Window wrapper = None;
static Window child = None;
static Window vertical_scrollbar_track = None;
static Window vertical_scrollbar_thumb = None;
static Window horizontal_scrollbar_track = None;
static Window horizontal_scrollbar_thumb = None;
static Colormap scrollbar_colormap = None;

static int wrapper_width;
static int wrapper_height;
static int viewport_width;
static int viewport_height;
static int child_width;
static int child_height;
static int child_x;
static int child_y;
static int scroll_step;

static bool child_reparented;
static bool child_destroyed;
static bool wrapper_destroyed;
static bool wrapper_close_requested;
static bool wrapper_destroy_intentional;
static bool xi2_available;
static bool vertical_scrollbar_visible;
static bool horizontal_scrollbar_visible;
static bool vertical_scrollbar_dragging;
static bool horizontal_scrollbar_dragging;
static bool vertical_scrollbar_pointer_grabbed;
static bool horizontal_scrollbar_pointer_grabbed;
static int vertical_thumb_offset;
static int vertical_thumb_length;
static int vertical_drag_offset;
static int horizontal_thumb_offset;
static int horizontal_thumb_length;
static int horizontal_drag_offset;
static bool suppress_x_errors;
static bool suppressed_x_error;

static pid_t scrcpy_pid;
static int scrcpy_pidfd = -1;
static unsigned long long expected_scrcpy_start_time;
static unsigned long long scrcpy_start_time;
static bool scrcpy_identity_captured;
static bool scrcpy_exited;
static pid_t launcher_pid = -1;
static volatile sig_atomic_t running = 1;
static volatile sig_atomic_t x_error = 0;
static volatile sig_atomic_t caught_signal = 0;

static void drain_destroy_events(void);
static bool window_exists(Window window);
static bool target_window_matches_scrcpy(void);
static void update_scrollbar_layout(void);
static void update_scrollbar_thumbs(void);
static void raise_scrollbars(void);
static void cancel_vertical_scrollbar_drag(void);
static void cancel_horizontal_scrollbar_drag(void);

static void handle_signal(int signal_number) {
	caught_signal = signal_number;
	running = 0;
}

static void note_wrapper_destroyed(void) {
	bool was_destroyed = wrapper_destroyed;

	wrapper_destroyed = true;
	running = 0;
	if (!was_destroyed && !wrapper_close_requested
			&& !wrapper_destroy_intentional) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] wrapper window was destroyed unexpectedly\n");
		x_error = 1;
	}
}

static bool is_expected_window_error(const XErrorEvent *event) {
	bool invalid_window = event->error_code == BadWindow
			|| event->error_code == BadDrawable;

	if (!invalid_window) {
		return false;
	}

	if (child != None && event->resourceid == (XID) child) {
		child_destroyed = true;
		running = 0;
		return true;
	}

	if (wrapper != None && event->resourceid == (XID) wrapper) {
		note_wrapper_destroyed();
		return true;
	}

	return false;
}

static int x_error_handler(Display *display, XErrorEvent *event) {
	char message[128] = "unknown X11 error";

	if (suppress_x_errors) {
		suppressed_x_error = true;
		return 0;
	}

	if (is_expected_window_error(event)) {
		return 0;
	}

	XGetErrorText(display, event->error_code, message, sizeof(message));
	fprintf(stderr,
		"[x11-scrcpy-wrapper] X11 error: %s (request %u.%u, resource 0x%lx)\n",
		message,
		(unsigned int) event->request_code,
		(unsigned int) event->minor_code,
		event->resourceid);

	x_error = 1;
	running = 0;
	return 0;
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

static bool query_geometry(Window window, int *width, int *height) {
	Window geometry_root;
	int geometry_x;
	int geometry_y;
	unsigned int geometry_width;
	unsigned int geometry_height;
	unsigned int border_width;
	unsigned int depth;

	if (!XGetGeometry(dpy, window, &geometry_root, &geometry_x, &geometry_y,
			&geometry_width, &geometry_height, &border_width, &depth)) {
		return false;
	}

	if (geometry_width > INT_MAX || geometry_height > INT_MAX) {
		return false;
	}

	*width = (int) geometry_width;
	*height = (int) geometry_height;
	return true;
}

static bool query_parent(Window window, Window *parent) {
	Window query_root;
	Window query_parent;
	Window *children = NULL;
	unsigned int child_count = 0;

	if (!XQueryTree(dpy, window, &query_root, &query_parent, &children,
			&child_count)) {
		return false;
	}

	if (children) {
		XFree(children);
	}

	*parent = query_parent;
	return true;
}

static bool query_parent_and_root(Window window, Window *parent,
		Window *tree_root) {
	Window query_root;
	Window query_parent;
	Window *children = NULL;
	unsigned int child_count = 0;

	if (!XQueryTree(dpy, window, &query_root, &query_parent, &children,
			&child_count)) {
		return false;
	}

	if (children) {
		XFree(children);
	}

	*parent = query_parent;
	*tree_root = query_root;
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
	bool success = false;

	net_wm_pid = XInternAtom(dpy, "_NET_WM_PID", False);
	if (XGetWindowProperty(dpy, window, net_wm_pid, 0, 1, False,
			XA_CARDINAL, &actual_type, &actual_format, &item_count,
			&bytes_after, &property) != Success) {
		return false;
	}

	if (property && actual_type == XA_CARDINAL && actual_format == 32
			&& item_count == 1 && bytes_after == 0) {
		actual_pid = (pid_t) ((const unsigned long *) property)[0];
		success = actual_pid == expected_pid;
	}

	if (property) {
		XFree(property);
	}

	return success;
}

static void get_axis_bounds(int content_size, int viewport_size, int *minimum,
		int *maximum) {
	if (content_size > viewport_size) {
		*minimum = viewport_size - content_size;
		*maximum = 0;
	} else {
		*minimum = (viewport_size - content_size) / 2;
		*maximum = *minimum;
	}
}

static int clamp_int(int value, int minimum, int maximum) {
	if (value < minimum) {
		return minimum;
	}
	if (value > maximum) {
		return maximum;
	}
	return value;
}

static int get_scrollbar_thumb_length(int track_length, int viewport_size,
		int content_size) {
	long thumb_length;

	if (track_length <= 0 || viewport_size <= 0 || content_size <= 0) {
		return 0;
	}

	thumb_length = (long) track_length * viewport_size / content_size;
	if (thumb_length < SCROLLBAR_MIN_THUMB_LENGTH) {
		thumb_length = SCROLLBAR_MIN_THUMB_LENGTH;
	}
	if (thumb_length > track_length) {
		thumb_length = track_length;
	}

	return (int) thumb_length;
}

static int get_scrollbar_thumb_offset(int child_position, int minimum,
		int maximum, int track_length, int thumb_length) {
	long range = (long) maximum - minimum;
	long available = track_length - thumb_length;

	if (range <= 0 || available <= 0) {
		return 0;
	}

	return (int) ((long) (maximum - child_position) * available / range);
}

static int get_child_position_from_thumb_offset(int thumb_offset, int minimum,
		int maximum, int track_length, int thumb_length) {
	long range = (long) maximum - minimum;
	long available = track_length - thumb_length;
	long traveled;

	if (range <= 0 || available <= 0) {
		return maximum;
	}

	thumb_offset = clamp_int(thumb_offset, 0, available);
	traveled = (long) thumb_offset * range / available;
	return maximum - (int) traveled;
}

static void clamp_child_position(void) {
	int minimum_x;
	int maximum_x;
	int minimum_y;
	int maximum_y;

	get_axis_bounds(child_width, viewport_width, &minimum_x, &maximum_x);
	get_axis_bounds(child_height, viewport_height, &minimum_y, &maximum_y);

	if (child_x < minimum_x) {
		child_x = minimum_x;
	} else if (child_x > maximum_x) {
		child_x = maximum_x;
	}

	if (child_y < minimum_y) {
		child_y = minimum_y;
	} else if (child_y > maximum_y) {
		child_y = maximum_y;
	}
}

static void move_child(int delta_x, int delta_y) {
	if (child == None || child_destroyed || !child_reparented) {
		return;
	}

	child_x += delta_x;
	child_y += delta_y;
	clamp_child_position();

	XMoveWindow(dpy, child, child_x, child_y);
	XFlush(dpy);
	update_scrollbar_thumbs();
}

static void scroll_child(unsigned int button) {
	switch (button) {
	case 4:
		/* Wheel up: move the window down and reveal content above it. */
		move_child(0, scroll_step);
		break;
	case 5:
		/* Wheel down: move the window up and reveal content below it. */
		move_child(0, -scroll_step);
		break;
	case 6:
		/* Horizontal wheel left: reveal content to the left. */
		move_child(scroll_step, 0);
		break;
	case 7:
		/* Horizontal wheel right: reveal content to the right. */
		move_child(-scroll_step, 0);
		break;
	default:
		break;
	}
}

static bool calculate_scrollbar_visibility(bool *vertical, bool *horizontal) {
	bool wants_vertical = child_height > wrapper_height;
	bool wants_horizontal = child_width > wrapper_width;
	int iteration;

	for (iteration = 0; iteration < 4; iteration++) {
		int candidate_width = wrapper_width
				- (wants_vertical ? SCROLLBAR_THICKNESS : 0);
		int candidate_height = wrapper_height
				- (wants_horizontal ? SCROLLBAR_THICKNESS : 0);
		bool needs_vertical = child_height > candidate_height;
		bool needs_horizontal = child_width > candidate_width;

		if (needs_vertical == wants_vertical
				&& needs_horizontal == wants_horizontal) {
			break;
		}

		wants_vertical = needs_vertical;
		wants_horizontal = needs_horizontal;
	}

	*vertical = wants_vertical;
	*horizontal = wants_horizontal;
	return true;
}

static bool allocate_scrollbar_color(Colormap colormap, const char *color_name,
		unsigned long *pixel) {
	XColor color;
	XColor exact_color;

	if (!XAllocNamedColor(dpy, colormap, color_name, &color, &exact_color)) {
		return false;
	}

	*pixel = color.pixel;
	return true;
}

static Window create_scrollbar_window(Window parent, int x, int y, int width,
		int height, unsigned long background, unsigned long border,
		long event_mask) {
	XWindowAttributes root_attributes;
	XSetWindowAttributes attributes;

	if (!XGetWindowAttributes(dpy, root, &root_attributes)) {
		return None;
	}

	memset(&attributes, 0, sizeof(attributes));
	attributes.background_pixel = background;
	attributes.border_pixel = border;
	attributes.colormap = scrollbar_colormap;
	attributes.event_mask = event_mask;

	return XCreateWindow(dpy, parent, x, y, width, height, 0,
			root_attributes.depth, InputOutput, root_attributes.visual,
			CWBackPixel | CWBorderPixel | CWColormap | CWEventMask,
			&attributes);
}

static void set_scrollbar_class(Window window, const char *instance,
		const char *class_name) {
	XClassHint class_hint;

	class_hint.res_name = (char *) instance;
	class_hint.res_class = (char *) class_name;
	XSetClassHint(dpy, window, &class_hint);
}

static void free_scrollbar_colormap(void) {
	if (scrollbar_colormap != None) {
		XFreeColormap(dpy, scrollbar_colormap);
		scrollbar_colormap = None;
	}
}

static void destroy_scrollbar_windows(void) {
	if (vertical_scrollbar_thumb != None) {
		XDestroyWindow(dpy, vertical_scrollbar_thumb);
		vertical_scrollbar_thumb = None;
	}
	if (vertical_scrollbar_track != None) {
		XDestroyWindow(dpy, vertical_scrollbar_track);
		vertical_scrollbar_track = None;
	}
	if (horizontal_scrollbar_thumb != None) {
		XDestroyWindow(dpy, horizontal_scrollbar_thumb);
		horizontal_scrollbar_thumb = None;
	}
	if (horizontal_scrollbar_track != None) {
		XDestroyWindow(dpy, horizontal_scrollbar_track);
		horizontal_scrollbar_track = None;
	}
	free_scrollbar_colormap();
}

static bool create_scrollbar_windows(void) {
	XWindowAttributes root_attributes;
	unsigned long track_background;
	unsigned long track_border;
	unsigned long thumb_background;
	unsigned long thumb_border;
	long event_mask = ButtonPressMask | ButtonReleaseMask | ButtonMotionMask
			| PointerMotionMask | ExposureMask | StructureNotifyMask;

	if (!XGetWindowAttributes(dpy, root, &root_attributes)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not inspect scrollbar visual\n");
		return false;
	}

	scrollbar_colormap = XCreateColormap(dpy, root, root_attributes.visual,
			AllocNone);
	if (scrollbar_colormap == None) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not create scrollbar colormap\n");
		return false;
	}

	if (!allocate_scrollbar_color(scrollbar_colormap, "gray90",
			&track_background)
			|| !allocate_scrollbar_color(scrollbar_colormap, "gray75",
				&track_border)
			|| !allocate_scrollbar_color(scrollbar_colormap, "gray65",
				&thumb_background)
			|| !allocate_scrollbar_color(scrollbar_colormap, "gray45",
				&thumb_border)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not allocate scrollbar colors\n");
		destroy_scrollbar_windows();
		return false;
	}

	vertical_scrollbar_track = create_scrollbar_window(wrapper,
			wrapper_width - SCROLLBAR_THICKNESS, 0, SCROLLBAR_THICKNESS,
			wrapper_height, track_background, track_border, event_mask);
	if (vertical_scrollbar_track == None) {
		goto failure;
	}
	vertical_scrollbar_thumb = create_scrollbar_window(
			vertical_scrollbar_track, SCROLLBAR_THUMB_MARGIN,
			SCROLLBAR_THUMB_MARGIN,
			SCROLLBAR_THICKNESS - 2 * SCROLLBAR_THUMB_MARGIN,
			SCROLLBAR_THICKNESS - 2 * SCROLLBAR_THUMB_MARGIN,
			thumb_background, thumb_border, event_mask);
	if (vertical_scrollbar_thumb == None) {
		goto failure;
	}
	horizontal_scrollbar_track = create_scrollbar_window(wrapper, 0,
			wrapper_height - SCROLLBAR_THICKNESS, wrapper_width,
			SCROLLBAR_THICKNESS, track_background, track_border, event_mask);
	if (horizontal_scrollbar_track == None) {
		goto failure;
	}
	horizontal_scrollbar_thumb = create_scrollbar_window(
			horizontal_scrollbar_track, SCROLLBAR_THUMB_MARGIN,
			SCROLLBAR_THUMB_MARGIN,
			SCROLLBAR_THICKNESS - 2 * SCROLLBAR_THUMB_MARGIN,
			SCROLLBAR_THICKNESS - 2 * SCROLLBAR_THUMB_MARGIN,
			thumb_background, thumb_border, event_mask);
	if (horizontal_scrollbar_thumb == None) {
		goto failure;
	}

	set_scrollbar_class(vertical_scrollbar_track, "x11-scrcpy-wrapper-track",
			"X11ScrcpyWrapperTrack");
	set_scrollbar_class(vertical_scrollbar_thumb, "x11-scrcpy-wrapper-thumb",
			"X11ScrcpyWrapperThumb");
	set_scrollbar_class(horizontal_scrollbar_track, "x11-scrcpy-wrapper-track",
			"X11ScrcpyWrapperTrack");
	set_scrollbar_class(horizontal_scrollbar_thumb, "x11-scrcpy-wrapper-thumb",
			"X11ScrcpyWrapperThumb");

	return true;

failure:
	fprintf(stderr, "[x11-scrcpy-wrapper] could not create scrollbar windows\n");
	destroy_scrollbar_windows();
	return false;
}

static void set_scrollbar_mapped(Window track, Window thumb, bool visible) {
	if (visible) {
		XMapWindow(dpy, track);
		XMapWindow(dpy, thumb);
	} else {
		XUnmapWindow(dpy, thumb);
		XUnmapWindow(dpy, track);
	}
}

static void update_scrollbar_layout(void) {
	bool wants_vertical;
	bool wants_horizontal;
	int vertical_track_height;
	int horizontal_track_width;

	calculate_scrollbar_visibility(&wants_vertical, &wants_horizontal);
	viewport_width = wrapper_width
			- (wants_vertical ? SCROLLBAR_THICKNESS : 0);
	viewport_height = wrapper_height
			- (wants_horizontal ? SCROLLBAR_THICKNESS : 0);

	if (wants_vertical != vertical_scrollbar_visible) {
		if (!wants_vertical) {
			cancel_vertical_scrollbar_drag();
		}
		vertical_scrollbar_visible = wants_vertical;
		set_scrollbar_mapped(vertical_scrollbar_track,
				vertical_scrollbar_thumb, vertical_scrollbar_visible);
	}
	if (wants_horizontal != horizontal_scrollbar_visible) {
		if (!wants_horizontal) {
			cancel_horizontal_scrollbar_drag();
		}
		horizontal_scrollbar_visible = wants_horizontal;
		set_scrollbar_mapped(horizontal_scrollbar_track,
				horizontal_scrollbar_thumb, horizontal_scrollbar_visible);
	}

	vertical_track_height = horizontal_scrollbar_visible
			? wrapper_height - SCROLLBAR_THICKNESS : wrapper_height;
	horizontal_track_width = vertical_scrollbar_visible
			? wrapper_width - SCROLLBAR_THICKNESS : wrapper_width;

	if (vertical_scrollbar_track != None) {
		XMoveResizeWindow(dpy, vertical_scrollbar_track,
				wrapper_width - SCROLLBAR_THICKNESS, 0,
				SCROLLBAR_THICKNESS, vertical_track_height);
	}
	if (horizontal_scrollbar_track != None) {
		XMoveResizeWindow(dpy, horizontal_scrollbar_track, 0,
				wrapper_height - SCROLLBAR_THICKNESS,
				horizontal_track_width, SCROLLBAR_THICKNESS);
	}

	update_scrollbar_thumbs();
	raise_scrollbars();
	XFlush(dpy);
}

static void update_scrollbar_thumbs(void) {
	int minimum;
	int maximum;

	if (vertical_scrollbar_visible) {
		get_axis_bounds(child_height, viewport_height, &minimum, &maximum);
		vertical_thumb_length = get_scrollbar_thumb_length(viewport_height,
				viewport_height, child_height);
		vertical_thumb_offset = get_scrollbar_thumb_offset(child_y, minimum,
				maximum, viewport_height, vertical_thumb_length);
		if (vertical_scrollbar_thumb != None) {
			XMoveResizeWindow(dpy, vertical_scrollbar_thumb,
					SCROLLBAR_THUMB_MARGIN, vertical_thumb_offset,
					SCROLLBAR_THICKNESS - 2 * SCROLLBAR_THUMB_MARGIN,
					vertical_thumb_length);
		}
	} else {
		vertical_thumb_offset = 0;
		vertical_thumb_length = 0;
	}

	if (horizontal_scrollbar_visible) {
		get_axis_bounds(child_width, viewport_width, &minimum, &maximum);
		horizontal_thumb_length = get_scrollbar_thumb_length(viewport_width,
				viewport_width, child_width);
		horizontal_thumb_offset = get_scrollbar_thumb_offset(child_x, minimum,
				maximum, viewport_width, horizontal_thumb_length);
		if (horizontal_scrollbar_thumb != None) {
			XMoveResizeWindow(dpy, horizontal_scrollbar_thumb,
					horizontal_thumb_offset, SCROLLBAR_THUMB_MARGIN,
					horizontal_thumb_length,
					SCROLLBAR_THICKNESS - 2 * SCROLLBAR_THUMB_MARGIN);
		}
	} else {
		horizontal_thumb_offset = 0;
		horizontal_thumb_length = 0;
	}

	XFlush(dpy);
}

static void raise_scrollbars(void) {
	if (vertical_scrollbar_visible) {
		XRaiseWindow(dpy, vertical_scrollbar_track);
		XRaiseWindow(dpy, vertical_scrollbar_thumb);
	}
	if (horizontal_scrollbar_visible) {
		XRaiseWindow(dpy, horizontal_scrollbar_track);
		XRaiseWindow(dpy, horizontal_scrollbar_thumb);
	}
}

static void refresh_wrapper_geometry(void) {
	int width;
	int height;

	if (wrapper_destroyed || !query_geometry(wrapper, &width, &height)) {
		return;
	}

	if (width != wrapper_width || height != wrapper_height) {
		int previous_x = child_x;
		int previous_y = child_y;

		wrapper_width = width;
		wrapper_height = height;
		update_scrollbar_layout();
		clamp_child_position();

		if ((child_x != previous_x || child_y != previous_y)
				&& child != None && !child_destroyed
				&& child_reparented) {
			XMoveWindow(dpy, child, child_x, child_y);
			XFlush(dpy);
		}
		update_scrollbar_thumbs();
		raise_scrollbars();
	}
}

static void refresh_child_geometry(void) {
	int width;
	int height;
	int actual_x;
	int actual_y;
	Window translated_child;
	bool position_changed = false;

	if (child == None || child_destroyed || !child_reparented) {
		return;
	}

	if (!query_geometry(child, &width, &height)) {
		return;
	}

	if (width != child_width || height != child_height) {
		child_width = width;
		child_height = height;
		position_changed = true;
		update_scrollbar_layout();
	}

	if (XTranslateCoordinates(dpy, child, wrapper, 0, 0, &actual_x,
			&actual_y, &translated_child)) {
		if (actual_x != child_x || actual_y != child_y) {
			child_x = actual_x;
			child_y = actual_y;
			position_changed = true;
		}
	}

	{
		int clamped_x = child_x;
		int clamped_y = child_y;

		clamp_child_position();
		if (child_x != clamped_x || child_y != clamped_y) {
			position_changed = true;
		}
	}

	if (position_changed) {
		XMoveWindow(dpy, child, child_x, child_y);
		XFlush(dpy);
	}
	update_scrollbar_thumbs();
	raise_scrollbars();
}

static bool capture_child_geometry(void) {
	Window ignored_parent;
	Window tree_root;

	if (!query_parent_and_root(child, &ignored_parent, &tree_root)) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] could not determine target root\n");
		return false;
	}
	root = tree_root;

	if (!query_geometry(child, &child_width, &child_height)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not inspect target size\n");
		return false;
	}

	return true;
}

static bool create_wrapper(void) {
	XSetWindowAttributes attributes;
	XWindowAttributes root_attributes;
	XSizeHints size_hints;
	XClassHint class_hint;
	char class_instance[] = "x11-scrcpy-wrapper";
	char class_class[] = "X11ScrcpyWrapper";
	char title[] = "X11 Scrcpy Wrapper";
	char net_wm_title[] = "X11 Scrcpy Wrapper";
	Atom wm_delete_window;
	Atom net_wm_name;
	Atom utf8_string;
	Atom net_wm_pid;
	Atom net_wm_window_type;
	Atom normal_window_type;
	long pid;

	if (!XGetWindowAttributes(dpy, root, &root_attributes)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not inspect target root\n");
		return false;
	}

	memset(&attributes, 0, sizeof(attributes));
	attributes.background_pixel = 0;
	attributes.border_pixel = 0;
	attributes.event_mask = ExposureMask | StructureNotifyMask
			| SubstructureNotifyMask;

	wrapper = XCreateWindow(dpy, root, 50, 50, wrapper_width, wrapper_height, 0,
			root_attributes.depth, InputOutput, root_attributes.visual,
			CWBackPixel | CWBorderPixel | CWEventMask, &attributes);
	if (wrapper == None) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not create wrapper window\n");
		return false;
	}

	XStoreName(dpy, wrapper, title);
	class_hint.res_name = class_instance;
	class_hint.res_class = class_class;
	XSetClassHint(dpy, wrapper, &class_hint);

	wm_delete_window = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
	XSetWMProtocols(dpy, wrapper, &wm_delete_window, 1);

	net_wm_name = XInternAtom(dpy, "_NET_WM_NAME", False);
	utf8_string = XInternAtom(dpy, "UTF8_STRING", False);
	XChangeProperty(dpy, wrapper, net_wm_name, utf8_string, 8, PropModeReplace,
			(unsigned char *) net_wm_title, sizeof(net_wm_title) - 1);

	net_wm_pid = XInternAtom(dpy, "_NET_WM_PID", False);
	pid = (long) getpid();
	XChangeProperty(dpy, wrapper, net_wm_pid, XA_CARDINAL, 32, PropModeReplace,
			(unsigned char *) &pid, 1);

	net_wm_window_type = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
	normal_window_type = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_NORMAL", False);
	XChangeProperty(dpy, wrapper, net_wm_window_type, XA_ATOM, 32,
			PropModeReplace, (unsigned char *) &normal_window_type, 1);

	memset(&size_hints, 0, sizeof(size_hints));
	size_hints.flags = PMinSize | PBaseSize | PSize;
	size_hints.min_width = MIN_WRAPPER_SIZE;
	size_hints.min_height = MIN_WRAPPER_SIZE;
	size_hints.base_width = wrapper_width;
	size_hints.base_height = wrapper_height;
	size_hints.width = wrapper_width;
	size_hints.height = wrapper_height;
	XSetWMNormalHints(dpy, wrapper, &size_hints);

	XMapWindow(dpy, wrapper);
	XSync(dpy, False);

	return !x_error;
}

static bool select_xi_button_events(void) {
	int major_version = 2;
	int minor_version = 0;
	unsigned char event_mask_bytes[XIMaskLen(XI_LASTEVENT)] = { 0 };
	XIEventMask event_mask;
	int status = BadValue;
	bool version_available;
	bool success = false;

	suppress_x_errors = true;
	suppressed_x_error = false;

	version_available =
			XIQueryVersion(dpy, &major_version, &minor_version) == Success;
	if (version_available) {
		event_mask_bytes[XI_ButtonPress / 8] |=
				(unsigned char) (1U << (XI_ButtonPress % 8));
		event_mask.deviceid = XIAllMasterDevices;
		event_mask.mask_len = (int) sizeof(event_mask_bytes);
		event_mask.mask = event_mask_bytes;

		status = XISelectEvents(dpy, child, &event_mask, 1);
	}

	XSync(dpy, False);
	success = version_available && status == Success && !suppressed_x_error;

	suppress_x_errors = false;

	if (!success) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] could not select XInput2 button events\n");
		return false;
	}

	return true;
}

static bool pointer_is_over_child(double root_x, double root_y) {
	int wrapper_x;
	int wrapper_y;
	Window translated_wrapper;
	long visible_left;
	long visible_right;
	long visible_top;
	long visible_bottom;
	double local_x;
	double local_y;

	if (wrapper_destroyed || child_destroyed || child == None) {
		return false;
	}

	if (!XTranslateCoordinates(dpy, wrapper, root, 0, 0, &wrapper_x,
			&wrapper_y, &translated_wrapper)) {
		return false;
	}

	local_x = root_x - wrapper_x;
	local_y = root_y - wrapper_y;

	visible_left = child_x > 0 ? child_x : 0;
	visible_right = (long) child_x + child_width;
	if (visible_right > viewport_width) {
		visible_right = viewport_width;
	}

	visible_top = child_y > 0 ? child_y : 0;
	visible_bottom = (long) child_y + child_height;
	if (visible_bottom > viewport_height) {
		visible_bottom = viewport_height;
	}

	return local_x >= visible_left && local_x < visible_right
			&& local_y >= visible_top && local_y < visible_bottom;
}

static bool reparent_child(void) {
	Window current_parent;

	if (!select_xi_button_events()) {
		return false;
	}
	xi2_available = true;

	if (!target_window_matches_scrcpy()) {
		return false;
	}
	if (!create_scrollbar_windows()) {
		return false;
	}
	update_scrollbar_layout();

	XReparentWindow(dpy, child, wrapper, 0, 0);
	child_reparented = true;

	XMapWindow(dpy, child);
	XSync(dpy, False);
	if (x_error || child_destroyed || wrapper_destroyed) {
		return false;
	}

	if (!query_parent(child, &current_parent) || current_parent != wrapper) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] could not reparent the target window\n");
		return false;
	}
	if (!target_window_matches_scrcpy()) {
		return false;
	}

	refresh_wrapper_geometry();
	refresh_child_geometry();

	if (child_width <= viewport_width) {
		child_x = (viewport_width - child_width) / 2;
	} else {
		child_x = 0;
	}

	if (child_height <= viewport_height) {
		child_y = (viewport_height - child_height) / 2;
	} else {
		child_y = 0;
	}

	clamp_child_position();
	XMoveWindow(dpy, child, child_x, child_y);
	update_scrollbar_thumbs();
	raise_scrollbars();
	XSync(dpy, False);

	if (x_error || child_destroyed || wrapper_destroyed) {
		return false;
	}

	return !x_error && !child_destroyed && !wrapper_destroyed;
}

static bool window_exists(Window window) {
	XWindowAttributes attributes;
	bool exists;

	if (window == None) {
		return false;
	}

	suppress_x_errors = true;
	suppressed_x_error = false;
	exists = XGetWindowAttributes(dpy, window, &attributes) != 0;
	XSync(dpy, False);
	suppress_x_errors = false;

	return exists && !suppressed_x_error;
}

static bool destroy_wrapper(void) {
	bool success;

	if (wrapper == None || wrapper_destroyed) {
		return true;
	}

	wrapper_destroy_intentional = true;
	suppress_x_errors = true;
	suppressed_x_error = false;
	XDestroyWindow(dpy, wrapper);
	XSync(dpy, False);
	success = !suppressed_x_error;
	suppress_x_errors = false;

	if (!success && !window_exists(wrapper)) {
		success = true;
	}
	if (!success) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not destroy the wrapper window\n");
	}
	if (success) {
		wrapper_destroyed = true;
	}

	return success;
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

static bool target_window_matches_scrcpy(void) {
	if (!window_belongs_to_process(child, scrcpy_pid)) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] target window does not belong to scrcpy process %ld\n",
			(long) scrcpy_pid);
		return false;
	}
	if (!scrcpy_is_running()) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] scrcpy process %ld exited before wrapping its window\n",
			(long) scrcpy_pid);
		return false;
	}

	return true;
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
			"[x11-scrcpy-wrapper] could not stop scrcpy process %ld: %s\n",
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
			"[x11-scrcpy-wrapper] could not force scrcpy process %ld to stop: %s\n",
			(long) scrcpy_pid,
			strerror(errno));
		return false;
	}

	if (!wait_for_process_to_exit(50)) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] scrcpy process %ld did not stop after SIGKILL\n",
			(long) scrcpy_pid);
		return false;
	}

	return true;
}

static bool hide_child_for_cleanup(void) {
	bool success;

	if (child == None || child_destroyed) {
		return true;
	}

	suppress_x_errors = true;
	suppressed_x_error = false;
	XUnmapWindow(dpy, child);
	XSync(dpy, False);
	success = !suppressed_x_error;
	suppress_x_errors = false;

	if (!success && !window_exists(child)) {
		child_destroyed = true;
		return true;
	}

	return success;
}

static bool cleanup_resources(void) {
	bool success = true;

	drain_destroy_events();

	if (child_reparented && !child_destroyed) {
		if (!hide_child_for_cleanup()) {
			success = false;
		}
	}

	if (!stop_scrcpy()) {
		success = false;
	}

	/* Ensure the server processed the child's connection teardown. */
	XSync(dpy, False);
	drain_destroy_events();

	if (!wrapper_destroyed && !destroy_wrapper()) {
		success = false;
	}

	XSync(dpy, False);
	drain_destroy_events();
	if (wrapper_destroyed) {
		free_scrollbar_colormap();
	}
	return success;
}

static int x_io_error_handler(Display *display) {
	(void) display;
	fprintf(stderr, "[x11-scrcpy-wrapper] X11 connection lost\n");
	stop_scrcpy();
	_exit(1);
}

static void handle_configure_notify(const XConfigureEvent *event) {
	if (event->window == wrapper) {
		refresh_wrapper_geometry();
	} else if (event->window == child) {
		refresh_child_geometry();
	}
}

static void handle_reparent_notify(const XReparentEvent *event) {
	if (!child_reparented || event->window != child) {
		return;
	}

	if (event->parent != wrapper) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] target was reparented away from the wrapper\n");
		x_error = 1;
		running = 0;
	}
}

static bool grab_scrollbar_pointer(Window window) {
	int grab_result;
	bool success;

	suppress_x_errors = true;
	suppressed_x_error = false;
	grab_result = XGrabPointer(dpy, window, False,
			ButtonPressMask | ButtonReleaseMask | ButtonMotionMask
			| PointerMotionMask,
			GrabModeAsync, GrabModeAsync, None, None, CurrentTime);
	XSync(dpy, False);
	success = grab_result == GrabSuccess && !suppressed_x_error;
	suppress_x_errors = false;

	return success;
}

static void ungrab_scrollbar_pointer(void) {
	XUngrabPointer(dpy, CurrentTime);
	XFlush(dpy);
}

static void cancel_vertical_scrollbar_drag(void) {
	vertical_scrollbar_dragging = false;
	vertical_drag_offset = 0;
	if (vertical_scrollbar_pointer_grabbed) {
		vertical_scrollbar_pointer_grabbed = false;
		ungrab_scrollbar_pointer();
	}
}

static void cancel_horizontal_scrollbar_drag(void) {
	horizontal_scrollbar_dragging = false;
	horizontal_drag_offset = 0;
	if (horizontal_scrollbar_pointer_grabbed) {
		horizontal_scrollbar_pointer_grabbed = false;
		ungrab_scrollbar_pointer();
	}
}

static void handle_scrollbar_button_press(XButtonEvent *event) {
	if (event->window == vertical_scrollbar_track
			|| event->window == vertical_scrollbar_thumb) {
		if (!vertical_scrollbar_visible) {
			return;
		}
		if (event->button == 4) {
			move_child(0, viewport_height);
			return;
		}
		if (event->button == 5) {
			move_child(0, -viewport_height);
			return;
		}
		if (event->button == 6) {
			move_child(viewport_width, 0);
			return;
		}
		if (event->button == 7) {
			move_child(-viewport_width, 0);
			return;
		}
	}

	if (event->window == horizontal_scrollbar_track
			|| event->window == horizontal_scrollbar_thumb) {
		if (!horizontal_scrollbar_visible) {
			return;
		}
		if (event->button == 4) {
			move_child(0, viewport_height);
			return;
		}
		if (event->button == 5) {
			move_child(0, -viewport_height);
			return;
		}
		if (event->button == 6) {
			move_child(viewport_width, 0);
			return;
		}
		if (event->button == 7) {
			move_child(-viewport_width, 0);
			return;
		}
	}

	if (event->button != Button1) {
		return;
	}

	cancel_vertical_scrollbar_drag();
	cancel_horizontal_scrollbar_drag();

	if (event->window == vertical_scrollbar_thumb
			&& vertical_scrollbar_visible) {
		if (grab_scrollbar_pointer(vertical_scrollbar_track)) {
			vertical_scrollbar_dragging = true;
			vertical_drag_offset = event->y;
			vertical_scrollbar_pointer_grabbed = true;
		}
	} else if (event->window == vertical_scrollbar_track
			&& vertical_scrollbar_visible) {
		if (event->y < vertical_thumb_offset) {
			move_child(0, viewport_height);
		} else if (event->y >= vertical_thumb_offset + vertical_thumb_length) {
			move_child(0, -viewport_height);
		}
	} else if (event->window == horizontal_scrollbar_thumb
			&& horizontal_scrollbar_visible) {
		if (grab_scrollbar_pointer(horizontal_scrollbar_track)) {
			horizontal_scrollbar_dragging = true;
			horizontal_drag_offset = event->x;
			horizontal_scrollbar_pointer_grabbed = true;
		}
	} else if (event->window == horizontal_scrollbar_track
			&& horizontal_scrollbar_visible) {
		if (event->x < horizontal_thumb_offset) {
			move_child(viewport_width, 0);
		} else if (event->x >= horizontal_thumb_offset
				+ horizontal_thumb_length) {
			move_child(-viewport_width, 0);
		}
	}
}

static void handle_scrollbar_button_release(XButtonEvent *event) {
	if (event->button != Button1) {
		return;
	}

	cancel_vertical_scrollbar_drag();
	cancel_horizontal_scrollbar_drag();
}

static void handle_scrollbar_motion(XMotionEvent *event) {
	int minimum;
	int maximum;
	int position;

	/* Never treat buttonless pointer motion as a scrollbar drag. */
	if (!(event->state & Button1Mask)) {
		return;
	}

	if (vertical_scrollbar_dragging
			&& vertical_scrollbar_visible
			&& (event->window == vertical_scrollbar_track
				|| event->window == vertical_scrollbar_thumb)) {
		int thumb_offset;

		if (event->window == vertical_scrollbar_thumb) {
			thumb_offset = vertical_thumb_offset + event->y
					- vertical_drag_offset;
		} else {
			thumb_offset = event->y - vertical_drag_offset;
		}
		thumb_offset = clamp_int(thumb_offset, 0,
				viewport_height - vertical_thumb_length);

		get_axis_bounds(child_height, viewport_height, &minimum, &maximum);
		position = get_child_position_from_thumb_offset(thumb_offset, minimum,
				maximum, viewport_height, vertical_thumb_length);
		move_child(0, position - child_y);
	} else if (horizontal_scrollbar_dragging
			&& horizontal_scrollbar_visible
			&& (event->window == horizontal_scrollbar_track
				|| event->window == horizontal_scrollbar_thumb)) {
		int thumb_offset;

		if (event->window == horizontal_scrollbar_thumb) {
			thumb_offset = horizontal_thumb_offset + event->x
					- horizontal_drag_offset;
		} else {
			thumb_offset = event->x - horizontal_drag_offset;
		}
		thumb_offset = clamp_int(thumb_offset, 0,
				viewport_width - horizontal_thumb_length);

		get_axis_bounds(child_width, viewport_width, &minimum, &maximum);
		position = get_child_position_from_thumb_offset(thumb_offset, minimum,
				maximum, viewport_width, horizontal_thumb_length);
		move_child(position - child_x, 0);
	}
}

static void handle_xi_event(XEvent *event) {
	XGenericEventCookie *cookie = &event->xcookie;
	Bool has_data;

	has_data = XGetEventData(dpy, cookie);
	if (has_data && cookie->data != NULL
			&& cookie->evtype == XI_ButtonPress) {
		XIDeviceEvent *button_event = cookie->data;
		unsigned int button = (unsigned int) button_event->detail;

		if (button >= 4 && button <= 7 && button_event->event == child
				&& pointer_is_over_child(button_event->root_x,
					button_event->root_y)) {
			scroll_child(button);
		}
	}

	if (has_data) {
		XFreeEventData(dpy, cookie);
	}
}

static void drain_destroy_events(void) {
	XEvent event;

	while (XPending(dpy) > 0) {
		XNextEvent(dpy, &event);

		if (event.type == DestroyNotify) {
			if (event.xdestroywindow.window == child) {
				child_destroyed = true;
			} else if (event.xdestroywindow.window == wrapper) {
				note_wrapper_destroyed();
			}
		} else if (event.type == GenericEvent && xi2_available) {
			XGenericEventCookie *cookie = &event.xcookie;

			if (XGetEventData(dpy, cookie)) {
				XFreeEventData(dpy, cookie);
			}
		}
	}
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
	set_process_name("scrcpy-watch");
	scrcpy_pid = target_pid;

	if (!read_process_identity(parent_pid, &parent_state, &parent_start_time)
			|| parent_state == 'Z' || parent_state == 'X') {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] could not identify launcher process %ld\n",
			(long) parent_pid);
		return 1;
	}
	if (!capture_scrcpy_identity()) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] could not identify monitored process %ld\n",
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
	Window target_child;
	XEvent event;
	pid_t parent_pid;
	pid_t target_pid;
	bool started = false;
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

	if (!parse_window_id(argv[1], &target_child)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] invalid window ID: %s\n", argv[1]);
		return 2;
	}

	if (!parse_pid(argv[2], &scrcpy_pid)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] invalid scrcpy PID: %s\n", argv[2]);
		return 2;
	}

	if (!parse_start_time(argv[3], &expected_scrcpy_start_time)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] invalid scrcpy start time: %s\n",
			argv[3]);
		return 2;
	}

	if (!capture_scrcpy_identity()) {
		fprintf(stderr,
			"[x11-scrcpy-wrapper] could not identify scrcpy process %ld\n",
			(long) scrcpy_pid);
		return 1;
	}

	wrapper_width = DEFAULT_WRAPPER_WIDTH;
	wrapper_height = DEFAULT_WRAPPER_HEIGHT;
	scroll_step = DEFAULT_SCROLL_STEP;

	if (argc >= 5
			&& !parse_positive_int(argv[4], MIN_WRAPPER_SIZE,
				MAX_WRAPPER_SIZE, &wrapper_width)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] invalid wrapper width: %s\n",
			argv[4]);
		return 2;
	}

	if (argc >= 6
			&& !parse_positive_int(argv[5], MIN_WRAPPER_SIZE,
				MAX_WRAPPER_SIZE, &wrapper_height)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] invalid wrapper height: %s\n",
		argv[5]);
		return 2;
	}

	if (argc >= 7
			&& !parse_positive_int(argv[6], MIN_SCROLL_STEP,
				MAX_SCROLL_STEP, &scroll_step)) {
		fprintf(stderr, "[x11-scrcpy-wrapper] invalid scroll step: %s\n",
		argv[6]);
		return 2;
	}

	install_signal_handlers();
	launcher_pid = getppid();

	dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fprintf(stderr, "[x11-scrcpy-wrapper] could not open X11 display\n");
		stop_scrcpy();
		return 1;
	}

	XSetErrorHandler(x_error_handler);
	XSetIOErrorHandler(x_io_error_handler);
	root = None;
	child = target_child;

	if (!target_window_matches_scrcpy()) {
		if (scrcpy_pidfd >= 0) {
			close(scrcpy_pidfd);
			scrcpy_pidfd = -1;
		}
		return 1;
	}

	if (!capture_child_geometry() || !create_wrapper() || !reparent_child()) {
		goto cleanup;
	}
	started = true;

	fprintf(stderr,
		"[x11-scrcpy-wrapper] wrapped window 0x%lx in a %dx%d viewport\n",
		(unsigned long) child,
		wrapper_width,
		wrapper_height);

	while (running) {
		if (XPending(dpy) > 0) {
			XNextEvent(dpy, &event);

			switch (event.type) {
			case ButtonPress:
				handle_scrollbar_button_press(&event.xbutton);
				break;
			case ButtonRelease:
				handle_scrollbar_button_release(&event.xbutton);
				break;
			case MotionNotify:
				handle_scrollbar_motion(&event.xmotion);
				break;
			case ConfigureNotify:
				handle_configure_notify(&event.xconfigure);
				break;
			case ReparentNotify:
				handle_reparent_notify(&event.xreparent);
				break;
			case DestroyNotify:
				if (event.xdestroywindow.window == child) {
					child_destroyed = true;
					running = 0;
				} else if (event.xdestroywindow.window == wrapper) {
					note_wrapper_destroyed();
				}
				break;
			case ClientMessage:
				if (event.xclient.window == wrapper) {
					Atom wm_protocols = XInternAtom(dpy,
							"WM_PROTOCOLS", False);
					Atom delete_window = XInternAtom(dpy,
							"WM_DELETE_WINDOW", False);
					if (event.xclient.message_type == wm_protocols
							&& event.xclient.format == 32
							&& (Atom) event.xclient.data.l[0]
								== delete_window) {
						wrapper_close_requested = true;
						running = 0;
					}
				}
				break;
			case GenericEvent:
				if (xi2_available) {
					handle_xi_event(&event);
				}
				break;
			default:
				break;
			}
		} else {
			struct timespec delay = {
				.tv_sec = 0,
				.tv_nsec = 10000000,
			};
			nanosleep(&delay, NULL);
		}

		if (!scrcpy_is_running()) {
			scrcpy_exited = true;
			break;
		}

		if (launcher_pid > 1 && getppid() != launcher_pid) {
			fprintf(stderr,
				"[x11-scrcpy-wrapper] launcher exited; stopping the wrapper\n");
			break;
		}
	}

	if (!scrcpy_exited) {
		if (!scrcpy_is_running()) {
			scrcpy_exited = true;
		} else if (child_destroyed) {
			if (wait_for_process_to_exit(100)) {
				scrcpy_exited = true;
			} else {
				fprintf(stderr,
					"[x11-scrcpy-wrapper] target window was destroyed while scrcpy was still running\n");
				x_error = 1;
			}
		}
	}

	exit_status = started && !x_error ? 0 : 1;
	if (scrcpy_exited && started && !x_error && caught_signal == 0) {
		exit_status = SCRCPY_EXIT_REPORT_STATUS;
	}
	if (caught_signal > 0) {
		exit_status = 128 + caught_signal;
	}
	if (x_error) {
		exit_status = 1;
	}

cleanup:
	if (!cleanup_resources()) {
		exit_status = 1;
	}
	if (caught_signal > 0) {
		exit_status = 128 + caught_signal;
	}

	if (scrcpy_pidfd >= 0) {
		close(scrcpy_pidfd);
		scrcpy_pidfd = -1;
	}

	if (dpy) {
		XCloseDisplay(dpy);
		dpy = NULL;
	}

	return exit_status;
}
