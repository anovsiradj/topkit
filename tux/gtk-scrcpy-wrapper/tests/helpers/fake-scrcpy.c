#define _DEFAULT_SOURCE

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t ignore_sigterm;
static volatile sig_atomic_t exit_status;

static void handle_signal(int signal_number) {
	if (signal_number == SIGTERM && ignore_sigterm) {
		return;
	}
	if (signal_number == SIGALRM) {
		if (exit_status > 128 && exit_status <= 128 + SIGKILL) {
			raise(SIGKILL);
		}
		_exit(exit_status);
	}
	_exit(0);
}

static void install_signal_handlers(void) {
	struct sigaction action;

	memset(&action, 0, sizeof(action));
	action.sa_handler = handle_signal;
	sigemptyset(&action.sa_mask);
	action.sa_flags = 0;
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGINT, &action, NULL);
	sigaction(SIGHUP, &action, NULL);
	sigaction(SIGALRM, &action, NULL);
}

static int parse_integer(const char *name, const char *text, int minimum,
		int maximum, int fallback) {
	char *end = NULL;
	long value;

	if (!text || !*text) {
		return fallback;
	}
	value = strtol(text, &end, 10);
	if (end == text || *end != '\0' || value < minimum || value > maximum) {
		fprintf(stderr, "Invalid %s: %s\n", name, text);
		exit(2);
	}
	return (int) value;
}

int main(void) {
	Display *display;
	Window window;
	XEvent event;
	XClassHint class_hint;
	XSizeHints size_hints;
	Atom net_wm_pid;
	long pid;
	int delay_seconds;
	int exit_after;
	int requested_exit_status;

	if (getenv("FAKE_SCRCPY_IGNORE_TERM")) {
		ignore_sigterm = 1;
	}
	install_signal_handlers();
	delay_seconds = parse_integer("FAKE_SCRCPY_DELAY",
			getenv("FAKE_SCRCPY_DELAY"), 0, 60, 0);
	exit_after = parse_integer("FAKE_SCRCPY_EXIT_AFTER",
			getenv("FAKE_SCRCPY_EXIT_AFTER"), 0, 60, 0);
	requested_exit_status = parse_integer("FAKE_SCRCPY_EXIT_STATUS",
			getenv("FAKE_SCRCPY_EXIT_STATUS"), 0, 255, 0);
	exit_status = requested_exit_status;

	if (delay_seconds > 0) {
		sleep(delay_seconds);
	}

	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}

	window = XCreateSimpleWindow(display, DefaultRootWindow(display), 100, 100,
			832, 1920, 0, BlackPixel(display, 0), WhitePixel(display, 0));
	class_hint.res_name = (char *) "scrcpy";
	class_hint.res_class = (char *) "scrcpy";
	XSetClassHint(display, window, &class_hint);
	net_wm_pid = XInternAtom(display, "_NET_WM_PID", False);
	pid = (long) getpid();
	XChangeProperty(display, window, net_wm_pid, XA_CARDINAL, 32,
			PropModeReplace, (unsigned char *) &pid, 1);
	XStoreName(display, window, "scrcpy");
	memset(&size_hints, 0, sizeof(size_hints));
	size_hints.flags = PSize | PMinSize;
	size_hints.width = 832;
	size_hints.height = 1920;
	size_hints.min_width = 1;
	size_hints.min_height = 1;
	XSetWMNormalHints(display, window, &size_hints);
	XMapWindow(display, window);
	XSync(display, False);
	printf("fake-scrcpy window=0x%lx pid=%ld\n", (unsigned long) window,
			(long) getpid());
	fflush(stdout);

	if (exit_after > 0) {
		alarm((unsigned int) exit_after);
	}

	for (;;) {
		XNextEvent(display, &event);
		if (event.type == DestroyNotify
				&& event.xdestroywindow.window == window) {
			break;
		}
	}

	XCloseDisplay(display);
	return 0;
}
