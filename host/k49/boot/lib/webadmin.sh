# SPDX-License-Identifier: GPL-3.0-or-later
# 管理网页（VeraHome 的“传输”网页，Transfer.java / WebAdmin.java）要宿主做的事。由 cmd.sh 的 `wa <编号>` 进来。
#
# 为什么不直接做成普通的 FIFO 命令：$X/ctl/cmd 是 666，Android 里任何应用都能写。这里有的请求能产生 root 级效果
# （加 SSH 公钥、开 SSH、关自动更新），有的会把内容交出去（截屏、日志）。所以：
#   - VeraHome 先把请求写进它自己的私有目录 /data/data/com.veradroid.home/files/hostreq/<编号>.req（别的应用进不去），
#     FIFO 里只传 32 位十六进制的随机编号；
#   - 宿主只认：普通文件、不是符号链接、属主正好是 VeraHome 的 uid（packages.list 里查）。读完就删；
#   - 请求第一行是“动词 参数”，第二行是可选的数据（只有 SSH 公钥用）。动词走白名单，参数逐个校验，绝不 eval；
#   - 结果写到 $X/wa/<编号>.out：目录属 root（0711，别的应用建不了文件、也列不出文件名），结果文件属 VeraHome、0400。
# 管理网页本身要 PIN 登录；这一层防的是“装在 Android 里的别的应用”冒充网页。
WA_PKG=com.veradroid.home
WA_OUT=$X/wa
WA_SSHB=/mnt/us/veradroid/ssh                       # SSH 诊断包的正式位置（docs/ssh-diagnostics.md）
WA_SSHSRC=/mnt/us/documents/VeraDroid-SSH           # 用户拷进书库的诊断包
WA_SSHRUN=/var/tmp/veradroid-ssh                    # 诊断包运行时目录（它自己定的）
# 诊断包里那份 dropbear（diagnostics/ssh/dropbear）的 SHA-256。书库里的文件管理网页能改，所以只认这一份，
# 不对就不拷（诊断包会退回设备上已有的 dropbear：KOReader / USBNetwork / 系统自带）。
WA_DROPBEAR_SHA=0e4340bcc9f098f87f0a27bee3f9cb0ee34a40a53e76e7c6367a2644f7898297

# wa_do 里的记录写到 stderr（进 VeraDroid 的日志），不能混进写给网页的结果里
wa_log() { t "$@" >&2; }
wa_uid() { awk -v p=$WA_PKG '$1 == p { print $2; exit }' $SYS/data/system/packages.list 2>/dev/null; }

wa_request() { # 编号
    n=$1
    case "$n" in ''|*[!0-9a-f]*) t "wa: bad id"; return 1 ;; esac
    [ ${#n} -eq 32 ] || { t "wa: bad id"; return 1; }
    u=$(wa_uid)
    case "$u" in ''|*[!0-9]*) t "wa: VeraHome uid unknown"; return 1 ;; esac
    f=$SYS/data/data/$WA_PKG/files/hostreq/$n.req
    if [ ! -f "$f" ] || [ -L "$f" ] || [ "$(stat -c %u "$f" 2>/dev/null)" != "$u" ]; then
        t "wa: request $n rejected (missing / not VeraHome's)"
        return 1
    fi
    req=$(head -c 9000 "$f" 2>/dev/null)
    rm -f "$f"
    l1=$(printf '%s\n' "$req" | sed -n 1p | tr -cd 'A-Za-z0-9 ._-' | cut -c1-80)
    l2=$(printf '%s\n' "$req" | sed -n 2p | tr -d '\r')
    verb=${l1%% *}; arg=
    [ "$verb" = "$l1" ] || arg=${l1#* }
    mkdir -p $WA_OUT && chown 0:0 $WA_OUT && chmod 711 $WA_OUT || return 1
    # 只留最近的 12 个结果（截屏一张两兆，放在内存盘里）
    ls -t $WA_OUT 2>/dev/null | tail -n +13 | while read -r o; do case "$o" in *[!0-9a-f.outmp]*) ;; *) rm -f "$WA_OUT/$o" ;; esac; done
    ( exec 3>&- 3<&- 2>&1; wa_do "$n" "$u" "$verb" "$arg" "$l2" ) </dev/null &
}

