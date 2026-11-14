#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 2026-11-13 incident (PW6 5.20.2, 0.88 -> 0.89): Android's PackageManager wiped user 0 (installd destroy_user_data) after
# vold crashed in a mandatory boot fstrim; the recursive delete of /data/media/0 went through the Kindle documents bind.
# Run from the repo root: sh tests/docs-wipe-guard-test.sh   (no root needed)
set -u
fail=0
f() { echo "FAIL $*"; fail=1; }
for m in pw6 k49 legacy; do
    C=host/$m/boot/lib/container.sh; L=host/$m/boot/lib/common.sh; A=host/$m/boot/lib/afterboot.sh
    # documents must never be mounted anywhere under the container's /data
    grep -q 'mount --bind /mnt/base-us/documents \$R/data' "$C" && f "$m: documents still bound under /data"
    grep -q 'mount --bind /mnt/base-us/documents \$R\$KLIB_MP' "$C" || f "$m: documents not bound at \$R\$KLIB_MP"
    grep -q '^KLIB_MP=/kindle_library$' "$L" || f "$m: KLIB_MP"
    case "$(sed -n 's/^KLIB_MP=//p' "$L")" in /data*|/storage*|/mnt*|'') f "$m: KLIB_MP inside a tree that Android deletes / vold unmounts" ;; esac
    case $m in
    legacy) # /data/media/0/KindleLibrary is a symlink to $KLIB_MP outside /data
        grep -q 'klib_link \$R/data' "$C" || f "$m: KindleLibrary symlink not set up" ;;
    *)      # 0.92: a real (empty) mount point again -- vold's FUSE does not follow symlinks -- bound read-only during boot,
            # the writable layer is stacked on top by after_boot (klib_rw)
        grep -q 'klib_dir \$R/data' "$C" || f "$m: KindleLibrary mount point not prepared (klib_dir)"
        grep -q 'mount -o remount,ro,bind \$R\$KLIB' "$C" || f "$m: library not bound read-only under /data during boot"
        grep -q '^    klib_rw$' "$A" || f "$m: after_boot does not stack the writable library layer" ;;
    esac
    # the trigger: boot-time mandatory fstrim -> vold SIGSEGV
    grep -q '^    fstrim_defuse$' "$C" && grep -q 'touch \$SYS/data/system/last-fstrim' "$C" || f "$m: last-fstrim not refreshed before start"
    # mount guard must look inside the container namespace
    grep -q 'mounts_under_ns "\$1"' "$L" || f "$m: mounts_under does not check the container namespace"
    grep -q '^    boot_data_check$' "$A" || f "$m: after_boot does not verify documents"
    grep -q 'docs_snapshot' "$C" || f "$m: no documents snapshot before start"
done
# legacy (3.0 kernel): $W/mode=chroot but the container has its own mount namespace (unshare -m + pivot_root), so the
# namespace check must not be skipped in chroot mode there (k49 skips it: its chroot mode has no unshare -m)
L=host/legacy/boot/lib/common.sh
grep -q 'setsid unshare -m sh \$VD/boot/veradroid.sh --in-chroot' host/legacy/boot/lib/container.sh || f "legacy: container no longer started with unshare -m (re-check mounts_under_ns)"
awk '/^mounts_under_ns\(\)/ {p=1} p && /mode/ && /chroot/ {bad=1} p && /^}/ {exit} END {exit !bad}' "$L" && f "legacy: mounts_under_ns skips the container namespace in chroot mode"
grep -q '" \$R\$KLIB_MP " /proc/mounts' host/legacy/boot/stop.sh || f "legacy: stop.sh does not check for a leftover library bind"
B=cloud/static/bootstrap.sh
grep -q 'DOCS_MANIFEST=/mnt/base-us/veradroid-docs-manifest' "$B" || f "installer: no pre-install documents manifest"
grep -q 'readlink /proc/\$mu_p/ns/mnt' "$B" || f "installer: mounts_under does not check the container namespace"
P=android/small-patches.py
grep -q 'VeraDroid: no fstab, nothing to trim' "$P" || f "vold TrimTask NULL fstab patch"
grep -q 'NOT destroying user' "$P" || f "PackageManager prepareUserDataLI patch"
grep -q 'vd_is_mount_point(subfd)' "$P" || f "installd delete-through-mount patch"
grep -q '"/kindle_library/"' android/packages/VeraHome/src/com/veradroid/home/VeraFileProvider.java || f "VeraFileProvider does not allow /kindle_library"

