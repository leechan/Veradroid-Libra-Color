# 屏幕旋转（竖 / 横 / 倒过来）

分支 `feat/rotation`。目标：竖屏、两个横屏、倒过来的竖屏，触摸和边缘手势跟着转；改动尽量小，默认（0 度）行为不变。

## 1. 现状：显示尺寸是谁定的

| 位置 | 做什么 | 尺寸从哪来 |
|---|---|---|
| `host/*/boot/lib/container.sh` `display_prepare` | 宿主开机前写 `$X/info`（容器里 `/dev/kfb/info`）：`宽 高 机型名` | `fbink -e` 的 `viewWidth/viewHeight`；没有 fbink 时读 `/sys/class/graphics/fb0/virtual_size` 和 `modes`（PW5 无 fbink：行宽 1248、可见 1236 x 1648） |
| `android/overlay/hardware/libhardware/modules/gralloc/framebuffer.cpp` `mapFrameBufferLocked` | 打开 `/dev/kfb/fb`，**`fscanf("/dev/kfb/info", "%d %d")`** 得到 w/h（读不到才用 1272x1696），据此填 `fb_var_screeninfo`（xres/yres、2 页、RGBX、300 dpi、物理毫米） | **宿主开机时给的**，不是编译时写死的 |
| SurfaceFlinger / WindowManager | 显示的“自然方向”和尺寸 = gralloc 报的 xres x yres；`ro.sf.lcd_density=300`（`veradroid_kindle.mk`） | 跟着 gralloc |
| `display/epd.c`（`veradroid-epd`） | `--w/--h`：共享缓冲每页 `W*H*4`、面板刷新区域、差分都按这个 | `display_start` 传 `viewWidth/viewHeight` |
| `input/vinput.c`（`veradroid-input`） | `--w/--h`：边缘条、四角、左右半屏都按它判断；虚拟触摸屏的坐标范围**照抄真触摸屏**的 absinfo | `input_start` 传 `viewWidth/viewHeight` |
| Android InputReader | 触摸屏原始范围线性映射到显示尺寸；内置触摸屏默认 `orientationAware`，显示转了它会跟着转坐标 | 虚拟触摸屏的 absinfo |

结论：**Android 的显示尺寸是开机时由宿主决定的**（`/dev/kfb/info`），系统镜像里没有写死。换尺寸只要“宿主写不同的 info + 重启 Android”，不用重编镜像。

早先的尝试：`settings put system user_rotation 1` 让 WindowManager 把显示转 90 度，SurfaceFlinger 往固定竖屏的缓冲里合成，输出错位。也就是说“Android 自己转”这条路在我们的软件 GL（libagl）+ fb HAL 组合上目前是坏的，而且原因没有查清。

## 2. 两个方案

### 方案 A：Android 自己转（`user_rotation` / `wm`，accelerometer_rotation=0）

- 缓冲保持面板的竖屏尺寸，WindowManager 把显示方向设成 90/180/270，SurfaceFlinger 合成时把画面转好再写进 fb。InputReader 会自动按显示方向转触摸坐标。
- 需要：
  1. 修好 SurfaceFlinger 在旋转时的错位（要在 `frameworks/native/services/surfaceflinger`（DisplayDevice 的 `setProjection` / 软件 GL 的 viewport/scissor 变换）或 libagl 里定位），**必须重编系统镜像**，问题还没定位，工作量未知；
  2. 或者（题目里的变体）让 gralloc/hwc 的 fb 尺寸跟着方向交换——这等于 Android 运行中改显示尺寸，fb HAL 不支持热改，仍要重启，而且还要改 gralloc；
  3. 宿主侧也要改：`veradroid-input` 的边缘手势（底边上滑返回、顶边下拉面板、四角、左右半屏亮度/色温）是在**面板坐标**里判断的，不知道 Android 转了，手势区不会跟着转；`veradroid-epd` 的翻页动画方向提示也是面板方向——宿主还得知道当前方向（从 Android 读 `user_rotation`）。
