#!/bin/sh
# Static checks for 传书 start-up (fix/transfer). No device access.
# Old Kindle kernels (3.0 / 4.1) have no IPv6: binding the server to the default "::" fails with EAFNOSUPPORT, start() returned
# false without a word, and the transfer page stayed "传输已关闭" whatever you tapped (user diagnostics, PW4 / Oasis 0.8.10).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

need   "$S/Transfer.java" 'getByAddress\(new byte\[\] \{ 0, 0, 0, 0 \}\), p\)' 'IPv4 0.0.0.0 fallback when the kernel has no IPv6'
need   "$S/Transfer.java" 'static final int\[\] PORTS = \{ PORT, ' 'spare ports when 8080 is taken'
need   "$S/Transfer.java" 'HostLink\.cmd\("fwd " \+ port\)' 'the host opens the port really in use'
need   "$S/Transfer.java" 'lastError = reason\(err\)' 'start() remembers why it failed'
forbid "$S/Transfer.java" 'server\.bind\(new InetSocketAddress\(PORT\)\)' 'single "::" bind (fails on kernels without IPv6)'
need   "$S/Transfer.java" 'catch \(Throwable e\) \{\s*$' 'staging-folder problems do not stop the server'
# every place that shows the address uses the port in use, and every switch says why it failed
for f in TransferActivity HomeActivity Panel BlocksSettings; do
    forbid "$S/$f.java" 'Transfer\.PORT\)' "$f shows the fixed port instead of port()"
done
need   "$S/TransferActivity.java" 'else if \(!transfer\.start\(\)\) VeraToast\.show' 'transfer page: tap on 打开传输 says why it failed'
need   "$S/TransferActivity.java" 'transfer\.lastError\(\)' 'transfer page shows the reason'
need   "$S/Panel.java" 'if \(!t\.start\(\)\) VeraToast\.show' 'classic panel toggle says why it failed'
need   "$S/BlocksPanel.java" 'if \(!t\.start\(\)\) VeraToast\.show' 'blocks panel tile says why it failed'
[ $fail = 0 ] && echo "transfer-start: ok"
exit $fail
