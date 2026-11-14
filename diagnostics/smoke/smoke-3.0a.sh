#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid 3.0.a 宿主侧冒烟测试（不依赖 Android，不碰 Kindle 界面）
#
# 验证：
#   1. unshare 出 mount/UTS/IPC/net/PID 命名空间，pivot_root 到只含 busybox 的小根
#   2. 容器进程在 freezer cgroup 里，冻结 / 解冻
#   3. nsenter 进容器执行命令（ashell 的原理）
#   4. kill -9 容器 init，整个命名空间被清掉，无残留挂载 / 进程 / cgroup
#
# 用法：通过 SSH：  ssh ... 'sh -s' < smoke-3.0a.sh
# 全部临时文件在 /var/tmp/vdsmoke（tmpfs，重启即消失），退出时自动清理。

T=/var/tmp/vdsmoke
R=$T/root
FZ=$T/fz
HB=$T/hb
rm -rf "$T"; mkdir -p "$T" "$R" "$FZ" "$HB"

ok()   { echo "PASS: $*"; }
bad()  { echo "FAIL: $*"; FAILED=1; }
step() { echo; echo "== $*"; }
FAILED=0

cleanup() {
    echo; echo "== cleanup"
    # 容器 init（新 PID 命名空间的 1 号）被 SIGKILL 后内核会杀掉整个命名空间
    for p in $(pgrep -f "vdsmoke-container" 2>/dev/null); do
        [ -d $FZ/android ] && echo THAWED > $FZ/android/freezer.state 2>/dev/null
        kill -9 $p 2>/dev/null
    done
    sleep 1
    [ -d $FZ/android ] && rmdir $FZ/android 2>/dev/null
    grep -q " $FZ " /proc/mounts && umount $FZ 2>/dev/null
    for m in $(grep " $T" /proc/mounts | cut -d' ' -f2 | sort -r); do umount -l "$m" 2>/dev/null; done
    rm -rf "$T"
    echo "leftover mounts under $T: $(grep -c " $T" /proc/mounts)"
    echo "leftover freezer mounts: $(grep -c freezer /proc/mounts)"
    echo "leftover processes: $(pgrep -f vdsmoke-container | wc -l)"
}
trap cleanup EXIT

step "0. 前置：当前环境"
echo "uid=$(id -u) kernel=$(uname -r) mem_avail_kB=$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
echo "mounts before: $(wc -l < /proc/mounts)"
echo "oom_score_adj(self)=$(cat /proc/$$/oom_score_adj)"

step "1. 挂 freezer，建 android 组"
mount -t cgroup -o freezer freezer $FZ && ok "freezer mounted" || { bad "freezer mount"; exit 1; }
mkdir $FZ/android && ok "cgroup created" || { bad "mkdir cgroup"; exit 1; }

step "2. 容器内要跑的脚本（心跳 + 自检）"
cat > $T/inside.sh <<'EOF'
#!/bin/sh
# 这里已经在新的 mount/UTS/IPC/net/PID 命名空间里，PID 应该是 1
R=$1; T=$2
mount --make-rprivate / || echo "rprivate failed"
mount -t tmpfs -o mode=755 tmpfs $R || exit 11
mkdir -p $R/bin $R/lib $R/usr $R/proc $R/dev $R/sys $R/tmp $R/hb $R/old
mount --bind /bin $R/bin   || exit 12
mount --bind /lib $R/lib   || exit 13
mount --bind /usr/lib $R/usr/lib 2>/dev/null || { mkdir -p $R/usr/lib; mount --bind /usr/lib $R/usr/lib; }
mount --bind $T/hb $R/hb   || exit 14
mount -t proc proc $R/proc || exit 15
mount -t tmpfs -o mode=755 tmpfs $R/dev || exit 16
for n in null zero random urandom full tty; do touch $R/dev/$n; mount --bind /dev/$n $R/dev/$n; done
mount -t sysfs -o ro sysfs $R/sys || echo "sysfs failed"
hostname vdroid
cd $R || exit 17
pivot_root . old || exit 18
cd /
umount -l /old; rmdir /old 2>/dev/null
# 心跳：每 0.2 秒写一个递增数，宿主靠它判断冻结 / 解冻
exec /bin/sh -c '
echo "container: pid=$$ host=$(hostname) ns_net=$(ls /sys/class/net 2>/dev/null | tr "\n" ",")" > /hb/info
echo "container: mounts=$(wc -l < /proc/mounts) root=$(ls / | tr "\n" " ")" >> /hb/info
echo "container: ps=$(ps | wc -l) uid=$(id -u)" >> /hb/info
n=0
while :; do n=$((n+1)); echo $n > /hb/count; usleep 200000; done
' vdsmoke-container
EOF
chmod 755 $T/inside.sh

