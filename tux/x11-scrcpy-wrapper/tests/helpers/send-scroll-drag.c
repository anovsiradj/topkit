#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void send_button(Display *display, Window window, Window root,
		int type, int button, int coordinate) {
	XEvent event;

	memset(&event, 0, sizeof(event));
	event.xbutton.type = type;
	event.xbutton.window = window;
	event.xbutton.root = root;
	event.xbutton.subwindow = None;
	event.xbutton.time = CurrentTime;
	event.xbutton.x = coordinate;
	event.xbutton.y = coordinate;
	event.xbutton.x_root = coordinate;
	event.xbutton.y_root = coordinate;
	event.xbutton.state = type == ButtonPress ? 0 : Button1Mask;
	event.xbutton.button = button;
	event.xbutton.same_screen = True;
	XSendEvent(display, window, False,
			type == ButtonPress ? ButtonPressMask : ButtonReleaseMask,
			&event);
}

static void send_motion(Display *display, Window window, Window root,
		int x, int y) {
	XEvent event;

	memset(&event, 0, sizeof(event));
	event.xmotion.type = MotionNotify;
	event.xmotion.window = window;
	event.xmotion.root = root;
	event.xmotion.subwindow = None;
	event.xmotion.time = CurrentTime;
	event.xmotion.x = x;
	event.xmotion.y = y;
	event.xmotion.x_root = x;
	event.xmotion.y_root = y;
	event.xmotion.state = Button1Mask;
	event.xmotion.is_hint = False;
	event.xmotion.same_screen = True;
	XSendEvent(display, window, False, PointerMotionMask, &event);
}

int main(int argc, char *argv[]) {
	Display *display;
	Window thumb;
	Window track;
	Window root;
	Window child;
	Window wrapper;
	Window *children = NULL;
	unsigned int child_count = 0;
	Bool has_pointer;
	int coordinate_x;
	int coordinate_y;
	int original_x = 0;
	int original_y = 0;
	int root_x = 0;
	int root_y = 0;
	unsigned int mask = 0;
	int thumb_x;
	int thumb_y;

	if (argc != 5) {
		fprintf(stderr, "usage: %s thumb-id track-id x y\n", argv[0]);
		return 2;
	}

	thumb = (Window) strtoul(argv[1], NULL, 0);
	track = (Window) strtoul(argv[2], NULL, 0);
	coordinate_x = (int) strtol(argv[3], NULL, 10);
	coordinate_y = (int) strtol(argv[4], NULL, 10);
	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}
	root = DefaultRootWindow(display);
	if (!XQueryTree(display, track, &root, &wrapper, &children,
			&child_count)) {
		XCloseDisplay(display);
		return 1;
	}
	if (children) {
		XFree(children);
	}
	XRaiseWindow(display, wrapper);
	XRaiseWindow(display, track);
	XRaiseWindow(display, thumb);
	XSync(display, False);
	has_pointer = XQueryPointer(display, root, &root, &child, &root_x,
			&root_y, &original_x, &original_y, &mask);
	if (!has_pointer) {
		original_x = 0;
		original_y = 0;
	}
	if (!XTranslateCoordinates(display, thumb, root, 5, 5, &thumb_x,
			&thumb_y, &child)) {
		XCloseDisplay(display);
		return 1;
	}
	XWarpPointer(display, None, root, 0, 0, 0, 0, thumb_x, thumb_y);
	XFlush(display);

	send_button(display, thumb, root, ButtonPress, Button1, 5);
	{
		struct timespec delay = { .tv_sec = 0, .tv_nsec = 100000000 };
		nanosleep(&delay, NULL);
	}
	send_motion(display, track, root, coordinate_x, coordinate_y);
	{
		struct timespec delay = { .tv_sec = 0, .tv_nsec = 100000000 };
		nanosleep(&delay, NULL);
	}
	send_button(display, track, root, ButtonRelease, Button1, 5);
	XFlush(display);
	if (has_pointer) {
		XWarpPointer(display, None, root, 0, 0, 0, 0,
				original_x, original_y);
		XFlush(display);
	}
	XCloseDisplay(display);
	return 0;
}
