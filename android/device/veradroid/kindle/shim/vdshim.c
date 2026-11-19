/*
 * VeraDroid shim: makes /dev/ashmem work on a kernel that has no ashmem driver.
 *
 * Many apps carry their own native code (their own sqlite CursorWindow, media code, ...) that opens /dev/ashmem
 * directly. The Kindle kernel has no such device, but memfd_create gives the same thing: an anonymous,
 * mmap-able, fd-passable memory region. This library is preloaded into every process (LD_PRELOAD exported by init);
 * it turns open("/dev/ashmem") into a memfd and answers the ashmem ioctls on those fds itself.
 * Everything else goes straight to the kernel untouched.
 *
 * Regions received from another process (binder fd passing) are recognised by their memfd name.
 * Pin/unpin (purgeable memory) always succeed with "not purged". Written for VeraDroid; Apache-2.0.
 *
 * The protection mask (ASHMEM_SET/GET_PROT_MASK) belongs to the region, not to the fd: Chromium makes a region
 * read-only (ReadOnlySharedMemoryRegion) and the process that receives it checks GET_PROT_MASK has no PROT_WRITE,
 * else CHECK-fails ("...has a wrong protection mask: it is not read-only but it should be", SIGTRAP). 番茄小说's own
 * WebView (libwebviewbytedance.so) died that way on every start, and the app then showed its own safe mode.
 * The mask is kept in the region's file mode, which every process holding the fd sees: S_ISVTX marks "mask set",
 * the "other" rwx bits are PROT_READ / PROT_WRITE / PROT_EXEC (memfd's default 0777 without S_ISVTX = rwx, as before).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef __NR_memfd_create
#define __NR_memfd_create 385   /* ARM EABI */
#endif
#define VD_MFD_CLOEXEC 1U
#define VD_O_LARGEFILE 0400000

#define ASHMEM_TYPE 0x77
#define MAXFD 8192
#define VD_PROT_ALL 7          /* PROT_READ | PROT_WRITE | PROT_EXEC */
#define VD_MASK_SET 01000      /* S_ISVTX on the region's file: the low 3 mode bits hold its prot mask */
/* version tag the host tests look for in the shipped binary */
__attribute__((used)) static const char vd_shim_tag[] = "vdshim: ashmem prot masks in the file mode";

/* one bit per fd: this fd is one of our fake ashmem regions */
static unsigned char fakefd[MAXFD / 8];
/* prot mask per fd, only for regions whose file mode we may not change (owned by another uid): 0 = not recorded */
static unsigned char fdprot[MAXFD];
static inline int is_fake(int fd) { return fd >= 0 && fd < MAXFD && (fakefd[fd >> 3] >> (fd & 7)) & 1; }
static inline void set_fake(int fd, int on)
{
    if (fd < 0 || fd >= MAXFD) return;
    if (on) fakefd[fd >> 3] |= (unsigned char)(1u << (fd & 7));
    else fakefd[fd >> 3] &= (unsigned char)~(1u << (fd & 7));
}

/*
 * The zygote must not hold any fd it does not know about when it forks (it checks /proc/self/fd and aborts on a
 * memfd), so inside the zygote itself /dev/ashmem stays "not found" like before. Apps are forked from it and renamed
 * (setArgV0) before any of their own code runs, so they get the working version.
 */
static int in_zygote(void)
{
    char buf[48];
    int fd = (int)syscall(__NR_openat, AT_FDCWD, "/proc/self/cmdline", O_RDONLY | VD_O_LARGEFILE, 0);
    if (fd < 0) return 0;
    ssize_t n = (ssize_t)syscall(__NR_read, fd, buf, sizeof(buf) - 1);
    syscall(__NR_close, fd);
    if (n <= 0) return 0;
    buf[n] = 0;
    return !strncmp(buf, "zygote", 6) || !strncmp(buf, "/system/bin/app_process", 23) || !strncmp(buf, "-Xzygote", 8);
}