- 好处：每个应用可以自己要横 / 竖（`screenOrientation`），切换不用重启。
- 坏处：要重编镜像（禁止在本任务里做）；软件 GL 每帧都多做一次旋转合成（libagl 的旋转纹理路径慢，墨水屏机器 CPU 弱）；旧问题根因不明；宿主还是要改。

### 方案 B：Android 永远正着画，宿主负责转（**采用**）

- Android 按“逻辑尺寸”开机并正着画：0/180 度逻辑尺寸 = 面板尺寸；90/270 度逻辑尺寸 = 高 x 可见宽（横屏）。Android 认为自己就是一块横屏（自然方向 = 横），WindowManager 不转、SurfaceFlinger 不转，**不走那条坏掉的旋转合成路径**。
- `veradroid-epd` 把每页从逻辑画面转到面板（90/180/270），差分、脏矩形合并、局部刷新、整屏闪刷全部仍在**面板坐标**里做（转换发生在“RGBA → 灰度”那一步，后面的代码一行没动）；`D x y w h` 命令的矩形按旋转映射；翻页动画方向（DIR / ANIM / 固定方向模式 2..5）按逻辑方向给出，在调 MTK 之前转成面板方向。
- `veradroid-input` 一读到事件就把面板坐标转成逻辑坐标（每个轴单独映射：换轴 + 可能翻转，不需要状态），之后的手势判断（边缘条、四角、半屏、方向提示）和转发给 Android 的坐标全部是逻辑坐标——手势区自动跟着转；虚拟触摸屏的坐标范围设成逻辑像素范围。
- 需要：宿主两个程序 + 几行脚本。**不用重编镜像**：180 度纯宿主；90/270 度只是宿主写交换过的 `/dev/kfb/info` 再重启 Android。
- 坏处：
  - 横竖切换要重启 Android（实测冷启动约 15–45 秒；180 度可当场切）；
  - Android 不知道“设备转了”，应用自己请求方向（`screenOrientation=portrait`）时，在横屏模式下 WindowManager 会去转显示——又回到方案 A 那条坏掉的路径（见第 5 节风险）；
  - 开机画面、屏保这些宿主直接用 fbink 画的东西仍是竖的。

### 选择 B 的理由

1. 满足“不重编镜像”：180 度和横屏都只动宿主；
2. 绕开已知坏掉、根因不明的 SurfaceFlinger 旋转合成；
3. 手势区跟着转是自然结果（逻辑坐标），不需要宿主去读 Android 的方向；
4. 0 度时完全走老代码：epd 的转换函数、vinput 的事件路径在 0 度都是原样（见第 4 节验证）。

## 3. 实现（本分支）

### 约定

`KFB_ROTATE=0|90|180|270`：**画面在面板上顺时针转的角度**。逻辑坐标 (lx, ly) 落在面板上的位置（VW = 可见宽，W = 行宽，H = 高）：

| KFB_ROTATE | 逻辑尺寸 | 面板位置 | 用户怎么拿 |
|---|---|---|---|
| 0 | W x H | (lx, ly) | 正常竖拿 |
| 90 | H x VW | (VW-1-ly, lx) | 画面的上边在面板右边：机器逆时针转 90 度拿（原来的右边朝上） |
| 180 | W x H | (VW-1-lx, H-1-ly) | 倒过来拿 |
| 270 | H x VW | (ly, H-1-lx) | 画面的上边在面板左边：机器顺时针转 90 度拿 |

触摸的逆映射（面板 → 逻辑）：90：lx = py，ly = VW-1-px；180：lx = VW-1-px，ly = H-1-py；270：lx = H-1-py，ly = px。两个程序都用**像素尺寸**（`--w/--h/--vw`）而不是触摸屏的原始范围来翻转，保证画面和触摸用的是同一个映射。

VW（可见宽）：PW5 没有 fbink 时 `viewWidth` 取的是 fb 的行宽 1248，可见只有 1236。0 度时右边 12 列本来就在屏幕外；转 180 时如果用 1248 翻转，逻辑画面的左边 12 列就被翻到屏幕外（实测最初版本“VeraDroid”标题贴边被切）。所以旋转一律在可见宽里做：`display_prepare` 记下 `viewVisWidth`（`modes` 里的宽），旋转时通过 `--vw` 传给两个程序；横屏的逻辑高 = VW。

