#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
	Display *display;
	Window window;
	Window root;
	XEvent event;
	const char *type;
	unsigned int state;
	int coordinate_x;
	int coordinate_y;

	if (argc != 6) {
		fprintf(stderr, "usage: %s window-id press|release|motion state x y\n",
				argv[0]);
		return 2;
	}

	window = (Window) strtoul(argv[1], NULL, 0);
	type = argv[2];
	state = (unsigned int) strtoul(argv[3], NULL, 0);
	coordinate_x = (int) strtol(argv[4], NULL, 10);
	coordinate_y = (int) strtol(argv[5], NULL, 10);
	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}
	root = DefaultRootWindow(display);

	memset(&event, 0, sizeof(event));
	if (strcmp(type, "motion") == 0) {
		event.xmotion.type = MotionNotify;
		event.xmotion.window = window;
		event.xmotion.root = root;
		event.xmotion.subwindow = None;
		event.xmotion.time = CurrentTime;
		event.xmotion.x = coordinate_x;
		event.xmotion.y = coordinate_y;
		event.xmotion.x_root = coordinate_x;
		event.xmotion.y_root = coordinate_y;
		event.xmotion.state = state;
		event.xmotion.is_hint = False;
		event.xmotion.same_screen = True;
		XSendEvent(display, window, False, PointerMotionMask, &event);
	} else {
		event.xbutton.type = strcmp(type, "press") == 0
				? ButtonPress : ButtonRelease;
		event.xbutton.window = window;
		event.xbutton.root = root;
		event.xbutton.subwindow = None;
		event.xbutton.time = CurrentTime;
		event.xbutton.x = coordinate_x;
		event.xbutton.y = coordinate_y;
		event.xbutton.x_root = coordinate_x;
		event.xbutton.y_root = coordinate_y;
		event.xbutton.state = state;
		event.xbutton.button = Button1;
		event.xbutton.same_screen = True;
		XSendEvent(display, window, False,
				event.xbutton.type == ButtonPress
					? ButtonPressMask : ButtonReleaseMask,
				&event);
	}

	XFlush(display);
	XCloseDisplay(display);
	return 0;
}