# 标准输入 -> $WA_OUT/<编号>.out（先写临时文件，改好属主和权限再改名，VeraHome 看到 .out 就是完整的）
wa_put() { # 编号 uid
    o=$WA_OUT/$1
    head -c 4194304 > "$o.tmp" && chown "$2" "$o.tmp" && chmod 400 "$o.tmp" && mv -f "$o.tmp" "$o.out" || rm -f "$o.tmp"
}

wa_do() { # 编号 uid 动词 参数 数据
    n=$1; u=$2; verb=$3; arg=$4; data=$5
    case "$verb" in
    sysinfo)  wa_sysinfo | wa_put "$n" "$u" ;;
    du)       wa_du | wa_put "$n" "$u" ;;
    logtail)  wa_logtail "$arg" | wa_put "$n" "$u" ;;
    shot)     wa_shot "$n" "$u" ;;
    sshstate) wa_sshstate | wa_put "$n" "$u" ;;
    sshstart) { wa_sshstart; wa_sshstate; } | wa_put "$n" "$u" ;;
    sshstop)  { wa_sshstop; wa_sshstate; } | wa_put "$n" "$u" ;;
    sshkeyadd) { wa_sshkeyadd "$data"; wa_sshstate; } | wa_put "$n" "$u" ;;
    sshkeydel) { wa_sshkeydel "$arg"; wa_sshstate; } | wa_put "$n" "$u" ;;
    autoupdate) wa_autoupdate "$arg" | wa_put "$n" "$u" ;;
    storage)  { echo "ok=1"; st_info; } | wa_put "$n" "$u" ;;
    storageresize) case "$arg" in ''|*[!0-9]*) echo "error=nan" ;; *) st_request "$arg" ;; esac | wa_put "$n" "$u" ;;
    storageauto) case "$arg" in 0|1) st_cmd auto "$arg" >/dev/null 2>&1; echo "ok=1"; st_info ;; *) echo "error=bad value" ;; esac | wa_put "$n" "$u" ;;
    libput)   wa_libput "$arg" "$u" "$data" | wa_put "$n" "$u" ;;
    wifipsk)  { type wifi_psk_put >/dev/null 2>&1 && wifi_psk_put "$arg" "$data" || echo "error=unknown"; } | wa_put "$n" "$u" ;;   # 新 Wi-Fi 的密码（cmd.sh wifi_connect）
    *) wa_log "wa: unknown request '$verb'"; echo "error=unknown" | wa_put "$n" "$u" ;;
    esac
}