### 文件

- `display/epd.c`
  - 新参数 `--rotate 0|90|180|270`、`--vw N`；新命令 `ROT <deg>`（只允许逻辑尺寸不变的切换：0↔180、90↔270，切完整屏闪刷）。
  - `rgba_to_y8_rot()`：逻辑页 → 面板灰度图（180 逐行倒序；90/270 按 16 行一带走源图，写目标时保持在缓存里）。`show_page()` 在旋转时调它，其余（差分分块、`push_region`、闪刷计数、动画触发）不变。
  - `rot_rect()`：逻辑矩形 → 面板矩形，`D x y w h` 路径用。
  - `rot_dir()`：MTK 滑动方向（0 下 1 上 2 左 3 右）逻辑 → 面板。90：左→上、右→下、上→右、下→左；180：上下、左右互换；270：左→下、右→上、上→左、下→右。
  - 共享缓冲的页偏移用逻辑尺寸（横屏且 VW≠W 时每页 `H*VW*4`）。
  - `test` / `file` / `paint` 忽略旋转（画面本来就是面板坐标）。
- `input/vinput.c`
  - 新参数 `--rotate`、`--vw`；`rot_frame()` 在 `handle_frame()` 之前改写每个 `ABS_MT_POSITION_X/Y`、`ABS_X/Y` 事件（真触摸和 `--inject` 都一样：inject 的坐标仍是“手指在面板上的位置”）。
  - 带 `--rotate` 时：W/H 换成逻辑尺寸；虚拟触摸屏的 X/Y 范围 = 逻辑像素；额外复制单点触摸的 `ABS_X/ABS_Y/ABS_PRESSURE`（PW5 goodix）。
  - `--gconf` 文件里的 `ROTATE=n`：当场切换（同样只允许 0↔180、90↔270），在两次触摸之间生效。
- `host/{pw6,k49}/boot/lib/`
  - `settings.sh`：默认 `KFB_ROTATE=0`；加进 `settings_publish` 和 `settings_apply` 的白名单；`gestures_write` 多写一行 `ROTATE=`；`settings_apply` 最后调 `rotate_apply`。
  - `container.sh`：`rot_deg`、`rot_args`（0 度时为空——命令行和以前一字不差）；90/270 时 `$X/info` 写 `高 可见宽`；`display_start` 把 `rot_args` 加到 epd 命令行，记下 `$W/rotate` 和能否当场切换（`$W/rotate.live`）。
  - `input.sh`：goodix（PW5）在旋转时也走 `veradroid-input`（0 度仍然直通，和以前一样）；`rot_args` 加到命令行。
  - `cmd.sh`：新命令 `rotate <deg>`（写进 settings.conf，然后 `rotate_apply`）。`rotate_apply`：同一逻辑尺寸、触摸前端在跑、启动时的参数允许 → 发 `ROT` 给显示桥 + 写 `ROTATE=` 给触摸前端，当场切换；否则 `do_restart` 让 Android 按新尺寸重启。
  - 用法：宿主 `echo "rotate 180" > /dev/shm/veradroid/kfb/ctl/cmd`；Android 里（桌面/面板）写 `/dev/kfb/ctl/cmd` 同一行，或者写 `/dev/kfb/ctl/settings.new` 里 `KFB_ROTATE=90` 再发 `apply`。桌面的设置界面还没加按钮（要改 VeraHome，属于系统镜像 / 应用）。

### 0 度不变的保证

- 脚本：`rot_args` 在 0 度输出空串，epd / input 的命令行和以前完全相同；PW5 goodix 仍然直通。新增的只有：`/dev/kfb/settings` 多一行 `KFB_ROTATE=0`、`$W/gestures` 多一行 `ROTATE=0`（老 vinput 忽略不认识的键）、`$W/rotate` 两个状态文件。
- `veradroid-epd`：`g_rot == 0` 时 `show_page` 仍调原来的 `rgba_to_y8_opaque`，`push` 走原路径，`rot_dir` 原样返回。
- `veradroid-input`：`ROT == 0` 时 `rot_frame` 只做一次 `gconf_load()`（只在 IDLE 时 stat 一下文件；IDLE 的第一帧本来就会调它），不改事件；不带 `--rotate` 时虚拟触摸屏的范围仍照抄真触摸屏。

