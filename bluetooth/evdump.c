// SPDX-License-Identifier: GPL-3.0-or-later
/* evdump NAME SECONDS: print EV_KEY events of the input device named NAME (no grab). */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    DIR *d = opendir("/sys/class/input"); struct dirent *e; char path[64] = "";
    while ((e = readdir(d))) { if (strncmp(e->d_name, "event", 5)) continue; char p[300], n[160] = ""; snprintf(p, sizeof p, "/sys/class/input/%s/device/name", e->d_name);
        FILE *f = fopen(p, "r"); if (!f) continue; fgets(n, sizeof n, f); fclose(f); n[strcspn(n, "\n")] = 0; if (!strcmp(n, argv[1])) snprintf(path, sizeof path, "/dev/input/%s", e->d_name); }
    if (!path[0]) { printf("no device %s\n", argv[1]); return 1; }
    int fd = open(path, O_RDONLY); printf("reading %s (%s)\n", path, argv[1]); fflush(stdout);
    time_t end = time(NULL) + atoi(argv[2]);
    while (time(NULL) < end) { struct pollfd p = { fd, POLLIN, 0 }; if (poll(&p, 1, 500) <= 0) continue;
        struct input_event ev; if (read(fd, &ev, sizeof ev) != sizeof ev) break;
        if (ev.type == EV_KEY) { printf("EV_KEY code=%d value=%d\n", ev.code, ev.value); fflush(stdout); } }
    return 0;
}
