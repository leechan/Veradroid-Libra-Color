// SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
/*
 * pivot_init <newroot> <put_old> <command> [args...]
 * Switch the mount namespace's root to <newroot> (which must be a mount point), detach the old root and exec the command
 * (Android's /init --second-stage). Static so it keeps working after the old root is gone.
 * VeraDroid, GPL-3.0-or-later or Apache-2.0 at your choice (original code, no third-party parts).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef MNT_DETACH
#define MNT_DETACH 2
#endif

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: %s <newroot> <put_old> <cmd> [args...]\n", argv[0]); return 2; }
    const char *newroot = argv[1], *put_old = argv[2];
    if (chdir(newroot) < 0) { perror("pivot_init: chdir newroot"); return 1; }
    if (syscall(SYS_pivot_root, ".", put_old) < 0) { perror("pivot_init: pivot_root"); return 1; }
    if (chdir("/") < 0) { perror("pivot_init: chdir /"); return 1; }
    char path[256];
    snprintf(path, sizeof(path), "/%s", put_old);
    if (umount2(path, MNT_DETACH) < 0) { perror("pivot_init: umount old root"); return 1; }
    execv(argv[3], &argv[3]);
    perror("pivot_init: exec");
    return 127;
}
