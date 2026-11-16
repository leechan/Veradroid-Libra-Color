# 真机跟手度测量工具（PW6 上用过，2026-11-12）

都在 Kindle 宿主上跑（`/dev/shm/vdb/`），从电脑用 ssh 驱动；不往 `/var` 写东西。

| 文件 | 作用 |
|---|---|
| `bench.sh <名字> <次数> <等待ms> "<注入命令>"…` | 注入触摸（`tap x y [按住ms]` / `swipe x1 y1 x2 y2 ms`），每次输出一行：手指按下 → 第一次刷新发出（first）→ 最后一次发出（last）→ 面板刷完（done，要先 `touch /dev/shm/veradroid/kfb/ctl/timing`）、刷新次数和面积、波形、Android 出了几帧、前台应用 / SurfaceFlinger / system_server / 显示桥各用了多少 CPU、缺页次数 |
| `agg.py < 原始输出` | 按场景取中位数 |
| `thr.sh <等待ms> "<注入命令>"` | 一次操作期间全机每个线程用的 CPU（找谁在忙） |
| `vm.sh` / `cyc.sh` | 换页计数（refault / pgpgin / swap）和微信读书“书架 ↔ 书”往返 |
| `epdrestart.sh [参数]` | 只重启显示桥（Android 不动），换参数 / 换二进制做对比 |
| `switch.sh <轮数> [等待秒]` | 应用轮换（桌面 → 微信读书 → 多看 → 静读天下）：每次切换到“最后一次 ≥30 % 屏幕的刷新”的时间、重新缺页、读盘、直接回收（docs/jank.md） |
| `vdwf.c` | 直接发 `MXCFB_SEND_UPDATE` 量各波形的时间。**只发普通更新；滚动标志会把驱动卡死，程序里已拒绝** |

显示桥在 `ctl/timing` 存在时多记两种行：`epd: frame page=N changed=K (T ms)`（每一帧到达、转换 + 比较用时）和
`epd: panel done after N ms … WxH+X+Y`（由等待线程异步记录，不再阻塞主循环，多块区域不会被量成串行）。
