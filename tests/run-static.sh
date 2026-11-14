#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run every static test (tests/*-test.sh): shell + python only, no device, no AOSP build.
#   sh tests/run-static.sh            # all static tests
#   LIVE=1 sh tests/run-static.sh     # also the tests that talk to the live update server (live-release-test.sh)
#   sh tests/run-static.sh home-ui kpm-package   # only these
set -u
cd "$(dirname "$0")/.."
NETWORK_TESTS="live-release"
if [ $# -gt 0 ]; then LIST=$*; else LIST=$(for f in tests/*-test.sh; do n=${f##*/}; echo "${n%-test.sh}"; done); fi
pass=0; failed=
for n in $LIST; do
    case " $NETWORK_TESTS " in *" $n "*) [ "${LIVE:-0}" = 1 ] || { echo "---- $n: skipped (network; LIVE=1 to run)"; continue; } ;; esac
    out=$(sh "tests/$n-test.sh" 2>&1); rc=$?
    if [ $rc = 0 ]; then pass=$((pass + 1)); echo "ok   $n"
    else failed="$failed $n"; echo "FAIL $n (exit $rc)"; printf '%s\n' "$out" | tail -20 | sed 's/^/     /'; fi
done
echo "----"
echo "$pass passed${failed:+, failed:$failed}"
[ -z "$failed" ]
