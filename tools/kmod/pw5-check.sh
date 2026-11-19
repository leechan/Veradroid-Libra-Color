#!/bin/sh
# Read-only check: can VeraDroid run on this Kindle Paperwhite 5 (firmware 5.14 - 5.19)?  Run as root:
#
#   sh /mnt/us/vd-pw5-test/pw5-check.sh
#
# Nothing is installed, loaded or changed. It looks at the kernel (uname, /proc/misc, namespaces, cgroups),
# compares `uname -v` with the PW5 firmware kernels we fingerprinted from Amazon's update packages (kernels.txt),
# and runs bindertest (a self-contained binder round trip) on /dev/hwbinder, which neither the Kindle nor
# VeraDroid use. Output goes to the screen and to pw5-check.log next to this script; the last line is RESULT.
cd "$(dirname "$0")" || exit 1
L=$PWD/pw5-check.log
exec 3>&1 > "$L.tmp" 2>&1
bad=0; warn=0
ok()   { echo "OK    $*"; }
no()   { echo "FAIL  $*"; bad=$((bad + 1)); }
note() { echo "NOTE  $*"; warn=$((warn + 1)); }
echo "== $(date)"
echo "firmware: $(head -1 /etc/prettyversion.txt 2>/dev/null)"
echo "kernel:   $(uname -r) $(uname -v)"
echo "model:    code $(cut -c4-6 /proc/usid 2>/dev/null), screen $(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)"
[ "$(id -u)" = 0 ] && ok "root" || no "not root (run it from the jailbreak's shell / KTerm as root)"
case "$(uname -r)" in 4.9.*) ok "4.9 kernel (PW5 / KT5 / KT6 family)" ;; *) no "kernel $(uname -r) is not a PW5 kernel" ;; esac
uv=$(uname -v)
m=$(awk -F'\t' -v u="$uv" '$2 == u {print $1}' kernels.txt | tr '\n' ' ')
[ -n "$m" ] && ok "uname -v is the stock kernel of PW5 firmware $m" || note "uname -v not in our list of PW5 stock kernels (custom kernel or a firmware we did not scan)"
if [ -e /lib/ld-linux-armhf.so.3 ]; then ok "hard-float firmware (armhf)"; else note "soft-float firmware (armel, 5.16.2.x and older): VeraDroid keeps the Kindle UI running in the background (no KINDLE_UI=stop)"; fi
for d in binder hwbinder vndbinder uinput tun; do
    grep -qw "$d" /proc/misc && ok "/proc/misc has $d" || { [ $d = hwbinder ] || [ $d = vndbinder ] && note "/proc/misc has no $d" || no "/proc/misc has no $d"; }
done
[ -e /dev/binder ] && ok "/dev/binder exists" || note "/dev/binder missing (VeraDroid creates its own node)"
[ -e /proc/self/ns/pid ] && ok "PID namespace (5.18+ style: container mode)" || ok "no PID namespace (5.17 and older): VeraDroid uses its chroot mode, same as on 5.17.1"
grep -qw freezer /proc/cgroups && ok "cgroup freezer" || no "no cgroup freezer"
grep -qw ext4 /proc/filesystems && ok "ext4" || no "no ext4"
grep -qw fuse /proc/filesystems && ok "fuse" || note "no fuse"
[ -e /dev/loop0 ] || [ -e /dev/loop-control ] && ok "loop devices" || note "no loop device nodes"
[ -x /var/local/kmc/bin/sh_integration_launcher ] && ok "jailbreak hotfix (library scriptlets run)" || note "no /var/local/kmc hotfix: start the installer from KUAL instead of the library"
fs=$(stat -f -c %T /mnt/base-us 2>/dev/null); free=$(df -m /mnt/base-us 2>/dev/null | awk 'NR==2{print $4}')
echo "user store: ${fs:-?}, ${free:-?} MB free"
[ "${free:-0}" -ge 2600 ] 2>/dev/null && ok "free space >= 2.6 GB" || note "less than 2.6 GB free: the installer may pick a smaller system disk or refuse"
echo "RAM: $(awk '/^MemTotal/{print int($2/1024)" MB"}' /proc/meminfo)"
if [ -f ./bindertest ] && grep -qw hwbinder /proc/misc; then
    # the user store (vfat) is mounted noexec on most Kindles: run the copy in /tmp
    n=/tmp/vd-test-hwbinder; b=/tmp/vd-bindertest; rm -f $n; cp ./bindertest $b && chmod 755 $b
    if mknod $n c 10 "$(awk '$2 == "hwbinder" {print $1}' /proc/misc)" 2>/dev/null; then
        $b $n; r=$?; rm -f $n $b
        [ $r = 0 ] && ok "bindertest on hwbinder" || no "bindertest on hwbinder rc=$r"
    else note "could not create a test node for hwbinder"; fi
fi
echo "== $bad FAIL, $warn NOTE"
[ $bad = 0 ] && echo "RESULT: OK" || echo "RESULT: FAIL"
mv "$L.tmp" "$L"; cat "$L" >&3
