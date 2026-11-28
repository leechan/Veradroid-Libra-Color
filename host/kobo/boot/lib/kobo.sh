# SPDX-License-Identifier: GPL-3.0-or-later
# Kobo hardware abstraction layer (HAL) for Libra 2 (N418) and Libra Colour (N428).
# Replaces Kindle lipc/powerd/wifid calls with direct Kobo sysfs / wpa_cli / busybox helpers.

# Kobo's /bin/busybox compiles in unshare & nsenter, but does not symlink them into PATH.
unshare() { busybox unshare "$@"; }
nsenter() { busybox nsenter "$@"; }

kobo_model() {
    ver=$(cat /mnt/onboard/.kobo/version 2>/dev/null)
    case "$ver" in
        N428*) echo libracolour ;;
        N418*) echo libra2 ;;
        *)
            case "$(cat /proc/device-tree/model 2>/dev/null)" in
                *"Libra Colour"*|*"Libra Color"*) echo libracolour ;;
                *"Libra 2"*) echo libra2 ;;
                *) echo libra2 ;;
            esac ;;
    esac
}

kobo_model_name() {
    case "$(kobo_model)" in
        libracolour) echo "Kobo Libra Colour" ;;
        *)           echo "Kobo Libra 2" ;;
    esac
}

kobo_model_code() {
    case "$(kobo_model)" in
        libracolour) echo N428 ;;
        *)           echo N418 ;;
    esac
}

kobo_is_mtk() {
    case "$(kobo_model)" in libracolour) return 0 ;; esac
    return 1
}

kobo_firmware() {
    awk -F, '{print $3}' /mnt/onboard/.kobo/version 2>/dev/null
}

# Battery capacity (0..100) and charging state (returns 0 if charging/external power).
kobo_battery() {
    for n in ${BATTERY_NODES:-mc13892_bat battery}; do
        p=/sys/class/power_supply/$n/capacity
        [ -r "$p" ] || continue
        v=$(cat "$p" 2>/dev/null | tr -cd '0-9')
        [ -n "$v" ] && { echo "$v"; return 0; }
    done
    for p in /sys/class/power_supply/*/capacity; do
        [ -r "$p" ] || continue
        v=$(cat "$p" 2>/dev/null | tr -cd '0-9')
        [ -n "$v" ] && { echo "$v"; return 0; }
    done
    echo 0
}

# one-line snapshot of all power_supply nodes (diagnosing wrong charge detection: a
# node that reports online=1 on battery keeps deep suspend disabled and drains it)
kobo_power_summary() {
    _s=
    for _p in /sys/class/power_supply/*; do
        [ -d "$_p" ] || continue
        _n=${_p##*/}
        _st=$(cat "$_p/status" 2>/dev/null)
        _on=$(cat "$_p/online" 2>/dev/null)
        _cp=$(cat "$_p/capacity" 2>/dev/null)
        _s="$_s $_n(status=${_st:-?} online=${_on:--} cap=${_cp:--})"
    done
    echo "${_s# }"
}

kobo_is_charging() {
    for n in ${BATTERY_NODES:-mc13892_bat battery}; do
        st=$(cat "/sys/class/power_supply/$n/status" 2>/dev/null)
        case "$st" in Charging|Full) return 0 ;; esac
    done
    for n in ${CHARGER_NODES:-acpwr usbpwr}; do
        for f in "/sys/class/power_supply/$n/online" "/sys/class/power_supply/$n/status"; do
            [ -r "$f" ] || continue
            v=$(cat "$f" 2>/dev/null)
            case "$v" in
                Charging|Full) return 0 ;;
                *) v=$(printf '%s' "$v" | tr -cd '0-9'); [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null && return 0 ;;
            esac
        done
    done
    # Fallback: any supply that says it is online. Skip Battery nodes: on N428
    # bd71827_bat reports online=1 ("battery present") while discharging, which
    # used to look like a charger and disabled deep suspend entirely.
    for p in /sys/class/power_supply/*/online; do
        d=${p%/online}
        [ "$(cat "$d/type" 2>/dev/null)" = Battery ] && continue
        case "${d##*/}" in *bat*) continue ;; esac
        v=$(cat "$p" 2>/dev/null | tr -cd '0-9')
        [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null && return 0
    done
    return 1
}