# ---- functional: the helpers in a sandbox (no mounts needed) ----
T=$(mktemp -d "${TMPDIR:-/tmp}/vdwipe.XXXXXX"); trap 'rm -rf "$T"' EXIT
for FM in pw6 legacy; do
FC=host/$FM/boot/lib/common.sh; rm -rf "$T"/*
fx() { awk -v n="$1" '$0 ~ "^" n "\\(\\) \\{" {p=1} p {print} p && /^}/ {exit}' "$FC"; }
if grep -q '^klib_dir()' "$FC"; then
    # pw6 / k49 (0.92+): KindleLibrary is a real mount point; klib_dir prepares it and never deletes anything
    { echo 't() { echo "[t] $*"; }'; echo 'KLIB_MP=/kindle_library'
      for n in mounts_under mounts_under_ns klib_dir docs_list docs_snapshot docs_verify; do fx $n; done; } > "$T/lib.sh"
    mkdir -p "$T/W" "$T/VD" "$T/base/documents/sub" "$T/sys/data/media/0/KindleLibrary"
    (
        SYS=$T/sys; R=$T/rootfs; W=$T/W; VD=$T/VD; DOCS_DIR=$T/base/documents
        . "$T/lib.sh"
        KL=$SYS/data/media/0/KindleLibrary
        # 1. an empty directory stays a plain directory (the mount point)
        klib_dir "$SYS/data" && [ -d "$KL" ] && [ ! -L "$KL" ] || { echo "FAIL klib_dir empty dir"; exit 1; }
        # 2. a non-empty directory is moved aside, never deleted, and an empty mount point takes its place
        echo keep > "$KL/x"
        klib_dir "$SYS/data" >/dev/null && [ -d "$KL" ] && [ -z "$(ls -A "$KL")" ] && cat "$SYS"/data/media/0/KindleLibrary.stray-*/x | grep -q keep || { echo "FAIL klib_dir non-empty dir"; exit 1; }
        # 3. the 0.89 candidate's symlink is removed (only the link) and replaced by a directory
        echo book > "$DOCS_DIR/b.txt"; rm -rf "$KL"; ln -s "$DOCS_DIR" "$KL"
        klib_dir "$SYS/data" && [ -d "$KL" ] && [ ! -L "$KL" ] && [ -f "$DOCS_DIR/b.txt" ] || { echo "FAIL klib_dir old symlink"; exit 1; }
        # 4. docs_verify: detects loss, restores from the newest pre-install backup, never overwrites
        echo one > "$DOCS_DIR/sub/one.txt"; echo two > "$DOCS_DIR/two.txt"
        docs_snapshot; grep -q '^documents/sub/one.txt$' "$W/docs.before" || { echo "FAIL docs_snapshot"; exit 1; }
        ( cd "$T/base" && tar -czf "$T/base/../veradroid-user-backup-20261113-000000.tgz" documents )
        docs_verify "$W/docs.before" test >/dev/null || { echo "FAIL docs_verify on intact library"; exit 1; }
        rm -f "$DOCS_DIR/sub/one.txt" "$DOCS_DIR/two.txt"; echo changed > "$DOCS_DIR/b.txt"
        sed "s|/mnt/base-us/veradroid-user-backup-|$T/veradroid-user-backup-|" "$T/lib.sh" > "$T/lib2.sh"; . "$T/lib2.sh"
        docs_verify "$W/docs.before" test >/dev/null && { echo "FAIL docs_verify did not report the loss"; exit 1; }
        [ "$(cat "$DOCS_DIR/sub/one.txt" 2>/dev/null)" = one ] && [ "$(cat "$DOCS_DIR/two.txt" 2>/dev/null)" = two ] || { echo "FAIL docs_verify did not restore"; exit 1; }
        [ "$(cat "$DOCS_DIR/b.txt")" = changed ] || { echo "FAIL docs_verify overwrote an existing file"; exit 1; }
        grep -q 'DOCUMENTS LOSS' "$VD/DOCUMENTS-LOSS.log" || { echo "FAIL loss not logged"; exit 1; }
        exit 0
    ) 2>/dev/null || { echo "FAIL $FM: helper functional test"; fail=1; }
