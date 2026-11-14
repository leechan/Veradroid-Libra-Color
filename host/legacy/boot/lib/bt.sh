# SPDX-License-Identifier: GPL-3.0-or-later
# 蓝牙翻页器 / 键盘（宿主侧桥，可选）。设计见 docs/bluetooth.md。
# Kindle 自己的蓝牙栈（btmanagerd / acsbtfd）一直管着芯片（/dev/stpbt），Android 里不跑蓝牙栈。配对在 Kindle 的
# 「设置 → 蓝牙设备」里做；连上以后 Kindle 的 HID host 经 /dev/uhid 生成一个内核输入设备（总线 BUS_BLUETOOTH）。
# 容器的 /dev 是私有的，后来才出现的节点 Android 看不见，所以 bin/vdbtkeys：
#   - 开机时建一个常驻的 uinput 设备 veradroid-btkeys，绑进容器（/dev/input/event3）；
#   - 翻页器（没有字母键的蓝牙设备，以及 5.20+ 的 kindle-input-pt）：独占后按 BT_PT_MAP 改写方向键再从 btkeys 发出；
#   - 键盘（有字母键）：另建 veradroid-btkbd 克隆，mknod 进容器的 /dev/input，Android 自己热插；断开时删掉；
#   - 返回 Kindle 时（input_release）放开设备，Kindle 自己照常用；冻结 / 屏保期间按键直接丢掉，解冻后不会连翻好几页。
# 没有 Kindle 蓝牙栈的机型（或 BT_BRIDGE=0）什么都不做，KFB_BTKEYS 为空，容器里也不多绑节点。
# 设置（$SYS/settings.conf）：BT_BRIDGE=0 关掉整个桥；BT_PT_MAP=volume|page|dpad|raw（默认 volume：
#   下一页 = 音量-，上一页 = 音量+，微信读书等阅读 App 都认）；BT_PT_SWAP=1 反转方向；BT_KINDLE_PT=0 不接管 kindle-input-pt。

bt_supported() {
    [ "$VD_BT_FORCE" = 1 ] && return 0
    [ -x /usr/bin/btmanagerd ] || [ -x /usr/bin/acsbtfd ] || [ -x /usr/bin/btfd ]
}

bt_start() {
    KFB_BTKEYS=; export KFB_BTKEYS
    rm -f $W/bt.state
    [ "${BT_BRIDGE:-0}" = 0 ] && { t "bt: bridge off (set BT_BRIDGE=1 to enable)"; return 0; }
    bt_supported || return 0                     # 没有蓝牙的机型：一行日志都不写
    [ -x "$VD/bin/vdbtkeys" ] || { t "bt: vdbtkeys missing"; return 0; }
    bt_stop                                      # 上次留下的（stop.sh 没跑完之类）
    case "$BT_PT_MAP" in volume|page|dpad|raw) btm=$BT_PT_MAP ;; *) btm=volume ;; esac
    bts=; [ "$BT_PT_SWAP" = 1 ] && bts=--swap
    btk=; [ "$BT_KINDLE_PT" = 0 ] && btk=--no-kindle-pt
    chmod 666 /dev/uinput /dev/input/uinput 2>/dev/null
    : > $W/bt.log
    # 和 veradroid-input 一样在 container_start 之前起：不在 freezer 组里，冻结时还能收到放开 / 独占的信号
    $VD/bin/vdbtkeys $W/bt.log --map $btm $bts $btk --conf $SYS/settings.conf --pidfile $W/pid --state $W/bt.state \
        --drop-flag $W/frozen --drop-flag $W/saver_frozen --action $VD/boot/action.sh </dev/null >/dev/null 2>&1 &
    echo $! > $W/bt.pid
    i=0; btn=
    while [ $i -lt 15 ]; do
        btn=$(input_sysname veradroid-btkeys); [ -n "$btn" ] && break
        usleep 200000; i=$((i + 1))
    done
    [ -n "$btn" ] || { t "bt: veradroid-btkeys did not appear, bridge off"; bt_stop; return 0; }
    # 没有 devtmpfs 的老内核：按 sysfs 的设备号自己建节点
    if [ ! -e /dev/input/$btn ]; then
        dev=$(cat /sys/class/input/$btn/dev 2>/dev/null)
        [ -n "$dev" ] && mknod /dev/input/$btn c ${dev%%:*} ${dev##*:}
    fi
    [ -c /dev/input/$btn ] || { t "bt: no node for $btn, bridge off"; bt_stop; return 0; }
    KFB_BTKEYS=/dev/input/$btn; chmod 666 $KFB_BTKEYS; export KFB_BTKEYS
    t "bt: bridge up, keys $KFB_BTKEYS map=$btm${bts:+ swap}"
}
bt_release() { alive $W/bt.pid && kill -USR1 "$(cat $W/bt.pid)" 2>/dev/null; return 0; }
bt_grab()    { alive $W/bt.pid && kill -USR2 "$(cat $W/bt.pid)" 2>/dev/null; return 0; }
bt_stop() {
    p=$(cat $W/bt.pid 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        kill "$p" 2>/dev/null
        # 等它自己删掉 uinput 设备和容器里的键盘节点；1 秒还不走就强杀（内核会随 fd 关闭销毁 uinput 设备）
        i=0; while kill -0 "$p" 2>/dev/null && [ $i -lt 10 ]; do usleep 100000; i=$((i + 1)); done
        kill -9 "$p" 2>/dev/null
    fi
    rm -f $W/bt.pid $W/bt.state
    return 0
}
# 桌面状态（status.sh 调）：bt=0 不支持 / 关着，1 桥在跑；btdev=当前接管的设备（kind:name，逗号分隔）
bt_status_lines() {
    if alive $W/bt.pid; then echo "bt=1"; else echo "bt=0"; fi
    echo "btdev=$(awk -F'\t' '{printf "%s%s:%s", (NR>1?",":""), $1, $2}' $W/bt.state 2>/dev/null)"
    echo "btmap=${BT_PT_MAP:-volume}"
}
# cmd FIFO："bt map volume|page|dpad|raw"、"bt swap 0|1"：写进 settings.conf，SIGHUP 让 vdbtkeys 立即重读（节点不变）。
# 配对 / 开关蓝牙不在这里做（交给 Kindle 自己的设置界面，不碰 com.lab126.btfd，免得和 Kindle 的蓝牙服务抢）。
bt_cmd() {
    case "$1" in
        map)  case "$2" in volume|page|dpad|raw) k=BT_PT_MAP ;; *) return 1 ;; esac ;;
        swap) case "$2" in 0|1) k=BT_PT_SWAP ;; *) return 1 ;; esac ;;
        *) return 1 ;;
    esac
    { grep -v "^$k=" $SYS/settings.conf 2>/dev/null; echo "$k=$2"; } > $SYS/settings.conf.tmp && mv -f $SYS/settings.conf.tmp $SYS/settings.conf
    eval "$k=$2"
    alive $W/bt.pid && kill -HUP "$(cat $W/bt.pid)" 2>/dev/null
    t "bt: $k=$2"
    status_write 2>/dev/null
}