# 书写进 Kindle 书库。KT6 / Scribe 的 5.17+ 固件用 fscrypt v1：密钥是 logon 类型，
# Amazon 的 fenc 分别塞进 root 和 framework 用户的 user-session keyring（DL_V1_POLICY=true），Android 里的应用 uid
# 拿不到，新建文件会得到 ENOKEY（Required key not available）。宿主是 root、没有自己的 session keyring，用的正是 root
# 那份 —— 所以由宿主代写，密钥永远不进容器。PW6 是 v2（文件系统级密钥），这条路同样能用。
#   请求：libput <编号>，第二行是文件名；数据在 VeraHome 私有目录 files/libput/<编号>.part（在系统盘里，同样是加密存放）。
#   检查：普通文件、不是链接、只有一个硬链接、属主是 VeraHome；名字不含 / 和控制字符、不以 . 开头、不超过 200 字节；
#   空间够。先拷成 documents/.vd-<编号>.part（同一目录 = 同一加密策略；跨策略 rename 在 4.9 上是 EPERM），sync，
#   再 ln 成正式名字（已存在就加 " (2)"…，绝不覆盖），最后删掉临时名和源文件。
WA_LIBDIR=/mnt/base-us/documents
wa_libput() { # 编号 uid 文件名
    id=$1; lu=$2; name=$(printf '%s' "$3" | tr -d '\000-\037\177' | head -c 200)
    case "$id" in ''|*[!0-9a-f]*) echo "error=badid"; return 0 ;; esac
    src=$SYS/data/data/$WA_PKG/files/libput/$id.part
    if [ ! -f "$src" ] || [ -L "$src" ] || [ "$(stat -c %u "$src" 2>/dev/null)" != "$lu" ] || [ "$(stat -c %h "$src" 2>/dev/null)" != 1 ]; then
        wa_log "wa: libput $id: source rejected"; echo "error=source"; return 0
    fi
    case "$name" in ''|.*|*/*) wa_log "wa: libput $id: bad name"; rm -f "$src"; echo "error=name"; return 0 ;; esac
    # 书库里的 .sh 会被 Kindle 当成脚本、以 root 运行：脚本和 SSH 相关的名字一律不收（结尾的点和空格 vfat 会去掉，先去掉再判断）
    lc=$(printf '%s' "$name" | tr 'A-Z' 'a-z' | sed 's/[. ]*$//')
    case "$lc" in *.sh|my-public-keys*|authorized_keys|dropbear*|*host_key*|id_rsa|id_ed25519|id_ecdsa|'') wa_log "wa: libput $id: blocked name"; rm -f "$src"; echo "error=name"; return 0 ;; esac
    [ -d "$WA_LIBDIR" ] || { echo "error=nolibrary"; rm -f "$src"; return 0; }
    sz=$(stat -c %s "$src" 2>/dev/null); free=$(df -kP "$WA_LIBDIR" 2>/dev/null | awk 'NR==2 { print $4 }')
    if [ -n "$free" ] && [ $(( (${sz:-0} / 1024) + 1024 )) -gt "$free" ]; then echo "error=space"; rm -f "$src"; return 0; fi
    tmp=$WA_LIBDIR/.vd-$id.part
    if ! cat "$src" > "$tmp" 2>/dev/null; then
        e=$(cat "$src" 2>&1 > "$tmp" | head -1)
        rm -f "$tmp"; rm -f "$src"
        wa_log "wa: libput $id: write failed: $e ($(grep -c fscrypt /proc/keys 2>/dev/null) fscrypt keys visible)"
        echo "error=write"; return 0
    fi
    sync
    final=$name; base=${name%.*}; ext=; [ "$base" != "$name" ] && ext=.${name##*.}; k=2
    while ! ln "$tmp" "$WA_LIBDIR/$final" 2>/dev/null; do
        [ -e "$WA_LIBDIR/$final" ] || { rm -f "$tmp" "$src"; wa_log "wa: libput $id: link failed"; echo "error=link"; return 0; }
        [ $k -gt 99 ] && { rm -f "$tmp" "$src"; echo "error=exists"; return 0; }
        final="$base ($k)$ext"; k=$((k + 1))
    done
    rm -f "$tmp" "$src"
    wa_log "wa: libput $id -> $final (${sz:-0} bytes)"
    echo "ok=1"; echo "name=$(printf '%s' "$final" | tr -d '\n')"; echo "size=${sz:-0}"
}

wa_clean() { tr -cd 'A-Za-z0-9 ._:/()+,=@#%-' | cut -c1-"${1:-120}"; }
wa_df() { # 名字 路径 -> df.名字=总KB 已用KB 可用KB
    [ -e "$2" ] || return 0
    l=$(df -kP "$2" 2>/dev/null | tail -1)
    [ -n "$l" ] || l=$(df -k "$2" 2>/dev/null | tail -1)
    set -- "$1" $l
    [ $# -ge 5 ] && echo "df.$1=$3 $4 $5"
}

wa_sysinfo() {
    echo "ok=1"
    echo "model=$(cat $SYS/model 2>/dev/null | wa_clean 32)"
    echo "firmware=$(head -1 /etc/prettyversion.txt 2>/dev/null | wa_clean 80)"
    echo "vdversion=$(cat $VD/version 2>/dev/null | wa_clean 32)"
    echo "kernel=$(uname -r | wa_clean 60)"
    up=$(cut -d' ' -f1 /proc/uptime); up=${up%%.*}
    echo "uptime=$up"
    p=$(cat $W/pid 2>/dev/null)
    if [ -n "$p" ] && [ -r /proc/$p/stat ]; then
        st=$(awk '{ print int($22 / 100) }' /proc/$p/stat 2>/dev/null)
        [ -n "$st" ] && echo "androidup=$((up - st))"
    fi
    echo "mode=$(cat $W/mode 2>/dev/null | wa_clean 12)"
    [ -f $W/frozen ] && echo "frozen=1" || echo "frozen=0"
    [ -f $W/fw/paused ] && echo "fwpaused=1" || echo "fwpaused=0"
    case "$(cat $VD/autoupdate 2>/dev/null)" in 0) echo "autoupdate=0" ;; notify) echo "autoupdate=notify" ;; *) echo "autoupdate=1" ;; esac
    ap=$(cat $W/autoupdate.pid 2>/dev/null)
    [ -n "$ap" ] && kill -0 "$ap" 2>/dev/null && echo "autoupdaterun=1" || echo "autoupdaterun=0"
    wa_df kindle /mnt/base-us
    wa_df android "$SYS"
    wa_df root /
    [ -f "$SYSTEM_IMG" ] && echo "sysimg=$(stat -c %s "$SYSTEM_IMG" 2>/dev/null)"
    type st_info >/dev/null 2>&1 && st_info
    [ -f $W/wa.du ] && cat $W/wa.du
    # 宿主上的进程：VeraDroid 自己的 + Kindle 界面相关的（只读）。State: R 运行 S 睡眠 T 被暂停（Kindle 界面暂停时 awesome 就是 T）
    # 一个 awk 读完所有 /proc/*/status（以前每个进程起几个 cat/sed，模拟器上 sysinfo 要十几秒）
    cat /proc/[0-9]*/status 2>/dev/null | awk '
        function out() { if (n ~ /^(veradroid-.*|slirp4netns|vdshutwatch|pivot_init|dropbear|lab126_gui|KPPMainApp|awesome|pillow.*|volumd|cvm|powerd|wifid|appmgrd|Xorg|X|kfxreader|webreader|mtp.*|stored)$/ && p != "") {
                             gsub(/[^A-Za-z0-9._-]/, "", n); printf "hp=%s|%s|%s|%d\n", p, substr(n, 1, 24), st, r } }
        /^Name:/ { out(); n = $2; st = "?"; r = 0; p = "" }
        /^State:/ { st = $2 } /^Pid:/ { p = $2 } /^VmRSS:/ { r = $2 }
        END { out() }'

    # 宿主脚本（都是 sh，按 pid 文件认）
    for k in cmd watchdog sleep boot autoupdate shutw; do
        p=$(cat $W/$k.pid 2>/dev/null)
        [ -n "$p" ] && [ -r /proc/$p/status ] || continue
        s=$(sed -n 's/^State:[[:space:]]*\([A-Z]\).*/\1/p' /proc/$p/status 2>/dev/null)
        r=$(sed -n 's/^VmRSS:[[:space:]]*\([0-9]*\).*/\1/p' /proc/$p/status 2>/dev/null)
        echo "hs=$p|$k|${s:-?}|${r:-0}"
    done
    wa_sshstate
}

