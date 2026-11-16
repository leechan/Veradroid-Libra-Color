# 卡顿：真机上量出来的原因和改动（PW6 5.19.5 测试机，0.94，2026-11-16，分支 `fix/jank`，基于 `fix/epd-flash` 6db4baa）

机主反馈“Android 用起来卡”。这一页只写量出来的东西。测量时测试机临时用了另一台测试机的 settings.conf（KFB_SMOOTH=3 画质优先、
MODE=3、FLASH=10、KINDLE_UI=auto → freeze、HZ 默认 30），测完还原。工具：`tools/bench/bench.sh`、`thr.sh`，simpleperf（容器里
`/system/xbin/simpleperf`，这个版本没有 `--duration` / `--percent-limit`，用 `record ... sleep N`）。

## 1. 原因，按量出来的影响排序

1. **页缓存反复丢了又读（换应用、打开应用时）。** PW6 的 `/mnt/base-us`（Android 的 rootfs 和 data 都在上面）是 eMMC 分区
   mmcblk0p10 上的 loop0（Kindle 自己的），缓冲方式：每个文件页在缓存里有两份（ext4 文件页 + loop0 下面块设备的页，
   `Buffers:` 150–170 MB）。几个应用的 odex（微信读书 161 MB、多看 92、Anki 88、静读天下 66）装不下，换一次应用读盘几百 MB。
   VeraHome 默认后台只留 1 个用户应用（Cleaner，`bg_keep`），所以换应用基本都是冷启动，全靠缓存。
   另一台测试机开机 4.9 天：`workingset_refault_file` 3160 万页（≈120 GB 重新读），`pgpgin` 143 GB，`pgsteal_direct` 182 万。
2. **微信读书自己的绘制和 GC。** 一次翻页应用主线程 370 ms + HeapTaskDaemon 110 ms（simpleperf：Skia 画路径 / 描边 33 %，
   GC 标记 24 %，odex 6 %）。长时间看书后的进程每翻一页要一次 8 MB 的大对象（整页位图），heapmaxfree=8m 让每页都触发一次
   partial GC（100–200 ms，后台线程，和合成 / 显示桥抢两个核）。刚启动的进程没有这个现象。应用内部的事，见第 3 节。
3. **多看阅读：SurfaceFlinger 每次操作 100 ms 以上。** 多看的阅读页是 3 个全屏层（书城页 + 阅读页 + 一个几乎全透明的全屏窗口），
   hwcomposer.kindle 只要遇到半透明层就把整行逐像素混合：每帧 28–62 ms。
4. 显示桥和面板：翻页“发出 → 面板刷完” 250–270 ms 是波形本身（GC16 / REAGL），桥自己每次 10–30 ms CPU。没有可省的。

量过、不是原因的：
- CPU 调速器：ondemand（20 ms 采样，up_threshold 95）。把最低频率钉到 2 GHz：微信读书翻页 240 → 245 ms、桌面 150 → 161 ms，没有差别。
- 应用编译：微信读书 / 多看 / 桌面都是 `speed`、`kOatUpToDate`，odex 的代码段是可执行映射，不是解释执行。
- 应用绘制：本来就是 CPU（Skia）绘制，不走 libagl 的 GLES（`docs/webview-nogpu.md`），没有可切的。
- 帧率：vsync 30 Hz（KFB_HZ 默认）；HWC 里 2/3 的帧是“内容没变”，到 HWC 就结束（一次比较）。
- 网络：容器里到 223.5.5.5 的 RTT 13.5–14.6 ms，宿主 14.2–15.4 ms，slirp 没有可见的延迟；多看自己的接口请求 0.5–1.4 s 是服务器的。
- 稳定状态下翻页时几乎不换页（refault 0–40 页 / 次），翻页卡不是内存造成的；内存只在换 / 开应用时是主因。
- 输入：桌面切标签 手指按下 → 刷新发出 150 ms（其中 60 ms 是注入的按住时间），输入路径不是瓶颈。

## 2. 改了什么（都在测试机上量过）

### 2.1 PW6 宿主：loop0 直读写（`lib/memory.sh` 的 `loopdio_on` / `loopdio_restore`，`bin/vdloopdio`）