elif grep -q '^klib_link()' "$FC"; then
    { echo 't() { echo "[t] $*"; }'; echo 'KLIB_MP=/kindle_library'
      for n in mounts_under mounts_under_ns klib_link docs_list docs_snapshot docs_verify; do fx $n; done; } > "$T/lib.sh"
    mkdir -p "$T/W" "$T/VD" "$T/base/documents/sub" "$T/sys/data/media/0/KindleLibrary"
    (
        SYS=$T/sys; R=$T/rootfs; W=$T/W; VD=$T/VD; DOCS_DIR=$T/base/documents
        . "$T/lib.sh"
        # 1. old empty mount-point directory becomes a symlink
        klib_link "$SYS/data" && [ -L "$SYS/data/media/0/KindleLibrary" ] && [ "$(readlink "$SYS/data/media/0/KindleLibrary")" = /kindle_library ] || { echo "FAIL klib_link empty dir"; exit 1; }
        # 2. a non-empty old directory is moved aside, never deleted
        rm "$SYS/data/media/0/KindleLibrary"; mkdir "$SYS/data/media/0/KindleLibrary"; echo keep > "$SYS/data/media/0/KindleLibrary/x"
        klib_link "$SYS/data" >/dev/null && [ -L "$SYS/data/media/0/KindleLibrary" ] && cat "$SYS"/data/media/0/KindleLibrary.stray-*/x | grep -q keep || { echo "FAIL klib_link non-empty dir"; exit 1; }
        # 3. what installd/our rm -rf does to /data/media/0 cannot reach the library through the link
        ln -s "$DOCS_DIR" "$T/linkcheck" 2>/dev/null; echo book > "$DOCS_DIR/b.txt"
        rm -f "$SYS/data/media/0/KindleLibrary"; ln -s "$DOCS_DIR" "$SYS/data/media/0/KindleLibrary"   # worst case: link resolvable on this side
        rm -rf "$SYS/data/media/0"; [ -f "$DOCS_DIR/b.txt" ] || { echo "FAIL recursive delete of media/0 reached the library through the link"; exit 1; }
        # 4. docs_verify: detects loss, restores from the newest pre-install backup, never overwrites
        echo one > "$DOCS_DIR/sub/one.txt"; echo two > "$DOCS_DIR/two.txt"
        docs_snapshot; grep -q '^documents/sub/one.txt$' "$W/docs.before" || { echo "FAIL docs_snapshot"; exit 1; }
        ( cd "$T/base" && tar -czf "$T/base/../veradroid-user-backup-20261113-000000.tgz" documents )
        docs_verify "$W/docs.before" test >/dev/null || { echo "FAIL docs_verify on intact library"; exit 1; }
        rm -f "$DOCS_DIR/sub/one.txt" "$DOCS_DIR/two.txt"; echo changed > "$DOCS_DIR/b.txt"
        # docs_verify looks for backups in /mnt/base-us: point it at the sandbox
        sed "s|/mnt/base-us/veradroid-user-backup-|$T/veradroid-user-backup-|" "$T/lib.sh" > "$T/lib2.sh"; . "$T/lib2.sh"
        docs_verify "$W/docs.before" test >/dev/null && { echo "FAIL docs_verify did not report the loss"; exit 1; }
        [ "$(cat "$DOCS_DIR/sub/one.txt" 2>/dev/null)" = one ] && [ "$(cat "$DOCS_DIR/two.txt" 2>/dev/null)" = two ] || { echo "FAIL docs_verify did not restore"; exit 1; }
        [ "$(cat "$DOCS_DIR/b.txt")" = changed ] || { echo "FAIL docs_verify overwrote an existing file"; exit 1; }
        grep -q 'DOCUMENTS LOSS' "$VD/DOCUMENTS-LOSS.log" || { echo "FAIL loss not logged"; exit 1; }
        exit 0
    ) 2>/dev/null || { echo "FAIL $FM: helper functional test"; fail=1; }
else
    f "$FM: klib_dir / klib_link / docs_verify helpers missing"
fi
done
[ "$fail" = 0 ] && echo 'DOCS WIPE GUARD OK' || echo 'DOCS WIPE GUARD FAILURES'
exit "$fail"