# 占用：慢（几秒到几十秒），按需算，结果留在 $W/wa.du 里给 sysinfo 用
wa_dusum() { du -sk "$@" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'; }
wa_du() {
    {
        echo "du.system=$(wa_dusum $R/system)"
        echo "du.apps=$(wa_dusum $SYS/data/app $SYS/data/app-lib $SYS/data/dalvik-cache)"
        echo "du.appdata=$(wa_dusum $SYS/data/data)"
        # Android 的共享存储，不算绑进去的 Kindle 书库 / 字体（它们本来就在 Kindle 那边）
        m=0
        for d in $SYS/data/media/0/* $SYS/data/media/0/.[!.]*; do
            [ -e "$d" ] || continue
            case "${d##*/}" in KindleLibrary|KindleFonts|Fonts) continue ;; esac
            m=$((m + $(wa_dusum "$d")))
        done
        echo "du.media=$m"
        echo "du.program=$(wa_dusum $VD)"
        echo "du.kindledocs=$(wa_dusum /mnt/base-us/documents)"
        echo "du.time=$(date +%s)"
    } > $W/wa.du.tmp && mv -f $W/wa.du.tmp $W/wa.du
    echo "ok=1"; cat $W/wa.du
}

wa_logtail() { # 行数 [main|update|ssh|fsck]
    nl=${1%% *}; w=main
    [ "$nl" = "$1" ] || w=${1#* }
    case "$nl" in ''|*[!0-9]*) nl=200 ;; esac
    [ "$nl" -ge 1 ] && [ "$nl" -le 2000 ] || nl=200
    case "$w" in
        main) lf=$LOG ;;
        update) lf=/mnt/base-us/veradroid/logs/autoupdate.log; [ -f "$lf" ] || lf=/mnt/base-us/veradroid-autoupdate.log ;;   # root-legacy: 老的自动更新进程（更新前起的）还写在根目录
        ssh) lf=$WA_SSHB/ssh.log ;;
        fsck) lf=/mnt/base-us/veradroid/logs/fsck.log; [ -f "$lf" ] || lf=/mnt/base-us/veradroid-fsck.log ;;   # root-legacy
        *) echo "error=unknown log"; return ;;
    esac
    [ -f "$lf" ] && [ ! -L "$lf" ] || { echo "(还没有这个日志)"; return; }
    tail -n "$nl" "$lf" 2>/dev/null | tr -d '\000' | tail -c 524288
}