k49 早就有，PW6 没有。启动时把 `/mnt/base-us` 的 loop 设成直读写，stop 时改回（loop0 是 Kindle 的）。
`LOOP_DIO=0` 可关。

应用轮换（桌面 → 微信读书 → 多看 → 静读天下，`am start` 后看最后一次 ≥30 % 屏幕的刷新，每轮 4 次，交替测两组各 3 轮）：

| | 一轮总时间 | 微信读书 | 多看 | 静读天下 | 每次切换读盘 | 每次重新缺页 |
|---|---|---|---|---|---|---|
| 缓冲（0.94） | 23.1 s | 5.6 s | 6.9 s | 7.7 s | 70–544 MB（中位） | 0.9–12.5 万页 |
| 直读写 | 17.4 s | 7.0 s | 5.8 s | 2.9 s | 3–157 MB | 300–1.2 万页 |
| 直读写 + 新 HWC，重启后（最后一次） | 11.5 s | 1.8 / 3.7 / 3.8 s | 1.4 / 5.1 / 5.9 s | 3.8 / 1.6 / 4.1 s | 12–148 MB | 0.2–1.9 万页 |

微信读书完全冷启动（drop_caches 后，3 次交替）：缓冲 2.01–2.09 s，直读写 1.76–1.79 s；直读写再把预读加到 512 KB 反而慢（1.87–1.94 s），保持 128。
翻页（微信读书 10 次中位）：发出 392 → 357 ms，刷完 676 → 622 ms，应用缺页 148 → 43 次。桌面不变（150 / 500 ms）。

### 2.2 hwcomposer.kindle：按行判断哪些层真的可见（`android/hwcomposer/hwc_kindle.c`）

每一行从上往下看：预乘层这一行全是 0（完全透明）就跳过；某个全宽层这一行全是不透明就从它开始、下面的不看；最后只剩一层就直接从
它的缓冲比较 / 拷贝（和单层的快路径一样），否则只混合真正可见的层。判断用 NEON 一次读 16 个像素，混着的行读到一半就停。
另外：`planeAlpha` 不是 255 的层交回 GLES（以前会被当成不透明画）。dumpsys 多了平均耗时和直拷 / 混合的行数。

多看阅读页，弹出 / 关掉“已到达最后一页”对话框（3–4 个全屏层，10 次）：SurfaceFlinger 每次 100 → 60 ms CPU，每帧 31 → 18 ms
（平均 12.6 ms），93 % 的行走直拷。画面和旧版逐像素比较一致（30 万采样点只有时钟那几个不同）。单层的应用（微信读书、桌面）不受影响。

### 2.3 卡顿记录（`lib/jankrec.sh`，默认关）

`JANKREC=1`（settings.conf，下次启动生效）：每 2 秒一行系统计数（CPU、换页、读盘、直接回收、频率、可用内存），每 10 秒一份所有
进程累计 CPU 的快照，只留最近 20–30 秒。机主觉得卡的时候用手势动作 `jank`（`G_* = jank`，例如 `G_TWO_LONG_ACT=jank`）或命令
`jankdump`，存到 `$SYS/jank/jank-<时间>.txt`（最多 20 个）：期间每个进程的 CPU、上面的计数、显示桥和输入的日志尾、meminfo。
开销：一个核的 1.5 %（每秒一次时 2–4 %，每次 fork 约 10 ms，所以改成 2 秒）。Android 冻结 / 屏保时不采。只在一台测试机上试过。

## 3. 没做的、为什么

- 微信读书每页一次 GC：把 `dalvik.vm.heapminfree` / `heapmaxfree` 调大（例如 16m / 32m）能让几页才 GC 一次，但每个前台应用多占
  十几到几十 MB，正和第 1 条的内存问题冲突；而且只在看了很久的进程上出现，没能稳定复现来量收益。
- 后台留几个应用（VeraHome `bg_keep`）：已重新评估，见第 6 节（957 MB 机型默认改成 2）。
- Kindle 自己的 `/var/tmp/chroot` 下 chromium / locale 的 squashfs 被重复挂了几十次（两台测试机上都有 31 个），是 Kindle 那边的，
  对 Android 的速度没量到影响，没动。
- k49（PW5 / KT5 / KT6 / Scribe）：已经有直读写；新的 hwcomposer.kindle.so 同时放进了 `host/k49/bin`（同一个系统镜像），没在 k49 真机上测。
  卡顿记录只做了 PW6。
