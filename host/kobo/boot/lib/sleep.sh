# SPDX-License-Identifier: GPL-3.0-or-later
# Sleep / screensaver manager for Kobo.
# Driven by hardware KEY_POWER (via veradroid-input -> action.sh power -> $W/power.fifo),
# VeraHome "sleep" command, and optional idle timeout ($SLEEP_TIMEOUT).

saver_resolve_img() {
    case "$1" in
        "$SYS/data/media/0/Screensaver/"*)
            c="$SYS/data/media/0/Screensaver/.vd-cache/sd-${1##*/}.png"
            [ -f "$c" ] && { echo "$c"; return 0; } ;;
        "$VD/screensaver/"*)
            c="$SYS/data/media/0/Screensaver/.vd-cache/vd-${1##*/}.png"
            [ -f "$c" ] && { echo "$c"; return 0; } ;;
    esac
    echo "$1"
}

screensaver_show() {
    list=$W/saver.list
    : > "$list"
    smode=; sone=
    type saver_choice >/dev/null 2>&1 && saver_choice
    if [ "$smode" = one ] && [ -n "$sone" ]; then
        echo "$sone" >> "$list"
    elif [ "$smode" = kindle ]; then
        for d in /mnt/onboard/.kobo/screensaver /mnt/onboard/.adds/koreader/screensaver; do
            [ -d "$d" ] || continue
            for f in "$d"/*.[pP][nN][gG] "$d"/*.[jJ][pP][gG] "$d"/*.[jJ][pP][eE][gG] "$d"/*.[bB][mM][pP] "$d"/*.[gG][iI][fF]; do
                [ -f "$f" ] && [ ! -L "$f" ] && echo "$f" >> "$list"
            done
            [ -s "$list" ] && break
        done
    else
        for d in "$VD/screensaver" "$SYS/data/media/0/Screensaver" /mnt/onboard/.kobo/screensaver; do
            [ -d "$d" ] || continue
            for f in "$d"/*.[pP][nN][gG] "$d"/*.[jJ][pP][gG] "$d"/*.[jJ][pP][eE][gG] "$d"/*.[bB][mM][pP] "$d"/*.[gG][iI][fF] "$d"/*.[wW][eE][bB][pP]; do
                [ -f "$f" ] && [ ! -L "$f" ] || continue
                case "$f" in */default.png|*/default.PNG) continue ;; esac
                echo "$f" >> "$list"
            done
        done
    fi
    if [ "$smode" = wall ]; then
        for f in "$SYS/data/media/0/.vdhome/theme/wallpaper.png" \
                 "$SYS/data/media/0/.vdhome/theme/wallpaper.jpg" \
                 "$SYS/data/media/0/.vdhome/theme/wallpaper.jpeg" \
                 "$SYS/data/media/0/.vdhome/theme/wallpaper.webp"; do
            [ -f "$f" ] || continue
            echo "$f" >> "$list"
            t "screensaver: wall mode, using $f"
            break
        done
    fi
    n=$(wc -l < "$list" 2>/dev/null | tr -d ' ')
    # No screensaver image? Use the launcher wallpaper the user picked, so pressing
    # power always shows their picture instead of only the "已休眠" splash.
    if [ "${n:-0}" -eq 0 ]; then
        for f in "$SYS/data/media/0/.vdhome/theme/wallpaper.png" \
                 "$SYS/data/media/0/.vdhome/theme/wallpaper.jpg" \
                 "$SYS/data/media/0/.vdhome/theme/wallpaper.jpeg" \
                 "$SYS/data/media/0/.vdhome/theme/wallpaper.webp"; do
            [ -f "$f" ] || continue
            echo "$f" >> "$list"
            n=1
            t "screensaver: no saver image, using home wallpaper $f"
            break
        done
    fi
    if [ "${n:-0}" -eq 0 ] && [ -f "$VD/boot/screensaver-default.png" ]; then
        echo "$VD/boot/screensaver-default.png" >> "$list"
        n=1
        t "screensaver: using bundled default image"
    fi
    fb_img="$VD/bin/fbink-img"
    [ -x "$fb_img" ] || fb_img="$FBINK"
    if [ "${n:-0}" -gt 0 ] && [ -x "$fb_img" ]; then
        i=$(cat "$W/saver.index" 2>/dev/null || echo 0)
        case "$i" in ''|*[!0-9]*) i=0 ;; esac
        i=$(( (i % n) + 1 ))
        echo "$i" > "$W/saver.index"
        img=$(sed -n "${i}p" "$list")
        draw_img=$(saver_resolve_img "$img")
        if [ -f "$draw_img" ]; then
            if [ -p "$X/epd.fifo" ] && [ -f "$W/epd.pid" ] && kill -0 "$(cat "$W/epd.pid" 2>/dev/null)" 2>/dev/null; then
                ( printf 'IMG %s\n' "$draw_img" > "$X/epd.fifo" ) &
                sleep 1
                t "screensaver: img via bridge $draw_img"
                return 0
            fi
            if "$fb_img" -q -c -f -i "$draw_img" -g w=-2,h=-2,halign=CENTER,valign=CENTER,dither >/dev/null 2>&1; then
                t "screensaver: $img"
                return 0
            fi
            t "screensaver: fbink failed for $draw_img"
            if [ -f "$VD/boot/screensaver-default.png" ] \
               && "$fb_img" -q -c -f -i "$VD/boot/screensaver-default.png" -g w=-2,h=-2,halign=CENTER,valign=CENTER,dither >/dev/null 2>&1; then
                t "screensaver: fallback bundled default"
                return 0
            fi
        fi
    fi
    t "screensaver: no usable image (mode=${smode:-default}, n=${n:-0}, fbink=$([ -x "$fb_img" ] && echo yes || echo no)) -> splash"
    splash "已休眠 · 按电源键唤醒" 40 || true
}