step "3. 启动容器（freezer 组里 fork，随后本进程回到根组）"
# 本 shell 先进 android 组再 fork，容器所有进程从一开始就在组里
echo $$ > $FZ/android/tasks
unshare -m -u -i -n -p -f -- sh $T/inside.sh $R $T </dev/null >$T/container.out 2>&1 &
UPID=$!
# 回到根组：写进根层级的 tasks
echo $$ > $FZ/tasks
i=0; P=
while [ $i -lt 20 ]; do
    read -r P _ < /proc/$UPID/task/$UPID/children 2>/dev/null
    [ -n "$P" ] && break
    usleep 100000; i=$((i+1))
done
[ -n "$P" ] && ok "container init found: host pid=$P (unshare pid=$UPID)" || { bad "no container child"; cat $T/container.out; exit 1; }
sleep 2
cat $T/hb/info 2>/dev/null
cat $T/container.out
[ -f $T/hb/count ] && ok "heartbeat running: $(cat $T/hb/count)" || { bad "no heartbeat"; exit 1; }

step "4. 命名空间隔离检查（对比宿主）"
for ns in mnt uts ipc net pid; do
    a=$(readlink /proc/$$/ns/$ns); b=$(readlink /proc/$P/ns/$ns)
    [ "$a" != "$b" ] && ok "ns $ns differs" || bad "ns $ns same as host"
done
echo "container tasks in cgroup: $(cat $FZ/android/tasks | wc -l)"
echo "host hostname still: $(hostname)"

step "5. 冻结 / 解冻"
c1=$(cat $T/hb/count); sleep 1; c2=$(cat $T/hb/count)
[ "$c2" -gt "$c1" ] && ok "running before freeze ($c1 -> $c2)" || bad "heartbeat not advancing before freeze"
echo FROZEN > $FZ/android/freezer.state
i=0; while [ "$(cat $FZ/android/freezer.state)" != FROZEN ] && [ $i -lt 50 ]; do usleep 100000; i=$((i+1)); done
echo "freezer.state=$(cat $FZ/android/freezer.state) after ${i}x100ms"
f1=$(cat $T/hb/count); sleep 2; f2=$(cat $T/hb/count)
[ "$f1" = "$f2" ] && ok "frozen: heartbeat stopped at $f1" || bad "heartbeat still advancing while frozen ($f1 -> $f2)"
echo THAWED > $FZ/android/freezer.state
sleep 1
t1=$(cat $T/hb/count); sleep 1; t2=$(cat $T/hb/count)
[ "$t2" -gt "$t1" ] && ok "thawed: heartbeat resumed ($t1 -> $t2)" || bad "heartbeat did not resume"

step "6. nsenter 进容器（ashell 的原理）"
nsenter -t $P -m -u -i -n -p -r -w /bin/sh -c 'echo "in-container: pid1=$(cat /proc/1/cmdline | tr "\000" " ") host=$(hostname) cwd=$(pwd)"; ls /' 2>&1 | head -8
nsenter -t $P -m -p -r -w /bin/sh -c 'cat /hb/count' >/dev/null 2>&1 && ok "nsenter works" || bad "nsenter failed"

step "7. kill -9 容器 init"
kill -9 $P
sleep 1
kill -0 $P 2>/dev/null && bad "container init still alive" || ok "container init gone"
left=$(pgrep -f vdsmoke-container | wc -l)
[ "$left" = 0 ] && ok "no container processes left" || bad "$left container processes left"
echo "tasks left in cgroup: $(cat $FZ/android/tasks | wc -l)"

echo
[ "$FAILED" = 0 ] && echo "RESULT: ALL PASS" || echo "RESULT: SOME FAILED"