# Frontlight brightness: 0..100 via /sys/class/backlight/<FL_COLD>/brightness
# ComfortLight PRO color mixer: 0..10, inverted (10 = coolest / 0 warmth, 0 = warmest / 24 warmth).
# Paths and range come from the model profile (FL_COLD / FL_WARM / FL_MAX).
KOBO_BL_BRIGHT=/sys/class/backlight/mxc_msp430.0/brightness
KOBO_BL_MAX=100
KOBO_BL_COLOR=/sys/class/backlight/lm3630a_led/color
KOBO_BL_COLOR_MAX=10

kobo_light_init() {
    KOBO_BL_BRIGHT=/sys/class/backlight/${FL_COLD:-mxc_msp430.0}/brightness
    KOBO_BL_COLOR=/sys/class/backlight/${FL_WARM:-lm3630a_led}/color
    KOBO_BL_MAX=${FL_MAX:-100}
    KOBO_BL_COLOR_MAX=10
}
kobo_light_init

kobo_has_light() { [ -w "$KOBO_BL_BRIGHT" ]; }
kobo_has_warmth() { [ -w "$KOBO_BL_COLOR" ]; }

kobo_light_get() {
    [ -r "$KOBO_BL_BRIGHT" ] || { echo 0; return 1; }
    v=$(cat "$KOBO_BL_BRIGHT" 2>/dev/null | tr -cd '0-9')
    echo "${v:-0}"
}

kobo_light_set() {
    v=$1
    case "$v" in ''|*[!0-9]*) return 1 ;; esac
    [ "$v" -lt 0 ] && v=0
    [ "$v" -gt "$KOBO_BL_MAX" ] && v=$KOBO_BL_MAX
    [ -w "$KOBO_BL_BRIGHT" ] && printf '%d\n' "$v" > "$KOBO_BL_BRIGHT" 2>/dev/null
    # 记住最后一次非零亮度：唤醒时驱动偶尔会把亮度清成 0，靠它兜底
    [ "$v" -gt 0 ] && [ -n "$W" ] && echo "$v" > "$W/fl.last" 2>/dev/null || true
    return 0
}

# VeraHome warmth scale is 0..24 (0 = cool, 24 = warmest).
# Kobo lm3630a_led/color is 10..0 (10 = cool, 0 = warmest).
kobo_warmth_get() {
    [ -r "$KOBO_BL_COLOR" ] || { echo 0; return 1; }
    raw=$(cat "$KOBO_BL_COLOR" 2>/dev/null | tr -cd '0-9')
    [ -n "$raw" ] || { echo 0; return 1; }
    [ "$raw" -gt "$KOBO_BL_COLOR_MAX" ] && raw=$KOBO_BL_COLOR_MAX
    inv=$(( KOBO_BL_COLOR_MAX - raw ))
    echo $(( (inv * 24 + KOBO_BL_COLOR_MAX / 2) / KOBO_BL_COLOR_MAX ))
}

kobo_warmth_set() {
    v=$1
    case "$v" in ''|*[!0-9]*) return 1 ;; esac
    [ "$v" -lt 0 ] && v=0
    [ "$v" -gt 24 ] && v=24
    inv=$(( (v * KOBO_BL_COLOR_MAX + 12) / 24 ))
    raw=$(( KOBO_BL_COLOR_MAX - inv ))
    [ "$raw" -lt 0 ] && raw=0
    [ "$raw" -gt "$KOBO_BL_COLOR_MAX" ] && raw=$KOBO_BL_COLOR_MAX
    [ -w "$KOBO_BL_COLOR" ] && printf '%d\n' "$raw" > "$KOBO_BL_COLOR" 2>/dev/null
}