static int open_ashmem(int flags)
{
    if (in_zygote()) { errno = ENOENT; return -1; }
    int fd = (int)syscall(__NR_memfd_create, "ashmem", VD_MFD_CLOEXEC);
    if (fd < 0 && errno == ENOSYS) {
        /* kernel < 3.17 (Kindle 3.0.35): unlinked file on the host-prepared tmpfs /dev/vdshm */
        static unsigned int seq;
        char path[64];
        for (int i = 0; i < 16 && fd < 0; i++) {
            snprintf(path, sizeof(path), "/dev/vdshm/s%d-%u-%d", getpid(), __sync_fetch_and_add(&seq, 1), i);
            fd = (int)syscall(__NR_openat, AT_FDCWD, path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW | VD_O_LARGEFILE, 0600);
            if (fd >= 0) syscall(__NR_unlinkat, AT_FDCWD, path, 0);
            else if (errno != EEXIST) break;
        }
    }
    if (fd >= 0) {
        if (flags & O_CLOEXEC) { /* memfd is already close-on-exec; callers that did not ask for it keep it anyway */ }
        set_fake(fd, 1);
    }
    return fd;
}

static int is_ashmem_path(const char *p) { return p && !strcmp(p, "/dev/ashmem"); }

static int do_openat(int dirfd, const char *path, int flags, mode_t mode)
{
    if (is_ashmem_path(path)) return open_ashmem(flags);
    return (int)syscall(__NR_openat, dirfd, path, flags | VD_O_LARGEFILE, mode);
}

int open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT | 020000000 /* O_TMPFILE */)) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
    return do_openat(AT_FDCWD, path, flags, mode);
}

int open64(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT | 020000000)) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
    return do_openat(AT_FDCWD, path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT | 020000000)) { va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap); }
    return do_openat(dirfd, path, flags, mode);
}

/* with _FORTIFY_SOURCE the compiler calls these instead of open()/openat() */
int __open_2(const char *path, int flags) { return do_openat(AT_FDCWD, path, flags, 0); }
int __openat_2(int dirfd, const char *path, int flags) { return do_openat(dirfd, path, flags, 0); }

int close(int fd)
{
    set_fake(fd, 0);
    if (fd >= 0 && fd < MAXFD) fdprot[fd] = 0;
    return (int)syscall(__NR_close, fd);
}

static void copy_prot(int from, int to)
{
    if (to >= 0 && to < MAXFD) fdprot[to] = (from >= 0 && from < MAXFD) ? fdprot[from] : 0;
}

int dup(int fd)
{
    int n = (int)syscall(__NR_dup, fd);
    if (n >= 0) { set_fake(n, is_fake(fd)); copy_prot(fd, n); }
    return n;
}

int dup2(int fd, int fd2)
{
    int n = (int)syscall(__NR_dup2, fd, fd2);
    if (n >= 0 && n != fd) { set_fake(n, is_fake(fd)); copy_prot(fd, n); }
    return n;
}

int dup3(int fd, int fd2, int flags)
{
    int n = (int)syscall(__NR_dup3, fd, fd2, flags);
    if (n >= 0) { set_fake(n, is_fake(fd)); copy_prot(fd, n); }
    return n;
}

/* the fd's target as /proc shows it, e.g. "/memfd:ashmem-1294 (deleted)"; "" on error */
static void fd_link(int fd, char *buf, size_t len)
{
    char p[32];
    snprintf(p, sizeof(p), "/proc/self/fd/%d", fd);
    ssize_t n = (ssize_t)syscall(__NR_readlinkat, AT_FDCWD, p, buf, len - 1);
    buf[n > 0 ? n : 0] = 0;
}

#define MEMFD_PFX "/memfd:ashmem"
#define DELETED_SFX " (deleted)"

/*
 * Is fd one of "our" ashmem regions? Those we opened ourselves are in the bitmap. Regions created in another process
 * (by this shim or by libcutils' ashmem_create_region, both memfds named "ashmem…") and received over binder, or
 * inherited / dup'd behind our back, are recognised by their /proc name and cached. Only called for ashmem-type ioctls.
 */
static int is_ashmem_fd(int fd)
{
    if (is_fake(fd)) return 1;
    if (fd < 0 || fd >= MAXFD) return 0;
    char l[300];
    fd_link(fd, l, sizeof(l));
    if (strncmp(l, MEMFD_PFX, sizeof(MEMFD_PFX) - 1) && strncmp(l, "/dev/vdshm/", 11)) return 0;
    set_fake(fd, 1);
    return 1;
}

/*
 * ASHMEM_SET_NAME: a memfd's name is fixed at creation, so while the region is still empty swap in a fresh memfd
 * called "ashmem-<name>" under the same fd number. Then every process the fd reaches reads the name back from /proc
 * (MMKV checks it against its mmapID). Best effort: on any problem the old unnamed region stays, as before.
 */