- 另一台测试机没装：一台的数据足够，另一台上只读了累计计数（上面第 1 条）。

## 4. 需要人眼看的

- 新 HWC 改的是合成：多看的对话框、菜单、半透明浮层、有 `planeAlpha` 渐变的窗口（现在交回 GLES）是否显示正常、有没有残留。
- 直读写只改缓存方式，不改数据；回到 Kindle（stop）时改回缓冲。

## 5. 复现

测试机上：`tools/bench/bench.sh`（翻页 / 标签），`tools/bench/switch.sh <轮数>`（应用轮换；冷启动同样做法：`am start` 后在 `epd.log` 里找最后一次 ≥30 % 的刷新，
同时记 `/proc/vmstat` 的 `workingset_refault_file` / `pgpgin` / `pgsteal_direct`）；直读写现场切换：`vdloopdio /dev/loop0 1|0`。

## 6. 后台保留应用（bg_keep）在直读写下重新评估（测试机，同一轮换，3 轮，每个值重启 Android 后测）

| bg_keep | 一轮总时间 | 每次切换读盘（中位） | 重新缺页（中位） | MemAvailable 最低 / 平均 | swap 最多 | 被杀 |
|---|---|---|---|---|---|---|
| 1（原默认） | 14.7 s | 171 MB | 2.2 万页 | 309 / 396 MB | 360 MB | 15 次 “kill background”（VeraHome 的清理） |
| **2** | **8.4 s** | **24 MB** | **3200 页** | 332 / 370 MB | 313 MB | 1 次（Anki） |
| 3 | 8.7 s | 23 MB | 3000 页 | 316 / 367 MB | 324 MB | 0 |

三种都没有 lmkd 或内核 OOM 杀进程；轮换完再在微信读书里连翻 20 页，进程没变（没有被杀后重开）。2 和 3 一样快，2 留的内存余量最多，
所以 **957 MB 机型默认 2，512 MB 机型保持 1**（`Cleaner.defaultLimit()` 看 MemTotal < 700 MB；用户选过的值不变）。

## 7. 其他应用（测试机，另一台测试机的显示设置；“改前” = 0.94 宿主，“改后” = 本分支宿主 + 新 HWC + bg_keep 2；各 12 次中位，毫秒）

| 场景 | 手指按下 → 第一次刷新 | → 面板刷完 | 应用 CPU | SurfaceFlinger CPU |
|---|---|---|---|---|
| 静读天下 书架列表滑动 | 146 → 152 | 994 → 1158 | 735 → 755 | 325 → 350 |
| KOReader 文件列表翻页（底栏按钮） | 188 → 222 | 676 → 710 | — | 0 → 25 |
| EinkBro 维基百科页面滑动（WebView） | 188 → 200 | 1958 → 1905 | 1305 → 1560 | 385 → 385 |
| 多看 弹出 / 关掉对话框（3–4 层） | 172 → 164 | 420 → — | — | 100 → 60 |

应用内部的滑动 / 翻页（稳定状态，不换页）两边在噪声内：这些路径不受内存影响，单层窗口 HWC 也没变。改进在换应用 / 开应用（第 2.1、6 节）
和多层窗口（多看）。Anki、miniread 停在欢迎 / 登录页，没法测滚动。

**HWC 正确性**（`hwccmp`：同一画面先用 hwcomposer.kindle 合成，再用 `/dev/kfb/hwc.gles` 让 SurfaceFlinger 自己用 GLES 合成，
`service call SurfaceFlinger 1004` 重画，逐字节比较合成出来的整页）：桌面、静读天下、KOReader、微信读书、EinkBro（含输入法弹出）、
多看书城 / 阅读页（2 层）/ 对话框（3 层）/ 阅读菜单（3 层）—— RGB 全部一致（0 字节不同）；只有每个像素的第 4 个字节（X，
显示桥不用）不同：GLES 写 0xff，我们保留应用缓冲里的值，旧版也是这样。

