/*
 * LD_PRELOAD shim for the native veradroid-input test (tests/vinput-test.sh): no real evdev / uinput needed.
 *
 *   VT_SRC=<path>   the touch "device" vinput opens (a FIFO the test writes struct input_event into). ioctls on it are
 *                   answered from VT_CAPS: B (goodix-ts gtx8: slots, tracking id, MT x/y, touch major, BTN_TOUCH),
 *                   A (MT x/y + touch major, no slots), AID (A + ABS_MT_TRACKING_ID), ST (ABS_X/ABS_Y + BTN_TOUCH).
 *                   VT_MAXX / VT_MAXY: the position ranges (default 1272 / 1696, one past the last pixel like fts_ts).
 *   VT_OUT=<dir>    /dev/input/uinput and /dev/uinput open <dir>/uinput0 (touch), uinput1 (keys), ... Every
 *                   struct input_event written there gets the CLOCK_MONOTONIC time of the write (latency check);
 *                   UI_SET_ABSBIT calls are listed in <dir>/uinputN.abs.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static int srcfd = -1, ufds[8], nufd = 0;
static int is_ufd(int fd) { for (int i = 0; i < nufd; i++) if (ufds[i] == fd) return i; return -1; }

static int do_open(const char *path, int flags, mode_t mode, int (*real)(const char *, int, ...))
{
    const char *out = getenv("VT_OUT"), *src = getenv("VT_SRC");
    if (out && (!strcmp(path, "/dev/input/uinput") || !strcmp(path, "/dev/uinput")) && nufd < 8) {
        char p[512];
        snprintf(p, sizeof(p), "%s/uinput%d", out, nufd);
        int fd = real(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) ufds[nufd++] = fd;
        return fd;
    }
    int fd = real(path, flags, mode);
    if (src && !strcmp(path, src)) srcfd = fd;
    return fd;
}
int open(const char *path, int flags, ...)
{
    static int (*real)(const char *, int, ...);
    if (!real) real = dlsym(RTLD_NEXT, "open");
    mode_t m = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); m = va_arg(ap, int); va_end(ap); }
    return do_open(path, flags, m, real);
}
int open64(const char *path, int flags, ...)
{
    static int (*real)(const char *, int, ...);
    if (!real) real = dlsym(RTLD_NEXT, "open64");
    mode_t m = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); m = va_arg(ap, int); va_end(ap); }
    return do_open(path, flags, m, real);
}

ssize_t write(int fd, const void *buf, size_t n)
{
    static ssize_t (*real)(int, const void *, size_t);
    if (!real) real = dlsym(RTLD_NEXT, "write");
    if (is_ufd(fd) >= 0 && n == sizeof(struct input_event)) {
        struct input_event e;
        memcpy(&e, buf, sizeof(e));
        struct timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        e.time.tv_sec = ts.tv_sec; e.time.tv_usec = ts.tv_nsec / 1000;
        return real(fd, &e, sizeof(e));
    }
    return real(fd, buf, n);
}

static void setbit(void *bits, int len, int b) { if (b / 8 < len) ((unsigned char *)bits)[b / 8] |= 1 << (b % 8); }

int ioctl(int fd, unsigned long req, ...)
{
    static int (*real)(int, unsigned long, ...);
    if (!real) real = dlsym(RTLD_NEXT, "ioctl");
    va_list ap; va_start(ap, req); void *arg = va_arg(ap, void *); va_end(ap);
    int u = is_ufd(fd);
    if (u >= 0) {
        if (req == UI_SET_ABSBIT) {
            char p[512]; snprintf(p, sizeof(p), "%s/uinput%d.abs", getenv("VT_OUT"), u);
            FILE *f = fopen(p, "a"); if (f) { fprintf(f, "%ld\n", (long)arg); fclose(f); }
        }
        return 0;
    }
    if (fd != srcfd || srcfd < 0) return real(fd, req, arg);
    const char *caps = getenv("VT_CAPS"); if (!caps) caps = "B";
    int st = !strcmp(caps, "ST"), b = !strcmp(caps, "B"), aid = !strcmp(caps, "AID");
    int maxx = getenv("VT_MAXX") ? atoi(getenv("VT_MAXX")) : 1272, maxy = getenv("VT_MAXY") ? atoi(getenv("VT_MAXY")) : 1696;
    int pres = getenv("VT_PRES") ? atoi(getenv("VT_PRES")) : 0;   /* > 0: the panel has ABS_MT_PRESSURE 0..VT_PRES */
    if (_IOC_TYPE(req) == 'E' && _IOC_NR(req) == 0x90) return 0;                 /* EVIOCGRAB */
    if (_IOC_TYPE(req) == 'E' && _IOC_NR(req) >= 0x20 && _IOC_NR(req) < 0x40) {  /* EVIOCGBIT(ev, len) */
        int ev = _IOC_NR(req) - 0x20, len = _IOC_SIZE(req);
        memset(arg, 0, len);
        if (ev == EV_KEY) { setbit(arg, len, BTN_TOUCH); setbit(arg, len, BTN_TOOL_FINGER); }
        if (ev == EV_ABS) {
            if (st) { setbit(arg, len, ABS_X); setbit(arg, len, ABS_Y); }
            else {
                setbit(arg, len, ABS_MT_POSITION_X); setbit(arg, len, ABS_MT_POSITION_Y); setbit(arg, len, ABS_MT_TOUCH_MAJOR);
                if (b) { setbit(arg, len, ABS_MT_SLOT); setbit(arg, len, ABS_X); setbit(arg, len, ABS_Y); }
                if (b || aid) setbit(arg, len, ABS_MT_TRACKING_ID);
                if (pres) setbit(arg, len, ABS_MT_PRESSURE);
            }
        }
        return len;
    }
    if (_IOC_TYPE(req) == 'E' && _IOC_NR(req) >= 0x40 && _IOC_NR(req) < 0x40 + ABS_CNT) {   /* EVIOCGABS(code) */
        int c = _IOC_NR(req) - 0x40;
        struct input_absinfo *ai = arg;
        memset(ai, 0, sizeof(*ai));
        int ok = 0;
        if (st) {
            if (c == ABS_X) { ai->maximum = maxx; ok = 1; }
            if (c == ABS_Y) { ai->maximum = maxy; ok = 1; }
        } else {
            if (c == ABS_MT_POSITION_X || (b && c == ABS_X)) { ai->maximum = maxx; ok = 1; }
            if (c == ABS_MT_POSITION_Y || (b && c == ABS_Y)) { ai->maximum = maxy; ok = 1; }
            if (c == ABS_MT_TOUCH_MAJOR) { ai->maximum = 255; ok = 1; }
            if (b && c == ABS_MT_SLOT) { ai->maximum = 9; ok = 1; }
            if ((b || aid) && c == ABS_MT_TRACKING_ID) { ai->maximum = 65535; ok = 1; }
            if (pres && c == ABS_MT_PRESSURE) { ai->maximum = pres; ok = 1; }
        }
        if (!ok) { errno = EINVAL; return -1; }
        return 0;
    }
    errno = ENOTTY;
    return -1;
}
