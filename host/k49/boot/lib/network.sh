# SPDX-License-Identifier: GPL-3.0-or-later
# 网络：Kindle 内核没有 veth，容器有自己的 net 命名空间，用 slirp4netns（用户态 NAT，官方静态二进制）经 /dev/net/tun
# 在里面造 eth0。容器内网段刻意避开常见的 10.0.2.0/24、198.18/15（Clash）、100.64/10（Tailscale）、172.17（Docker）、10.233（K8s）。
# 系统里的 Wi-Fi 是假的：真正的 Wi-Fi 连接由 Kindle 管，系统只看到一块 eth0。
NET=10.157.43
SLIRP=$VD/bin/slirp4netns

net_setup() {
    # DNS：ANDROID_DNS 在前，Kindle 当前的在后。只在 slirp 自己的 mount 命名空间里 bind，不动 Kindle 的 /etc
    { for d in $ANDROID_DNS; do echo "nameserver $d"; done
      grep '^nameserver' "$(readlink -f /etc/resolv.conf)" 2>/dev/null; } > $W/resolv.conf
    # Wi-Fi 省电模式保持开着（电池优先）：以前这里会关掉它，空闲耗电明显更高
}

# Wi-Fi 省电。设置 WIFI_PS：
#   on   = 一直保持 Kindle 自己的省电模式（省电，下载慢）
#   off  = Android 运行期间关掉省电（下载快、耗电多）；回到 Kindle / 屏保 / 停止时恢复
#   auto = 平时保持省电；传书开着（端口转发在）或 Wi-Fi 上正在大量收数据（下载、同步书）时临时关掉，
#          闲下来 1 分钟后恢复。判断只读 /sys 里网卡的收包字节数，看门狗每一轮（20 秒）看一次。
# 只恢复我们自己关掉的（$W/wifi.ps 标记）：用户或 Kindle 本来就关着省电时不去动它。
wifi_dev() { for d in wlan0 eth0; do [ -d /sys/class/net/$d ] && { echo $d; return 0; }; done; echo wlan0; }
wifi_ps_state() { # 输出 on / off / 空（读不到）
    d=$(wifi_dev)
    if command -v iw >/dev/null 2>&1; then
        s=$(iw dev $d get power_save 2>/dev/null | sed -n 's/.*[Pp]ower save: *\(o[nf]*\).*/\1/p')
        [ -n "$s" ] && { echo $s; return 0; }
    fi
    iwconfig $d 2>/dev/null | sed -n 's/.*Power Management:\(o[nf]*\).*/\1/p'
}
wifi_ps_set() { # on|off
    d=$(wifi_dev)
    if command -v iw >/dev/null 2>&1 && iw dev $d set power_save $1 2>/dev/null; then return 0; fi
    iwconfig $d power $1 2>/dev/null
}
# 运行期间关 Wi-Fi 省电（回到 Kindle 时 stop.sh / do_exit 恢复）
wifi_ps_off() {
    [ -f $W/wifi.ps ] && return 0
    [ "$(wifi_ps_state)" = on ] && wifi_ps_set off && touch $W/wifi.ps && t "wifi: power saving off (${WIFI_PS:-auto})"
    return 0
}
wifi_ps_restore() { [ -f $W/wifi.ps ] && rm -f $W/wifi.ps && wifi_ps_set on && t "wifi: power saving restored"; return 0; }
# 看门狗每轮调一次（冻结 / 屏保时不调，那时已经恢复）
wifi_ps_tick() {
    case "${WIFI_PS:-auto}" in
        on)  wifi_ps_restore ;;
        off) wifi_ps_off ;;
        *)
            d=$(wifi_dev); now=$(cut -d. -f1 /proc/uptime)
            rx=$(cat /sys/class/net/$d/statistics/rx_bytes 2>/dev/null || echo 0)
            set -- $(cat $W/wifi.rx 2>/dev/null); prx=${2:-$rx}; pt=${1:-$now}
            echo "$now $rx" > $W/wifi.rx
            busy=
            [ -f $W/fwd.id ] && busy=fwd                                  # 传书网页开着
            dt=$((now - pt)); [ $dt -gt 0 ] && [ $(( (rx - prx) / dt )) -ge ${WIFI_BUSY_BPS:-32768} ] && busy=rx   # ≥ 32 KB/s
            if [ -n "$busy" ]; then echo $now > $W/wifi.busy; wifi_ps_off
            elif [ -f $W/wifi.ps ] && [ $((now - $(cat $W/wifi.busy 2>/dev/null || echo 0))) -ge 60 ]; then wifi_ps_restore
            fi ;;
    esac
}

