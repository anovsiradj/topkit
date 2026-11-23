#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
	Display *display;
	Window window;
	Atom protocols;
	Atom delete_window;
	XEvent event;

	if (argc != 2) {
		fprintf(stderr, "usage: %s window-id\n", argv[0]);
		return 2;
	}

	window = (Window) strtoul(argv[1], NULL, 0);
	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}

	protocols = XInternAtom(display, "WM_PROTOCOLS", False);
	delete_window = XInternAtom(display, "WM_DELETE_WINDOW", False);
	memset(&event, 0, sizeof(event));
	event.xclient.type = ClientMessage;
	event.xclient.window = window;
	event.xclient.message_type = protocols;
	event.xclient.format = 32;
	event.xclient.data.l[0] = (long) delete_window;
	event.xclient.data.l[1] = CurrentTime;
	XSendEvent(display, window, False, NoEventMask, &event);
	XFlush(display);
	XCloseDisplay(display);
	return 0;
}