# Wi-Fi helpers (wlan0 + wpa_cli)
kobo_wifi_if() { echo "${WIFI_IF:-wlan0}"; }

kobo_wifi_ip() {
    ifconfig "$(kobo_wifi_if)" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -1
}

kobo_wifi_enabled() {
    dev=$(kobo_wifi_if)
    [ -d "/sys/class/net/$dev" ] || { echo 0; return 0; }
    st=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null)
    case "$st" in
        down) echo 0 ;;
        *)    [ -n "$(kobo_wifi_ip)" ] || [ "$st" = up ] && echo 1 || echo 0 ;;
    esac
}

# Report active SSH server listening port (e.g. 2222 for KOReader dropbear, 22 for sshd), or 0 if not running.
kobo_ssh_port() {
    if pidof dropbear >/dev/null 2>&1 || pidof sshd >/dev/null 2>&1; then
        if awk 'NR>1 && $4=="0A" && $2 ~ /:08AE$/ { found=1; exit } END { exit !found }' /proc/net/tcp 2>/dev/null; then
            echo 2222; return 0
        fi
        if awk 'NR>1 && $4=="0A" && $2 ~ /:0016$/ { found=1; exit } END { exit !found }' /proc/net/tcp 2>/dev/null; then
            echo 22; return 0
        fi
        p=$(netstat -tln 2>/dev/null | awk '$6=="LISTEN" && $4 ~ /:[0-9]+$/ { sub(/.*:/, "", $4); if ($4==2222 || $4==22) { print $4; exit } }')
        [ -n "$p" ] && { echo "$p"; return 0; }
    fi
    echo 0
}

kobo_wifi_set() { # $1 = 0|1
    dev=$(kobo_wifi_if)
    if [ "$1" = 0 ]; then
        cp -a /etc/resolv.conf /tmp/vd-resolv.bak 2>/dev/null || true
        if [ -x /sbin/dhcpcd ]; then
            /sbin/dhcpcd -k "$dev" >/dev/null 2>&1 || true
        fi
        killall -q -TERM udhcpc dhcpcd 2>/dev/null || true
        command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" terminate >/dev/null 2>&1 || true
        killall -q -TERM wpa_supplicant 2>/dev/null || true
        usleep 200000
        rm -f "/var/run/wpa_supplicant/$dev"
        ifconfig "$dev" down 2>/dev/null || true
        # Only unload SDIO modules on models that load them out-of-tree (i.MX6).
        # MTK combo Wi-Fi is built into 4.9.77; leaving it loaded keeps the
        # interface recoverable without a full driver re-init.
        if [ -n "${WIFI_MODULES:-}" ]; then
            wdir=${WIFI_KO_DIR:-/drivers/mx6sll-ntx/wifi}
            rev=
            for n in $WIFI_MODULES; do rev="$n $rev"; done
            for n in $rev; do
                if grep -q "^$n " /proc/modules 2>/dev/null; then
                    usleep 200000
                    rmmod "$n" >/dev/null 2>&1 || true
                fi
            done
        fi
        [ -s /tmp/vd-resolv.bak ] && [ ! -s /etc/resolv.conf ] && mv -f /tmp/vd-resolv.bak /etc/resolv.conf 2>/dev/null || rm -f /tmp/vd-resolv.bak
    elif [ "$1" = 1 ]; then
        if [ -n "${WIFI_MODULES:-}" ]; then
            wdir=${WIFI_KO_DIR:-/drivers/mx6sll-ntx/wifi}
            for n in $WIFI_MODULES; do
                if ! grep -q "^$n " /proc/modules 2>/dev/null && [ -f "$wdir/$n.ko" ]; then
                    insmod "$wdir/$n.ko" >/dev/null 2>&1 || true
                    usleep 250000
                fi
            done
            sleep 1
        fi
        ifconfig "$dev" up 2>/dev/null || true
        t "wifi: up iface=$([ -d /sys/class/net/$dev ] && echo yes || echo no) oper=$(cat /sys/class/net/$dev/operstate 2>/dev/null) mods=$(grep -iE 'wlan|mtk|mt76|gen4' /proc/modules 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ')"
        if ! kobo_wpa_ensure >/dev/null 2>&1; then t "wifi: wpa_supplicant could not start"; fi
        command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" reconnect >/dev/null 2>&1 || true
        # Wait for the supplicant to associate before asking for a lease.
        # A sleepy AP can stay in SCANNING for a while: nudge it twice before giving up.
        i=0
        while [ $i -lt 40 ]; do
            st=$(wpa_cli -i "$dev" status 2>/dev/null | sed -n 's/^wpa_state=//p')
            case "$st" in COMPLETED|ASSOCIATED) break ;; esac
            if [ $i -eq 12 ] || [ $i -eq 26 ]; then
                wpa_cli -i "$dev" reassociate >/dev/null 2>&1 || true
            fi
            sleep 1; i=$((i + 1))
        done
        t "wifi: state=${st:-?} after ${i}s"
        if [ -x /sbin/dhcpcd ]; then
            /sbin/dhcpcd -d -t 20 -w "$dev" >/dev/null 2>&1 || true
        else
            udhcpc -S -i "$dev" -s /etc/udhcpc.d/default.script -b -q >/dev/null 2>&1 || true
        fi
        # Wait for the lease; retry once for a slow AP
        i=0
        while [ $i -lt 10 ]; do
            [ -n "$(kobo_wifi_ip)" ] && break
            sleep 1; i=$((i + 1))
        done
        if [ -z "$(kobo_wifi_ip)" ]; then
            wpa_cli -i "$dev" reassociate >/dev/null 2>&1 || true
            sleep 3
            if [ -x /sbin/dhcpcd ]; then
                /sbin/dhcpcd -k "$dev" >/dev/null 2>&1 || true
                /sbin/dhcpcd -d -t 20 -w "$dev" >/dev/null 2>&1 || true
            fi
            i=0
            while [ $i -lt 15 ]; do
                [ -n "$(kobo_wifi_ip)" ] && break
                sleep 1; i=$((i + 1))
            done
        fi
        t "wifi: ip=$(kobo_wifi_ip)" 
    fi
}

