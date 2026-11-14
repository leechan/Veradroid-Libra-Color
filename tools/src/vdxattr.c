// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * vdxattr: give Android app-data directories an SELinux label so installd stops wiping them.
 *
 * The container runs with SELinux not loaded, so the directories under /data/data have no
 * "security.selinux" xattr. installd's create_app_data() calls getfilecon() on them, gets ENODATA
 * and fails; for *system* apps (VeraHome) PackageManager then "recovers" by destroying the app data
 * and creating it again -- on every boot. Settings were lost on every reboot / update.
 *
 * usage: vdxattr DIR...   labels DIR and its direct sub-directories that have no label yet.
 */
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/xattr.h>

static const char NAME[] = "security.selinux";
static const char LABEL[] = "u:object_r:app_data_file:s0";
static int fixed, failed;

static void label(const char *p) {
    char buf[256];
    struct stat st;
    if (lstat(p, &st) != 0 || !S_ISDIR(st.st_mode)) return;
    if (lgetxattr(p, NAME, buf, sizeof buf) >= 0) return;          /* already labelled */
    if (errno != ENODATA) return;                                  /* Linux: "no such attribute" */
    if (lsetxattr(p, NAME, LABEL, sizeof LABEL, 0) == 0) fixed++;
    else { failed++; fprintf(stderr, "vdxattr: %s: %s\n", p, strerror(errno)); }
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        label(argv[i]);
        DIR *d = opendir(argv[i]);
        if (!d) continue;
        struct dirent *e;
        char path[4096];
        while ((e = readdir(d)) != NULL) {
            if (e->d_name[0] == '.') continue;
            snprintf(path, sizeof path, "%s/%s", argv[i], e->d_name);
            label(path);
        }
        closedir(d);
    }
    printf("vdxattr: labelled %d, failed %d\n", fixed, failed);
    return failed ? 1 : 0;
}