## 4. 验证（eink-emulator `pw5-5182`）

环境：PW5 模拟器（固件 5.18.2，面板 1236x1648，无 fbink → `viewWidth=1248`（行宽）、可见 1236；goodix 触摸屏，0 度直通），
装的是 VeraDroid 0.83（比仓库的 k49 树旧一点）。测试时把本分支对 `container.sh / input.sh / settings.sh / cmd.sh` 的改动
打到 0.83 的同名文件上（`cmd.sh` 里 0.83 没有 `epd_send`，测试副本改成直接写 FIFO，仓库版本不变），换上新编的两个程序；
测完全部还原（md5 与原文件一致），`settings.conf` 删掉，VeraDroid 停着（和测试前一样）。

| 项目 | 方法 | 结果 |
|---|---|---|
| 重编的 epd（未改代码）与发布的一致 | FBInk 用 `MINIMAL=1 IMAGE=1 DRAW=1 KINDLE=1 staticlib`（带 `patches/fbink-state-dump-args.patch`）重编；比较 | 段大小完全相同（text 619648 / data 4008 / bss 5468），字符串表相同；只有 `fbink_state_dump` 里的寄存器分配不同（191 字节，epd 不调用它）。vinput 重编后 strip 的 md5 与发布版**完全相同** |
| 新 epd 在 0 度和旧的画面一致 | 运行中换成新 epd，同参数，REDRAW，截图与旧 epd 截图逐像素比较 | `base-shipped.png` vs `rot0-new.png`：**0 个像素不同** |
| 新脚本 0 度冷启动 | 改过的脚本 + 新程序冷启动，看命令行和截图 | epd 命令行与旧的一字不差；goodix 仍直通；截图只有状态栏时间/内存那一行不同（`rot0-scripts.png`） |
| 180 显示 | `rotate 180`（PW5 走重启路径），截图与 0 度截图转 180 比较 | 全部 1236x1648 像素对得上，只差状态栏时钟（`rot180-boot.png`）。最初版本用 1248 翻转，左边 12 列被切（`rot180-live.png`），因此加了 `--vw` |
| 180 触摸 | inject `tap 131 1572`（面板坐标 = 逻辑上的齿轮）；QMP 硬件级 `tap 131 1572`（经过真的 goodix 驱动 → veradroid-input） | 两种都打开了设置页（`rot180-settings.png`、`rot180-hwtap.png`）；Android `dumpsys input`：viewport 1248x1648、orientation 0、XScale 1.000 |
| 180 边缘手势 | inject 从面板顶部往下划（逻辑底边往上）；从面板底部往上划（逻辑顶边往下） | `edge swipe up -> back` 回到主页（`rot180-edgeback.png`）；`action panel` 打开面板 PanelActivity（`rot180-panel.png`，从逻辑顶部也就是面板底部出来） |
| 翻页动画方向 | epd 日志 | 逻辑上点右半屏 → DIR 2（左），180 度发给 MTK 的是 `dir=3`（右）——映射生效 |
| 当场切换 180 → 0 | `rotate 0`（触摸前端在跑） | `rotate 180 -> 0 (live)`；vinput 日志 `rotate 180 -> 0`；epd `rotate 180 -> 0`，画面正过来（`live0b.png`） |
| 横屏 90 | `rotate 90`（重启），`/dev/kfb/info` = `1648 1236`；`wm size` = 1648x1236；配置 `land`、`sw659dp`；面板截图与 Android 共享缓冲转 90 比较 | 几何对得上（`>40` 的像素 0.000%；平均差 14.8 是对比度曲线造成的整体灰度差）；主页按横屏排版（`rot90-boot.png`） |
| 90 触摸 + 手势 | inject 点齿轮 (1161,1500)；从面板左边往右划（逻辑底边往上）；从面板右边往左划（逻辑顶边往下） | 打开设置（`rot90-settings2.png`）；back 回主页；面板从逻辑顶部（面板右侧）出来（`rot90-panel2.png`） |
| 当场切换 90 → 270 | `rotate 270` | `rotate 90 -> 270 (live)`；与共享缓冲比较 `>40` 像素 0.006%（`rot270-live.png`）；点齿轮 (72,141) 打开设置、从面板右边往左划 = back（`rot270-settings.png`、`rot270-back.png`） |
| `D` 矩形映射（90 度） | 往共享缓冲第 0 页逻辑 (100,100) 画 200x100 黑块，发 `D 100 100 200 100 G` | 面板上 (1036..1135, 100..299) 全黑、四周白，刷新区 `104x200+1032+100`（宽对齐到 8）——与 `rot_rect` 一致（`rot90-D.png`） |
| 回到 0 | `rotate 0`（重启） | goodix 恢复直通，epd 命令行恢复原样 |

