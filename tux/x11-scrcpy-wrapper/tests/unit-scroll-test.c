#define main scrcpy_scroll_program_main
#include "../x11-scrcpy-wrapper.c"
#undef main

static int expect_int(const char *name, int actual, int expected) {
	if (actual == expected) {
		printf("PASS: %s is %d\n", name, actual);
		return 0;
	}
	printf("FAIL: %s is %d, expected %d\n", name, actual, expected);
	return 1;
}

int main(void) {
	int failures = 0;
	Display *display;
	Window test_child;

	display = XOpenDisplay(NULL);
	if (!display) {
		fprintf(stderr, "could not open X11 display\n");
		return 1;
	}

	dpy = display;
	test_child = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0,
			832, 1920, 0, BlackPixel(display, 0), WhitePixel(display, 0));
	child = test_child;
	child_reparented = true;
	child_width = 832;
	child_height = 1920;
	wrapper_width = 480;
	wrapper_height = 360;
	viewport_width = 480;
	viewport_height = 360;
	scroll_step = 50;
	child_x = 0;
	child_y = 0;

	scroll_child(5);
	failures += expect_int("wheel-down y", child_y, -50);
	scroll_child(4);
	failures += expect_int("wheel-up y", child_y, 0);
	child_x = -352;
	scroll_child(6);
	failures += expect_int("horizontal-left x", child_x, -302);
	scroll_child(7);
	failures += expect_int("horizontal-right x", child_x, -352);
	child_x = 0;

	for (int index = 0; index < 100; index++) {
		scroll_child(5);
	}
	failures += expect_int("repeated wheel-down lower bound", child_y, -1560);
	for (int index = 0; index < 100; index++) {
		scroll_child(4);
	}
	failures += expect_int("repeated wheel-up upper bound", child_y, 0);

	failures += expect_int("vertical scrollbar thumb length",
			get_scrollbar_thumb_length(344, 344, 1920), 61);
	failures += expect_int("vertical scrollbar thumb at top",
			get_scrollbar_thumb_offset(0, -1576, 0, 344, 61), 0);
	failures += expect_int("vertical scrollbar thumb at bottom",
			get_scrollbar_thumb_offset(-1576, -1576, 0, 344, 61), 283);
	failures += expect_int("vertical scrollbar bottom position",
			get_child_position_from_thumb_offset(283, -1576, 0, 344, 61),
			-1576);
	failures += expect_int("horizontal scrollbar thumb length",
			get_scrollbar_thumb_length(464, 464, 832), 258);
	failures += expect_int("horizontal scrollbar thumb at top",
			get_scrollbar_thumb_offset(0, -368, 0, 464, 258), 0);
	failures += expect_int("horizontal scrollbar thumb at bottom",
			get_scrollbar_thumb_offset(-368, -368, 0, 464, 258), 206);
	failures += expect_int("horizontal scrollbar bottom position",
			get_child_position_from_thumb_offset(206, -368, 0, 464, 258),
			-368);

	XDestroyWindow(display, test_child);
	XCloseDisplay(display);
	return failures == 0 ? 0 : 1;
}
