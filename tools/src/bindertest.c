// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * bindertest: minimal check of a binder driver (our out-of-tree module on old Kindle kernels).
 * Opens the device, checks the protocol version (7 = 32-bit ABI, what veradroid_kindle32 expects),
 * maps the receive buffer, becomes context manager, and does a full self transaction round trip:
 * a second process looks up handle 0 and sends a one-way transaction the first one receives.
 * Static, no Android libraries. Build: arm-linux-gnueabihf-gcc -static -O2 -mcpu=cortex-a9 bindertest.c
 *
 *   bindertest [/dev/vndbinder]
 */
/* Freestanding (no libc): the static glibc of our cross image crashes in its startup code on 3.0.35.
 * Build: arm-linux-gnueabihf-gcc -static -nostdlib -ffreestanding -fno-builtin -O2 -mcpu=cortex-a9 bindertest.c */
typedef unsigned int uint32_t; typedef int int32_t; typedef unsigned char uint8_t;
typedef unsigned int size_t; typedef unsigned int uintptr_t; typedef int pid_t;
#define NULL ((void *)0)
static long sc(long n, long a, long b, long c, long d, long e, long f)
{
    register long r7 __asm__("r7") = n; register long r0 __asm__("r0") = a; register long r1 __asm__("r1") = b;
    register long r2 __asm__("r2") = c; register long r3 __asm__("r3") = d; register long r4 __asm__("r4") = e;
    register long r5 __asm__("r5") = f;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r7), "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5) : "memory");
    return r0;
}
static int errno;
static long chk(long r) { if (r < 0 && r > -4096) { errno = -r; return -1; } return r; }
#define O_RDWR 2
#define O_CLOEXEC 02000000
#define PROT_READ 1
#define MAP_PRIVATE 2
#define MAP_NORESERVE 0x4000
#define MAP_FAILED ((void *)-1)
static int open(const char *p, int f) { return chk(sc(5, (long)p, f, 0, 0, 0, 0)); }
static int ioctl(int fd, unsigned long r, void *a) { return chk(sc(54, fd, r, (long)a, 0, 0, 0)); }
static void *mmap(void *a, size_t l, int p, int f, int fd, long o) { long r = sc(192, (long)a, l, p, f, fd, o >> 12); return (r < 0 && r > -4096) ? MAP_FAILED : (void *)r; }
static long write(int fd, const void *b, size_t n) { return sc(4, fd, (long)b, n, 0, 0, 0); }
static pid_t fork(void) { return sc(2, 0, 0, 0, 0, 0, 0); }
static void _exit(int c) { for (;;) sc(1, c, 0, 0, 0, 0, 0); }
static pid_t waitpid(pid_t p, int *st, int o) { return sc(114, p, (long)st, o, 0, 0, 0); }
static size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
static void *memset(void *d, int c, size_t n) { unsigned char *p = d; while (n--) *p++ = (unsigned char)c; return d; }
#define WIFEXITED(s) (((s) & 0x7f) == 0)
#define WEXITSTATUS(s) (((s) >> 8) & 0xff)
#define _IOC(d, t, n, s) (((d) << 30) | ((s) << 16) | ((t) << 8) | (n))
#define _IO(t, n) _IOC(0, t, n, 0)
#define _IOW(t, n, ty) _IOC(1, t, n, sizeof(ty))
#define _IOR(t, n, ty) _IOC(2, t, n, sizeof(ty))
#define _IOWR(t, n, ty) _IOC(3, t, n, sizeof(ty))
#define _IOC_SIZE(c) (((c) >> 16) & 0x3fff)
int main(int, char **);
__attribute__((naked, noreturn)) void _start(void)
{
    __asm__ volatile("ldr r0, [sp]\n add r1, sp, #4\n bl main\n mov r7, #1\n svc 0\n");
}

/* 32-bit binder ABI (protocol 7): pointers and sizes are 32 bits, as on these kernels */
typedef uint32_t binder_uintptr_t;
typedef uint32_t binder_size_t;
struct binder_write_read {
    binder_size_t write_size, write_consumed; binder_uintptr_t write_buffer;
    binder_size_t read_size, read_consumed; binder_uintptr_t read_buffer;
};
struct binder_version { int32_t protocol_version; };
struct binder_transaction_data {
    union { uint32_t handle; binder_uintptr_t ptr; } target;
    binder_uintptr_t cookie; uint32_t code; uint32_t flags;
    int32_t sender_pid; uint32_t sender_euid;
    binder_size_t data_size, offsets_size;
    union { struct { binder_uintptr_t buffer, offsets; } ptr; uint8_t buf[8]; } data;
};
#define B_IOWR(nr, t) _IOWR('b', nr, t)
#define B_IOW(nr, t)  _IOW('b', nr, t)
#define BINDER_WRITE_READ        B_IOWR(1, struct binder_write_read)
#define BINDER_SET_MAX_THREADS   B_IOW(5, uint32_t)
#define BINDER_SET_CONTEXT_MGR   B_IOW(7, int)
#define BINDER_VERSION           B_IOWR(9, struct binder_version)
#define BC_TRANSACTION   _IOW('c', 0, struct binder_transaction_data)
#define BC_ENTER_LOOPER  _IO('c', 12)
#define BR_TRANSACTION   _IOR('r', 2, struct binder_transaction_data)
#define BR_NOOP          _IO('r', 12)
#define TF_ONE_WAY 0x01


