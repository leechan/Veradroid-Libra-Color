// SPDX-License-Identifier: GPL-3.0-or-later
/* fakebt: QEMU test helper. Creates a uinput device that looks like a Bluetooth HID device (bus BUS_BLUETOOTH)
 * and types a key sequence.  fakebt pt|kbd <hold-seconds> [code ...]   (pt: page turner keys; kbd: full keyboard) */
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static void ev(int fd, int t, int c, int v) { struct input_event e; memset(&e, 0, sizeof e); e.type = t; e.code = c; e.value = v; write(fd, &e, sizeof e); }
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    int kbd = !strcmp(argv[1], "kbd");
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK); if (fd < 0) fd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("uinput"); return 1; }
    ioctl(fd, UI_SET_EVBIT, EV_KEY); ioctl(fd, UI_SET_EVBIT, EV_SYN);
    if (kbd) { ioctl(fd, UI_SET_EVBIT, EV_REP); for (int k = 1; k < 128; k++) ioctl(fd, UI_SET_KEYBIT, k); }
    else { int ks[] = { KEY_PAGEUP, KEY_PAGEDOWN, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_NEXTSONG, KEY_PREVIOUSSONG, KEY_PLAYPAUSE };
           for (unsigned i = 0; i < sizeof ks / sizeof ks[0]; i++) ioctl(fd, UI_SET_KEYBIT, ks[i]); }
    struct uinput_user_dev u; memset(&u, 0, sizeof u);
    snprintf(u.name, sizeof u.name, kbd ? "Fake BT Keyboard" : "Fake BT Page Turner");
    u.id.bustype = BUS_BLUETOOTH; u.id.vendor = 0x248a; u.id.product = kbd ? 0x8266 : 0x8255; u.id.version = 1;
    write(fd, &u, sizeof u);
    if (ioctl(fd, UI_DEV_CREATE) < 0) { perror("create"); return 1; }
    printf("created %s\n", u.name); fflush(stdout);
    sleep(2);
    for (int i = 3; i < argc; i++) {
        int c = atoi(argv[i]);
        ev(fd, EV_KEY, c, 1); ev(fd, EV_SYN, 0, 0); usleep(80000);
        ev(fd, EV_KEY, c, 0); ev(fd, EV_SYN, 0, 0); usleep(700000);
        printf("sent %d\n", c); fflush(stdout);
    }
    sleep(atoi(argv[2]));
    ioctl(fd, UI_DEV_DESTROY);
    printf("destroyed\n");
    return 0;
}