static int set_name(int fd, const char *name)
{
    char l[300], nm[256];
    struct stat st;
    if (!name) return 0;
    fd_link(fd, l, sizeof(l));
    if (strncmp(l, "/memfd:", 7)) return 0;                       /* /dev/vdshm fallback: no names */
    if (fstat(fd, &st) < 0 || st.st_size != 0) return 0;         /* real ashmem: EINVAL once mapped; keep data */
    snprintf(nm, sizeof(nm), "ashmem-%.200s", name);
    int n = (int)syscall(__NR_memfd_create, nm, VD_MFD_CLOEXEC);
    if (n < 0) return 0;
    int fl = (int)syscall(__NR_fcntl, fd, F_GETFD);
    if (fl >= 0) syscall(__NR_dup3, n, fd, (fl & FD_CLOEXEC) ? O_CLOEXEC : 0);
    syscall(__NR_close, n);
    return 0;
}

/* ASHMEM_GET_NAME: name from /proc (memfd "ashmem-<name>"); unnamed regions read "dev/ashmem" like the real driver */
static void get_name(int fd, char *out)
{
    char l[300];
    fd_link(fd, l, sizeof(l));
    size_t n = strlen(l), sl = sizeof(DELETED_SFX) - 1;
    if (n >= sl && !strcmp(l + n - sl, DELETED_SFX)) l[n -= sl] = 0;
    if (!strncmp(l, MEMFD_PFX "-", sizeof(MEMFD_PFX)) && l[sizeof(MEMFD_PFX)]) {
        snprintf(out, 256, "%s", l + sizeof(MEMFD_PFX));
        return;
    }
    strcpy(out, "dev/ashmem");
}

/* ASHMEM_GET_PROT_MASK: from the region's file mode (see the top), else what this process recorded, else rwx */
static int get_prot(int fd)
{
    struct stat st;
    if (fd >= 0 && fd < MAXFD && fdprot[fd]) return fdprot[fd] & VD_PROT_ALL;
    if (fstat(fd, &st) < 0) return -1;
    if (st.st_mode & VD_MASK_SET) return (int)(st.st_mode & VD_PROT_ALL);
    return VD_PROT_ALL;
}

/* ASHMEM_SET_PROT_MASK: like the driver, a mask can only lose bits (EINVAL otherwise). Kept in the file mode so the
 * processes the fd is sent to see it; if this process may not chmod the region, only this process remembers it. */
static int set_prot(int fd, unsigned long prot)
{
    struct stat st;
    int cur = get_prot(fd);
    if (cur < 0) return -1;
    if ((prot & ~(unsigned long)VD_PROT_ALL) || (prot & ~(unsigned long)cur)) { errno = EINVAL; return -1; }
    if (fstat(fd, &st) < 0) return -1;
    mode_t m = (st.st_mode & 0770) | VD_MASK_SET | (mode_t)prot;
    if ((int)syscall(__NR_fchmod, fd, m) == 0) {
        if (fd < MAXFD) fdprot[fd] = 0;
        return 0;
    }
    if (fd < MAXFD) { fdprot[fd] = (unsigned char)(0x80 | prot); return 0; }
    return -1;
}

int ioctl(int fd, int req, ...)
{
    va_list ap;
    va_start(ap, req);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    if ((((unsigned)req >> 8) & 0xff) == ASHMEM_TYPE && is_ashmem_fd(fd)) {
        switch ((unsigned)req & 0xff) {
        case 1: return set_name(fd, (const char *)arg);       /* SET_NAME */
        case 2: if (arg) get_name(fd, (char *)arg); return 0; /* GET_NAME */
        case 3: return (int)syscall(__NR_ftruncate, fd, (long)(size_t)arg) < 0 ? -1 : 0;   /* SET_SIZE */
        case 4: { struct stat st; if (fstat(fd, &st) < 0) return -1; return (int)st.st_size; }   /* GET_SIZE */
        case 5: return set_prot(fd, (unsigned long)(size_t)arg);   /* SET_PROT_MASK */
        case 6: return get_prot(fd);                        /* GET_PROT_MASK */
        case 7: return 0;                                   /* PIN */
        case 8: return 0;                                   /* UNPIN */
        case 9: return 0;                                   /* GET_PIN_STATUS: ASHMEM_IS_PINNED */
        case 10: return 0;                                  /* PURGE_ALL_CACHES */
        default: errno = ENOTTY; return -1;
        }
    }
    return (int)syscall(__NR_ioctl, fd, req, arg);
}
