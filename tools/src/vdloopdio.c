/* vdloopdio: switch a loop device to direct I/O (LOOP_SET_DIRECT_IO, Linux >= 4.4) or back.
 *   vdloopdio <loopdev> 1|0         exit 0 = done, 2 = kernel refused (EINVAL: no dio support / unaligned backing),
 *                                   1 = usage / open error. Prints nothing on success.
 *   vdloopdio --drop <file>...      posix_fadvise(DONTNEED) on each file / block device: drops its clean, unmapped
 *                                   page cache (dirty pages are queued for writeback, never discarded). For kernels
 *                                   without loop direct I/O (4.1 / 3.0), where the only way to stop the duplicate
 *                                   copies piling up is to drop them now and then.
 * Why (docs/pw5-perf.md): on the 512 MB Kindles the Android system image is ext4 on a loop device whose backing file
 * sits on the vfat userstore, itself a loop device over the eMMC partition. Buffered loop I/O keeps every page of
 * Android's code up to three times in the page cache (ext4 file, vfat file, block device under the userstore loop).
 * busybox losetup has no --direct-io, so the host sets the flag with this. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#ifndef LOOP_SET_DIRECT_IO
#define LOOP_SET_DIRECT_IO 0x4C08
#endif
int main(int argc, char **argv)
{
    if (argc >= 3 && strcmp(argv[1], "--drop") == 0) {
        int rc = 0;
        for (int i = 2; i < argc; i++) {
            int fd = open(argv[i], O_RDONLY);
            if (fd < 0) { fprintf(stderr, "%s: %s\n", argv[i], strerror(errno)); rc = 1; continue; }
            int e = posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED);
            if (e) { fprintf(stderr, "%s: fadvise: %s\n", argv[i], strerror(e)); rc = 1; }
            close(fd);
        }
        return rc;
    }
    if (argc != 3 || (argv[2][0] != '0' && argv[2][0] != '1')) {
        fprintf(stderr, "usage: %s <loopdev> 1|0 | --drop <file>...\n", argv[0]);
        return 1;
    }
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) { fprintf(stderr, "%s: %s\n", argv[1], strerror(errno)); return 1; }
    if (ioctl(fd, LOOP_SET_DIRECT_IO, (unsigned long)(argv[2][0] == '1')) < 0) {
        fprintf(stderr, "%s: LOOP_SET_DIRECT_IO: %s\n", argv[1], strerror(errno));
        close(fd);
        return 2;
    }
    close(fd);
    return 0;
}
