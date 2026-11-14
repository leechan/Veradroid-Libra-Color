// SPDX-License-Identifier: GPL-3.0-or-later
/* absinfo <evdev>: print the axis ranges, resolution and name of an input device (what the driver reports) */
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
int main(int argc, char **argv)
{
    int fd = open(argc > 1 ? argv[1] : "/dev/input/event1", O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }
    char name[128] = "";
    ioctl(fd, EVIOCGNAME(sizeof(name)), name);
    struct input_id id; ioctl(fd, EVIOCGID, &id);
    printf("name=%s bus=%x vendor=%x product=%x version=%x\n", name, id.bustype, id.vendor, id.product, id.version);
    unsigned char prop[8] = {0}; ioctl(fd, EVIOCGPROP(sizeof(prop)), prop); printf("props=%02x\n", prop[0]);
    for (int c = 0; c < 0x40; c++) {
        struct input_absinfo a;
        if (ioctl(fd, EVIOCGABS(c), &a) == 0 && (a.maximum || a.minimum || a.resolution))
            printf("abs 0x%02x: min=%d max=%d fuzz=%d flat=%d res=%d value=%d\n", c, a.minimum, a.maximum, a.fuzz, a.flat, a.resolution, a.value);
    }
    return 0;
}