模拟器限制（与旋转无关）：带硬件滑动动画（`anim=1`）的整屏刷新，模拟器的 hwtcon 不显示新画面，要再发一次 `FULL` 才看得到。
用**发布版** epd 在 0 度点齿轮也一样（`rot0-shipped-anim.png`：设置页已经画进缓冲，面板还是主页）。所以上面的截图大多在 `FULL` 之后拍。

没有验证的：
- 真机（PW6 / PW5）上的任何东西：MTK 硬件动画方向、刷新速度（横屏每页一次转置）、PW6 fts_ts 的原始范围是否等于像素（影响“0 度开机后当场转 180”）；
- 两指手势（inject 只能一个手指；代码上它们在逻辑坐标里判断，左右半屏 = 逻辑左右）；四角长按（2026-11-14 起左下角默认回到 Kindle，其余默认关）；
- 真 PW5 的单点 goodix（只有 ABS_X/ABS_Y）——模拟器的 goodix 也报 MT 坐标，单点轴的改写和转发只从代码推断；
- 微信读书等第三方应用在横屏下的表现（模拟器里没装），尤其是锁竖屏的应用（见第 5 节）。

### 合并 origin/main 之后的复测（2026-11-12，`kt6-5192`，KT6 1072x1448，k49 包 0.95）

合并后（小改动暂缓 `--hold` / `HOLD`、非 MTK 面板不做滑动动画 `g_is_mtk`、`KFB_HOLD`、`GLOB_*`、蓝牙桥、appdisp 修正都保留）重编两个程序，
放进 `host/pw6/bin`、`host/k49/bin`。模拟器上装的就是 main 的 k49 宿主树，直接换上本分支的 `container/input/settings/cmd.sh` 和两个程序；
测完还原（md5 一致）、删掉测试用的 `settings.conf`、模拟器已停。

| 项目 | 结果 |
|---|---|
| 0 度画面与 main 的 epd 一致 | 同一画面先后用 main 的 `veradroid-epd`（md5 0c0bd5…）和合并后的画，整屏截图 **0 个像素不同**（`k-base-main.png` / `k-rot0-merged.png`） |
| 0 度冷启动的命令行 | 与 main 完全相同（含 `--hold 70`，没有 `--rotate`）；goodix 直通；`/dev/kfb/settings` 多一行 `KFB_ROTATE=0` |
| `HOLD` 命令 / `--hold` | 合并后的程序照常接受（日志无报错，小改动暂缓的代码路径未改）；非 MTK 分支只从代码确认（`maybe_animate` 和整页动画判断里的 `g_is_mtk` 原样保留，`rot_dir` 在它之后才用到） |
| 180 | `rotate 180`（重启）→ 面板与共享缓冲转 180 比较 `>40` 像素 0.000%；点齿轮打开设置；面板顶部下划 = 返回；底部上划 = 面板；`rotate 0` 当场切回 |
| 90 | `rotate 90`（重启），`/dev/kfb/info` = `1448 1072`；比较 0.000%；点齿轮、返回（面板左边往右划）、面板（右边往左划）都对 |
| 270 | `rotate 270` 当场切；比较 0.000%；点齿轮、返回都对 |