kobo_wpa_conf() {
    for c in /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant.conf /mnt/onboard/.kobo/wpa_supplicant.conf; do
        [ -f "$c" ] && { echo "$c"; return 0; }
    done
    echo /etc/wpa_supplicant/wpa_supplicant.conf
}

kobo_wpa_ensure() {
    drv=${1:-nl80211}
    dev=$(kobo_wifi_if)
    sock=/var/run/wpa_supplicant/$dev
    # A socket left behind after a sleep/Wi-Fi-off cycle is not a live supplicant.
    # Check the process too, otherwise every later connect silently fails.
    if [ -S "$sock" ] && pidof wpa_supplicant >/dev/null 2>&1; then return 0; fi
    [ -S "$sock" ] && rm -f "$sock"
    conf=$(kobo_wpa_conf)
    t "wifi: ensure dev=$dev iface=$([ -d /sys/class/net/$dev ] && echo yes || echo no) oper=$(cat /sys/class/net/$dev/operstate 2>/dev/null) conf=$conf wpa=$(command -v wpa_supplicant)"
    [ -f "$conf" ] || { t "wifi: wpa config missing"; return 1; }
    command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi 2>/dev/null || true
    mkdir -p /var/run/wpa_supplicant 2>/dev/null || true
    killall -q -TERM wpa_supplicant 2>/dev/null || true
    usleep 400000
    killall -q -KILL wpa_supplicant 2>/dev/null || true
    rm -f "$sock"
    _werr=$(wpa_supplicant -D "$drv" -s -i "$dev" -c "$conf" -C /var/run/wpa_supplicant -B 2>&1)
    _wrc=$?
    if [ "$_wrc" != 0 ]; then t "wifi: wpa start rc=$_wrc err=$_werr"; return 1; fi
    i=0
    while [ $i -lt 15 ]; do
        [ -S "$sock" ] && pidof wpa_supplicant >/dev/null 2>&1 && return 0
        usleep 200000; i=$((i + 1))
    done
    return 1
}