kobo_rtc_wakeup_set() { # $1 = enabled|disabled
    want=$1
    if [ "$want" = disabled ]; then
        [ -w /sys/class/rtc/rtc0/wakealarm ] && echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
    fi
    for f in ${RTC_WAKEUP_PATHS:-} \
             /sys/class/rtc/rtc0/device/power/wakeup \
             /sys/class/rtc/rtc0/power/wakeup; do
        [ -n "$f" ] || continue
        [ -w "$f" ] && echo "$want" > "$f" 2>/dev/null || true
    done
}

kobo_wake_irq_supported() {
    awk -v names="${SUSPEND_IRQ_NAMES:-Power Hall PageUp PageDown}" '
        BEGIN { n = split(names, a, " ") }
        { for (i = 1; i <= n; i++) if ($NF == a[i]) { found = 1; exit } }
        END { exit !found }' /proc/interrupts 2>/dev/null
}

kobo_wake_irq_sum() {
    awk -v names="${SUSPEND_IRQ_NAMES:-Power Hall PageUp PageDown}" '
        BEGIN { n = split(names, a, " ") }
        { for (i = 1; i <= n; i++) if ($NF == a[i]) { s += $2; break } }
        END { print s + 0 }' /proc/interrupts 2>/dev/null
}

sleep_timeout_get() {
    _to=$(sed -n 's/^SLEEP_TIMEOUT=//p' "$SYS/settings.conf" 2>/dev/null | tail -n 1)
    case "$_to" in
        ''|*[!0-9]*) _to=${SLEEP_TIMEOUT:-600} ;;
    esac
    echo "$_to"
}

sleep_wait_1s() {
    # Interruptible 1s wait: wakes immediately if user presses power/wake while waiting for EPDC VEE stable.
    if [ "${SLEEP_FIFO_READY:-0}" = 1 ]; then
        if read -t 1 -r _ev <&4 2>/dev/null; then
            case "$_ev" in
                wake|power|toggle) return 2 ;;
            esac
        fi
    else
        sleep 1
    fi
    return 0
}

