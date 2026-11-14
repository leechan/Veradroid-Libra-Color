#!/bin/sh
# Runs ON an emulated (or real) Kindle: replays synthetic gestures through a uinput touch screen of each source protocol
# into a second, private veradroid-input instance (the running one and Android are not touched: the private instance
# has its own virtual devices, its actions go to a logging stub instead of action.sh).
#   sh emu-replay.sh DIR      DIR holds evreplay and the veradroid-input to test; results in DIR/out/
# Check the results with tests/vinput/emu-check.py (on the build host).
set -u
D=$1; O=$D/out; rm -rf $O; mkdir -p $O
SC=${SC:-"tap swipe edge_back edge_panel corner two_tap two_long two_back two_light two_warmth"}
ev_of() { for d in /sys/class/input/input*; do [ "$(cat $d/name 2>/dev/null)" = "$1" ] && ls $d | grep '^event'; done; }
printf '#!/bin/sh\necho "$*" >> %s/act.$VT_P\n' $O > $O/act.sh
printf 'G_EDGE_BACK=1\nG_EDGE_PANEL=1\nG_TWO_TAP=1\nG_TWO_LONG=1\nG_TWO_BACK=1\nG_TWO_SLIDE=1\n' > $O/gestures
for P in ${PROTOS:-B A AID ST}; do
    rm -f $O/in; mkfifo $O/in
    $D/evreplay src $P vdtest-$P < $O/in > $O/src.$P 2>&1 &
    RP=$!
    exec 3> $O/in
    i=0; while [ -z "$(ev_of vdtest-$P)" ] && [ $i -lt 50 ]; do usleep 100000; i=$((i+1)); done
    SRC=/dev/input/$(ev_of vdtest-$P)
    before=$(ev_of veradroid-touch; ev_of veradroid-keys)
    VT_P=$P $D/veradroid-input $SRC $O/vi.$P.log $O/act.sh --w 1272 --h 1696 --edge 120 --window 40 --edge-hold 60 \
        --edge-swipe 80 --edge-back 1 --corner-ms 2000 --gconf $O/gestures 2> $O/vi.$P.err &
    VP=$!
    vt=; vk=; i=0
    while [ $i -lt 50 ]; do
        for n in $(ev_of veradroid-touch); do echo "$before" | grep -qx $n || vt=$n; done
        for n in $(ev_of veradroid-keys); do echo "$before" | grep -qx $n || vk=$n; done
        [ -n "$vt" ] && [ -n "$vk" ] && break; usleep 100000; i=$((i+1))
    done
    echo "$P: source $SRC -> touch $vt keys $vk" >> $O/devices
    $D/evreplay dump /dev/input/$vt > $O/touch.$P & T1=$!
    $D/evreplay dump /dev/input/$vk > $O/keys.$P & T2=$!
    usleep 300000
    for s in $SC; do
        [ $P = ST ] && case $s in two_*) continue;; esac
        echo $s >&3; sleep 3
    done
    echo quit >&3; exec 3>&-
    sleep 1; kill $VP $T1 $T2 2>/dev/null; wait $RP 2>/dev/null
done
grep -h . $O/devices