# 连不上时留一份现场：模块、固件消息、supplicant 状态都记到 logs/wifi-diag.txt
wifi_diag() {
    f="$VD/logs/wifi-diag.txt"
    mkdir -p "$VD/logs" 2>/dev/null || true
    [ -f "$f" ] && [ "$(wc -c < "$f" 2>/dev/null || echo 0)" -gt 262144 ] && mv -f "$f" "$f.1" 2>/dev/null || true
    dev=$(kobo_wifi_if)
    {
        echo "=== $(date '+%F %T') $* ==="
        echo "--- modules"; grep -E 'wlan_drv|wmt_|cfg80211|mtk' /proc/modules 2>/dev/null
        echo "--- module files"
        for d in /lib/modules/$(uname -r) /usr/lib/modules/$(uname -r) /drivers; do
            [ -d "$d" ] || continue
            find "$d" -maxdepth 8 \( -name 'wlan_drv_gen4m.ko*' -o -name 'wmt_chrdev_wifi.ko*' -o -name 'wmt_drv.ko*' \) 2>/dev/null | head -10
        done
        echo "--- dmesg (wifi/wmt)"
        dmesg 2>/dev/null | grep -i -E 'wlan|wifi|wmt|stp|conninfra|8723|cfg80211' | tail -60
        echo "--- scan"
        wpa_cli -i "$dev" scan >/dev/null 2>&1
        sleep 3
        wpa_cli -i "$dev" scan_results 2>&1 | head -25
        echo "--- addr / route"
        ip -4 addr show dev "$dev" 2>&1 | head -5
        ip route 2>&1 | head -5
        echo "--- ping"
        gw=$(ip route 2>/dev/null | awk '$1 == "default" { for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')
        [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && echo "gw $gw ok" || echo "gw ${gw:-?} unreachable"
        ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1 && echo "dns 223.5.5.5 ok" || echo "dns 223.5.5.5 unreachable"
        echo "--- scan bands"
        wpa_cli -i "$dev" scan_results 2>/dev/null | awk 'NR > 1 { if ($2 < 3000) a++; else b++ } END { print "2.4G=" a+0 " 5G=" b+0 }'
        echo "--- reg"
        iw reg get 2>&1 | head -6
        echo "--- networks"
        wpa_cli -i "$dev" list_networks 2>&1 | head -15
        echo "--- supplicant"
        wpa_cli -i "$dev" status 2>&1 | head -20
        echo "--- iface"
        ifconfig "$dev" 2>&1 | head -5
        echo
    } >> "$f" 2>/dev/null
}

# 长时间休眠后 MTK 组合 Wi-Fi 有时整个卡住：supplicant 起得来，但扫不到 / 连不上、拿不到地址。
# 把接口彻底 down/up 一次、清掉旧 socket 再重启 supplicant，多数情况下能救回来。
wifi_hard_recover() {
    dev=$(kobo_wifi_if)
    t "wifi: hard recover on $dev"
    command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" terminate >/dev/null 2>&1 || true
    killall -q -TERM wpa_supplicant 2>/dev/null || true
    usleep 300000
    killall -q -KILL wpa_supplicant 2>/dev/null || true
    rm -f "/var/run/wpa_supplicant/$dev"
    ifconfig "$dev" down 2>/dev/null || true
    sleep 1
    ifconfig "$dev" up 2>/dev/null || true
    sleep 1
    kobo_wpa_ensure >/dev/null 2>&1 || t "wifi: hard recover: supplicant restart failed"
    command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" reconnect >/dev/null 2>&1 || true
    # 唤醒后 nl80211 有时扫不到任何 AP（scan 一直超时），换 wext 再试一次
    sleep 2
    if ! wifi_scan_ok; then
        t "wifi: hard recover: no scan results, retrying supplicant with wext"
        kobo_wpa_ensure wext >/dev/null 2>&1 || t "wifi: hard recover: wext supplicant failed"
        command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" reconnect >/dev/null 2>&1 || true
    else
        t "wifi: hard recover: scan sees APs"
    fi
}

# 唤醒后这个 MTK 驱动经常只能扫到 5GHz：如果同名 -5G 网络已经保存过，就直接切过去
wifi_try_saved_5g() {
    dev=$(kobo_wifi_if)
    command -v wpa_cli >/dev/null 2>&1 || return 1
    cur=$(kobo_wifi_current)
    [ -n "$cur" ] || return 1
    case "$cur" in *-5G) return 1 ;; esac
    nid=$(wpa_cli -i "$dev" list_networks 2>/dev/null | awk -F'\t' -v s="$cur-5G" 'NR > 1 && $2 == s { print $1; exit }')
    [ -n "$nid" ] || return 1
    wpa_cli -i "$dev" scan >/dev/null 2>&1
    sleep 3
    wpa_cli -i "$dev" scan_results 2>/dev/null | grep -q "	$cur-5G$" || return 1
    t "wifi: 2.4G not visible, switching to saved $cur-5G"
    wpa_cli -i "$dev" select_network "$nid" >/dev/null 2>&1
}