kobo_deep_suspend() {
    # Enter true Linux mem suspend on Kobo (drops standby draw from ~1.8%/h / 34mA to ~0.1%/h).
    # Skipped while charging so USB charging & SSH debugging stay uninterrupted (screensaver stays active).
    # Spurious RTC/PMIC wakeups (e.g. Android 10-min healthd/AlarmManager alarmtimer) are filtered by
    # checking hardware Power/Hall IRQ counters in /proc/interrupts and immediately re-suspending.
    # Return codes:
    #   0 = resumed by real user wakeup (Power key / Hall sleepcover)
    #   2 = cancelled by user power/wake press during pre-suspend wait
    #   1 = skipped or failed (caller stays in screensaver fallback)
    [ -w /sys/power/state ] || { t "sleep: no /sys/power/state"; return 1; }
    suspend_state=
    for _ss in ${SUSPEND_STATES:-mem}; do
        grep -qw "$_ss" /sys/power/state 2>/dev/null && { suspend_state=$_ss; break; }
    done
    [ -n "$suspend_state" ] || { t "sleep: no usable suspend state in '$(cat /sys/power/state 2>/dev/null)': cannot deep suspend"; return 1; }
    if kobo_is_charging; then
        t "sleep: deep suspend skipped (charging): $(kobo_power_summary)"
        return 1
    fi
    _bat0=$(kobo_battery); _dst0=$(date +%s)
    t "sleep: deep suspend $suspend_state (battery ${_bat0}%, available: $(cat /sys/power/state 2>/dev/null | tr '\n' ' '))"

    [ -f "$W/saver_nofreeze" ] && return 1

    # Power off SDIO Wi-Fi on models that load it out-of-tree, so the radio
    # cannot block suspend or leak current. MTK combo Wi-Fi is built in and
    # stays associated (SLEEP_WIFI_OFF=0): interface down/up would drop SSH and
    # force a reconnect on every wake.
    if [ "${SLEEP_WIFI_OFF:-1}" = 1 ] && [ "$(kobo_wifi_enabled)" = 1 ]; then
        echo 1 > "$W/sleep.wifi"
        kobo_wifi_set 0
        t "sleep: wifi powered off for deep suspend (state=$suspend_state)"
    elif [ ! -f "$W/sleep.wifi" ]; then
        rm -f "$W/sleep.wifi"
    fi

    sync

    # Kobo (1264x1680) mxc_epdc_v2_fb enforces dwSafeTicksEP3V3 = 900 ticks (9.0s @ HZ=100)
    # after epdc_powerdown() for VEE rail stabilization; earlier /sys/power/state writes fail with -2.
    # Wait interruptibly until >= 10s have elapsed since screensaver draw (and EPDC power_state is off).
    # MTK hwtcon has no such rail: SUSPEND_VEE_WAIT=0 skips the wait entirely.
    t0=$(cat "$W/saver.t0" 2>/dev/null || echo 0)
    case "$t0" in ''|*[!0-9]*) t0=0 ;; esac
    if [ "${SUSPEND_VEE_WAIT:-1}" = 1 ]; then
        w=0
        while [ $w -lt 12 ]; do
            if kobo_is_charging; then
                [ -w /sys/power/state-extended ] && echo 0 > /sys/power/state-extended 2>/dev/null || true
                t "sleep: deep suspend aborted (charger connected)"
                return 1
            fi
            now=$(date +%s)
            pstate=$(cat /sys/class/graphics/fb0/power_state 2>/dev/null || echo off)
            if [ "$pstate" = off ] && { [ "$t0" -eq 0 ] || [ $((now - t0)) -ge 10 ] || [ "$now" -lt "$t0" ]; }; then
                break
            fi
            sleep_wait_1s
            if [ $? -eq 2 ]; then
                [ -w /sys/power/state-extended ] && echo 0 > /sys/power/state-extended 2>/dev/null || true
                t "sleep: deep suspend cancelled by user wakeup"
                return 2
            fi
            w=$((w + 1))
        done
    fi

    rc=1
    spurious_burst=0
    spurious_t0=0
    while :; do
        kobo_is_charging && { rc=1; break; }
        i=0
        mem_ok=0
        rm -f "$W/suspend.err"
        [ -w /sys/power/state-extended ] && echo 1 > /sys/power/state-extended 2>/dev/null || true
        # Disable hardware RTC wakeups across mem suspend; also guard against kernel alarmtimer
        # re-arming rtc_ricoh619 inside suspend_devices_and_enter() via Power/Hall IRQ check below.
        kobo_rtc_wakeup_set disabled
        irq_before=$(kobo_wake_irq_sum)
        while [ $i -lt 8 ]; do
            kobo_is_charging && break
            i=$((i + 1))
            _st0=$(date +%s)
            if echo "$suspend_state" > /sys/power/state 2>"$W/suspend.err"; then
                mem_ok=1
                t "sleep: left $suspend_state after $(( $(date +%s) - _st0 ))s"
                break
            fi
            sleep_wait_1s
            if [ $? -eq 2 ]; then
                kobo_rtc_wakeup_set enabled
                [ -w /sys/power/state-extended ] && echo 0 > /sys/power/state-extended 2>/dev/null || true
                t "sleep: deep suspend cancelled by user wakeup (after $i tries)"
                return 2
            fi
        done

        if [ "$mem_ok" -ne 1 ]; then
            rc=1
            break
        fi

        # Give GPIO/PMIC IRQ accounting a brief moment to settle, then check if Power or Hall woke us.
        usleep 150000
        irq_after=$(kobo_wake_irq_sum)
        if [ "${irq_after:-0}" != "${irq_before:-0}" ]; then
            rc=0
            t "sleep: real user wakeup from mem suspend (tries=$i irq $irq_before->$irq_after)"
            break
        fi
        # MTK boards do not expose the i.MX IRQ labels. Trust the first resume
        # (SUSPEND_TRUST_WAKE=1) instead of treating every wake as a spurious
        # RTC alarm and re-suspending five times.
        if [ "${SUSPEND_TRUST_WAKE:-0}" = 1 ] && ! kobo_wake_irq_supported; then
            rc=0
            t "sleep: woke from mem suspend (IRQ accounting unavailable, trusting wake)"
            break
        fi

        # If a charger was plugged in during mem suspend, stay in charging screensaver (do not light up screen).
        if kobo_is_charging; then
            rc=1
            t "sleep: mem suspend ended on charger connect, staying in charging screensaver"
            break
        fi

        # N428/MTK: the PMIC power-key IRQ counter often does not move on wake. vinput turns
        # the press into a power/toggle FIFO event within ~100 ms of resume; wait briefly for
        # it and treat that as a real user wake before assuming an RTC/PMIC spurious wakeup.
        if [ "${SLEEP_FIFO_READY:-0}" = 1 ]; then
            _w=0
            while [ "$_w" -lt 8 ]; do
                if read -t 0.1 -r _ev <&4 2>/dev/null; then
                    case "$_ev" in
                        wake|power|toggle) _w=99; break ;;
                    esac
                fi
                _w=$((_w + 1))
            done
            if [ "$_w" = 99 ]; then
                rc=0
                t "sleep: real user wakeup (power event after mem, tries=$i)"
                break
            fi
        fi

        # Spurious wakeup (e.g. kernel alarmtimer / rtc_ricoh61x 10-min alarm or PMIC noise): re-suspend silently.
        now_s=$(date +%s)
        if [ "$spurious_t0" -eq 0 ] || [ $((now_s - spurious_t0)) -gt 30 ]; then
            spurious_t0=$now_s
            spurious_burst=1
        else
            spurious_burst=$((spurious_burst + 1))
        fi
        t "sleep: ignoring spurious mem wakeup (tries=$i irq=$irq_after burst=$spurious_burst), re-suspending"
        if [ "$spurious_burst" -ge 5 ]; then
            t "sleep: spurious wakeup burst limit reached, falling back to screensaver"
            rc=1
            break
        fi
        sleep_wait_1s
        if [ $? -eq 2 ]; then
            kobo_rtc_wakeup_set enabled
            [ -w /sys/power/state-extended ] && echo 0 > /sys/power/state-extended 2>/dev/null || true
            t "sleep: user wakeup pressed during re-suspend wait"
            return 2
        fi
    done

    # Resume subsystems immediately on real wakeup or fallback.
    kobo_rtc_wakeup_set enabled
    [ -w /sys/power/state-extended ] && echo 0 > /sys/power/state-extended 2>/dev/null || true
    usleep 250000
    if [ "$rc" -ne 0 ]; then
        err=$(tr '\n' ' ' < "$W/suspend.err" 2>/dev/null)
        t "sleep: left deep suspend (rc=$rc err=${err:-charger_or_retry})"
    fi
    t "sleep: deep suspend $suspend_state ended rc=$rc after $(( $(date +%s) - _dst0 ))s, battery ${_bat0}% -> $(kobo_battery)%"
    return $rc
}

