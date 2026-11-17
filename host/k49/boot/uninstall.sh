#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 卸载 VeraDroid（cmd.sh 的 uninstall 先把本脚本拷到 /dev/shm 再运行，因为它会删掉 $VD）。
# 保留：Android 里的书 / 微信读书下载 / 账号 token（data/media）、Kindle 自己的一切。
# 2026-11-10 修正（eink-emulator 复现）：旧版先跑 stop.sh（会卸载 loop 系统盘），再去 mv data/media，
# 这时已经找不到了，接着删掉 veradroid-sys.img —— PW5 / KT5 / KT6 上 Android 里的书全没了。
{
VD=/mnt/base-us/veradroid
. $VD/boot/lib/common.sh
ULOG=/mnt/base-us/veradroid-uninstall.log
exec >>$ULOG 2>&1
echo "== $(date) uninstall"
say() { command -v eips >/dev/null 2>&1 && eips 1 ${2:-4} "$1" >/dev/null 2>&1; t "uninstall: $1"; }
# 卸载停止时：本次从 loop 系统盘拷出来的书（KEEP）只是副本，原件还在镜像里 → 删掉副本，否则下次重试会因为 KEEP 已存在而永远停住
MADEKEEP=0
fail() { if [ "$MADEKEEP" = 1 ] && [ -d "$SYS/data/media" ] && [ -d "$KEEP" ]; then rm -rf /mnt/base-us/veradroid-media-keep; t "uninstall: 已删掉本次的书副本 $KEEP（原件仍在系统盘里）"; fi; say "卸载停止：$1（什么都没删）" 5; exit 1; }
KEEP=/mnt/base-us/veradroid-media-keep
sleep 1
cd /                                   # 自己的工作目录也不能在 $SYS 里
# 2026-11-12（kt6-517104 模拟器复现）：卸载以前不管自动更新。auto-update.sh 跑的是 /dev/shm 里的副本，卸载后还活着；
# 它看到“Android 没在运行 + 服务器有新版”就下载整包重装——卸载进行到一半时它已经在往同一个系统盘里装（结果是一套开不了机的系统，
# 之后点安装只得到“另一个安装/更新正在进行”），卸载完成以后它也会在下一次检查时把刚卸掉的 VeraDroid 又装回来。
# 所以：先停自动更新，再停正在跑的安装器（连同它的 curl / tar），清掉它们的锁和临时目录，然后才开始卸载。
kill_tree() { for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
ap=$(cat $W/autoupdate.pid 2>/dev/null); [ -n "$ap" ] || ap=$(cat /mnt/base-us/veradroid-autoupdate.lock/pid 2>/dev/null)
if [ -n "$ap" ] && [ "$ap" != "$$" ] && kill -0 "$ap" 2>/dev/null; then kill_tree "$ap"; t "uninstall: 已停止自动更新（pid $ap）"; fi
ip=$(cat /mnt/base-us/veradroid-install.lock/pid 2>/dev/null)
if [ -n "$ip" ] && [ "$ip" != "$$" ] && kill -0 "$ip" 2>/dev/null; then
    kill_tree "$ip"; t "uninstall: 已停止正在运行的安装器（pid $ip）"
    i=0; while [ $i -lt 10 ] && kill -0 "$ip" 2>/dev/null; do sleep 1; i=$((i + 1)); done
    kill -9 "$ip" 2>/dev/null
fi
rm -rf /mnt/base-us/veradroid-autoupdate.lock /mnt/base-us/veradroid-install.lock 2>/dev/null
rm -f $W/autoupdate.pid /mnt/base-us/veradroid-autoupdate-bootstrap.sh /mnt/base-us/veradroid-autoupdate-bootstrap.sh.part 2>/dev/null
sh $VD/boot/stop.sh >/dev/null 2>&1
# 2026-11-10（pw5-5182 模拟器复现）：开机途中的 veradroid.sh 还开着 $SYS/veradroid.log（exec >>$LOG），
# stop.sh 不杀它 → 系统盘卸不掉 → “卸载停止：还挂着”。卸载前先关掉所有还打开 $SYS 的进程（不含自己）。
sys_holders() {
    for p in /proc/[0-9]*; do
        pid=${p#/proc/}; [ "$pid" = "$$" ] && continue
        ls -l $p/cwd $p/root $p/fd 2>/dev/null | grep -qE -- "-> $SYS(/|\$)" && echo "$pid"
    done
}
i=0
while [ $i -lt 6 ]; do
    h=$(sys_holders); [ -z "$h" ] && break
    t "uninstall: 关掉仍占用 $SYS 的进程: $(for x in $h; do printf '%s(%s) ' $x "$(tr '\0' ' ' < /proc/$x/cmdline 2>/dev/null | cut -c1-60)"; done)"
    if [ $i -lt 4 ]; then kill $h 2>/dev/null; else kill -9 $h 2>/dev/null; fi
    sleep 1; i=$((i + 1))
done
say '正在卸载 VeraDroid，保留书和账号…'
[ -e "$KEEP" ] && fail "$KEEP 已存在（上一次卸载留下的书还在那里）"
LOOPIMG=0
if [ -f "$SYSTEM_IMG" ]; then
    LOOPIMG=1
    storage_mount || fail "系统盘挂不上"
    grep -q " $SYS " /proc/mounts || fail "系统盘没有挂上"
fi
mounts_under "$SYS/rootfs" 1 && fail "$SYS/rootfs 下面还有挂载"
if [ -d "$SYS/data/media" ]; then
    if [ "$LOOPIMG" = 1 ]; then
        # 系统盘里的 data/media 和 /mnt/base-us 不是同一个文件系统：先完整拷出来，核对，再删镜像
        need=$(du -sk "$SYS/data/media" 2>/dev/null | awk '{print $1}')
        free=$(df -k /mnt/base-us | awk 'NR==2{print $4}')
        if [ $(( ${need:-0} + 51200 )) -gt "${free:-0}" ]; then
            # 空间不够拷：只删系统部分，镜像（里面有书）留下
            rm -rf "$SYS/rootfs" "$SYS/data/dalvik-cache" 2>/dev/null
            storage_umount
            mounts_under "$VD" 1 && fail "$VD 下面有挂载"
            rm -rf "$VD" 2>/dev/null
            say "空间不够把书拷出来：系统已删除，书和账号还在 veradroid-sys.img 里（重新安装会接着用）" 5
            exit 0
        fi
        rm -rf "$KEEP.partial" 2>/dev/null
        # vfat 用户存储（KT5、PW5 等，pw5b-5192 模拟器实测）不能 chown：busybox cp -a 照样把文件全拷过去，只是报
        # "can't preserve ownership" 并返回 1，以前卸载因此总是停在“拷贝书失败”。只有这一种报错时不算失败（下面还要核对数量）。
        if ! cp -a "$SYS/data/media" "$KEEP.partial" 2>/tmp/vd-uninstall-cp.err; then
            if grep -v "preserve ownership" /tmp/vd-uninstall-cp.err | grep -q .; then rm -rf "$KEEP.partial"; fail "拷贝书失败"; fi
            t "uninstall: 用户存储不能保留文件属主（vfat），书照样拷完了"
        fi
        rm -f /tmp/vd-uninstall-cp.err
        n1=$(find "$SYS/data/media" | wc -l); n2=$(find "$KEEP.partial" | wc -l)
        [ "$n1" = "$n2" ] || { rm -rf "$KEEP.partial"; fail "拷贝核对失败 ($n1/$n2)"; }
        mv "$KEEP.partial" "$KEEP" || fail "无法保存书"
        MADEKEEP=1
    else
        mv "$SYS/data/media" "$KEEP" || fail "无法保存书"
    fi
fi
storage_umount
mounts_under "$SYS" 1 && fail "$SYS 还挂着（或下面有挂载）"
mounts_under "$VD" 1 && fail "$VD 下面有挂载"
rm -rf "$VD" 2>/dev/null
[ "$LOOPIMG" = 1 ] && rm -f "$SYSTEM_IMG"
rm -f /mnt/base-us/veradroid-resize.state /mnt/base-us/veradroid-resize.pending /mnt/base-us/veradroid-resize.last /mnt/base-us/veradroid-resize.notify /mnt/base-us/veradroid-resize.log 2>/dev/null   # 系统盘大小调整留下的记录（storage.sh）
rm -rf "$SYS" 2>/dev/null
rm -rf /mnt/base-us/veradroid-install.[0-9]* 2>/dev/null; rm -f /mnt/base-us/veradroid-install.incomplete 2>/dev/null   # 被上面停掉的安装器留下的临时目录 / 半截标记
rm -rf /mnt/base-us/veradroid.bak.* 2>/dev/null       # 很早的版本留下的程序目录备份（没有用户数据）
# $SYS.pre-ext4.* 可能是 loop 系统盘之前的书，不删（重新安装时会搬回去）
if [ "$LOOPIMG" = 1 ]; then
    # KT5 / KT6 等：/mnt/base-us/system 是 fscrypt 加密目录，不加密的目录 mv 不进去（EPERM，模拟器实测）。
    # 书就留在 veradroid-media-keep，重新安装时 bootstrap 会把它搬进新的系统盘。
    :
else
    mkdir -p "$SYS/data"
    [ -d "$KEEP" ] && mv "$KEEP" "$SYS/data/media"
fi
rm -f /mnt/base-us/veradroid-version /mnt/base-us/veradroid-model /mnt/base-us/veradroid-device-id /mnt/base-us/veradroid-fullupdate.log /mnt/base-us/veradroid-fullupdate.rc
# 书库里我们自己建的启动入口和 KUAL 菜单也拿掉：程序没了以后入口还留着，点了只会说“未安装”（用户报告：只剩一个入口而且打不开）。
# 只按固定名字删我们自己建的东西；KUAL 目录要确认里面是我们那几份文件才删。别的 .sh 入口、别的扩展一律不动。
for uL in "/mnt/us/documents/VeraDroid 启动.sh" "/mnt/base-us/documents/VeraDroid 启动.sh"; do
    if [ -f "$uL" ] && grep -q '/mnt/base-us/veradroid/boot/veradroid.sh' "$uL" 2>/dev/null; then
        rm -f "$uL"; [ -d "$uL.sdr" ] && [ ! -L "$uL.sdr" ] && rm -rf "$uL.sdr"
        t "uninstall: 已删除书库入口 $uL"
    fi
done
# 用户为了卸载拷进 documents 的 VeraDroid-Uninstall.sh：卸完就没用了，一起拿掉（只认我们自己那份）
# BEGIN vd_retire_uninstall_entry
# 只认我们自己放的那一个：固定文件名 documents/VeraDroid-Uninstall.sh（历来只用过这一个名字），普通文件（不是链接），
# 头里是我们的标题，内容指向我们的程序目录。用户别的文件、同名但内容不是我们的文件一律不动。
vd_retire_uninstall_entry() {
    for d in /mnt/us/documents /mnt/base-us/documents; do
        f=$d/VeraDroid-Uninstall.sh
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        grep -q '^# Name: VeraDroid 卸载$' "$f" 2>/dev/null && grep -q '^VD=/mnt/base-us/veradroid$' "$f" 2>/dev/null || continue
        rm -f "$f" 2>/dev/null || continue
        for s in "$d/VeraDroid-Uninstall.sh.sdr" "$d/VeraDroid-Uninstall.sdr"; do [ -d "$s" ] && [ ! -L "$s" ] && rm -rf "$s" 2>/dev/null; done
        command -v vlog >/dev/null 2>&1 && vlog "library: removed the old uninstall entry $f"
        RETIRED=1
    done
    return 0
}
# END vd_retire_uninstall_entry
vd_retire_uninstall_entry
uK=/mnt/us/extensions/VeraDroid
if [ -d "$uK" ] && [ ! -L "$uK" ] && grep -q 'veradroid' "$uK/start.sh" 2>/dev/null; then
    rm -f "$uK/start.sh" "$uK/install.sh" "$uK/config.xml" "$uK/menu.json"; rmdir "$uK" 2>/dev/null && t "uninstall: 已删除 KUAL 菜单 $uK"
fi
say 'VeraDroid 已卸载，书和账号保留。可随时重新安装。' 5
exit 0
}