# 彻底重启 MTK 组合 Wi-Fi：按依赖顺序卸掉 4 个模块（含蓝牙那个，否则 wmt_drv 卸不掉），
# 再按依赖顺序装回来。中途任何一步失败就回滚（把已卸的装回去），不会把 wlan0 弄丢。
WIFI_KO_DIR_MTK=/drivers/mt8113t-ntx/mt66xx
wifi_stack_load_missing() {
    for m in wmt_drv wmt_chrdev_wifi wmt_cdev_bt wlan_drv_gen4m; do
        if ! grep -q "^$m " /proc/modules 2>/dev/null; then
            insmod "$WIFI_KO_DIR_MTK/$m.ko" 2>/dev/null || t "wifi: insmod $m failed"
        fi
        sleep 1
    done
}

wifi_stack_restart() {
    dev=$(kobo_wifi_if)
    for m in wlan_drv_gen4m wmt_chrdev_wifi wmt_cdev_bt wmt_drv; do
        [ -f "$WIFI_KO_DIR_MTK/$m.ko" ] || { t "wifi restart: $m.ko missing"; return 1; }
    done
    t "wifi: restarting combo stack"
    type wifi_diag >/dev/null 2>&1 && wifi_diag "before stack restart"
    command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" terminate >/dev/null 2>&1 || true
    killall -q -TERM wpa_supplicant 2>/dev/null || true
    killall -q -TERM wmt_launcher 2>/dev/null || true
    usleep 300000
    killall -q -KILL wpa_supplicant wmt_launcher 2>/dev/null || true
    ifconfig "$dev" down 2>/dev/null || true
    rm -f "/var/run/wpa_supplicant/$dev"
    sleep 1
    for m in wlan_drv_gen4m wmt_chrdev_wifi wmt_cdev_bt wmt_drv; do
        rmmod "$m" 2>/dev/null || true
        if grep -q "^$m " /proc/modules 2>/dev/null; then
            t "wifi restart: cannot unload $m, rolling back"
            wifi_stack_load_missing
            ifconfig "$dev" up 2>/dev/null || true
            kobo_wpa_ensure >/dev/null 2>&1 || true
            return 1
        fi
        sleep 1
    done
    wifi_stack_load_missing
    sleep 3
    if [ ! -d "/sys/class/net/$dev" ]; then
        t "wifi restart: $dev did not appear"
        return 1
    fi
    ifconfig "$dev" up 2>/dev/null || true
    kobo_wpa_ensure >/dev/null 2>&1 || t "wifi restart: supplicant failed"
    command -v wpa_cli >/dev/null 2>&1 && wpa_cli -i "$dev" reconnect >/dev/null 2>&1 || true
    t "wifi restart: stack back up"
    return 0
}

