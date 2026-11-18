#!/bin/sh
# chroot (host namespace) mode, kernels without a PID namespace (PW6 / KT6 firmware 5.17.x): zygote and apps read host paths
# from /proc/self/maps (/mnt/base-us/system/veradroid/rootfs/system/lib/libart.so). Packers that reopen libart.so from that
# path (ijiami: 晋江 6.8.8 / 7.1.9) abort with "Null DexFile::mCookie" -> GetArrayLength(null). container.sh links $R inside
# Android's /mnt back to the root. This checks the link is made, made only in chroot mode, and is relative and correct.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*"; exit 1; }
for h in pw6 k49; do
    C=host/$h/boot/lib/container.sh
    grep -q '^hostns_selflink() {' $C || fail "$h: hostns_selflink missing"
    awk '/^container_start\(\)/ {p=1} p && /if hostns; then/ {h=1} h && /hostns_selflink .*&$/ {ok=1} p && /^}/ {exit} END {exit !ok}' $C ||
        fail "$h: hostns_selflink not started in the chroot branch of container_start"
    awk '/^container_start\(\)/ {p=1} p && /unshare -m -u -i -n -p/ {u=1} u && /hostns_selflink/ {bad=1} p && /^}/ {exit} END {exit !bad}' $C &&
        fail "$h: hostns_selflink also runs in namespace mode"
    grep -q 'ln -s "$sl_up" "$R$R"' $C || fail "$h: link is not relative"
    # the relative target computed by the same awk must resolve to the link's own root
    up=$(sed -n "s/^    sl_up=\$(echo \"\$sl_dir\" | awk -F\/ '\(.*\)')\$/\1/p" $C)
    [ -n "$up" ] || fail "$h: cannot extract the sl_up awk"
    T=${TMPDIR:-/tmp}/vd-selflink.$$; rm -rf "$T"
    for R in /mnt/base-us/system/veradroid/rootfs /mnt/us/vd/rootfs; do
        sl_dir=${R%/*}; sl_up=$(echo "$sl_dir" | awk -F/ "$up")
        mkdir -p "$T$sl_dir" && ln -s "$sl_up" "$T$R"
        [ "$(cd "$T$R" && pwd -P)" = "$(cd "$T" && pwd -P)" ] || { rm -rf "$T"; fail "$h: $R -> $sl_up does not resolve to the root"; }
        rm -rf "$T"
    done
done
echo "hostns-selflink: ok"
