#!/bin/sh
# 无线调试（adb over Wi-Fi，feat/adb-wifi）: static checks + the host key handling run against a temp dir. No device access.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

for tree in pw6 k49; do
    H=$REPO/host/$tree/boot
    need "$H/lib/webadmin.sh" 'adbstart\) \{ wa_adbstart "\$arg"' "$tree: adbstart verb"
    need "$H/lib/webadmin.sh" 'wa_adb_ipv6 \|\| \{ echo "adb.error=noipv6"' "$tree: refuses on kernels without IPv6"
    need "$H/lib/webadmin.sh" '\[ -n "\$\(wa_adb_validkeys\)" \] \|\| \{ echo "adb.error=nokey"' "$tree: never starts without a key"
    need "$H/lib/webadmin.sh" 'rm -f \$SYS/data/misc/adb/adb_keys \$W/adb.until' "$tree: keys removed from Android when switched off"
    need "$H/lib/watchdog.sh" 'wa_adb_tick' "$tree: watchdog switches it off on time"
    need "$H/stop.sh" 'adbfwd\.ipt' "$tree: stop.sh closes the firewall port"
    forbid "$H/lib/webadmin.sh" 'ro\.adb\.secure 0' "$tree: adb auth must never be switched off"
    need "$H/lib/webadmin.sh" '\[ "\$sec" = 1 \] \|\| \{ echo "adb.error=insecure"' "$tree: never starts unless ro.adb.secure reads back 1 (PW6 / k49 images leave it unset)"
    sh -n "$H/lib/webadmin.sh" || { echo "FAIL $tree webadmin.sh syntax"; fail=1; }
done
need "$S/WebAdmin.java" 'p\.equals\("/api/adb/start"\)' 'web: start endpoint'
need "$S/WebAdmin.java" 'int v = t\.checkPin\(b\.optString\("pin"\)\);' 'web: start asks for the PIN again'
need "$S/WebAdmin.java" 'p\.startsWith\("/api/adb/"\)' 'web: adb POST bodies are read'
need "$S/AdbWifi.java" 'blob\.length != 524' 'key check: 524-byte RSA public key'
need "$S/BlocksSettings.java" '"无线调试 \(adb\)"' 'blocks settings toggle'
need "$S/HomeActivity.java" '"无线调试 \(adb\)"' 'classic settings toggle'
need "$REPO/android/packages/VeraHome/assets/web.html" "post\('/api/adb/start',\{min:" 'web page start button'

# --- host key handling against a temp dir (the real functions, stubbed environment)
T=$(mktemp -d "${TMPDIR:-/tmp}/vdadb.XXXXXX")
key() { { printf '\100\000\000\000'; head -c 520 /dev/zero | tr '\0' "$1"; } | base64 | tr -d '\n'; }
K1=$(key a); K2=$(key b)
[ ${#K1} -eq 700 ] || { echo "FAIL fixture key length ${#K1}"; fail=1; }
out=$(
    X=$T/x W=$T/w SYS=$T/sys VD=$T/vd; mkdir -p $X/ctl $W $SYS
    t() { :; }
    . "$REPO/host/pw6/boot/lib/webadmin.sh"
    WA_ADBB=$T/adb
    wa_adbkeyadd "$K1 me@pc"
    wa_adbkeyadd "$K1 me@pc"
    wa_adbkeyadd "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA x"
    wa_adbkeyadd "$K2 command=evil"
    wa_adbkeyadd "$K2 other"
    echo "count=$(wa_adb_validkeys | wc -l | tr -d ' ')"
    wa_adbkeydel 1
    echo "after=$(wa_adb_validkeys | wc -l | tr -d ' ') $(wa_adb_validkeys | cut -f2 | cut -d' ' -f2)"
    wa_adbstart 30 2>/dev/null | head -1
)
rm -rf "$T"
exp="adb.msg=added
adb.msg=exists
adb.error=badkey
adb.msg=added
adb.msg=exists
count=2"
case "$out" in "$exp"*) ;; *) echo "FAIL key handling:"; printf '%s\n' "$out" | sed 's/^/   /'; fail=1 ;; esac
printf '%s\n' "$out" | grep -q '^after=1 command=evil$' || { echo "FAIL keydel removes the first key only"; fail=1; }
# a second line with the same key is "exists"; the comment is kept as plain text (adbd ignores it)
# not booted (no $W/booted) -> refuses before touching Android (or noipv6 on a kernel without IPv6)
printf '%s\n' "$out" | tail -1 | grep -qE '^adb\.error=(notbooted|noipv6)$' || { echo "FAIL start without boot: $(printf '%s\n' "$out" | tail -1)"; fail=1; }
[ $fail = 0 ] && echo "adb-wifi: ok"
exit $fail