# 截屏：直接读墨水屏的帧缓冲（显示桥画上去的就是屏幕上的），8 位灰度时输出“头一行 + 原始像素”，VeraHome 转成 PNG。
# 别的格式退回 Android 的 screencap。
wa_shot() { # 编号 uid
    o=$WA_OUT/$1
    fbd=/sys/class/graphics/fb0
    bpp=$(cat $fbd/bits_per_pixel 2>/dev/null)
    stride=$(cat $fbd/stride 2>/dev/null)
    pany=$(cut -d, -f2 $fbd/pan 2>/dev/null)
    xres=$(sed -n 's/^[^:]*:\([0-9]*\)x\([0-9]*\).*/\1/p' $fbd/modes 2>/dev/null | head -1)
    yres=$(sed -n 's/^[^:]*:\([0-9]*\)x\([0-9]*\).*/\2/p' $fbd/modes 2>/dev/null | head -1)
    if [ "$bpp" = 8 ] && [ -n "$stride" ] && [ -n "$xres" ] && [ -n "$yres" ] && [ "$xres" -le "$stride" ] 2>/dev/null; then
        { echo "fb $xres $yres $stride"; dd if=/dev/fb0 bs=$stride skip=${pany:-0} count=$yres 2>/dev/null; } > "$o.tmp"
    elif [ "$bpp" = 32 ] && [ -n "$stride" ] && [ -n "$xres" ] && [ -n "$yres" ] && [ $((xres * 4)) -le "$stride" ] 2>/dev/null; then
        # 彩色屏（Colorsoft）：32 位 BGRA
        { echo "fb32 $xres $yres $stride"; dd if=/dev/fb0 bs=$stride skip=${pany:-0} count=$yres 2>/dev/null; } > "$o.tmp"
    else
        $(vd_in) /system/bin/screencap -p /dev/kfb/wa/$1.tmp >/dev/null 2>&1
    fi
    if [ -s "$o.tmp" ]; then chown "$2" "$o.tmp" && chmod 400 "$o.tmp" && mv -f "$o.tmp" "$o.out"
    else rm -f "$o.tmp"; echo "error=screenshot failed" | wa_put "$1" "$2"; fi
}

wa_autoupdate() { # 0|1|notify|?   （0 关闭，1 自动安装，notify 只提醒：发现新版本只写 $VD/update.available，不装）
    case "$1" in
    0) echo 0 > $VD/autoupdate; wa_log "web: auto update off" ;;
    1|notify)
       echo "$1" > $VD/autoupdate; wa_log "web: auto update $1"
       # 关着开机时更新程序根本没起来：现在起一个（和 veradroid.sh 一样从 tmpfs 副本运行）
       ap=$(cat $W/autoupdate.pid 2>/dev/null)
       if ! { [ -n "$ap" ] && kill -0 "$ap" 2>/dev/null; } && [ -f "$VD/boot/lib/auto-update.sh" ]; then
           cp "$VD/boot/lib/auto-update.sh" $W/auto-update.sh 2>/dev/null && ( cd / && exec setsid sh $W/auto-update.sh ) </dev/null >/dev/null 2>&1 &
       fi ;;
    '?') ;;
    *) echo "error=bad value"; return ;;
    esac
    echo "ok=1"
    case "$(cat $VD/autoupdate 2>/dev/null)" in 0) echo "autoupdate=0" ;; notify) echo "autoupdate=notify" ;; *) echo "autoupdate=1" ;; esac
}