**新发现（微信读书，锁竖屏的应用）**：横屏（Android 自然方向 = 横）下打开微信读书，它请求竖屏，WindowManager 把显示转到 `ROTATION_270`
（`dumpsys input`：`SurfaceOrientation: 3`），SurfaceFlinger 把竖屏画面转进横的缓冲——**这次画面是完整、正确的，没有错位**。叠加宿主的旋转后：
- `KFB_ROTATE=90`：微信读书在面板上是**正的竖屏**（和 0 度拿法一样，`k90-weread-tap.png`），点“已阅读并同意”的勾选框有效（`k90-weread-check.png`）——Android 自己把触摸也转了回去；
- `KFB_ROTATE=270`：微信读书是**倒着的竖屏**（`k270-weread2.png`）。

也就是说：横屏只对支持横屏的应用（桌面、设置、大多数阅读器）是横的；锁竖屏的应用会自己转回竖屏，这时 90 是“对的”那个横屏方向，270 会让它们倒过来。
所以**推荐的横屏是 90**；270 留给需要另一只手的用户，但要知道锁竖屏的应用会倒。要让这些应用也强制横屏，仍需第 7 节第 1 条的镜像改动。
另外这也说明 SurfaceFlinger 的旋转合成在现在的镜像上（至少横屏自然方向 → 竖屏）是能用的，早先记录的“错位”可能只在当时的镜像 / 竖屏自然方向上出现，方案 A 值得以后重新评估。

## 5. 风险 / 没做的

- **横屏里请求竖屏的应用**：Android 的自然方向变成横屏后，`screenOrientation=portrait/sensorPortrait` 的应用会让 WindowManager 把显示转过去。在 kt6-5192 上用微信读书实测（见上）：画面没有错位，`KFB_ROTATE=90` 时它是正的竖屏，`270` 时是倒的竖屏。VeraHome 用的是 `nosensor`（跟自然方向），不受影响。要让这类应用也横过来，需要系统镜像里把 WindowManager 锁在自然方向，见第 7 节。
- 横屏是“Android 认为自己天生是横屏”，不是转出来的；切横竖要重启 Android（容器冷启动，模拟器上 10–40 秒）。
- PW5 goodix 在真机上是单点触摸（只有 ABS_X/ABS_Y）。模拟器里的 goodix 同时报 MT 坐标。旋转时 vinput 两种轴都转并都转发；但手势识别只看 MT 槽位，真机 PW5 旋转后**没有边缘手势**（0 度时本来也没有，因为直通）。
- 不带 `--rotate` 启动的 vinput（0 度开机）当场切到 180 时，虚拟触摸屏的范围仍是真触摸屏的原始范围；翻转用的是像素宽高。PW6 的 fts_ts 范围若不等于 0..1271 / 0..1695，会有比例误差——真机上要 `cat /proc/bus/input/devices` + absinfo 确认；不确定时宁可走重启（把 `$W/rotate.live` 的条件收紧）。
- 宿主直接画的画面（开机画面 `splash.sh`、“正在恢复”、屏保）不转。
- 翻页动画方向的映射只按 MTK 的方向定义推算，模拟器的 hwtcon 不做硬件动画，**没有在真机上看过**。
- 横屏时 epd 每页做一次 90 度转置（1648x1236），比 0 度的顺序转换慢；模拟器上没有可靠的计时，真机需要看 `epd.log` 里的毫秒数。

## 6. 构建

```
# FBInk 静态库（与发布的 veradroid-epd 相同的配置；源码要带 patches/fbink-state-dump-args.patch）
make CROSS_TC=arm-linux-gnueabihf KINDLE=1 MINIMAL=1 IMAGE=1 DRAW=1 staticlib      # -> Release/libfbink.a（约 210 KB）
arm-linux-gnueabihf-gcc -O2 -static -I FBInk display/epd.c FBInk/Release/libfbink.a -lm -o veradroid-epd
arm-linux-gnueabihf-gcc -O2 -static input/vinput.c -o veradroid-input
```

