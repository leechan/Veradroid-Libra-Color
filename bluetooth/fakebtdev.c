// SPDX-License-Identifier: GPL-3.0-or-later
/* fakebtdev: emulator test helper for the pairing tests (fakebtfd.sh). Creates a uinput device that looks like a
 * Bluetooth HID device (bus BUS_BLUETOOTH, the name the Kindle would give it) and stays until SIGTERM; key codes
 * written to the FIFO (one decimal code per line) are typed as press + release.
 *   fakebtdev pt|kbd <name> <fifo>          (pt: page-turner keys only; kbd: full keyboard)
 * Build: arm-linux-gnueabihf-gcc -static -O2 -o fakebtdev fakebtdev.c */
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

static volatile sig_atomic_t quit;
static void on_term(int s) { (void)s; quit = 1; }
static void ev(int fd, int t, int c, int v) {
    struct input_event e; memset(&e, 0, sizeof e); e.type = t; e.code = c; e.value = v;
    if (write(fd, &e, sizeof e) < 0) perror("write");
}

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: fakebtdev pt|kbd <name> <fifo>\n"); return 2; }
    int kbd = !strcmp(argv[1], "kbd");
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK); if (fd < 0) fd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("uinput"); return 1; }
    ioctl(fd, UI_SET_EVBIT, EV_KEY); ioctl(fd, UI_SET_EVBIT, EV_SYN);
    if (kbd) { ioctl(fd, UI_SET_EVBIT, EV_REP); for (int k = 1; k < 128; k++) ioctl(fd, UI_SET_KEYBIT, k); }
    else {
        int ks[] = { KEY_PAGEUP, KEY_PAGEDOWN, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_VOLUMEUP, KEY_VOLUMEDOWN,
                     KEY_NEXTSONG, KEY_PREVIOUSSONG, KEY_PLAYPAUSE };
        for (unsigned i = 0; i < sizeof ks / sizeof ks[0]; i++) ioctl(fd, UI_SET_KEYBIT, ks[i]);
    }
    struct uinput_user_dev u; memset(&u, 0, sizeof u);
    snprintf(u.name, sizeof u.name, "%s", argv[2]);
    u.id.bustype = BUS_BLUETOOTH; u.id.vendor = 0x248a; u.id.product = kbd ? 0x8266 : 0x8255; u.id.version = 1;
    if (write(fd, &u, sizeof u) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) { perror("create"); return 1; }
    struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = on_term;
    sigaction(SIGTERM, &sa, NULL); sigaction(SIGINT, &sa, NULL);
    mkfifo(argv[3], 0666);
    int in = open(argv[3], O_RDWR);        /* RDWR: never sees EOF when a writer goes away */
    if (in < 0) { perror("fifo"); ioctl(fd, UI_DEV_DESTROY); return 1; }
    printf("created %s\n", u.name); fflush(stdout);
    char buf[256]; size_t have = 0;
    while (!quit) {
        ssize_t r = read(in, buf + have, sizeof buf - 1 - have);
        if (r < 0) { if (errno == EINTR) continue; break; }
        have += r; buf[have] = 0;
        char *nl;
        while ((nl = strchr(buf, '\n'))) {
            *nl = 0;
            int c = atoi(buf);
            if (c > 0 && c < KEY_CNT) {
                ev(fd, EV_KEY, c, 1); ev(fd, EV_SYN, 0, 0); usleep(80000);
                ev(fd, EV_KEY, c, 0); ev(fd, EV_SYN, 0, 0); usleep(300000);
                printf("sent %d\n", c); fflush(stdout);
            }
            size_t rest = have - (nl + 1 - buf);
            memmove(buf, nl + 1, rest); have = rest; buf[have] = 0;
        }
        if (have >= sizeof buf - 1) have = 0;
    }
    ioctl(fd, UI_DEV_DESTROY);
    printf("destroyed\n");
    return 0;
}
