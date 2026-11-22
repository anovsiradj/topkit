#include <X11/Xlib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
	Display *display;
	Window window;
	XEvent event;
	int coordinate;

	if (argc != 3) {
		fprintf(stderr, "usage: %s window-id coordinate\n", argv[0]);
		return 2;
	}

	window = (Window) strtoul(argv[1], NULL, 0);
	coordinate = (int) strtol(argv[2], NULL, 10);
	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}

	memset(&event, 0, sizeof(event));
	event.xbutton.type = ButtonPress;
	event.xbutton.window = window;
	event.xbutton.root = DefaultRootWindow(display);
	event.xbutton.subwindow = None;
	event.xbutton.time = CurrentTime;
	event.xbutton.x = coordinate;
	event.xbutton.y = coordinate;
	event.xbutton.x_root = coordinate;
	event.xbutton.y_root = coordinate;
	event.xbutton.state = 0;
	event.xbutton.button = Button1;
	event.xbutton.same_screen = True;
	XSendEvent(display, window, False, ButtonPressMask, &event);
	XFlush(display);
	XCloseDisplay(display);
	return 0;
}