sleep_transfer_busy() {
    [ -f "$W/fwd.id" ] || alive "$W/installing" || [ -f "$W/compile.lock" ] || alive "$W/compile.guard"
}

kobo_enter_sleep() {
    [ -f "$W/saver_frozen" ] || [ -f "$W/sleeping" ] && return 0
    touch "$W/sleeping" "$X/ctl/sleep"
    kobo_wifi_enabled > "$W/wifi.was" 2>/dev/null || true
    type lock_request >/dev/null 2>&1 && lock_request
    usleep 250000
    cur_fl=$(kobo_light_get)
    if [ "${cur_fl:-0}" -eq 0 ] && [ -f "$W/fl.dimmed" ]; then
        dim_fl=$(tr -cd '0-9' < "$W/fl.dimmed" 2>/dev/null)
        [ "${dim_fl:-0}" -gt 0 ] && cur_fl=$dim_fl
        rm -f "$W/fl.dimmed"
    fi
    echo "${cur_fl:-0}" > "$W/sleep.fl"
    kobo_light_set 0
    if sleep_transfer_busy; then
        touch "$W/saver_nofreeze"
        t "sleep: transfer/install in progress, leaving android running"
    else
        android_freeze && touch "$W/saver_frozen"
        type wifi_ps_restore >/dev/null 2>&1 && wifi_ps_restore
    fi
    screensaver_show
    usleep 400000
    date +%s > "$W/saver.t0"
    t "sleep: entered screensaver (saved frontlight=$cur_fl, charging=$(kobo_is_charging && echo 1 || echo 0))"
    t "sleep: power: $(kobo_power_summary)"

    kobo_deep_suspend
    ds_rc=$?
    if [ "$ds_rc" -eq 0 ]; then
        kobo_exit_sleep
        MEM_WAKE_TS=$(date +%s)
    elif [ "$ds_rc" -eq 2 ]; then
        kobo_exit_sleep
    fi
}

