// SPDX-License-Identifier: GPL-3.0-or-later
/* vdshutwatch: wait (without polling) until the Kindle starts shutting down or rebooting,
 * then exec the given command (VeraDroid: sh stop.sh --shutdown).
 *
 * /etc/upstart/shutdown.conf writes /tmp/shutdown_in_progress as its first step, before it
 * stops the framework and long before it unmounts the user store. If VeraDroid still holds
 * /mnt/base-us at that point (loop system image, open files), "umount /mnt/base-us" fails
 * with EBUSY and the user store is left dirty (reproduced in eink-emulator, kt6-5192).
 *
 * usage: vdshutwatch command [args...]
 * Static armhf build: arm-linux-gnueabihf-gcc -O2 -static -o vdshutwatch vdshutwatch.c
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/inotify.h>
#include <unistd.h>

#define DIR_ "/tmp"
#define NAME "shutdown_in_progress"

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s command [args...]\n", argv[0]);
        return 2;
    }
    int fd = inotify_init();
    if (fd < 0) { perror("inotify_init"); return 1; }
    if (inotify_add_watch(fd, DIR_, IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE) < 0) {
        perror("inotify_add_watch " DIR_);
        return 1;
    }
    if (access(DIR_ "/" NAME, F_OK) != 0) {
        char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
        for (;;) {
            ssize_t n = read(fd, buf, sizeof buf);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) { perror("read"); return 1; }
            int hit = 0;
            for (char *p = buf; p < buf + n;) {
                struct inotify_event *e = (struct inotify_event *)p;
                if (e->len && strcmp(e->name, NAME) == 0) hit = 1;
                p += sizeof(*e) + e->len;
            }
            if (hit) break;
        }
    }
    close(fd);
    execvp(argv[1], argv + 1);
    perror("execvp");
    return 127;
}
