# SPDX-License-Identifier: GPL-3.0-or-later
# 内存：Kindle 没有 swap。运行期间用内核自带的 zram 做压缩 swap，停止时恢复 swappiness，zram 本身不撤
# （swapoff 要把换出去的页读回来，会拖很久）。zram 的大小只能在它空闲时改。
# 小内存机型（PW5/KT5/KT6，512 MB）：lab126 4.9 内核的启发式 overcommit 拒绝“大于当前可用内存”的单块私有可写映射，
# ART 的 256 MB 堆（memfd + MAP_PRIVATE）和 zygote fork 都会被拒 → zygote 无限崩溃。运行期间改为 1，停止时恢复。
# 957 MB 的 PW6（5.15 内核）不受影响，不改。
overcommit_on() {
    mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    [ -n "$mt" ] && [ "$mt" -lt 700000 ] || return 0
    [ -f $W/overcommit.state ] || cat /proc/sys/vm/overcommit_memory > $W/overcommit.state
    echo 1 > /proc/sys/vm/overcommit_memory && t "low ram ${mt}kB: overcommit_memory=1"
}
overcommit_restore() {
    [ -f $W/overcommit.state ] || return 0
    cat $W/overcommit.state > /proc/sys/vm/overcommit_memory
    rm -f $W/overcommit.state
}

# Kernel LMK (drivers/staging/android/lowmemorykiller.c) is what actually kills
# processes on lab126 4.9. The log "cache X is below limit Y for oom_adj Z"
# comes from the kernel module, NOT lmkd. vdlmk only talks to the lmkd socket;
# ActivityManager often logs "Error writing to lowmemorykiller socket", and the
# stock large-screen table stays (adj0=72MB, adj100=92MB, adj200=108MB).
# User 092A032524017 (Kindle 2022 / KT5, 485 MB): 8× foreground WeRead kills.
lmk_kernel_tune() {
    mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    [ -n "$mt" ] && [ "$mt" -lt 700000 ] || return 0
    mf=/sys/module/lowmemorykiller/parameters/minfree
    ad=/sys/module/lowmemorykiller/parameters/adj
    [ -f "$mf" ] || return 0
    echo 2048,3072,4096,5120,6144,8192 > "$mf" 2>/dev/null || return 1
    [ -f "$ad" ] && echo 0,100,200,300,900,906 > "$ad" 2>/dev/null || true
    t "lmk: kernel minfree 8/12/16/20/24/32MB (was stock 72/92/108MB class)"
}

# heap + low_ram props. Must run before the container starts (build.prop is read by zygote).
# Do NOT raise 512 MB devices to 256m/512m (that was a PW6-oriented fix and causes LMK kills).
heap_fix() {
    f=$R/system/build.prop
    [ -f "$f" ] || return 0
    mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    _prop() {
        k=$1; v=$2
        if grep -q "^$k=" "$f"; then
            sed -i "s|^$k=.*|$k=$v|" "$f"
        else
            echo "$k=$v" >> "$f"
        fi
    }
    if [ -n "$mt" ] && [ "$mt" -lt 700000 ]; then
        _prop dalvik.vm.heapstartsize 8m
        _prop dalvik.vm.heapgrowthlimit 128m
        _prop dalvik.vm.heapsize 192m
        _prop dalvik.vm.heapminfree 512k
        _prop dalvik.vm.heapmaxfree 2m
        _prop dalvik.vm.heaptargetutilization 0.75
        _prop ro.config.low_ram true
        _prop ro.config.max_starting_bg 2
        _prop ro.sys.fw.bg_apps_limit 2
        t "low ram ${mt}kB: heap 8/128/192m + ro.config.low_ram=true"
    else
        if grep -q '^dalvik.vm.heapgrowthlimit=128m$' "$f"; then
            sed -i 's/^dalvik.vm.heapgrowthlimit=128m$/dalvik.vm.heapgrowthlimit=256m/; s/^dalvik.vm.heapsize=256m$/dalvik.vm.heapsize=512m/' "$f" \
                && t "heap limit raised to 256m/512m (was 128m)"
        fi
    fi
}

