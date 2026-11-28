// SPDX-License-Identifier: GPL-3.0-or-later
// Small image drawer for the boot splash: the shipped fbink CLI is a MINIMAL
// build without image support, so this links FBInk with FBINK_WITH_IMAGE and
// draws one PNG at an exact pixel position.
//
// usage: fbink-png [--refresh] X Y FILE
//       0 puts x/y at the top-left corner; the image is not scaled.

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "fbink.h"

int main(int argc, char** argv) {
	int    argi    = 1;
	bool   refresh = false;
	if (argi < argc && !strcmp(argv[argi], "--refresh")) {
		refresh = true;
		argi++;
	}
	if (argc - argi < 3) {
		fprintf(stderr, "usage: fbink-png [--refresh] X Y FILE\n");
		return 2;
	}
	short       x    = (short) atoi(argv[argi]);
	short       y    = (short) atoi(argv[argi + 1]);
	const char* path = argv[argi + 2];

	int fbfd = open("/dev/fb0", O_RDWR);
	if (fbfd < 0) {
		perror("fbink-png: /dev/fb0");
		return 1;
	}

	FBInkConfig cfg;
	memset(&cfg, 0, sizeof(cfg));
	if (fbink_init(fbfd, &cfg) < 0) {
		fprintf(stderr, "fbink-png: fbink_init failed\n");
		return 1;
	}

	FBInkConfig ic;
	memset(&ic, 0, sizeof(ic));
	ic.no_refresh     = !refresh;
	ic.is_flashing    = refresh;
	ic.halign         = NONE;
	ic.valign         = NONE;
	ic.scaled_width   = 0;
	ic.scaled_height  = 0;
	ic.dithering_mode = HWD_PASSTHROUGH;

	int rv = fbink_print_image(fbfd, path, x, y, &ic);
	if (rv < 0) {
		fprintf(stderr, "fbink-png: %s -> %d\n", path, rv);
		return 1;
	}
	fbink_close(fbfd);
	return 0;
}