/* no stdio: the static glibc in our cross image crashes inside printf on the 3.0.35 kernel */
static void out(const char *s) { write(1, s, strlen(s)); }
static void outn(long v) { char b[24]; int i = 23; int neg = v < 0; unsigned long u = neg ? -v : v; b[i] = 0;
    do { b[--i] = '0' + u % 10; u /= 10; } while (u); if (neg) b[--i] = '-'; out(b + i); }

static int bwr(int fd, void *w, size_t wn, void *r, size_t rn, size_t *got)
{
    struct binder_write_read b = { wn, 0, (uintptr_t)w, rn, 0, (uintptr_t)r };
    int rc = ioctl(fd, BINDER_WRITE_READ, &b);
    if (got) *got = b.read_consumed;
    return rc;
}

int main(int argc, char **argv)
{
    const char *dev = argc > 1 ? argv[1] : "/dev/vndbinder";
    int fd = open(dev, O_RDWR | O_CLOEXEC);
    if (fd < 0) { out("FAIL open\n"); return 1; }
    struct binder_version v = { 0 };
    if (ioctl(fd, BINDER_VERSION, &v) < 0) { out("FAIL BINDER_VERSION errno="); outn(errno); out("\n"); return 1; }
    out("protocol version "); outn(v.protocol_version); out(v.protocol_version == 7 ? " (32-bit ABI, ok)\n" : " (UNEXPECTED)\n");
    void *map = mmap(NULL, 128 * 1024, PROT_READ, MAP_PRIVATE | MAP_NORESERVE, fd, 0);
    if (map == MAP_FAILED) { out("FAIL mmap errno="); outn(errno); out("\n"); return 1; }
    int zero = 0;
    if (ioctl(fd, BINDER_SET_CONTEXT_MGR, &zero) < 0) { out("FAIL SET_CONTEXT_MGR errno="); outn(errno); out("\n"); return 1; }
    out("context manager ok\n");

    pid_t c = fork();
    if (c == 0) {  /* client: one-way transaction to handle 0 with a 4-byte payload */
        int cfd = open(dev, O_RDWR | O_CLOEXEC);
        void *cm = mmap(NULL, 128 * 1024, PROT_READ, MAP_PRIVATE | MAP_NORESERVE, cfd, 0);
        if (cfd < 0 || cm == MAP_FAILED) _exit(2);
        uint32_t payload = 0x56444f4b;   /* "KODV" */
        struct { uint32_t cmd; struct binder_transaction_data t; } __attribute__((packed)) w;
        memset(&w, 0, sizeof(w));
        w.cmd = BC_TRANSACTION;
        w.t.target.handle = 0; w.t.code = 42; w.t.flags = TF_ONE_WAY;
        w.t.data_size = sizeof(payload); w.t.data.ptr.buffer = (uintptr_t)&payload;
        _exit(bwr(cfd, &w, sizeof(w), NULL, 0, NULL) < 0 ? 3 : 0);
    }
    uint32_t looper = BC_ENTER_LOOPER;
    bwr(fd, &looper, sizeof(looper), NULL, 0, NULL);
    uint32_t rb[64]; size_t got = 0; int ok = 0;
    for (int i = 0; i < 5 && !ok; i++) {
        if (bwr(fd, NULL, 0, rb, sizeof(rb), &got) < 0) { out("FAIL read errno="); outn(errno); out("\n"); break; }
        for (size_t off = 0; off + 4 <= got;) {
            uint32_t cmd = *(uint32_t *)((char *)rb + off); off += 4;
            if (cmd == BR_NOOP) continue;
            if (cmd == BR_TRANSACTION) {
                struct binder_transaction_data *t = (void *)((char *)rb + off);
                uint32_t val = *(uint32_t *)(uintptr_t)t->data.ptr.buffer;
                out("received transaction code="); outn(t->code); out(" size="); outn(t->data_size);
                out(val == 0x56444f4b ? " payload=ok from pid " : " payload=WRONG from pid "); outn(t->sender_pid); out("\n");
                ok = (t->code == 42 && val == 0x56444f4b);
                break;
            }
            off += _IOC_SIZE(cmd);
        }
    }
    int st = 0; waitpid(c, &st, 0);
    out("client exit "); outn(WIFEXITED(st) ? WEXITSTATUS(st) : -1); out("\n");
    out(ok ? "BINDER OK\n" : "BINDER FAIL\n");
    return ok ? 0 : 1;
}
