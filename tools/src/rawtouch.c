// SPDX-License-Identifier: GPL-3.0-or-later
/* rawtouch <evdev> <seconds>: record the raw coordinate extent of real touches (min/max X/Y, number of frames, a sparse trace) */
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
int main(int argc, char **argv)
{
    int fd = open(argv[1], O_RDONLY);
    int secs = argc > 2 ? atoi(argv[2]) : 30;
    if (fd < 0) { perror("open"); return 1; }
    int minx = 99999, maxx = -1, miny = 99999, maxy = -1, x = 0, y = 0, n = 0, slot = 0, last = 0;
    time_t end = time(NULL) + secs;
    struct input_event e;
    while (time(NULL) < end) {
        struct pollfd p = { fd, POLLIN, 0 };
        if (poll(&p, 1, 500) <= 0) continue;
        if (read(fd, &e, sizeof(e)) != sizeof(e)) continue;
        if (e.type == EV_ABS && e.code == ABS_MT_SLOT) slot = e.value;
        if (e.type == EV_ABS && e.code == ABS_MT_POSITION_X) { x = e.value; if (x < minx) minx = x; if (x > maxx) maxx = x; }
        if (e.type == EV_ABS && e.code == ABS_MT_POSITION_Y) { y = e.value; if (y < miny) miny = y; if (y > maxy) maxy = y; }
        if (e.type == EV_SYN && e.code == SYN_REPORT) { n++; if (n - last >= 15) { printf("slot%d x=%d y=%d\n", slot, x, y); last = n; fflush(stdout); } }
    }
    printf("frames=%d X=%d..%d Y=%d..%d\n", n, minx, maxx, miny, maxy);
    return 0;
}
