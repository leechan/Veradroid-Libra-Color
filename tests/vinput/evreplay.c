/*
 * On-device replay for veradroid-input (tests/vinput/emu-replay.sh): a uinput touch screen that speaks a chosen
 * multitouch protocol, fed with the same synthetic gestures as the native test (tests/vinput/run.py), plus an evdev
 * dumper with time stamps for the virtual touch screen / keys that veradroid-input creates.
 *   evreplay src B|A|AID|ST NAME   creates "NAME" (1272x1696 like fts_ts / the PW5 panel), then reads scenario names
 *                                  from stdin, one per line, and plays each one ("quit" or EOF ends)
 *   evreplay dump /dev/input/eventN   prints "sec.usec type code value" for every event until killed
 * Build (armhf, static): arm-linux-gnueabihf-gcc -O2 -static tests/vinput/evreplay.c -o evreplay
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int fd, proto;   /* 0 B, 1 A, 2 AID, 3 ST */
static void ev(int t, int c, int v) { struct input_event e; memset(&e, 0, sizeof(e)); e.type = t; e.code = c; e.value = v; if (write(fd, &e, sizeof(e)) < 0) perror("write"); }

/* one frame: n fingers (id, x, y); the encoder keeps what the previous frame had, like a driver + input core */
static int pn, pid_[4], px[4], py[4], btn, nfr;
static void frame(int n, const int *id, const int *x, const int *y)
{
    nfr++;
    if (proto == 0) {
        for (int s = 0; s < 4; s++) {
            int was = -1, now = -1;
            for (int i = 0; i < pn; i++) if (pid_[i] == s) was = i;
            for (int i = 0; i < n; i++) if (id[i] == s) now = i;
            if (was >= 0 && now < 0) { ev(EV_ABS, ABS_MT_SLOT, s); ev(EV_ABS, ABS_MT_TRACKING_ID, -1); }
            if (now >= 0) {
                ev(EV_ABS, ABS_MT_SLOT, s);
                if (was < 0) ev(EV_ABS, ABS_MT_TRACKING_ID, s);   /* goodix gtx8: tracking id = slot */
                ev(EV_ABS, ABS_MT_POSITION_X, x[now]); ev(EV_ABS, ABS_MT_POSITION_Y, y[now]);
                if (was < 0) ev(EV_ABS, ABS_MT_TOUCH_MAJOR, 30);
            }
        }
    } else if (proto <= 2) {
        for (int k = 0; k < n; k++) {
            int i = nfr % 2 ? k : n - 1 - k;                      /* contacts in a different order every other frame */
            if (proto == 2) ev(EV_ABS, ABS_MT_TRACKING_ID, 100 + id[i]);
            ev(EV_ABS, ABS_MT_POSITION_X, x[i]); ev(EV_ABS, ABS_MT_POSITION_Y, y[i]); ev(EV_ABS, ABS_MT_TOUCH_MAJOR, 30);
            ev(EV_SYN, SYN_MT_REPORT, 0);
        }
        if (!n) ev(EV_SYN, SYN_MT_REPORT, 0);
    } else if (n) { ev(EV_ABS, ABS_X, x[0]); ev(EV_ABS, ABS_Y, y[0]); }
    if (n && !btn) ev(EV_KEY, BTN_TOUCH, 1);
    if (!n && btn) ev(EV_KEY, BTN_TOUCH, 0);
    btn = n > 0;
    ev(EV_SYN, SYN_REPORT, 0);
    pn = n; for (int i = 0; i < n; i++) { pid_[i] = id[i]; px[i] = x[i]; py[i] = y[i]; }
}
static void ms(int m) { usleep(m * 1000); }
static void one(int x, int y) { int id = 0; frame(1, &id, &x, &y); }
static void two(int x0, int y0, int x1, int y1) { int id[2] = { 0, 1 }, x[2] = { x0, x1 }, y[2] = { y0, y1 }; frame(2, id, x, y); }
static void up(void) { frame(0, NULL, NULL, NULL); }
static void line1(int x1, int y1, int x2, int y2, int dur, int steps)
{
    for (int i = 0; i <= steps; i++) { one(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps); if (i < steps) ms(dur / steps); }
    ms(20); up();
}