kobo_exit_sleep() {
    [ -f "$W/sleeping" ] || [ -f "$W/saver_frozen" ] || return 0
    [ -w /sys/power/state-extended ] && echo 0 > /sys/power/state-extended 2>/dev/null || true
    if [ -f "$W/saver_nofreeze" ]; then
        rm -f "$W/saver_nofreeze"
    else
        android_thaw 2>/dev/null || true
    fi
    rm -f "$W/saver_frozen" "$W/sleeping"
    if [ -f "$W/sleep.fl" ]; then
        kobo_light_set "$(cat "$W/sleep.fl" 2>/dev/null)"
        rm -f "$W/sleep.fl"
    fi
    touch "$W/lastinput" "$X/lasttouch" 2>/dev/null || true
    chmod 644 "$X/lasttouch" 2>/dev/null || true
    rm -f "$X/ctl/sleep"
    # Reset vinput slot state again after opening the sleep gate so any stale Elan resume event is cleared.
    type vinput_reset >/dev/null 2>&1 && vinput_reset thaw
    epd_send REDRAW
    type status_write >/dev/null 2>&1 && status_write 2>/dev/null || true
    if [ -f "$W/sleep.wifi" ]; then
        rm -f "$W/sleep.wifi"
        (
            kobo_wifi_set 1
            type hostnet_write >/dev/null 2>&1 && hostnet_write
            type wifi_ps_set >/dev/null 2>&1 && wifi_ps_set on
            type status_write >/dev/null 2>&1 && status_write 2>/dev/null || true
            t "sleep: wifi restored after wakeup"
        ) </dev/null >>"$LOG" 2>&1 &
    else
        type wifi_resume >/dev/null 2>&1 && ( wifi_resume ) </dev/null >>"$LOG" 2>&1 &
    fi
    t "sleep: woke up and redrew screen (battery $(kobo_battery)%)"
}