默认编出的 `FBInk/Release/libfbink.a` 是**完整**版（带 OpenType，编出来 1.5 MB），和发布的
epd 不一样；用的是按上面命令重编的最小版。合并 origin/main 之后，`host/pw6/bin` 和
`host/k49/bin` 里的 `veradroid-epd`、`veradroid-input` 就是用合并后的源码按这个方法编的（`arm-linux-gnueabihf-strip` 过）。

## 7. 如果要更完整的横屏，需要改系统镜像的地方（本次没做）

方案 B 本身不需要改镜像。下面是让横屏“更好用”还需要的镜像侧改动：

1. **锁住显示方向**（想让锁竖屏的应用也横过来时才需要）：横屏开机后，请求竖屏的应用会让 WindowManager 转显示（实测微信读书：90 时是正的竖屏，270 时是倒的）。
   改 `frameworks/base/services/core/java/com/android/server/policy/PhoneWindowManager.java` 的 `rotationForOrientationLw()`：
   有属性（例如 `persist.veradroid.lockrot=1`，宿主在横屏时写进 `$SYS/data/property`）时一律返回 `Surface.ROTATION_0`（自然方向），
   应用拿到的就是横屏配置而不是被转过去的显示。也可以先试资源覆盖 `config_forceDefaultOrientation`
   （`device/veradroid/kindle/overlay/frameworks/base/core/res/res/values/config.xml`），但 7.1 里它只在部分条件下生效，要在源码里确认。
2. **设置界面的入口**（VeraHome，本分支没有动它的源码）。设置 → 显示里加“屏幕方向”一项，四个值 0 / 90 / 180 / 270：
   - **读当前值**：`/dev/kfb/settings` 里的 `KFB_ROTATE=<0|90|180|270>` 一行（宿主 `settings_publish` 写；老宿主没有这一行 → 当 0，并且不显示这一项）。
   - **改**：往 FIFO `/dev/kfb/ctl/cmd` 写一行 `rotate <deg>\n`（和 `clear`、`invert`、`light N` 同一个通道，HostService 现有的写法）。
     宿主把 `KFB_ROTATE=<deg>` 存进 `settings.conf`，然后：0↔180、90↔270 当场切（约 1 秒，整屏闪刷一次）；
     横竖互换时宿主直接 `do_restart`——Android 会被停掉再按新尺寸开机（10–40 秒），桌面进程会被杀。
     所以横竖互换前桌面要先弹确认（“切换横竖屏需要重启 Android，未保存的内容会丢失”），确认后再写命令。
   - 另一种等价写法：把 `KFB_ROTATE=<deg>` 写进 `/dev/kfb/ctl/settings.new` 再发 `apply`（和其他显示设置一样走 `settings_apply`，白名单里已经有这个键）。
   - `KFB_ROTATE` 是全局设置，不进每个应用的显示参数（`appdisp` 的白名单没有它）。
   - 判断“会不会重启”：新旧角度 `% 180` 不同就会；相同时一般当场切，但触摸屏直通（PW5 / KT6 的 goodix 在 0 度不经过 veradroid-input）时 0→180 也会重启——
     桌面不必自己判断，统一提示“可能需要重启”即可，或者看 `/dev/kfb/settings` 更新后的 `KFB_ROTATE` 确认生效。
3. （可选，方案 A 的前提）修 SurfaceFlinger 旋转错位：`frameworks/native/services/surfaceflinger/DisplayDevice.cpp`
   `setProjection()` / `SurfaceFlinger::doComposeSurfaces()` 在 libagl（`frameworks/native/opengl/libagl`）下的 viewport / scissor
   变换。修好以后“应用自己要横屏”才能不重启就转。
4. 宿主侧（不是镜像）：开机画面 `splash.sh`、“正在恢复”提示、`sleep.sh` 的屏保画面目前不转；fbink 有旋转相关选项，可以按 `KFB_ROTATE` 画。

不需要改的：`gralloc/framebuffer.cpp` 已经从 `/dev/kfb/info` 读尺寸（物理毫米也按它算），`ro.sf.lcd_density=300` 横竖都合适，
不需要 IDC 文件（虚拟触摸屏的范围就是逻辑像素，Android 1:1 映射）。