static void play(const char *s)
{
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    printf("start %s %ld.%06ld\n", s, (long)ts.tv_sec, ts.tv_nsec / 1000); fflush(stdout);
    if (!strcmp(s, "tap")) { one(500, 800); ms(60); up(); }
    else if (!strcmp(s, "swipe")) line1(900, 800, 200, 820, 300, 12);
    else if (!strcmp(s, "edge_back")) line1(636, 1680, 636, 1450, 80, 4);
    else if (!strcmp(s, "edge_panel")) line1(636, 10, 636, 300, 150, 6);
    else if (!strcmp(s, "corner")) { for (int t = 0; t < 2400; t += 200) { one(50, 140); ms(200); } up(); }
    else if (!strcmp(s, "two_tap")) { two(400, 800, 800, 800); ms(80); two(401, 800, 800, 801); ms(70); up(); }
    else if (!strcmp(s, "two_long")) { for (int t = 0; t < 2400; t += 200) { two(400, 800, 800, 800); ms(200); } up(); }
    else if (!strcmp(s, "two_back")) { for (int i = 0; i <= 10; i++) { two(300 + 50 * i, 800, 300 + 50 * i, 1000); ms(20); } up(); }
    else if (!strcmp(s, "two_light")) { for (int i = 0; i <= 10; i++) { two(300, 1200 - 50 * i, 400, 1200 - 50 * i); ms(20); } up(); }
    else if (!strcmp(s, "two_warmth")) { for (int i = 0; i <= 10; i++) { two(900, 600 + 50 * i, 1000, 600 + 50 * i); ms(20); } up(); }
    else { fprintf(stderr, "unknown scenario %s\n", s); return; }
    printf("played %s\n", s); fflush(stdout);
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "dump")) {
        int d = open(argv[2], O_RDONLY);
        if (d < 0) { perror(argv[2]); return 1; }
        struct input_event e;
        setvbuf(stdout, NULL, _IOLBF, 0);
        while (read(d, &e, sizeof(e)) == sizeof(e)) {
            struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
            printf("%ld.%06ld %d %d %d\n", (long)ts.tv_sec, ts.tv_nsec / 1000, e.type, e.code, e.value);
        }
        return 0;
    }
    if (argc != 4 || strcmp(argv[1], "src")) { fprintf(stderr, "usage: evreplay src B|A|AID|ST NAME | dump DEV\n"); return 2; }
    proto = !strcmp(argv[2], "A") ? 1 : !strcmp(argv[2], "AID") ? 2 : !strcmp(argv[2], "ST") ? 3 : 0;
    fd = open("/dev/uinput", O_WRONLY); if (fd < 0) fd = open("/dev/input/uinput", O_WRONLY);
    if (fd < 0) { perror("uinput"); return 1; }
    struct uinput_user_dev u; memset(&u, 0, sizeof(u));
    snprintf(u.name, sizeof(u.name), "%s", argv[3]);
    u.id.bustype = BUS_VIRTUAL; u.id.vendor = 0x1d6b; u.id.product = 0x0100 + proto;
    ioctl(fd, UI_SET_EVBIT, EV_SYN); ioctl(fd, UI_SET_EVBIT, EV_KEY); ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ioctl(fd, UI_SET_KEYBIT, BTN_TOUCH); ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT);
#define AX(c, lo, hi) do { ioctl(fd, UI_SET_ABSBIT, c); u.absmin[c] = lo; u.absmax[c] = hi; } while (0)
    if (proto == 3) { AX(ABS_X, 0, 1272); AX(ABS_Y, 0, 1696); }
    else {
        AX(ABS_MT_POSITION_X, 0, 1272); AX(ABS_MT_POSITION_Y, 0, 1696); AX(ABS_MT_TOUCH_MAJOR, 0, 255);
        if (proto == 0) { AX(ABS_MT_SLOT, 0, 9); AX(ABS_MT_TRACKING_ID, 0, 65535); }
        if (proto == 2) AX(ABS_MT_TRACKING_ID, 0, 65535);
    }
    if (write(fd, &u, sizeof(u)) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) { perror("create"); return 1; }
    printf("created %s proto %s\n", argv[3], argv[2]); fflush(stdout);
    char line[64];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!strcmp(line, "quit")) break;
        if (line[0]) play(line);
    }
    ioctl(fd, UI_DEV_DESTROY);
    return 0;
}
