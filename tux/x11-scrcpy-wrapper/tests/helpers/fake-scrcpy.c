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

static void handle_signal(int signal_number) {
	if (signal_number == SIGTERM && ignore_sigterm) {
		return;
	}
	_exit(0);
}

static void install_signal_handlers(void) {
	struct sigaction action;

	sigemptyset(&action.sa_mask);
	action.sa_handler = handle_signal;
	action.sa_flags = 0;
	sigaction(SIGTERM, &action, NULL);
	sigaction(SIGINT, &action, NULL);
	sigaction(SIGHUP, &action, NULL);
}

int main(void) {
	Display *display;
	Window window;
	XEvent event;
	XClassHint class_hint;
	XSizeHints size_hints;
	Atom net_wm_pid;
	long pid;
	const char *delay_text;
	unsigned int delay_seconds = 0;
	char class_instance[] = "scrcpy";
	char class_class[] = "scrcpy";

	if (getenv("FAKE_SCRCPY_IGNORE_TERM")) {
		ignore_sigterm = 1;
	}
	install_signal_handlers();
	delay_text = getenv("FAKE_SCRCPY_DELAY");
	if (delay_text && *delay_text) {
		char *end = NULL;
		unsigned long parsed = strtoul(delay_text, &end, 10);

		if (end != delay_text && *end == '\0' && parsed <= 60) {
			delay_seconds = (unsigned int) parsed;
		}
	}

	if (delay_seconds > 0) {
		sleep(delay_seconds);
	}

	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}

	window = XCreateSimpleWindow(display, DefaultRootWindow(display), 100, 100,
			832, 1920, 0, BlackPixel(display, 0), WhitePixel(display, 0));
	class_hint.res_name = class_instance;
	class_hint.res_class = class_class;
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

	while (XNextEvent(display, &event)) {
		if (event.type == DestroyNotify
				&& event.xdestroywindow.window == window) {
			break;
		}
	}

	XCloseDisplay(display);
	return 0;
}
