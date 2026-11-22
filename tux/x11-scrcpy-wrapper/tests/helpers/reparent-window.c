#include <X11/Xlib.h>

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
	Display *display;
	Window window;
	Window root;

	if (argc != 2) {
		fprintf(stderr, "usage: %s window-id\n", argv[0]);
		return 2;
	}

	display = XOpenDisplay(NULL);
	if (!display) {
		return 1;
	}

	window = (Window) strtoul(argv[1], NULL, 0);
	root = DefaultRootWindow(display);
	XReparentWindow(display, window, root, 100, 100);
	XSync(display, False);
	XCloseDisplay(display);
	return 0;
}
