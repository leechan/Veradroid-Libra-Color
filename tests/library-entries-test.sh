#!/bin/sh
# Kindle library entries: every kind of entry has its own cover (tools/gen-entry-covers.py), "VeraDroid 卸载" is not put
# into the library any more (users tapped it instead of "VeraDroid 启动": same cover), it is shipped as
# veradroid/VeraDroid-Uninstall.sh for USB recovery, and an upgrade / uninstall removes only OUR old documents/VeraDroid-Uninstall.sh.
set -u
cd "$(dirname "$0")/.."
fail=0; F() { echo "FAIL $*"; fail=1; }
icon() { sed -n 's/^# Icon: //p' "$1" | head -1; }

# ---- covers ----
start=$(icon cloud/static/VeraDroid-Launch.sh)
case "$start" in data:image/png\;base64,iVBOR*) ;; *) F "start entry has no PNG cover" ;; esac
for f in host/*/VeraDroid-Launch.sh; do [ "$(icon "$f")" = "$start" ] || F "$f: start cover differs from cloud/static/VeraDroid-Launch.sh"; done
seen=
for f in cloud/static/VeraDroid.sh cloud/static/VeraDroid-Experimental.sh cloud/static/VeraDroid-Legacy.sh cloud/static/VeraDroid-Offline.sh \
         cloud/static/VeraDroid-Update.sh cloud/static/VeraDroid-Factory.sh host/*/entries/VeraDroid-Report.sh host/*/entries/VeraDroid-Uninstall.sh; do
    [ -f "$f" ] || continue
    i=$(icon "$f")
    case "$i" in data:image/png\;base64,iVBOR*) ;; *) F "$f: no PNG cover in # Icon:"; continue ;; esac
    [ "$i" = "$start" ] && F "$f: same cover as the start entry"
    [ ${#i} -lt 12000 ] || F "$f: cover larger than ~8 KB"
    h=$(printf '%s' "$i" | cksum | cut -d' ' -f1)
    case "$f" in */entries/VeraDroid-Uninstall.sh) u=$h ;; esac
    seen="$seen $h"
done
# the uninstall cover is used by the uninstall entry only
n=0; for h in $seen; do [ "$h" = "${u:-x}" ] && n=$((n + 1)); done
u_files=$(ls host/*/entries/VeraDroid-Uninstall.sh 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = "$u_files" ] || F "the uninstall cover is used by something other than the uninstall entry ($n / $u_files)"
if python3 -c 'import PIL' 2>/dev/null; then python3 tools/gen-entry-covers.py --check || F "covers differ from tools/gen-entry-covers.py"
else echo "note: no Pillow here, tools/gen-entry-covers.py --check skipped"; fi

# ---- uninstall entry: two taps, no purge on models that were tested on real devices ----
ours() { # entry / uninstall.sh path -> 0 when its family's installer already has this change (host/legacy in the
         # PW6 / k49 tree is an old copy; the legacy release is built from release/legacy-*)
    case "$1" in host/legacy/*) grep -q 'vd_retire_uninstall_entry()' cloud/static/bootstrap-legacy.sh 2>/dev/null ;;
                 *) grep -q 'vd_retire_uninstall_entry()' cloud/static/bootstrap.sh 2>/dev/null ;; esac
}
for e in host/*/entries/VeraDroid-Uninstall.sh; do
    ours "$e" || continue
    sh -n "$e" || F "$e: syntax"
    head -3 "$e" | grep -q '^# Name: VeraDroid 卸载$' || F "$e: title"
    grep -q '^VD=/mnt/base-us/veradroid$' "$e" || F "$e: VD line (vd_retire_uninstall_entry matches on it)"
    grep -q '\[ $((now - cu)) -ge 10 \] && \[ $((now - cu)) -le 120 \]' "$e" || F "$e: no second-tap confirm"
    grep -q 'PG=0; \[ "$(cat $VD/tested 2>/dev/null)" = emulator-only \] && PG=1' "$e" || F "$e: purge not limited to emulator-only models"
done

# ---- installers: uninstall entry goes to the program dir, never into documents ----
for B in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh; do
    [ -f "$B" ] || continue
    grep -q 'vd_retire_uninstall_entry()' "$B" || continue   # bootstrap-legacy.sh of the other family is not ours to check
    grep -q 'cp "$TMP/veradroid-pw6/entries/VeraDroid-Uninstall.sh" "$VD/VeraDroid-Uninstall.sh"' "$B" || F "$B: uninstall entry not put in veradroid/"
    if grep -q 'for e in "$TMP/veradroid-pw6/entries"/\*.sh' "$B"; then
        grep -q '\[ "${e##\*/}" = VeraDroid-Uninstall.sh \] && continue' "$B" || F "$B: entries loop still copies the uninstall entry into documents"
    fi
    grep -q '^vd_retire_uninstall_entry$' "$B" || F "$B: old uninstall entry not removed on upgrade"
done
for U in host/*/boot/uninstall.sh; do
    ours "$U" || continue
    grep -q '^vd_retire_uninstall_entry$' "$U" || F "$U: does not remove a copied uninstall entry"
done
# the same function everywhere
fn() { sed -n '/^# BEGIN vd_retire_uninstall_entry/,/^# END vd_retire_uninstall_entry/p' "$1"; }
ref=; for f in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh host/*/boot/uninstall.sh; do
    [ -f "$f" ] && b=$(fn "$f") && [ -n "$b" ] || continue
    [ -z "$ref" ] && ref=$b && rf=$f && continue
    [ "$b" = "$ref" ] || F "vd_retire_uninstall_entry in $f differs from $rf"
done
[ -n "$ref" ] || F "no vd_retire_uninstall_entry found"

# ---- functional: only our own file goes, user files stay ----
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/us/documents" "$T/base/documents"
eval "$(printf '%s\n' "$ref" | sed -e "s#/mnt/us/documents#$T/us/documents#g" -e "s#/mnt/base-us/documents#$T/base/documents#g")"
e=$(ls host/*/entries/VeraDroid-Uninstall.sh | head -1)
cp "$e" "$T/us/documents/VeraDroid-Uninstall.sh"; mkdir -p "$T/us/documents/VeraDroid-Uninstall.sh.sdr"; echo x > "$T/us/documents/VeraDroid-Uninstall.sh.sdr/icon.png"
printf '#!/bin/sh\n# Name: VeraDroid 卸载\necho mine\n' > "$T/base/documents/VeraDroid-Uninstall.sh"      # same name, not ours
cp "$e" "$T/us/documents/VeraDroid-Uninstall (1).sh"                                                # other name
echo book > "$T/us/documents/book.txt"
RETIRED=; vd_retire_uninstall_entry
[ -e "$T/us/documents/VeraDroid-Uninstall.sh" ] && F "our old entry not removed"
[ -e "$T/us/documents/VeraDroid-Uninstall.sh.sdr" ] && F "its .sdr not removed"
[ "$RETIRED" = 1 ] || F "RETIRED not set"
[ -f "$T/base/documents/VeraDroid-Uninstall.sh" ] || F "a user file with the same name was removed"
[ -f "$T/us/documents/VeraDroid-Uninstall (1).sh" ] || F "a file with another name was removed"
[ -f "$T/us/documents/book.txt" ] || F "a book was removed"
ln -s "$T/us/documents/book.txt" "$T/us/documents/VeraDroid-Uninstall.sh"; vd_retire_uninstall_entry
[ -L "$T/us/documents/VeraDroid-Uninstall.sh" ] || F "a symlink was removed"
[ "$fail" = 0 ] && echo "LIBRARY ENTRIES OK"
exit $fail
