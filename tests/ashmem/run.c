/* Host test of android/device/veradroid/kindle/shim/vdshim.c: ashmem protection masks (tests/ashmem-prot-test.sh).
 * Linked together with the shim, so open("/dev/ashmem") / ioctl() / dup() below are the shim's. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#define A_SET_SIZE _IOW(0x77, 3, size_t)
#define A_SET_PROT _IOW(0x77, 5, unsigned long)
#define A_GET_PROT _IO(0x77, 6)

static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); fails++; } } while (0)

static int region(void)
{
    int fd = open("/dev/ashmem", O_RDWR | O_CLOEXEC);
    if (fd < 0 || ioctl(fd, A_SET_SIZE, (size_t)4096) < 0) { perror("ashmem"); exit(2); }
    return fd;
}

static void send_fd(int s, int fd)
{
    char c = 0, buf[CMSG_SPACE(sizeof(int))];
    struct iovec io = { &c, 1 };
    struct msghdr m = { .msg_iov = &io, .msg_iovlen = 1, .msg_control = buf, .msg_controllen = sizeof(buf) };
    struct cmsghdr *h = CMSG_FIRSTHDR(&m);
    h->cmsg_level = SOL_SOCKET; h->cmsg_type = SCM_RIGHTS; h->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(h), &fd, sizeof(int));
    if (sendmsg(s, &m, 0) != 1) { perror("sendmsg"); exit(2); }
}

static int recv_fd(int s)
{
    char c, buf[CMSG_SPACE(sizeof(int))];
    struct iovec io = { &c, 1 };
    struct msghdr m = { .msg_iov = &io, .msg_iovlen = 1, .msg_control = buf, .msg_controllen = sizeof(buf) };
    int fd = -1;
    if (recvmsg(s, &m, 0) != 1) { perror("recvmsg"); exit(2); }
    memcpy(&fd, CMSG_DATA(CMSG_FIRSTHDR(&m)), sizeof(int));
    return fd;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "recv")) {      /* a fresh process (exec'd): knows nothing about the regions */
        int s = atoi(argv[2]);
        int ro = recv_fd(s), rw = recv_fd(s);
        CHECK(ioctl(ro, A_GET_PROT) == PROT_READ, "receiver: read-only region reads %d", ioctl(ro, A_GET_PROT));
        CHECK(ioctl(rw, A_GET_PROT) == (PROT_READ | PROT_WRITE | PROT_EXEC), "receiver: untouched region reads %d", ioctl(rw, A_GET_PROT));
        CHECK(ioctl(ro, A_SET_PROT, (unsigned long)(PROT_READ | PROT_WRITE)) < 0 && errno == EINVAL, "receiver: write bit could be added back");
        void *p = mmap(NULL, 4096, PROT_READ, MAP_SHARED, ro, 0);
        CHECK(p != MAP_FAILED && ((char *)p)[0] == 'x', "receiver: read-only mapping does not show the data");
        return fails ? 1 : 0;
    }

    int a = region();
    CHECK(ioctl(a, A_GET_PROT) == (PROT_READ | PROT_WRITE | PROT_EXEC), "new region: mask %d, want rwx", ioctl(a, A_GET_PROT));
    char *w = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, a, 0);
    CHECK(w != MAP_FAILED, "writable mapping before the mask"); if (w != MAP_FAILED) w[0] = 'x';
    /* Chromium's ReadOnlySharedMemoryRegion::ConvertToReadOnly, then PlatformSharedMemoryRegion::Take checks it */
    CHECK(ioctl(a, A_SET_PROT, (unsigned long)PROT_READ) == 0, "set PROT_READ: %s", strerror(errno));
    CHECK(ioctl(a, A_GET_PROT) == PROT_READ, "after PROT_READ: mask %d", ioctl(a, A_GET_PROT));
    errno = 0;
    CHECK(ioctl(a, A_SET_PROT, (unsigned long)(PROT_READ | PROT_WRITE)) < 0 && errno == EINVAL, "mask grew back (errno %d)", errno);
    CHECK(ioctl(a, A_SET_PROT, (unsigned long)8) < 0 && errno == EINVAL, "unknown prot bit accepted");
    int d = dup(a);
    CHECK(ioctl(d, A_GET_PROT) == PROT_READ, "dup'd fd: mask %d", ioctl(d, A_GET_PROT));
    int b = region();
    CHECK(ioctl(b, A_GET_PROT) == (PROT_READ | PROT_WRITE | PROT_EXEC), "second region inherited the mask: %d", ioctl(b, A_GET_PROT));
    CHECK(ioctl(b, A_SET_PROT, (unsigned long)0) == 0 && ioctl(b, A_GET_PROT) == 0, "PROT_NONE mask");
    close(b);
    int c = region();                                   /* same fd number as b: nothing left over from it */
    CHECK(ioctl(c, A_GET_PROT) == (PROT_READ | PROT_WRITE | PROT_EXEC), "reused fd number: mask %d", ioctl(c, A_GET_PROT));

    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) { perror("socketpair"); return 2; }
    pid_t pid = fork();
    if (pid == 0) {
        char n[16]; snprintf(n, sizeof(n), "%d", sv[1]);
        close(sv[0]);
        execl("/proc/self/exe", argv[0], "recv", n, (char *)NULL);
        _exit(3);
    }
    close(sv[1]);
    send_fd(sv[0], a); send_fd(sv[0], c);
    int st = 0;
    waitpid(pid, &st, 0);
    CHECK(WIFEXITED(st) && WEXITSTATUS(st) == 0, "receiver process failed (status %d)", st);
    if (!fails) printf("ashmem prot: ok\n");
    return fails ? 1 : 0;
}