# 共用宿主网络（没有 net 命名空间的内核：3.0 的 PW2/PW3，4.9 的 KT6 5.17 等，走 chroot）：把 Kindle 现在的网卡、
# 地址、网关、DNS 写给系统（系统里的以太网服务直接用它注册一个已连接的网络，不跑 DHCP、不改网卡；见 VdHostNet.java）。
hostnet_write() {
    dev=$(ip route 2>/dev/null | awk '$1 == "default" { for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    gw=$(ip route 2>/dev/null | awk '$1 == "default" { for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')
    [ -n "$dev" ] || dev=wlan0
    addr=$(ip -4 addr show dev "$dev" 2>/dev/null | awk '$1 == "inet" { print $2; exit }')
    {
        echo "iface=$dev"
        [ -n "$addr" ] && echo "addr=$addr"
        [ -n "$gw" ] && echo "gw=$gw"
        for d in $ANDROID_DNS; do echo "dns=$d"; done
        # 只要 IPv4：以前的 [0-9.]* 把 IPv6 的 "240c::6666" 截成了 "240"（用户诊断 632015 的 dns=240）
        sed -n 's/^nameserver[[:space:]]*\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)[[:space:]]*$/dns=\1/p' "$(readlink -f /etc/resolv.conf)" 2>/dev/null
    } > $X/hostnet
    chmod 644 $X/hostnet
    t "net: host network for android: $(tr '\n' ' ' < $X/hostnet)"
}

# 0.79–0.81 在 chroot 模式下跑的是没打补丁的 netd：它清掉了 Kindle 的策略路由（连 32766 main 都删了），只留自己的规则，
# 其中 32000 unreachable 会让带 netId 标记的连接全部不通。发现这种残留就恢复成 Linux 默认的规则（只删 10000–32000 段）。
hostnet_fix_rules() {
    for v in -4 -6; do
        ip $v rule 2>/dev/null | grep -qE '^(1[0-9]{4}|2[0-9]{4}|3[01][0-9]{3}|32000):' || continue
        ip $v rule 2>/dev/null | grep -q '^32766:' || ip $v rule add pref 32766 lookup main 2>/dev/null
        ip $v rule 2>/dev/null | grep -q '^32767:' || ip $v rule add pref 32767 lookup default 2>/dev/null
        for p in $(ip $v rule 2>/dev/null | sed -n 's/^\([0-9]*\):.*/\1/p'); do
            [ "$p" -ge 10000 ] && [ "$p" -le 32000 ] && ip $v rule del pref "$p" 2>/dev/null
        done
        t "net: removed stale netd ip $v rules from the Kindle"
    done
    return 0
}

net_start() {
    # chroot 模式（内核没有 net 命名空间）：Android 和 Kindle 共用网络，不起 slirp，改走 hostnet
    if [ "$(cat $W/mode 2>/dev/null)" = chroot ] || hostns; then hostnet_fix_rules; hostnet_write; return 0; fi
    [ -x "$SLIRP" ] || { t "net: $SLIRP missing, no network"; return 0; }
    rm -f $W/slirp.sock
    # 演示系统没有 DHCP 客户端，用 --configure 直接配好；真的 Android 自己 DHCP（slirp 发 .15）
    CONF=; [ -f $R/.demo ] && CONF=--configure
    target=$(readlink -f /etc/resolv.conf)
    unshare -m sh -c "{ mount --make-rprivate / 2>/dev/null || true; } &&
        { [ -e '$target' ] && mount --bind $W/resolv.conf '$target'; true; } &&
        exec $SLIRP --mtu=1500 --cidr=$NET.0/24 $CONF --api-socket $W/slirp.sock $P eth0" > $W/slirp.log 2>&1 &
    echo $! > $W/slirp.pid
    i=0; while [ $i -lt 20 ] && ! grep -q 'sent tapfd' $W/slirp.log 2>/dev/null; do usleep 500000; i=$((i + 1)); done
    t "net: slirp4netns $(grep -q 'sent tapfd' $W/slirp.log && echo up || echo 'NOT up'): $(tail -1 $W/slirp.log)"
}