sleep_watch() {
    pf=$W/power.fifo
    rm -f "$pf"; mkfifo "$pf" 2>/dev/null || return 1
    chmod 666 "$pf"
    touch "$W/lastinput" "$X/lasttouch" 2>/dev/null || true
    chmod 644 "$X/lasttouch" 2>/dev/null || true
    exec 4<>"$pf"
    SLEEP_FIFO_READY=1
    MEM_WAKE_TS=0
    SUSPEND_BACKOFF_UNTIL=0
    while :; do
        # Non-blocking check with 15s timeout (FIFO events still wake immediately with 0ms latency)
        if read -t 15 -r ev <&4 2>/dev/null; then
            case "$ev" in
                toggle|power)
                    if [ -f "$W/sleeping" ] || [ -f "$W/saver_frozen" ]; then
                        SUSPEND_BACKOFF_UNTIL=0
                        kobo_exit_sleep
                    else
                        now=$(date +%s)
                        if [ "${MEM_WAKE_TS:-0}" -gt 0 ] && [ $((now - MEM_WAKE_TS)) -lt 2 ]; then
                            t "sleep: ignoring trailing $ev right after mem wakeup"
                            continue
                        fi
                        SUSPEND_BACKOFF_UNTIL=0
                        kobo_enter_sleep
                    fi ;;
                sleep) SUSPEND_BACKOFF_UNTIL=0; kobo_enter_sleep ;;
                wake)  SUSPEND_BACKOFF_UNTIL=0; kobo_exit_sleep ;;
            esac
            continue
        fi
        # While sleeping in screensaver fallback (e.g. unplugged after charging sleep or transient suspend failure),
        # automatically upgrade to true mem deep suspend once not charging.
        if [ -f "$W/sleeping" ]; then
            now=$(date +%s)
            if ! kobo_is_charging && [ ! -f "$W/saver_nofreeze" ] && [ "$now" -ge "${SUSPEND_BACKOFF_UNTIL:-0}" ]; then
                kobo_deep_suspend
                ds_rc=$?
                if [ "$ds_rc" -eq 0 ]; then
                    SUSPEND_BACKOFF_UNTIL=0
                    kobo_exit_sleep
                    MEM_WAKE_TS=$(date +%s)
                elif [ "$ds_rc" -eq 2 ]; then
                    SUSPEND_BACKOFF_UNTIL=0
                    kobo_exit_sleep
                elif ! kobo_is_charging; then
                    SUSPEND_BACKOFF_UNTIL=$(( $(date +%s) + 120 ))
                fi
            fi
            continue
        fi
        # Idle timeout check (runs both on battery and while charging; deep mem suspend is skipped while charging)
        to=$(sleep_timeout_get)
        case "$to" in ''|0|*[!0-9]*) continue ;; esac
        last=$(stat -c %Y "$W/lastinput" 2>/dev/null || echo 0)
        now=$(date +%s)
        if [ "$last" -gt "$now" ]; then
            touch "$W/lastinput" "$X/lasttouch" 2>/dev/null || true
    chmod 644 "$X/lasttouch" 2>/dev/null || true
            last=$now
        fi
        if [ "$last" -gt 0 ] && [ $((now - last)) -ge "$to" ]; then
            if sleep_transfer_busy; then
                touch "$W/lastinput" "$X/lasttouch" 2>/dev/null || true
    chmod 644 "$X/lasttouch" 2>/dev/null || true
                continue
            fi
            t "sleep: idle ${to}s reached (charging=$(kobo_is_charging && echo 1 || echo 0))"
            kobo_enter_sleep
        fi
    done
}