# 扫一次：3 秒内有任何 AP（scan_results 的表头之外还有行）就算射频正常
wifi_scan_ok() {
    dev=$(kobo_wifi_if)
    command -v wpa_cli >/dev/null 2>&1 || return 1
    wpa_cli -i "$dev" scan >/dev/null 2>&1
    sleep 3
    n=$(wpa_cli -i "$dev" scan_results 2>/dev/null | awk 'NR > 1 { c++ } END { print c + 0 }')
    [ "${n:-0}" -gt 0 ]
}

kobo_wifi_current() {
    dev=$(kobo_wifi_if); cur=
    if [ -S "/var/run/wpa_supplicant/$dev" ] && command -v wpa_cli >/dev/null 2>&1; then
        cur=$(wpa_cli -i "$dev" status 2>/dev/null | sed -n 's/^ssid=//p' | head -1)
    fi
    if [ -z "$cur" ] && command -v iwconfig >/dev/null 2>&1; then
        cur=$(iwconfig "$dev" 2>/dev/null | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p' | head -1)
    fi
    [ -n "$cur" ] && printf '%s\n' "$cur"
}

kobo_wifi_saved() {
    dev=$(kobo_wifi_if); out=
    if [ -S "/var/run/wpa_supplicant/$dev" ] && command -v wpa_cli >/dev/null 2>&1; then
        out=$(wpa_cli -i "$dev" list_networks 2>/dev/null | awk -F'\t' 'NR > 1 && $2 != "" { print $2 }' | head -50)
    fi
    if [ -z "$out" ]; then
        conf=$(kobo_wpa_conf)
        [ -r "$conf" ] && out=$(sed -n 's/^[[:space:]]*ssid="\([^"]*\)".*/\1/p' "$conf" 2>/dev/null | head -50)
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
}

kobo_wifi_select() { # $1 = ssid
    dev=$(kobo_wifi_if)
    command -v wpa_cli >/dev/null 2>&1 || return 1
    kobo_wpa_ensure || return 1
    nid=$(wpa_cli -i "$dev" list_networks 2>/dev/null | awk -F'\t' -v s="$1" 'NR > 1 && $2 == s { print $1; exit }')
    [ -n "$nid" ] || return 1
    wpa_cli -i "$dev" enable_network "$nid" >/dev/null 2>&1
    wpa_cli -i "$dev" select_network "$nid" >/dev/null 2>&1
}

# Scan nearby Wi-Fi APs via wpa_cli (or iwlist fallback when wpa ctrl socket was removed by Nickel)
# and print TAB-separated lines for WifiActivity:
#   saved(y|n) \t secured(y|n) \t bars(1..5) \t mgmt \t ssid
kobo_wifi_scan() {
    dev=$(kobo_wifi_if)
    saved=$(kobo_wifi_saved)
    if [ -S "/var/run/wpa_supplicant/$dev" ] && command -v wpa_cli >/dev/null 2>&1; then
        wpa_cli -i "$dev" scan >/dev/null 2>&1 || true
        sleep 2
        res=$(wpa_cli -i "$dev" scan_results 2>/dev/null | awk -F'\t' -v saved="$saved" '
            BEGIN {
                n = split(saved, sv, "\n")
                for (i = 1; i <= n; i++) if (sv[i] != "") is_saved[sv[i]] = 1
            }
            NR > 1 && NF >= 5 && $5 != "" {
                ssid = $5; sig = $3 + 0; flags = $4
                if (!(ssid in best) || sig > best[ssid]) {
                    best[ssid] = sig
                    flg[ssid] = flags
                }
            }
            END {
                for (s in best) {
                    sig = best[s]
                    bars = (sig >= -55) ? 5 : (sig >= -65) ? 4 : (sig >= -75) ? 3 : (sig >= -85) ? 2 : 1
                    f = flg[s]
                    sec = (f ~ /WPA|WEP|RSN/) ? "y" : "n"
                    mgmt = (f ~ /WPA2/) ? "WPA2" : (f ~ /WPA/) ? "WPA" : (f ~ /WEP/) ? "WEP" : "NONE"
                    sv_f = (s in is_saved) ? "y" : "n"
                    printf "%s\t%s\t%d\t%s\t%s\n", sv_f, sec, bars, mgmt, s
                }
            }' | sort -t"$(printf '\t')" -k3,3nr)
        if [ -n "$res" ]; then
            printf '%s\n' "$res"
            return 0
        fi
    fi
    command -v iwlist >/dev/null 2>&1 || return 1
    iwlist "$dev" scan 2>/dev/null | awk -v saved="$saved" '
        BEGIN {
            n = split(saved, sv, "\n")
            for (i = 1; i <= n; i++) if (sv[i] != "") is_saved[sv[i]] = 1
        }
        function flush() {
            if (ssid != "") {
                if (!(ssid in best) || qual > best[ssid]) {
                    best[ssid] = qual
                    bsec[ssid] = sec
                    bmgmt[ssid] = mgmt
                }
            }
            ssid = ""; qual = 0; sec = "n"; mgmt = "NONE"
        }
        /Cell [0-9]+ - Address:/ { flush(); next }
        /ESSID:"/ {
            s = $0; sub(/.*ESSID:"/, "", s); sub(/".*/, "", s)
            ssid = s; next
        }
        /Encryption key:on/ { sec = "y"; if (mgmt == "NONE") mgmt = "WEP"; next }
        /WPA2|IEEE 802\.11i/ { sec = "y"; mgmt = "WPA2"; next }
        /WPA Version/ { sec = "y"; if (mgmt != "WPA2") mgmt = "WPA"; next }
        /Quality=/ {
            q = $0; sub(/.*Quality=/, "", q); sub(/\/.*/, "", q)
            qual = q + 0; next
        }
        END {
            flush()
            for (s in best) {
                q = best[s]
                bars = (q >= 80) ? 5 : (q >= 60) ? 4 : (q >= 40) ? 3 : (q >= 20) ? 2 : 1
                sv_f = (s in is_saved) ? "y" : "n"
                printf "%s\t%s\t%d\t%s\t%s\n", sv_f, bsec[s], bars, bmgmt[s], s
            }
        }' | sort -t"$(printf '\t')" -k3,3nr
}

# Add & connect to a new Wi-Fi network (open if $2 empty, WPA-PSK if $2 non-empty).
kobo_wifi_connect_new() { # $1 = ssid  $2 = psk (optional)
    dev=$(kobo_wifi_if)
    command -v wpa_cli >/dev/null 2>&1 || return 1
    kobo_wpa_ensure || return 1
    nid=$(wpa_cli -i "$dev" list_networks 2>/dev/null | awk -F'\t' -v s="$1" 'NR > 1 && $2 == s { print $1; exit }')
    if [ -z "$nid" ]; then
        nid=$(wpa_cli -i "$dev" add_network 2>/dev/null | tail -1 | tr -cd '0-9')
        [ -n "$nid" ] || return 1
        wpa_cli -i "$dev" set_network "$nid" ssid "\"$1\"" >/dev/null 2>&1 || return 1
    fi
    if [ -n "$2" ]; then
        wpa_cli -i "$dev" set_network "$nid" psk "\"$2\"" >/dev/null 2>&1 || return 1
    else
        wpa_cli -i "$dev" set_network "$nid" key_mgmt NONE >/dev/null 2>&1 || return 1
    fi
    wpa_cli -i "$dev" enable_network "$nid" >/dev/null 2>&1 || return 1
    wpa_cli -i "$dev" select_network "$nid" >/dev/null 2>&1 || return 1
    wpa_cli -i "$dev" save_config >/dev/null 2>&1 || true
    return 0
}

# Timezone from /etc/localtime symlink (/etc/zoneinfo/Asia/Shanghai -> Asia/Shanghai)
kobo_tz() {
    lt=$(readlink /etc/localtime 2>/dev/null)
    case "$lt" in
        */zoneinfo/*) echo "${lt#*/zoneinfo/}" ;;
        *) echo "Asia/Shanghai" ;;
    esac
}