zram_on() {
    overcommit_on
    heap_fix
    lmk_kernel_tune
    Z=/sys/block/zram0
    [ "${ZRAM_MB:-0}" -gt 0 ] && [ -e $Z/disksize ] || return 0
    if ! grep -q '^/dev/zram0 ' /proc/swaps; then
        [ "$(cat $Z/disksize)" != 0 ] && echo 1 > $Z/reset
        [ "$(cat $Z/disksize)" = 0 ] || { t "zram0 busy, skipped"; return 0; }
        echo ${ZRAM_MB}M > $Z/disksize && mkswap /dev/zram0 >/dev/null && swapon -p 100 /dev/zram0 || {
            echo 1 > $Z/reset 2>/dev/null; t "zram failed"; return 0; }
    fi
    [ -f $W/zram.state ] || echo "$(cat /proc/sys/vm/swappiness) $(cat /proc/sys/vm/page-cluster)" > $W/zram.state
    # swappiness：957 MB 的 PW6 用 40（100 会把正在用的应用页也换出去，再用时要从 zram 解压回来）。
    # 512 MB 机型用 100：内存紧的时候 40 让内核去扔文件页（应用的 odex / apk 代码），下一次用到就是一次读盘的主缺页；
    # 换成往 zram 里压匿名页更便宜。KT5 模拟器（stop，3 轮脚本操作）：微信读书主缺页 −25 %，直接回收次数减半；
    # PW5 模拟器冷启动到主界面 81 / 97 / 70 s -> 62 / 65 / 45 s（docs/slim-android.md 第 7 节）。设置里写 VM_SWAPPINESS 可覆盖。
    sw=40; lowmem_ram && sw=100
    echo ${VM_SWAPPINESS:-$sw} > /proc/sys/vm/swappiness
    echo 0 > /proc/sys/vm/page-cluster
    # 实验用：kswapd 提前多少开始回收（watermark_scale_factor，万分之几，内核默认 10）。空 = 不动
    if [ -n "$VM_WATERMARK" ] && [ -w /proc/sys/vm/watermark_scale_factor ]; then
        [ -f $W/wsf.state ] || cat /proc/sys/vm/watermark_scale_factor > $W/wsf.state
        echo "$VM_WATERMARK" > /proc/sys/vm/watermark_scale_factor 2>/dev/null
    fi
    t "zram ${ZRAM_MB}MB on"
}
zram_restore() {
    overcommit_restore
    [ -f $W/zram.state ] || return 0
    read sw pc < $W/zram.state
    echo $sw > /proc/sys/vm/swappiness
    [ -n "$pc" ] && echo $pc > /proc/sys/vm/page-cluster
    rm -f $W/zram.state
    [ -f $W/wsf.state ] && cat $W/wsf.state > /proc/sys/vm/watermark_scale_factor 2>/dev/null; rm -f $W/wsf.state
}

# CPU governor (from rel-next-perf): powersave while frozen, restore on thaw. Fail-soft.
cpu_gov_set() {
    want=$1
    [ -n "$want" ] || return 0
    for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$g" ] || continue
        if [ ! -f $W/cpu_gov.state ]; then
            cat "$g" > $W/cpu_gov.state
        fi
        echo "$want" > "$g" 2>/dev/null || true
    done
    [ -f $W/cpu_gov.state ] && t "cpu_gov -> $want (was $(cat $W/cpu_gov.state))"
}
cpu_gov_restore() {
    [ -f $W/cpu_gov.state ] || return 0
    prev=$(cat $W/cpu_gov.state)
    for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$g" ] || continue
        echo "$prev" > "$g" 2>/dev/null || true
    done
    rm -f $W/cpu_gov.state
    t "cpu_gov restored -> $prev"
}

# 存储预读：Kindle 把 eMMC 和 loop 设备的 read_ahead_kb 设成 4（每次缺页只读一页）。Android 的应用是几十到一百多 MB 的
# 预编译文件，靠缺页读进来，4 KB 预读时冷启动很慢。PW6 实测（清掉缓存后）：微信读书冷启动 3.6–4.1 s -> 2.5–2.8 s，
# 到界面可见 8.5–9.2 s -> 5.9–6.3 s；Android 开机 15.8 s -> 12.9 s。128 和 256/512/1024 没有差别，取最小的。
# 只调大、不调小；原值记在内存盘里，stop 时恢复。
readahead_on() {
    [ "${READAHEAD_KB:-128}" -gt 0 ] 2>/dev/null || return 0
    : > $W/readahead.saved
    for b in /sys/block/mmcblk0 /sys/block/loop[0-9]*; do
        f=$b/queue/read_ahead_kb
        [ -w "$f" ] || continue
        case "$b" in */loop*) [ -s "$b/loop/backing_file" ] || continue ;; esac
        old=$(cat "$f" 2>/dev/null); [ -n "$old" ] || continue
        [ "$old" -lt "${READAHEAD_KB:-128}" ] 2>/dev/null || continue
        echo "$b $old" >> $W/readahead.saved
        echo "${READAHEAD_KB:-128}" > "$f" 2>/dev/null
    done
    return 0
}
readahead_restore() {
    [ -f $W/readahead.saved ] || return 0
    while read b old; do [ -w "$b/queue/read_ahead_kb" ] && echo "$old" > "$b/queue/read_ahead_kb" 2>/dev/null; done < $W/readahead.saved
    rm -f $W/readahead.saved
    return 0
}
