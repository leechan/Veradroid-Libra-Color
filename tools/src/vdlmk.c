// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * vdlmk: set Android 7.1 lmkd's kill thresholds from the host.
 *
 * ActivityManager picks lmkd's minfree table by RAM *and* screen size; the Kindle's large e-ink screen
 * selects the big-phone table, so on 512 MB Kindles the foreground app is killed whenever file cache drops
 * below 72 MB (KT5 emulator: WeChat Read killed at adj 0 every ~12 s, endless restart loop).
 * This sends lmkd the same LMK_TARGET command ActivityManager sends at startup, with smaller values.
 *
 *   vdlmk <lmkd socket> <minfree_pages>:<oom_adj> ...    (at most 6 pairs)
 *   e.g. vdlmk /proc/<init pid>/root/dev/socket/lmkd 2048:0 3072:100 4096:200 5120:300 6144:900 8192:906
 *
 * lmkd keeps one control connection, so this briefly replaces ActivityManager's; AM reconnects on its next
 * write (ProcessList.writeLmkd retries) and only re-sends targets on a configuration change.
 * Build static with the legacy cross image so it runs on every Kindle kernel:
 *   arm-linux-gnueabihf-gcc -std=gnu11 -O2 -static -mcpu=cortex-a9 vdlmk.c -o vdlmk
 */
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define LMK_TARGET 0
#define MAX_TARGETS 6

int main(int argc, char **argv)
{
    if (argc < 3 || argc - 2 > MAX_TARGETS) {
        fprintf(stderr, "usage: %s <lmkd socket> <minfree_pages>:<oom_adj> ... (1-%d pairs)\n", argv[0], MAX_TARGETS);
        return 2;
    }
    int buf[1 + 2 * MAX_TARGETS], n = 0;
    buf[n++] = htonl(LMK_TARGET);
    for (int i = 2; i < argc; i++) {
        char *colon = strchr(argv[i], ':');
        if (!colon) { fprintf(stderr, "bad pair %s\n", argv[i]); return 2; }
        long pages = strtol(argv[i], NULL, 10), adj = strtol(colon + 1, NULL, 10);
        if (pages <= 0 || pages > 262144 || adj < -1000 || adj > 1000) { fprintf(stderr, "bad pair %s\n", argv[i]); return 2; }
        buf[n++] = htonl((int)pages);
        buf[n++] = htonl((int)adj);
    }
    int fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    if (fd < 0) { perror("socket"); return 1; }
    struct sockaddr_un a;
    memset(&a, 0, sizeof(a));
    a.sun_family = AF_UNIX;
    if (strlen(argv[1]) >= sizeof(a.sun_path)) { fprintf(stderr, "socket path too long\n"); return 2; }
    strcpy(a.sun_path, argv[1]);
    if (connect(fd, (struct sockaddr *)&a, sizeof(a)) < 0) { perror("connect"); return 1; }
    ssize_t w = write(fd, buf, n * sizeof(int));
    if (w != (ssize_t)(n * sizeof(int))) { perror("write"); return 1; }
    usleep(200000);   /* let lmkd read it before we disconnect */
    close(fd);
    printf("lmkd targets set (%d)\n", (argc - 2));
    return 0;
}
