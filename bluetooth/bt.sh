# SPDX-License-Identifier: GPL-3.0-or-later
# 蓝牙（宿主侧）。Kindle 自己的蓝牙栈（btmanagerd / acsbtfd，Bluedroid 分支）一直管着射频，Android 里不跑蓝牙栈：
#   - 翻页器 / 键盘 / Kindle Remote 连上后，Kindle 的 HID host 经 /dev/uhid 生成一个内核输入设备（总线 BUS_BLUETOOTH），
#     5.20+ 的 input_manager 还会把 Kindle Remote 转成虚拟的 kindle-input-pt。
#   - 容器的 /dev 是私有 tmpfs，后来才出现的节点 Android 看不见；vdbtkeys 开机时建一个常驻的 veradroid-btkeys 绑进容器，
#     翻页器的键（右/下/PageDown/音量-/下一曲/空格/回车 = 下一页，反之上一页）按 BT_PT_MAP 改写后从这里发出去；
#     键盘则另建一个 veradroid-btkbd 克隆设备，热插进容器的 /dev/input（Android 的 EventHub 用 inotify 自己会发现）。
#   - 回到 Kindle（冻结）时放开设备，Kindle 自己的翻页器功能照常；屏保冻结期间按键直接丢掉，不会解冻后连翻好几页。
#   - 配对、开关、扫描走 Kindle 的 lipc（com.lab126.btfd），不碰 /dev/stpbt，不和 Kindle 的有声书 / VoiceView 抢控制器。
# 设置（$SYS/settings.conf）：BT_PT_MAP=volume|page|dpad|raw（默认 volume：微信读书等阅读 App 都支持音量键翻页）
#                            BT_PT_SWAP=1 反转方向；BT_BRIDGE=0 关掉整个桥
BTF=com.lab126.btfd

bt_conf() { sed -n "s/^$1=//p" $SYS/settings.conf 2>/dev/null | tail -1; }

bt_supported() {
    [ "$VD_BT_FORCE" = 1 ] && return 0
    [ -x /usr/bin/btmanagerd ] || [ -x /usr/bin/btfd ] || [ -x /usr/bin/acsbtfd ]
}

bt_start() {
    KFB_BTKEYS=
    [ "$(bt_conf BT_BRIDGE)" = 0 ] && { t "bt: bridge off (BT_BRIDGE=0)"; return 0; }
    bt_supported || { t "bt: no Kindle bluetooth stack on this model"; return 0; }
    [ -x "$VD/bin/vdbtkeys" ] || { t "bt: vdbtkeys missing"; return 0; }
    _btm=$(bt_conf BT_PT_MAP); case "$_btm" in volume|page|dpad|raw) ;; *) _btm=volume ;; esac
    _bts=; [ "$(bt_conf BT_PT_SWAP)" = 1 ] && _bts=--swap
    chmod 666 /dev/uinput /dev/input/uinput 2>/dev/null
    $VD/bin/vdbtkeys $W/bt.log --map $_btm $_bts --conf $SYS/settings.conf --pidfile $W/pid --drop-flag $W/saver_frozen --drop-flag $W/frozen \
        --action $VD/boot/action.sh ${VD_BT_NAME:+--name-match "$VD_BT_NAME"} >/dev/null 2>&1 &
    echo $! > $W/bt.pid
    _bti=0; _btn=
    while [ $_bti -lt 15 ]; do
        _btn=$(input_sysname veradroid-btkeys); [ -n "$_btn" ] && break
        usleep 200000; _bti=$((_bti + 1))
    done
    [ -n "$_btn" ] || { t "bt: veradroid-btkeys did not appear"; return 0; }
    KFB_BTKEYS=/dev/input/$_btn; chmod 666 $KFB_BTKEYS; export KFB_BTKEYS
    t "bt: bridge up, keys $KFB_BTKEYS map=$_btm"
}
bt_release() { alive $W/bt.pid && kill -USR1 "$(cat $W/bt.pid)" 2>/dev/null; }
bt_grab()    { alive $W/bt.pid && kill -USR2 "$(cat $W/bt.pid)" 2>/dev/null; }
bt_stop()    { alive $W/bt.pid && kill "$(cat $W/bt.pid)" 2>/dev/null; rm -f $W/bt.pid; }

# VeraHome -> cmd FIFO: "bt <sub> [arg]"，结果写到 $X/ctl/bt.status（key=value 行）
bt_addr_ok() { echo "$1" | grep -qiE '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$'; }
bt_status() {
    { echo "supported=$(bt_supported && echo 1 || echo 0)"
      echo "bridge=$(alive $W/bt.pid && echo 1 || echo 0)"
      echo "map=$(bt_conf BT_PT_MAP)"
      echo "state=$(lipc-get-prop $BTF BTstate 2>/dev/null)"
      echo "connected=$(lipc-get-prop -s $BTF BTconnectedDevName 2>/dev/null)"
      echo "devices=$(grep -c '^\[.*\] add ' $W/bt.log 2>/dev/null)"
      for _btl in ListPaired ListConnected ListDiscovered; do
          echo "$_btl=$(lipc-hash-prop $BTF $_btl 2>/dev/null </dev/null | tr '\n' ' ' | cut -c1-2000)"
      done
      echo "time=$(date +%s)"; } > $X/ctl/bt.status.tmp 2>/dev/null
    mv -f $X/ctl/bt.status.tmp $X/ctl/bt.status
}
bt_cmd() {
    _btc=$1; _bta=$2
    case "$_btc" in
        status) ;;
        on)   lipc-set-prop -s $BTF BTenable 1 2>/dev/null ;;
        off)  lipc-set-prop -s $BTF BTenable 0 2>/dev/null ;;
        scan) lipc-set-prop -i $BTF triggerBTscan 1 2>/dev/null ;;
        bond|connect|disconnect|unbond)
            bt_addr_ok "$_bta" || { t "bt: bad address '$_bta'"; return 1; }
            case "$_btc" in bond) _btp=Bond ;; connect) _btp=Connect ;; disconnect) _btp=Disconnect ;; *) _btp=Unbond ;; esac
            lipc-set-prop -s $BTF $_btp "$_bta" 2>/dev/null ;;
        swap) case "$_bta" in 0|1)
                  grep -v '^BT_PT_SWAP=' $SYS/settings.conf > $SYS/settings.conf.tmp 2>/dev/null
                  echo "BT_PT_SWAP=$_bta" >> $SYS/settings.conf.tmp; mv -f $SYS/settings.conf.tmp $SYS/settings.conf
                  alive $W/bt.pid && kill -HUP "$(cat $W/bt.pid)" 2>/dev/null ;;
              esac ;;
        map)  case "$_bta" in volume|page|dpad|raw)
                  grep -v '^BT_PT_MAP=' $SYS/settings.conf > $SYS/settings.conf.tmp 2>/dev/null
                  echo "BT_PT_MAP=$_bta" >> $SYS/settings.conf.tmp; mv -f $SYS/settings.conf.tmp $SYS/settings.conf
                  alive $W/bt.pid && kill -HUP "$(cat $W/bt.pid)" 2>/dev/null   # 立即生效，节点不变
                  t "bt: map=$_bta" ;;
              esac ;;
    esac
    t "bt: cmd $_btc $_bta"
    ( sleep 1; bt_status ) &
}