**帧率 15 Hz（`KFB_HZ=15`，新增可选值 15 / 20，默认仍 30）**：滑动时应用 + 合成的 CPU 减半（静读天下 755+350 → 380+170 ms，
EinkBro 1560+385 → 1035+230 ms），但第一次刷新晚 40–80 ms（静读天下 152 → 238，EinkBro 200 → 282），刷完时间不变。
省电有用，跟手更差，所以不改默认，只作为选项。

## 8. 调度优先级、写盘

- 每翻一页（微信读书，各 12 次中位）：Kindle 那边的进程用 115–160 ms CPU（dbus-daemon 30–50、syslog-ng、kswapd / kcompactd，
  不含显示桥）；排队等 CPU 的时间：微信读书 74–85 ms（所有线程合计）、SurfaceFlinger 27–56 ms、显示桥 4–12 ms、输入 < 1 ms。
  把 66 个 Kindle 用户进程 nice +10、显示桥和输入 -10：排队时间（81 / 58 / 5 ms）和第一次刷新（254 → 257 ms）都没变。
  排队主要是 Android 自己的线程（GC、合成、显示桥）在两个核上互相等，不是 Kindle 抢的。**不改**。
- 写盘（strace -T 跟 fsync / fdatasync / msync，所有线程）：微信读书 10 页 292 次 fdatasync，共 273 ms，最长 15 ms，**全部在后台线程**，
  主线程 0 次；10 页应用写 168 KB，脏页最多 108 KB、回写中最多 4 KB。多看（两个进程）8 页 0 次同步。写盘不是卡顿的原因，**不改**。

## 9. 给前台应用和页缓存多留内存

- Kindle 那边（Android 在前台、KINDLE_UI=auto → freeze）：java（Kindle 框架）85 MB 常驻 + 21 MB 已换出，KPPMainApp 已停（28 MB），
  其余都在 10 MB 以下。改成 KINDLE_UI=stop（连框架也停）只多出 10 MB MemAvailable（498 → 508 MB；它们大多已经被换到 zram），**不改**。
- zram：内核只有 lzo / lzo-rle（没有 lz4，没得换）；512 MB 里用了 234 MB，压到 125 MB（1.9 倍），没满，大小不是限制。swappiness 40 不动。
- 后台保留应用：第 6 节（默认 2）是这一块里量出来收益最大的。
- Android 自己的常驻：system_server 32 MB、SurfaceFlinger 26、桌面 24、zygote 10、输入法 8、media 6，其余守护进程合计约 10 MB（PSS）。
  已经是精简过的镜像（docs/slim-android.md），剩下能停的（media 6 MB）会影响应用选文件，收益太小，**不改**。
- 堆参数：heapminfree / heapmaxfree 512k / 8m → 4m / 16m，微信读书预热 40 页后再翻 20 页：第一次刷新 238 → 234 ms、应用 CPU 150 → 135 ms，
  两边都没有每页 GC（第 1 条里“长时间看书后每页一次 GC”这次没复现）；PSS 反而因为进程状态不同没法比。没有量出收益，**不改**。
- ART：应用都已是 `speed`（speed 冷启动最快，space / interpret-only 更慢）。speed-profile + 应用镜像要先有
  JIT 生成的配置文件、重编一次 161 MB 的微信读书要 10 分钟以上，这次**没测**。

## 10. 安装前备份有上限（bootstrap.sh，同 legacy 6aa5c04 / 63d717c）

`cloud/static/bootstrap.sh`（PW6 / k49 共用）：书以外的文件（20 MB 以下）全备；书 20 MB 以下从小到大放到 300 MB（`VD_BACKUP_MB`）；
缩略图不备；`tar -cvf | gzip -1`；进度画面“已备份 / 总共 MB · 还要约 N 分钟”（FBInk 画面，没有时 eips 只画英文那半句）；
书库清单（veradroid-docs-manifest）和开机核对不变；升级时把 `veradroid/kindle-crash/` 带到新程序目录。

pw6-dl 模拟器，1036 MB 书库（330 本 3 MB 的书 + 330 个 .sdr + 一个 40 MB 的 pdf + 5 MB 缩略图）：
旧 618 s、1037 MB、720 个文件 → 新 207 s、295 MB、481 个文件（全部 .sdr + 110 本书；pdf 和缩略图不在里面）；
解开新备份逐个和书库 cmp：481 个全部一致。测试数据已删掉，模拟器原来的备份放回原处。