# ---------------------------------------------------------------- SSH 诊断（docs/ssh-diagnostics.md）
wa_sha256() { { sha256sum "$1" 2>/dev/null || openssl dgst -sha256 "$1" 2>/dev/null | sed 's/.*= *//'; } | cut -c1-64; }
wa_ssh_pids() {   # 一次 ls 看完所有进程的可执行文件（逐个 readlink 太慢）
    ls -l /proc/[0-9]*/exe 2>/dev/null | sed -n "s#.* /proc/\([0-9]*\)/exe -> $WA_SSHRUN/dropbear\( (deleted)\)\{0,1\}\$#\1#p"
}
# 和诊断包同一个过滤：只认格式正确的公钥行（不接受选项前缀），输出“行号<TAB>原行”
wa_ssh_validkeys() {
    [ -f "$WA_SSHB/my-public-keys.txt" ] || return 0
    tr -d '\r' < "$WA_SSHB/my-public-keys.txt" | sed '1s/^\xef\xbb\xbf//' | awk '
        $1 ~ /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)$/ \
            && $2 ~ /^AAAA[A-Za-z0-9+\/]+=*$/ && length($2) >= 60 { print NR "\t" $0 }'
}
wa_sshstate() {
    ps=$(wa_ssh_pids)
    [ -n "$ps" ] && echo "ssh.running=1" || echo "ssh.running=0"
    echo "ssh.port=2222"
    [ -f "$WA_SSHSRC/VeraDroid-SSH.sh" ] && echo "ssh.script=1" || echo "ssh.script=0"
    ip=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -1)
    [ -n "$ip" ] || ip=$(ifconfig eth0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -1)
    echo "ssh.ip=$ip"
    if [ -s "$WA_SSHB/device_host_key.pub" ]; then
        echo "ssh.hostkeytype=$(awk '{ print $1; exit }' "$WA_SSHB/device_host_key.pub" | wa_clean 40)"
        if command -v openssl >/dev/null 2>&1; then
            fp=$(awk '{ print $2; exit }' "$WA_SSHB/device_host_key.pub" | openssl base64 -d -A 2>/dev/null | openssl dgst -sha256 -binary 2>/dev/null | openssl base64 -A 2>/dev/null | tr -d '=')
            [ -n "$fp" ] && echo "ssh.fingerprint=SHA256:$(printf '%s' "$fp" | wa_clean 60)"
        fi
    fi
    wa_ssh_validkeys | awk -F'\t' '{ na = split($2, a, " "); c = ""; for (i = 3; i <= na; i++) c = c (c == "" ? "" : " ") a[i]
        gsub(/[^A-Za-z0-9@._+:= -]/, "", c); printf "ssh.key=%d|%s|%s|%s\n", ++k, a[1], substr(a[2], length(a[2]) - 11), substr(c, 1, 60) }'
    [ -f "$WA_SSHB/my-public-keys.txt" ] && echo "ssh.keyfile=1" || echo "ssh.keyfile=0"
    tail -1 "$WA_SSHB/ssh.log" 2>/dev/null | wa_clean 160 | sed 's/^/ssh.last=/'
}
wa_sshstart() {
    [ -n "$(wa_ssh_pids)" ] && { echo "ssh.msg=already running"; return 0; }
    src=$WA_SSHSRC/VeraDroid-SSH.sh
    if [ ! -f "$src" ] || [ -L "$src" ]; then echo "ssh.error=noscript"; return 1; fi
    # 拷到内存盘里运行：诊断包会优先用“脚本旁边的 dropbear”，而书库目录网页能写。dropbear 只认校验和对得上的那份。
    d=$W/sshrun
    rm -rf $d; mkdir -p $d && chmod 700 $d || { echo "ssh.error=tmp"; return 1; }
    cp "$src" $d/VeraDroid-SSH.sh || { echo "ssh.error=copy"; return 1; }
    if [ -f "$WA_SSHSRC/dropbear" ] && [ ! -L "$WA_SSHSRC/dropbear" ]; then
        cp "$WA_SSHSRC/dropbear" $d/dropbear 2>/dev/null
        if [ "$(wa_sha256 $d/dropbear)" != "$WA_DROPBEAR_SHA" ]; then rm -f $d/dropbear; wa_log "web ssh: documents/VeraDroid-SSH/dropbear checksum mismatch, not used"; fi
    fi
    ( cd / && VD_SSH_HOLD=0 sh $d/VeraDroid-SSH.sh ) </dev/null > $d/out 2>&1
    rc=$?
    epd_send FULL >/dev/null 2>&1      # 诊断包会用 eips 在屏幕上写几行英文：重画 Android 的画面
    echo "ssh.rc=$rc"
    tail -6 $d/out 2>/dev/null | wa_clean 100 | sed 's/^/ssh.out=/'
    wa_log "web: ssh start rc=$rc"
}
wa_sshstop() {
    d=$W/sshrun
    if [ -n "$(wa_ssh_pids)" ]; then
        if [ -f "$WA_SSHSRC/VeraDroid-SSH.sh" ] && [ ! -L "$WA_SSHSRC/VeraDroid-SSH.sh" ]; then
            mkdir -p $d && chmod 700 $d && cp "$WA_SSHSRC/VeraDroid-SSH.sh" $d/VeraDroid-SSH.sh
            ( cd / && VD_SSH_HOLD=0 sh $d/VeraDroid-SSH.sh stop ) </dev/null > $d/out 2>&1
            epd_send FULL >/dev/null 2>&1
        fi
        # 诊断包不在了也要能关：只杀可执行文件是那份拷贝的进程，撤掉它加的防火墙规则和防休眠
        ps=$(wa_ssh_pids)
        if [ -n "$ps" ]; then
            kill $ps 2>/dev/null; sleep 1; ps=$(wa_ssh_pids); [ -z "$ps" ] || kill -9 $ps 2>/dev/null
            [ -f $WA_SSHRUN/iptables-rule ] && iptables -D INPUT -i wlan0 -p tcp --dport 2222 -j ACCEPT 2>/dev/null
            [ -f $WA_SSHRUN/keep-awake ] && { lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null; iwconfig wlan0 power on 2>/dev/null; }
            rm -rf $WA_SSHRUN
        fi
    fi
    rm -rf $d
    echo "ssh.msg=stopped"; wa_log "web: ssh stopped"
}
# 加一把公钥：数据行必须正好是一把公钥（类型 + base64 + 可选的简单注释），不接受选项前缀
wa_sshkeyadd() { # 公钥行
    k=$1
    [ ${#k} -le 8192 ] || { echo "ssh.error=badkey"; return 1; }
    printf '%s\n' "$k" | grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) AAAA[A-Za-z0-9+/]+=*( [A-Za-z0-9@._+:=-]+)?$' \
        || { echo "ssh.error=badkey"; wa_log "web ssh: rejected a key line"; return 1; }
    blob=$(printf '%s\n' "$k" | awk '{ print $2 }')
    [ ${#blob} -ge 60 ] || { echo "ssh.error=badkey"; return 1; }
    mkdir -p "$WA_SSHB" || { echo "ssh.error=dir"; return 1; }
    kf=$WA_SSHB/my-public-keys.txt
    [ -L "$kf" ] && { echo "ssh.error=symlink"; return 1; }
    if [ -f "$kf" ] && grep -qF "$blob" "$kf"; then echo "ssh.msg=exists"; return 0; fi
    [ "$(wa_ssh_validkeys | wc -l)" -lt 20 ] || { echo "ssh.error=toomany"; return 1; }
    { echo; echo "# 管理网页添加 $(date '+%F %T')"; printf '%s\n' "$k"; } >> "$kf" || { echo "ssh.error=write"; return 1; }
    sync
    echo "ssh.msg=added"; wa_log "web ssh: key added ($(printf '%s' "$k" | awk '{ print $1 }'))"
}
wa_sshkeydel() { # 第几把（ssh.key= 的编号）
    case "$1" in ''|*[!0-9]*) echo "ssh.error=bad index"; return 1 ;; esac
    kf=$WA_SSHB/my-public-keys.txt
    [ -f "$kf" ] && [ ! -L "$kf" ] || { echo "ssh.error=nofile"; return 1; }
    ln=$(wa_ssh_validkeys | sed -n "${1}p" | cut -f1)
    case "$ln" in ''|*[!0-9]*) echo "ssh.error=bad index"; return 1 ;; esac
    tr -d '\r' < "$kf" | sed '1s/^\xef\xbb\xbf//' | awk -v drop="$ln" 'NR != drop' > "$kf.tmp" && mv -f "$kf.tmp" "$kf" || { rm -f "$kf.tmp"; echo "ssh.error=write"; return 1; }
    sync
    echo "ssh.msg=deleted"; wa_log "web ssh: key $1 deleted"
}
