#!/bin/sh
# Capture raw evdev events from a Kindle touchscreen and summarize them.
# Usage: sh veradroid_touchcap.sh /dev/input/event1 [tap|hold|swipe|two] [seconds]
set -u

DEV=${1:-}
MODE=${2:-tap}
SECS=${3:-15}
case "$SECS" in ''|*[!0-9]*) SECS=15 ;; esac
[ -n "$DEV" ] || { echo "usage: $0 /dev/input/eventN [tap|hold|swipe|two] [seconds]" >&2; exit 2; }
[ -r "$DEV" ] || { echo "cannot read $DEV" >&2; exit 1; }

RAW=/mnt/us/touchcap-$(date +%Y%m%d-%H%M%S).bin
PIDF=/dev/shm/veradroid/input.pid
RELEASED=0

say() {
    echo "$*"
    command -v eips >/dev/null 2>&1 && eips 2 4 "VeraDroid touchcap: $*" >/dev/null 2>&1
    return 0
}

if [ -f "$PIDF" ]; then
    kill -USR1 "$(cat "$PIDF")" 2>/dev/null && RELEASED=1
    sleep 1
fi

case "$MODE" in
    tap)  ASK="请连续点 3 次屏幕" ;;
    hold) ASK="请按住屏幕 3 秒" ;;
    swipe) ASK="请从屏幕中间向上滑" ;;
    two)  ASK="请双指缩放一次" ;;
    *) ASK="请按 ${MODE} 操作" ;;
esac
say "${ASK}，${SECS} 秒后结束"
echo "raw=$RAW"

timeout "$SECS" dd if="$DEV" of="$RAW" bs=16 count=$((SECS * 200)) 2>/dev/null || true

if [ "$RELEASED" = 1 ]; then
    kill -USR2 "$(cat "$PIDF")" 2>/dev/null || true
fi

[ -s "$RAW" ] || { echo "RESULT=EMPTY (no raw events)"; echo "raw=$RAW"; exit 3; }

od -An -tu4 -v "$RAW" 2>/dev/null | awk '
function signed(v) { return (v >= 2147483648) ? v - 4294967296 : v }
BEGIN {
    n=0; abs_x=0; abs_y=0; abs_slot=0; abs_track=0; abs_major=0; abs_pressure=0;
    btn=0; btn_down=0; syn=0; xmin=99999; xmax=-1; ymin=99999; ymax=-1;
    track_seen=0; slot_seen=0; track_neg=0;
}
{
    for (i=1; i+3<=NF; i+=4) {
        w2=$(i+2); v=signed($(i+3));
        type=w2%65536; code=int(w2/65536);
        n++;
        if (type==3 && code==53) { abs_x++; if (v<xmin)xmin=v; if(v>xmax)xmax=v }
        else if (type==3 && code==54) { abs_y++; if (v<ymin)ymin=v; if(v>ymax)ymax=v }
        else if (type==3 && code==47) { abs_slot++; if(v==0||v==1)slot_seen=1 }
        else if (type==3 && code==57) { abs_track++; if(v>=0)track_seen=1; else track_neg=1 }
        else if (type==3 && code==48) abs_major++;
        else if (type==3 && code==58) abs_pressure++;
        else if (type==1 && code==330) { btn++; if(v)btn_down=1 }
        else if (type==0 && code==0) syn++;
    }
}
END {
    printf "RESULT=%s\n", (abs_track>0 ? "OK" : "NO_MT_TRACKING");
    printf "events=%d syn=%d\n", n, syn;
    printf "ABS_X=%d range=%d..%d\n", abs_x, (xmax>=0?xmin:-1), xmax;
    printf "ABS_Y=%d range=%d..%d\n", abs_y, (ymax>=0?ymin:-1), ymax;
    printf "ABS_MT_SLOT=%d saw_slot_0_or_1=%d\n", abs_slot, slot_seen;
    printf "ABS_MT_TRACKING_ID=%d saw_nonneg=%d saw_release=%d\n", abs_track, track_seen, track_neg;
    printf "ABS_MT_TOUCH_MAJOR=%d ABS_MT_PRESSURE=%d\n", abs_major, abs_pressure;
    printf "BTN_TOUCH=%d saw_press=%d\n", btn, btn_down;
}
' || true
echo "raw=$RAW"
