# 宿主设置键和命令（给桌面 / 传书网页做界面用）

更新：2026-11-12（分支 `feat/host-gaps`）。这一页只写宿主（Kindle 上的 shell 脚本）这边**已经实现**的接口，
界面（VeraHome 设置页、面板、传书网页）还没加，由做桌面 / 网页的人照这里接。

## 0. 通道（已有，复习）

| 方向 | 路径（Android 里看到的） | 说明 |
|---|---|---|
| 桌面 → 宿主：改设置 | `/dev/kfb/ctl/settings.new` 写 `KEY=value` 行，再往 `/dev/kfb/ctl/cmd` 发 `apply` | 只接受 `settings.sh` 白名单里的键；值只能是 `[0-9A-Za-z._,]`。合并进 `settings.conf`，立即生效的当场生效 |
| 宿主 → 桌面：当前设置 | `/dev/kfb/settings`（`KEY=value`，每次 apply 后重写） | 白名单里的键都会出现，没设过的是默认值 |
| 桌面 → 宿主：命令 | `/dev/kfb/ctl/cmd`（FIFO，一行一条） | 见 `lib/cmd.sh` |
| 宿主 → 桌面：状态 | `/dev/kfb/ctl/status`（发 `status` 命令后重写） | 电量、前光、Wi-Fi 等 |

## 1. 新增的设置键

| 键 | 取值（默认） | 作用 | 界面建议 |
|---|---|---|---|
| `WIFI_PS` | `auto` \| `on` \| `off`（`auto`） | Wi-Fi 省电。`on` 一直保持 Kindle 的省电模式；`off` Android 运行时关掉省电（下载快、耗电多）；`auto` 平时省电，**传书开着**或 **Wi-Fi 上 ≥ 32 KB/s 持续收数据**（看门狗每 20 秒看一次网卡字节数）时临时关，空闲 1 分钟后恢复。回到 Kindle、屏保、停止时一律交还 Kindle | 设置 → Wi-Fi 与蓝牙：“Wi-Fi 省电：自动 / 始终省电 / 运行时关闭” |
| `USB_ASK` | `1` \| `0`（`1`） | Android 在前台时插上 USB 线（`com.lab126.hal usbPlugIn`）：`1` 在 Android 里问“已连接电脑：要切换到 USB 传输吗？”，点“切换”= 返回 Kindle（有 MTP 的固件冻结 / 按 `RETURN_MODE`，USB 大容量存储的老固件完全退出），Kindle 接着进 USB 传输；`0` 不问。见 `boot/lib/usb.sh` | 设置 → 设备：“插上 USB 线时询问”；提示框里的“不再询问” |
| `APP_COMPILE` | `auto` \| `speed` \| `off`（`auto`） | 应用预编译（第 3 节）。`off` = 不在后台编译，安装时恢复以前的做法（957 MB 机型安装时直接 speed） | 设置 → 应用：“自动优化新装的应用” 开关（off / auto） |
| `TIME_12_24` | `auto` \| `12` \| `24`（`auto`） | Android 的 12 / 24 小时制（`settings put system time_12_24`）。`auto` = 跟 Kindle（第 5 节） | VeraHome 现有的 12 小时制开关改成三选一：“跟随 Kindle / 12 小时 / 24 小时”；桌面时钟读 Android 系统设置即可 |
| `G_TWO_TAP_ACT` | 动作名（`clear`） | 双指轻点做什么（以前固定整屏刷新） | 设置 → 手势：和四角长按同一个动作选择列表 |
| `G_TWO_LONG_ACT` | 动作名（`invert`） | 双指长按 2 秒做什么（以前固定反色） | 同上 |
| `GESTURE_HINT` | `all` \| `stuck` \| `off`（`all`） | 手势提示（`docs/gesture-hint.md`）：宿主画的小方块。`all` 每个手势都提示 0.8 秒；`stuck` 只在交给桌面的手势 2 秒没被接走（Android 卡住）时提示“没有响应”；`off` 都不提示。`action.sh` 每次手势都重读 `settings.conf`，apply 后下一个手势就生效 | 设置 → 手势：“手势提示：全部 / 只在没响应时 / 关”（写 `GESTURE_HINT=all|stuck|off`；`default` = 回到默认） |

| `G_TAP` | `0` \| `1`（`1`） | 机身双击翻页：Kindle 的 gesturetapd 有 `gesture_tap` 设备时，Android 在前台时双击机身 = 一次翻页键。没有这个设备的机器（devcap “Base config”）没有效果 | 设置 → 手势：“双击机身翻页”开关；宿主状态里有没有这个设备可以从 `input.log` 看，暂时没进 status |
| `G_TAP_KEY` | `voldown` \| `volup` \| `pagedown` \| `pageup`（`voldown`） | 双击机身发哪个键（音量- 是多数阅读应用的“下一页”） | 同上，二级选项 |
| `KFB_MODE` | 新增取值 `3` | 刷新方式“驱动自动”：交给 hwtcon 按直方图选 DU / GC16 / GL16，大区域自动 GLR16（和 Kindle 自己界面一样），不做抖动 | 刷新方式里加一档“自动（同 Kindle）”；建议先真机比较 |
| `KFB_LIGHTF` | `0`..`3`（`0`） | 浅色过滤（关 / 弱 / 中 / 强）：原始亮度 ≥ 235 / 220 / 200 的像素直接变 255（折进显示桥的灰度表，零额外开销；在对比度曲线之后、硬件抖动之前）。浅灰 / 米色 / 浅绿底和半透明灰色蒙层变纯白，差异和“大面积变化”少了，整屏闪刷少、字更清楚。也可以按应用设（`appdisp`） | 显示与刷新 → 画面；每个应用的显示效果；面板快捷开关 `lightf`（关 ↔ 上次的档位） |
| `KFB_DARKEN` | `0` \| `1`（`0`） | 深色加深：没被滤成白的部分在对比度曲线上再乘 1.8 次方（#999 的字 → 约 #4D）。可按应用设 | 同上 |
| `KFB_PWRDOWN` | 毫秒数 0..5000 \| `off`（不设 = 不碰） | 面板掉电延时（`MXCFB_SET_PWRDOWN_DELAY`）。驱动默认 0：每次刷完就断电，下次再上电。设 100–300 可以省掉连续刷新之间的上电时间（耗电略增）；VeraDroid 退出时还原驱动原值 | 先不放界面，真机测完（第 8 节）再决定默认值 |

`G_TL` / `G_TR` / `G_BL` / `G_BR`（四角长按）键不变，只是能选的动作多了（第 2 节）。
**2026-11-14 起 `G_BL` 默认 `kindle`**（左下角长按 2 秒回到 Kindle：Android 卡住时总有一个不经过 Android 的出口）；其余三个角默认 `none`。用户自己设过的值不变（写进 `settings.conf` 的优先），`G_BL=default` 回到 `kindle`。只有动作不是 `none` 的角才算手势：宿主把它们写进 `gestures` 文件的 `G_CORNERS`（如 `bl`），`veradroid-input` 下一次触摸就读到，其余角落的长按照样给 Android（以前任一角配了动作，四个角的 2 秒长按都会被吞掉）。

### 底边分三段（分支 `feat/edge-thirds`）

| 键 | 取值（默认） | 作用 |
|---|---|---|
| `G_EDGE_THIRDS` | `0` \| `1`（`0`） | `1`：从底边条（120 px，随 `G_EDGE_SENS`）往上划时，按起手位置在逻辑宽度的左 / 中 / 右三分之一分别做 `G_EB_L` / `G_EB_M` / `G_EB_R`；上划后手指停住（30 px 内，按 1272 px 宽折算）`G_EB_HOLD_MS` 毫秒做 `G_EB_HOLD`。`0`：整条底边都是返回（原来的做法） |
| `G_EB_L` / `G_EB_M` / `G_EB_R` | 第 2 节的动作名（`appopt` / `home` / `back`） | `back` 由 veradroid-input 直接发返回键（和原来的底边返回一样快），其余交给 `action.sh eb <动作>`。`none` 且 `G_EB_HOLD=none` 时这一段不算手势，触摸照常给 Android |
| `G_EB_HOLD` | 动作名（`switch`） | 上划后停住：默认切换应用（VeraHome 的切换器 = 最近任务）。`none` = 不等停住，划够距离马上做（和原来的底边返回同样的时机）；有停住动作时三段的动作在松手时才做 |
| `G_EB_HOLD_MS` | 200..3000（`500`） | 停住多久算 |

只在手势总开关开着（没有 `nogestures`）、`G_EDGE_BACK=1`、前台应用不在 `G_BACK_EXCLUDE` 里时生效；手势总开关关掉时底边仍是普通返回（不分段）。
和别的手势不冲突：四角长按要手指不动 2 秒，分段手势要先往上划够 `EDGE_SWIPE`；底边条里的轻点 / 长按照常 60 ms 后交给 Android；
上划被认出来时已经交给 Android 的触摸会先收回（取消）。滑动提示（`SCROLL 1`）在认出手势时就收回（`SCROLL 0`）。
左段为什么是“应用优化”而不是下拉面板：在应用里左段针对当前应用（刷新模式等）；
我们的“应用优化”页正是“只对这个应用”的刷新 / 全刷 / 对比度 / 字号；在桌面上没有“当前应用”，就开下拉面板（全局对比度、刷新等）。

PW5 / KT5 / KT6（k49，`goodix-ts`）以前触摸直通、没有任何全局手势；现在和 PW6 一样经过 veradroid-input，上面的手势全部可用
。只写进 `settings.conf`、不进界面的应急键：`KFB_TOUCH_RAW=1` = goodix 回到原样直通
（没有全局手势，竖屏时有效），下次启动 Android 生效。四角长按（角落 160 px 内按住不动 2 秒）现在从上下边缘条（120 px）里起手
也有效（以前边缘条里的触摸只当边缘手势，四角长按永远不触发）；从角落起手的上滑 / 下滑仍是返回 / 面板，角落里的轻点照常给 Android。

## 2. 手势动作（`boot/action.sh` 的 `run_action`，白名单）

| 动作名 | 做什么 | 备注 |
|---|---|---|
| `none` | 什么都不做 | 原有 |
| `back` `home` `panel` `switch` | 返回 / 桌面 / 下拉面板 / 切换应用 | 原有（桌面的 HostService 监听 `ctl/act.*`） |
| `kindle`（别名 `return`） | 回到 Kindle（按 `RETURN_MODE` 冻结或关闭） | 原有 |
| `clear`（别名 `refresh`） | 整屏刷新（清残影） | 原有 |
| `invert` | 反色 | 原有 |
| `stop` | 关闭 Android | 原有 |
| `frontlight` | 前光开关（关之前记住亮度，再开时恢复；记不到就开到一半） | 新 |
| `lighton` / `lightoff` | 前光开 / 关 | 新 |
| `sleep` | 立即休眠（进屏保，Android 随之冻结） | 新。`lipc-set-prop -i com.lab126.powerd powerButton 1`（失败时 `powerd_test -p`）。`preventScreenSaver=1`（调试时）powerd 不响应 |
| `restart` | 重启 Android | 新 |
| `screenshot` | 截图，存到 Android 的 `Screenshots/` | 新（宿主 `screenshot` 命令） |
| `wifi` | Wi-Fi 开关 | 新 |
| `app.<包名>` | 打开指定应用，例如 `app.com.tencent.weread.eink` | 新。走 `ctl/app`（和“启动时打开某应用”同一个通道）；包名只许 `A-Za-z0-9._` |
| `appopt` | 前台应用的显示设置：桌面的“应用优化”页（`AppDisplayActivity`，只对这个应用生效）；前台是桌面 / 我们自己的页面时打开下拉面板（全局显示设置） | 新（`feat/edge-thirds`）。要 VeraHome 认识 `ctl/act.appopt`（`feat/edge-thirds-home`），老桌面收到不认识的动作什么都不做，2 秒后提示“没有响应”。牌子字库里没有“显示优化”，所以这个动作只在没有响应时提示 |

界面上给一个固定列表即可；`app.` 那一项让用户从已装应用里挑。

## 3. 应用预编译（F6，`boot/lib/compile.sh`）

**触发**：宿主 `install` 命令装好后；`after_boot` 装 `veradroid/apps/*.apk` 后、Android 里自己装 / 更新的应用
（看门狗每 20 秒比较 `packages.list` 的时间和大小，变了就扫一遍）；开机完成 1 分钟后扫一遍（之前没编好的也会排上）；命令 `compile`。
**做法**：一次一个，`cmd package compile -m speed -f <包>`；dex2oat 是 Android 的 installd 起的，宿主每 2 秒把它的所有线程调成
`nice 19` + `ionice -c3`。安装本身改成只做 `interpret-only`（装得快），编译交给后台。
**跳过 / 暂停**：已经是 `speed` / `everything` 的（宿主直接读 odex 的 OAT 头）；电量 < 20 % 且没充电（暂停，5 分钟后再看）；
可用内存不够（957 MB 机型 < 180 MB、512 MB 机型 < 120 MB：等，10 分钟还不够就这一批先放弃）；Android 冻着（等解冻）；
同一个安装失败过两次。编译中可用内存掉到 40 MB 以下就杀掉 dex2oat（应用照常用解释执行）。512 MB 机型 dex2oat 限单线程。
dex2oat 自带 9.5 分钟看门狗（nice 19 下大应用会被它杀掉，模拟器上多看阅读实测 645 秒失败）：编译期间通过
`dalvik.vm.dex2oat-flags` 加 `--no-watch-dog`，改由宿主自己 40 分钟超时。编译失败时 installd 会删掉原来的 odex，
宿主马上补编一个 `interpret-only`，回到安装时的状态。

**调度（2026-11-14，0.89 用户诊断后）**：PW6 5.20.2 真机系统更新后微信读书的 odex 失效，宿主在用户正读书时给微信读书本身重编了
357 秒（dex2oat 173 MB + 微信读书 221 MB → system_server lowmem、微信读书 :seg 服务 ANR、WindowManager 锁等 8.9 秒）。现在：
- 前台应用（`$X/fg`，VeraHome 的 HostService 写）不编：队列里跳过它先编别的；它离开前台才编。编着的时候它到了前台：
  立刻停掉这个包的 dex2oat，重新排队（不算失败，不补 interpret-only）。状态 `reason=等你不用这个应用时再优化 code=foreground msg=…`（reason 写中文，老桌面原样显示也看得懂）。
- “在用”= `COMPILE_IDLE_S`（默认 300）秒内摸过屏（`action.sh poke` 每 20 秒最多 touch 一次 `$W/lastinput`；手势全关时没有 poke，按空闲算）。
  在用时开始编要可用内存 ≥ `COMPILE_ACTIVE_MB`（400；512 MB 机型 `COMPILE_ACTIVE_MB_LOW` 200），不够就一直等（`reason=busy`，不算放弃计时）；
  编着时掉到 `COMPILE_ACTIVE_ABORT_MB`（200 / 100）以下就停掉重排，之后要等空闲才再开始。
- dex2oat 线程：充电 + 空闲才用系统默认（PW6 两线程，峰值 378 MB）；其余一律 1 线程（峰值约 67 MB）。`COMPILE_THREADS` 可强制。
- 空闲时内存 10 分钟都不够：工作进程先停但队列保留，30 分钟后看门狗再起（以前是整个队列丢掉，到下次开机 / 装应用才再排）。
- 屏保时 Android 冻着编不了：不为编译解冻、也不推迟屏保，醒来接着编。
- 过滤器仍是 speed。speed-profile 在 7.1 上只编 JIT 记下的热点方法，更新后刚启动的应用还没有档案，编出来接近 interpret-only；
  阅读类应用 speed 的翻页 / 打开书实测更好。编得久 / 占内存的代价由上面的调度挡住。

**模拟器实测（2026-11-12，QEMU 比真机慢约一个数量级，构建机同时有别的负载，时间只能看相对值）**

| 机器 | 情况 | 结果 |
|---|---|---|
| pw6-5195（957 MB） | 微信读书 speed，dex2oat 2 线程，nice 19 | 1215 s 编完（超过 dex2oat 自带的 570 s 看门狗，靠 `--no-watch-dog`）；dex2oat 峰值 378 MB，可用内存最低 381 MB，换出 33 MB，没有任何进程被杀 |
| pw6-5195 | 多看阅读 / 静读天下，speed（修看门狗之前） | 645 s / 580 s 被 dex2oat 自己的看门狗杀掉 → 修了；修之后静读天下 506 s 编完 |
| pw6-5195 | KOReader | vmSafeMode=true，系统只肯给 interpret-only → 记成 capped，不再排队 |
| kt6-5192（1 GB，mlock 掉 450 MB 模拟 512 MB 机型，微信读书开在前台） | 微信读书 speed，dex2oat 单线程 | dex2oat 峰值只有 67 MB；可用内存一直在 160 MB 以上，没有 lowmemorykiller 杀进程，前台的微信读书一直活着；但单线程在 QEMU 上 40 分钟没编完 → 宿主超时杀掉、补回 interpret-only（超时路径验证了） |
| pw6-5195 | 微信读书冷启动（强杀 + 清页缓存，到 WeReadFragmentActivity 变成 resumed） | interpret-only：113 s / 98 s；speed：61 s（另一次 150 s 超时，模拟器噪声大）。真机数据仍以 10.6 s → 4.5 s 为准 |

结论：957 MB 机型用系统默认线程数编 speed；512 MB 机型编 speed 但限单线程（峰值内存从 378 MB 降到 67 MB），可用内存 ≥ 120 MB 才开始，
< 40 MB 立即中止。真机上单线程编微信读书要多久没有测（估计几分钟到十几分钟，宿主超时 40 分钟）。

**命令**

| 命令 | 说明 |
|---|---|
| `compile all` | 所有还没编成 speed 的数据区应用排队 |
| `compile <包名>` | 强制重编这一个（即使已经是 speed） |

**进度**：`/dev/kfb/ctl/compile.status`（每个状态变化重写）：

```
state=running          # idle | running | waiting | paused
pkg=com.tencent.weread.eink
index=2                # 这一批的第几个
total=5
reason=                # waiting / paused 时：battery | memory | frozen | off | install；前台 / 在用时是中文句子，另有 code=foreground|busy
msg=                   # 有就是给用户看的一句话（foreground / busy 时），桌面和传书网页直接显示
last=com.foo ok 37     # 上一个：包 结果(ok|fail) 秒数
```

桌面显示“正在优化 微信读书（2/5）”：名字按 `pkg` 自己查 PackageManager。结果记录（最近 200 条）在 Android 里的
`/data/.vd-compile.log`（宿主 `$SYS/data/.vd-compile.log`）。

## 4. 电量 / 耗电（E5、E6 附带，`boot/lib/energy.sh`）

`status` 命令写的 `/dev/kfb/ctl/status` 多了这些行：

| 键 | 说明 |
|---|---|
| `batstart` | 起算点的电量（Android 启动时；充电或电量回升后重设） |
| `batmins` | 从起算点过了多少分钟 |
| `batdrain` | 平均每小时掉多少 %（一位小数；不到 10 分钟或掉电不到 1 % 时没有这一行） |
| `wifips` | Wi-Fi 省电现在是 `on` 还是 `off`（读不到就没有这一行） |
| `wifipsmode` | `WIFI_PS` 的设置值 |

另外宿主每 10 分钟最多记一行到 `$SYS/battery.log`（Android 里 `/data/../battery.log` 看不到，桌面要的话以后加命令导出）：
`<unix 时间> <电量> <充电 0/1> <run|frozen|saver>`，最多 64 KB。按天的耗电曲线、前台 / 冻结 / 屏保分别的耗电可以从这里算。

## 5. 时区和 12 / 24 小时制（B8，`boot/lib/tz.sh`）

**调查结果**（5.19.x 固件，pw6-5195 / kt6-5192 模拟器）：

- `/etc/localtime` → `/var/local/system/tz`。用户在 Kindle 的“设备时间”里选了时区后这里是一个 TZif 文件；没选过就不存在（UTC）。
  Kindle 上没有 `/usr/share/zoneinfo` 的时区文件，也找不到存 IANA 名字的地方（KPP 界面的库另外读 `/var/local/system/tzVar`，
  格式是 `KINDLE_TZ=GMT+偏移`，只有偏移）。
- TZif v2+ 文件最后一行是 POSIX 规则（`CST-8`、`IST-5:30`、`EST5EDT,M3.2.0,M11.1.0`…），包含夏令时规则。
- 12 / 24 小时制：lipc `com.lab126.kppsettings timeFormat`（字符串 `12` / `24`，可读写；Kindle 设置界面改了会发 `timeFormatChanged` 事件）。
  模拟器上 `lipc-set-prop` 写 24 读回来仍是 12（这个属性大概由设置界面那个进程持有、只认自己的界面）：真机上用 Kindle 的设置界面改，宿主只读。
  **5.17 固件没有 `com.lab126.kppsettings`**（kt6-517104 实测 lipcErrNoSuchSource）：`TIME_12_24=auto` 时什么都不做，12 / 24 只能手动选。

**做法**：

- 开机前：从 TZif 末尾的规则查表（约 60 个常用时区，含 +05:30 / +05:45 / +06:30 / +09:30 / +08:45 / 夏令时地区），名字必须在 Android 的
  tzdata（2016g）里存在；表里没有的规则先按当前偏移（非整点偏移也映射到真实地区名，整点用 `Etc/GMT∓N`），同时在后台扫 Android 的 tzdata
  找规则完全相同的时区，结果缓存在 `$SYS/tzcache`，开机完成 / 下次解冻时换成准确的名字。
- 冻结期间 Kindle 上改了时区：解冻后用 `service call alarm 3 s16 <时区>`（AlarmManager.setTimeZone）通知 Android，应用会收到 `TIMEZONE_CHANGED`。
- 12 / 24：开机完成和每次解冻时读 `timeFormat`（`TIME_12_24=auto` 时），和上次写的不同才 `settings put system time_12_24`。

**时钟（AlarmManager，1.00 用户反馈“时间还是不对”，fix/100-hotfix）**：Android 和 Kindle 共用内核时钟，时间本身不会错；
错的是“什么时候更新显示”。7.1 的 AlarmManager 用 5 个 timerfd，其中 `CLOCK_REALTIME_ALARM` / `CLOCK_BOOTTIME_ALARM` 要
`CAP_WAKE_ALARM`，7.1 的 zygote 不给 system_server（8.0 才加），`timerfd_create` 返回 EPERM，logcat 里是
`AlarmManager: Failed to open alarm driver. Falling back to a handler.`。退回的 Handler 按 uptime 计时（休眠不算），唤醒 / 非唤醒闹钟
共用一条消息、后排的顶掉前面的，`TIME_TICK` 晚几分钟到几小时（测试机实测：`dumpsys alarm` 里 TIME_TICK 过期 22 分钟没发，
下一条唤醒闹钟在 10 小时后；另一台测试机过期 1 分多钟）。状态栏 / 阅读器里的时钟（多看、微信读书的页脚）、应用的定时任务都跟着停。
- 宿主（`container.sh` 的 `alarmfix_*`，镜像修好前的办法）：开机前复制 `system/lib/libandroid_servers.so`，改两处再绑到原位：
  时钟表里的两个 `*_ALARM` 换成 `CLOCK_REALTIME` / `CLOCK_BOOTTIME`（不叫醒 Kindle，休眠归 powerd；醒来后照样马上到期），
  epoll 不加 `EPOLLWAKEUP`（`movt r5,#0x2000` → `nop.w`：冻结中到期的定时器不在内核里挂唤醒源）。两处原字节都对上才改
  （1.00 的 pw6 64 位镜像和 32 位镜像偏移相同：表 154856、指令 52736），镜像里的文件不动（它和回退用的旧镜像是硬链接）。`ALARM_FIX=0` 关掉。
  测试机实测：改后没有 `Falling back`，`system_server` 的 6 个 timerfd 都在 epoll 里（events 0x19，没有 EPOLLWAKEUP），TIME_TICK 每分钟一次。
- 镜像（`android/small-patches.py`）：`timerfd_create` 得到 EPERM 时换成不要权限的时钟，epoll 不加 EPOLLWAKEUP；下次出镜像时带上。
- 桌面（VeraHome）：主页时钟、状态栏除了按 uptime 排的分钟 tick，也收 `TIME_TICK` / `TIME_SET` / `TIMEZONE_CHANGED`（Kindle 睡醒、改时区后马上刷新）；
  主页从应用回来时刷新时钟卡片（fix/home-clock-resume，1.00 的 perf/home-1core 之后它要等到下一个整分钟）。

## 6. 离线更新文件夹（H2，`boot/lib/localupdate.sh`）

**放哪里**：Kindle 的 `veradroid/update/`（USB 里看到的路径；设备上 `/mnt/us/veradroid/update/` = `/mnt/base-us/veradroid/update/`），
没有就自己建。放下面任意一种：

- `veradroid-pw6-<版本>.tar.gz`（PW6 / Colorsoft，5.x 内核）或 `veradroid-k49-<版本>.tar.gz`（PW5 / KT5 / KT6，4.9 内核）
- 整个离线包 `VeraDroid-Offline.zip` / `VeraDroid-Offline-Experimental.zip`（不用解压）
- 可选：`<包名>.sha256`（整个文件的 SHA-256），老的不带清单的包可以再放一个离线包里的 `bootstrap.sh`

**什么时候装**：下次点“VeraDroid 启动”（Android 没在运行时的冷启动），或者桌面发命令 `localupdate install`
（会先停掉 Android，装完自动启动新版本）。

**检查**（按顺序，前面的只看文件名，很快）：

1. 这台机器的内核对不对（5.x 只认 pw6，4.x 只认 k49；3.0 内核的老机型暂不支持）、版本是不是**比已装的新**——
   一样或更旧的绝不安装（不降级）。不合格的改名 `*.rejected`，以后不再看。
2. 包里的 `manifest.json`：`product` 必须是 `veradroid-<变体>`，`version` 必须和文件名一致。
3. 包里的 `SHA256SUMS`（pack.sh 从 0.89 / 0.97 起写，覆盖包里每个文件；系统镜像 `rootfs.tar.gz` 直接从整包流过 sha256sum，不解出来）逐个核对。
   之前打的包没有清单：退一步，整包和系统镜像的 gzip CRC 都完整读一遍。有 `.sha256` 时再核对整个文件。
4. 安装器：用包里自带的 `bootstrap.sh`（同版本），老包用 `update/` 里或 zip 里的。走书库离线安装同一条路（`VD_BUNDLE`）：
   安装前备份用户文件、`veradroid-install.incomplete` 标记、旧程序目录 / 系统留作 `host.bak.*` / `rootfs.bak.*`，被打断时下次启动自动回退。

**结果**：`veradroid/update/result.txt`（`KEY=value`）：

```
time=2026-11-12 08:40:01
result=ok              # running（正在校验 / 安装）| ok | failed | rejected
file=veradroid-pw6-0.89.tar.gz
from=0.88
to=0.89
reason=...             # failed / rejected 时的原因（中文，可以直接显示）
```

成功：安装包删掉。失败：改名 `*.failed` 留着。详细日志 `/mnt/base-us/veradroid-localupdate.log`（安装器本身的输出也在里面）。

**命令**

| 命令 | 说明 |
|---|---|
| `localupdate check` | 只按文件名列出候选，写 `/dev/kfb/ctl/update.local`：`installed=`、`variant=`、每个包一行 `candidate=<文件> <变体> <版本> <ok\|not-newer\|wrong-variant\|bad-name\|unsupported-kernel>`、上次结果 `last.result=`… |
| `localupdate install` | 校验并安装最新的合格包；Android 会先停掉，装完启动新版本 |

界面建议：设置 → 设备与更新里，`check` 有 `ok` 的候选时显示“发现离线更新 0.89，点此安装”；显示 `last.*` 的上次结果。
传书网页上传 `veradroid-*.tar.gz` / `VeraDroid-Offline*.zip` 时，可以直接存到 Kindle 的 `veradroid/update/`（宿主路径 `/mnt/base-us/veradroid/update/`）。

## 7. 存储空间：系统盘大小可调（`boot/lib/storage.sh`、`boot/resize.sh`，分支 `feat/storage-resize`）

只对“系统盘是 Kindle 存储上的一个镜像文件 `/mnt/base-us/veradroid-sys.img`”的机型有意义：用户分区是 FAT 或 fscrypt 加密的
PW5 / KT5 / KT6 / Scribe（`host/k49`）。PW6（`host/pw6`）没有镜像，Android 直接用 Kindle 的剩余空间：`st.mode=shared`，
调整类命令一律答 `error=shared`，界面显示“与 Kindle 共用空间，无需调整”和剩余空间。

**规则**

- 扩大：ext4 且镜像正挂着 → **在线**（加长文件 → `losetup -c` → `resize2fs /dev/loopN`，内核在线扩，Android 不停）。
  不能在线（ext3、losetup 没有 `-c`、在线失败）→ 离线。
- 缩小：只能**离线**：停 Android（开机画面上显示 1/4…4/4）→ `e2fsck -f` → `resize2fs` → 超级块确认文件系统已不超过目标 → 截短文件 → 再 `e2fsck -f` → 重新启动 Android。
  任何一步失败都不截短文件，照常开机，原因写进“上次结果”。
- 下限 `st.min` = 已用 ×1.03 + 128（日志）+ 200（余量），取到 64 的整数倍，不低于 768；离线时再用 `resize2fs -P` 核一遍。
- 上限 `st.max` = 镜像真正占着的（ext4 上是稀疏文件）+ Kindle 剩余 − 256（留给 Kindle）；用户分区是 FAT 时封顶 4095 MB（单个文件 4 GB − 1）。
- 断电 / 被杀：镜像外面有“进行中”标记 `/mnt/base-us/veradroid-resize.state`。下次挂载前先完整 `e2fsck`，再看超级块：
  缩小已做完就把文件截短（完成），没做完文件系统仍是原大小、文件没动过（回退）；扩大则把文件系统补到文件大小。
- 离线调整前电量低于 15% 且没在充电 → `error=battery`。
- 自动扩容 `STORAGE_AUTO`（默认 `1`，设置键，也可用命令改）：镜像里可用空间 < 200 MB 且还能扩时，看门狗（每 20 秒）扩 512 MB；
  能在线就当场做，不能就记到 `/mnt/base-us/veradroid-resize.pending`，下次启动 Android 时做。扩不动（Kindle 没地方 / FAT 4 GB）只提醒一次。
- 工具：固件自带的 `resize2fs` / `e2fsck` 优先，没有时用整包里的静态版（`bin/resize2fs`、`bin/e2fsck`，e2fsprogs 1.47.1，`tools/cross/build-e2fs.sh`）。
- 安装器（`bootstrap.sh`）新建镜像时不再固定 3072 MB：2048 起，Kindle 剩余空间不够（镜像 + 300 安装余量 + 256）依次退到 1536 / 1280 / 1024。

**命令（`/dev/kfb/ctl/cmd`）**

| 命令 | 作用 |
|---|---|
| `storage info` | 重写 `/dev/kfb/ctl/storage`（下面的 `st.*`，单位都是 MB） |
| `storage resize <MB>` | 调整到这么大。答复写 `/dev/kfb/ctl/storage.result`：`ok=1 mode=online image=<MB>`（已完成）、`ok=1 mode=offline from= to=`（Android 马上被关掉，做完自动重启）、`ok=0 error=<原因> min= max= image=` |
| `storage auto on\|off` | 改 `STORAGE_AUTO`（`off` 同时撤掉还没做的“下次启动时扩容”） |

`error=`：`shared`（PW6）、`nan`、`same`（和现在差不到 16 MB）、`small`（低于下限）、`nospace`（Kindle 空间不够）、`fatlimit`（FAT 4 GB）、
`toobig`（> 32 GB）、`busy`、`battery`、`notool`、`extend`（文件加长失败）。

`st.*` 键：`st.mode`（`image` / `shared`）、`st.image`（镜像文件大小）、`st.alloc`（真正占用的）、`st.total` / `st.used` / `st.free`（镜像里的文件系统）、
`st.kindle_total` / `st.kindle_free`（Kindle 这边）、`st.min` / `st.max`（可调范围）、`st.cap`（上限来自 `space` / `fat` / `hard`）、`st.keep`（256）、
`st.kfs`（用户分区文件系统）、`st.fs`（镜像的：ext4 / ext3）、`st.online`（扩大能不能在线）、`st.auto`、`st.busy`、`st.pending`（下次启动时扩到多少）、
`st.last.time` / `.result`（`ok` / `refused` / `failed` / `rolledback`）/ `.op`（`grow` / `shrink`）/ `.from` / `.to` / `.reason`。
`shared` 模式只有 `st.mode`、`st.kindle_total`、`st.kindle_used`、`st.kindle_free`、`st.kfs`。

宿主主动告诉桌面的话写在 `/dev/kfb/ctl/storage.notice`（一行，HostService 弹提示后删掉）：`grown <旧> <新>`、`pending <MB>`、`full <fat|space>`、
`result <ok|failed|rolledback|refused> <grow|shrink> <旧> <新>`。

**管理网页（`WebAdmin.java`，宿主动词 `storage` / `storageresize <MB>` / `storageauto 0|1`）**

| 接口 | 请求 | 返回 |
|---|---|---|
| `GET /api/sys/storage` | – | `{"ok":"1","st.mode":"image","st.image":"3072","st.used":"812",…}`（上面的 `st.*`，值都是字符串） |
| `POST /api/sys/storage/resize` | `{"mb":2048}` | `storage.result` 的内容：`{"ok":"1","mode":"online","image":"2560"}` / `{"ok":"1","mode":"offline","from":"3072","to":"2048"}` / `{"ok":"0","error":"small","min":"1536","max":"4095","image":"3072"}`。在线扩大做完才返回（FAT 上可能一两分钟）；`offline` 返回后几秒 Android 被关掉，网页会断线，几分钟后重连再读 `/api/sys/storage` 的 `st.last.*` |
| `POST /api/sys/storage/auto` | `{"on":true}` | `{"ok":"1", …st.*}` |
| `GET /api/overview` | – | `hostinfo` 里也带同样的 `st.*` 键，概览页可以直接画两条占用条（Android：`st.used`/`st.total`；Kindle：`st.kindle_free`/`st.kindle_total`） |

**模拟器实测（2026-11-12，ks1-5202 = Scribe 5.20.2 ext4+fscrypt 用户分区；pw5b-5192 = PW5 5.19.2 FAT、512 MB）**：
在线扩大（Android 运行中，FIFO / 网页 / 桌面界面）ks1 5 次、pw5b 5 次；离线缩小 / 扩大（resize.sh、FIFO 触发 Android 重启）ks1 2 次、pw5b 6 次；
拒绝（small / nospace / fatlimit / same / nan）两台各 ≥2 次；ks1 扩到 4200 MB（ext4 用户分区不受 4 GB 限制）；
自动扩容（填满镜像）两台各 2 次，在线完成并提示；“下次启动时扩容” ks1 2 次；kill -9 resize 过程（缩小 3 次、扩大 3 次、带 Android 2 次）后再启动：
全部完成或回退，校验和金丝雀（300+ 个文件、中文名、符号链接）全部一致，`e2fsck -f -n` 全部干净。
没在真机上验证；legacy（3.0 内核、ext3，只能离线）没测；PW6 共用空间模式只在 ks1 上模拟过 `st_info` / `st_request`。

日志：`/mnt/base-us/veradroid-resize.log`。SSH 里也可以直接跑 `sh /mnt/base-us/veradroid/boot/resize.sh <MB>`（Android 没在运行时只调整、不启动）。

## 真机补充（2026-11-12，PW6 5.19.5）

- 时区：真机的 `/var/local/system/tzVar` 存的是地区名（`KINDLE_TZ=Asia/Tokyo`），`/var/local/system/tz` 是不带 POSIX 规则的 TZif v1。
  `tz_kindle_name` 优先用这个名字（Android tzdata 里有才用），之后才走规则 / 偏移。修前 Android 是 `Etc/GMT-9`，修后 `Asia/Tokyo`（JST）。
- 预编译：开机后自动排队了唯一一个 interpret-only 的应用（静读天下），`ctl/compile.status` 正常显示进度。
- Wi-Fi 省电：`wifips=on wifipsmode=auto`。

## 7. 书库入口、返回 Kindle 后的自检（2026-11-12，KT6 固件 5.17 用户反馈）

### 我们在用户存储上写什么

安装 / 更新 / 卸载只按固定名字写和删，别的文件一律不碰（KUAL、KOReader、其它 `.sh` 入口、`extensions/` 下别的文件夹）：

| 位置 | 文件 | 谁写 | 谁删 |
|---|---|---|---|
| `documents/` | `VeraDroid 启动.sh`（书库标题 **VeraDroid**）和它的 `.sdr` | 安装器；被删后 `launcher_ensure` 补回 | 卸载 |
| `documents/` | `VeraDroid.sh` / `VeraDroid-Experimental.sh` / `VeraDroid-Offline.sh`（标题“VeraDroid 安装…”）和 `.sdr` | 用户自己放的 | 安装成功 30 秒后安装器删掉 |
| `documents/` | 离线包带来的 `veradroid-*-*.tar.gz`、`bootstrap.sh`、我们那份 `README.txt` | 用户放的 | 离线安装成功后 |
| `veradroid/` | 程序目录；其中 `VeraDroid-Launch.sh` 是入口的备份，标题 **VeraDroid（备用入口）** | 安装器 | 卸载 |
| `extensions/VeraDroid/` | KUAL 菜单（`start.sh` `install.sh` `config.xml` `menu.json`） | 安装器 | 卸载（只删这四个文件，目录空了才删） |
| 根目录 | `veradroid-sys.img`、`veradroid-*.log`、`veradroid-user-backup-*.tgz`、`veradroid-cc.db.*` | 安装器 | 卸载 / 轮替 |

- 备份入口的标题和正式入口不同：有用户把整个 `veradroid` 文件夹拷进 `documents`，书库里出现过两个一模一样的“VeraDroid”。
  `launcher_ensure` 把备份放回书库时会把标题改回 `VeraDroid`。
- 书库怎么运行脚本（Véra 越狱的 SH_Integration）：`appmgrd` 按 `text/x-shellscript` 找到
  `tech.hackerdude.shell_integration.launcher`，它执行 `fbink -k; sh -l "<脚本>" 2>&1 | fbink -y 5 -r`。同一个入口连点两次会跑两次
  （kt6-517104 模拟器用 `lipc-set-prop com.lab126.appmgrd start "file:///mnt/us/documents/<脚本>"` 实测）。
- 封面：索引服务的 `sh_integration_extractor.so` 把脚本头里 `# Icon: data:image/png;base64,…` 解成 `<脚本>.sdr/icon.png`，
  `cc.db` 的 `p_thumbnail` 指向它；没有 `# Icon:` 的脚本（用户自己的入口）显示成普通文档的样子，这是越狱环境的行为，不是我们能改的。
  我们的入口带图标；返回 Kindle 时如果入口已经在书库里却没有 `icon.png`，`launcher_ensure` 让索引服务对这一个文件重扫一次
  （每个固件版本只做一次，记在 `$SYS/launcher-icon.tried`）。

### 点“启动”之后可能遇到的状态（`boot/veradroid.sh`）

| 状态 | 以前 | 现在 |
|---|---|---|
| 另一个启动还在进行 | 直接退出，屏幕上什么都没有 | 屏幕提示“正在启动，请稍等” |
| 上一次的 `stop.sh` 还没跑完 | （0.96 及以前）和它踩在一起：Android 起在 Kindle 界面后面，系统盘被卸到一半 | 等它跑完（最多 120 秒），屏幕提示 |
| Android 活着、没冻结，Kindle 界面却在前面 | `open_app` 后退出：怎么点都没反应 | 完整停掉再冷启动 |
| Kindle 正在关机 / 重启 | 照常启动，关机钩子立刻把它停掉且不恢复 Kindle 界面 | 不启动；`/tmp/shutdown_in_progress` 只是残留时照常启动但不挂关机钩子 |

### 返回 Kindle 后的自检（`common.sh` 的 `userstore_check`）

`stop.sh` 结尾和冻结返回之后各跑一次，结果追加到 `veradroid/last-stop.log`（USB 里看得到，只留最近 60 行）和内核日志：

- `volumd` / `awesome` 还停在 SIGSTOP：补发 SIGCONT（`volumd` 停着时 USB 连电脑没有反应）；
- 我们停过的 `mtp` 任务没有回来：再起一次；`framework_start` 现在先起 `mtp`、等 `com.lab126.mtp` 登记好再唤醒 `volumd`；
- 完全退出后还有系统盘的挂载、loop 设备：列出挂载点和仍然开着系统盘 / 程序目录里文件的进程。

没有 PID 命名空间的内核（固件 5.17 的 KT6，chroot 模式）：

- 容器进程按“根目录在系统盘的 loop 设备上”识别（`chroot_pids`），不再只看 `/proc/PID/root` 的路径：根被延迟卸载以后那个链接读出来是 `/`，
  旧办法一个都认不出来，进程留着、loop 设备摘不掉，只能重启 Kindle；
- 返回 Kindle 一律完全退出（`RETURN_MODE` 强制为 `off`）：这种模式下容器的四十多个挂载直接落在 Kindle 的挂载表里，而且 freezer 组是空的，
  “冻结”其实什么都没冻住。更彻底的办法是像 `host/legacy` 那样用私有挂载命名空间 + `pivot_root`（4.9 内核的 CLONE_NEWNS 是否可用还没验证）。

没法在模拟器上验证的：真机上 USB 连电脑（模拟器没有 USB 主机，镜像里的 `mtp` 任务也被替换成了空任务）。

## 8. 设备上的新设置入口（分支 `feat/parity-gaps`，VeraHome `HostSettingsActivity`）

以前只有宿主 / 传书网页能改的键，现在设置页里有入口，全部走 `HostLink.settings`（`ctl/settings.new` + `apply` → `settings.conf`）。每项一行“‹ 值 ›”步进，点一下只改这一行的字。

| 入口 | 键 | 选项 |
|---|---|---|
| 设置 → 显示 → 显示与刷新 | `KFB_ROTATE` | 0 / 90 / 180 / 270（90、270 宿主自动重启 Android） |
| 同上 | `KFB_SMOOTH` | 0 自定义 / 1 流畅 / 2 均衡 / 3 画质（非 0 时决定下面两项） |
| 同上：局部刷新 | `KFB_MODE` | 0 均衡 / 1 灰度最准 / 2 最快 / 3 自动（同 Kindle） |
| 同上：整页刷新“多大算整页” | `KFB_REAGL_MIN` | 30 / 35 / 50 / 70 / 85（%，默认 35；0.94 及以前默认 85） |
| 自适应合并（epd2）| `KFB_SETTLE2` | 毫秒，默认 40：紧跟在一次刷新之后、只改了一小条（< 1/5 屏）的帧只等这么久，滚动 / 动画仍等满 `KFB_SETTLE`；0 = 以前的做法 |
| 滚动快刷（epd2）| `KFB_SCROLLDU` | 毫秒，默认 0（关）：大面积接连变化时用 DU，停下这么多毫秒后补一遍 16 级灰度；建议试 300 |
| 图片用灰度（epd2，均衡）| `KFB_IMG` | 百分比，默认 0（关）：小区域里中间灰占到这么多（图片）就用 GL16 而不是 DU；建议试 25 |
| 同上：整屏闪刷 | `KFB_FLASH` | 0 / 1 / 3 / 6 / 8 / 10 / 20 页 |
| 设置 → 设备与更新 → 系统与性能 | `WIFI_PS` | auto / on / off |
| 同上 | `LOWMEM`、`KINDLE_UI` | auto / on / off；auto / keep / freeze / stop（下次启动生效） |
| 同上 | `APP_COMPILE` | auto / off；下面显示 `ctl/compile.status`（inotify 跟着变），“全部优化”= 命令 `compile all` |

`LAN_PORTS` 已删除（从来没有实现）。

## 9. 锁屏密码（`LockScreen.java`、`LockSettingsActivity.java`、宿主 `boot/lib/lock.sh`）

- 设置 → 设备与更新 → 锁屏密码：4–6 位数字，默认关。存在 VeraHome 私有目录（设备加密区 `shared_prefs/lock.xml`）：16 字节随机盐 + PBKDF2-HMAC-SHA1 20000 轮，不存密码。
- 什么时候问：桌面进程起来（开机）一次；每次 Kindle 屏保：`sleep.sh` 进屏保时在冻结前写 `ctl/act.lock`（显示桥已经被 `ctl/sleep` 挡住，锁屏画好但不上屏），醒来解冻后再写一次（已经盖着就什么都不做）。
  从 Kindle 书库重新打开冻结的 Android 不问（那时已经过了 Kindle 自己的锁屏）。
- 锁屏是 `TYPE_SYSTEM_ERROR` 全屏悬浮窗，盖住状态栏、面板、导航条；返回键无效；锁着时宿主手势 `panel` / `switch` / `home` / `back` 被 HostService 忽略。
  不挡回 Kindle：锁屏上有“回到 Kindle”按钮（`exit`），宿主的四角长按 `kindle` 和电源键本来就不经过 Android。
- 输错：连续 5 次 → 30 秒不让输（存盘，重启 Android 不清零；时钟往回拨最多也只等 30 秒）；之后每再错 5 次再等 30 秒。等待时不倒计时，到点改一次字。
- 忘了密码：USB 连电脑，在 Kindle 存储的 `veradroid/` 里放 `reset-pin.txt`（也认 `reset-pin`、`RESET-PIN.txt`），拔线后打开 VeraDroid 或从屏保醒来：
  宿主 `lock_reset_check`（冷启动的 `after_boot`、书库解冻、屏保醒来）删掉文件并写 `ctl/lock.reset`，HostService 清掉密码并提示“锁屏密码已清除”。

## 10. 屏保挑选（`ScreensaverActivity.java`、宿主 `boot/lib/saver.sh`）

- 设置 → 设备与更新 → 屏保：第一格“Kindle 自带”，后面是 Android 的 `/sdcard/Screensaver/` 和 Kindle 存储 `veradroid/screensaver/` 里的图（缩略图 3×3 一页）；
  按钮“用 Kindle 自带的”“轮换全部图片”；点一张 = 只用这一张；“从内部存储导入…”把一张图复制进 `/sdcard/Screensaver/` 并选上。
- 选择文件 `/sdcard/Screensaver/.vd-saver`（宿主 `$SYS/data/media/0/Screensaver/.vd-saver`）：`mode=kindle|rotate|one`，`one` 时 `file=sd/<文件名>` 或 `file=vd/<文件名>`。
  宿主只认文件名（不含 `/`、不以 `.` 开头），文件不在了退回轮换。**没有这个文件 = 以前的做法**（有用户图就轮换，没有就 Kindle 自带），老用户不变。
- Android 看不到 `veradroid/screensaver/`：页面打开时发 `saver list`，宿主把那里的图（每张 ≤ 8 MB，最多 60 张）和一张 Kindle 自带屏保图（`.kindle-preview.png`）拷到 `/dev/kfb/saver/`（tmpfs），
  写 `ctl/saver.listed`；页面关掉发 `saver done` 删掉。

## 11. 单手模式、崩溃上传先问

- 单手模式（设置 → 桌面 → 单手模式，偏好 `onehand`）：主页顶栏和应用网格挪到屏幕下 60%，上面一块放一个大的“▼ 下拉面板”按钮。只影响主页。
- 桌面崩溃时的诊断上传（`DiagConsent.java`，偏好 `crash_upload`）：以前直接 `diag-upload`；现在 `always` 才自动传，`never` 不传，**没选过不传**，
  只记一个 `crash_pending`，下次桌面起来时问一次：总是上传 / 仅这次 / 不上传。设置 → 设备与更新 → 日志 里能改，说明文字列出了诊断包的内容
  （dmesg、last_kmsg、/proc/cmdline、/proc/cpuinfo 含序列号、/var/log/messages、logcat、dumpsys 等）。手动“上传完整系统日志”和“问题反馈”不变。

### 模拟器实测（2026-11-13，pw6-5186 = PW6 5.18.6，宿主换成本分支 host/pw6，VeraHome 93cac32；宿主机负载 9–12）

- 锁屏：设密码后 lock.xml 只有 salt / hash / len；电源键休眠 → 醒来第一帧是锁屏；连错 5 次 → “请 30 秒后再试”，等待期间输对也不放行，30 秒后输对解锁；
  `veradroid/reset-pin.txt` + 休眠 / 醒来 → 文件被删、lock.xml 清空、锁屏消失（做了两次）。
- 显示与刷新 / 系统与性能：`KFB_MODE`、`KFB_REAGL_MIN`、`KFB_ROTATE`（180 即时 `rotate 0 -> 180 (live)`；90 自动重启 Android）、`WIFI_PS` 都写进了 `settings.conf`（QEMU 上宿主 apply 要几秒）；
  “全部优化”后 `compile.status` 变成 running，页面上那行跟着变（inotify）。
- 屏保：选 veradroid/screensaver 里的一张 → `.vd-saver` = `mode=one file=vd/usb-test.png`，电源键休眠日志 `screensaver: …/usb-test.png`；改选 Kindle 自带 → `bg_ss01.png`。
- 单手模式：设置里打开、回主页后顶栏和网格在下 60%，“打开下拉面板”能打开面板。崩溃询问：放一个 `crash_pending` 后重启桌面 → 弹框；选“不上传” → `crash_upload=never`，没有触发上传。
  真正让桌面崩溃那一步（`onCrash` 写标记）没在模拟器上做。

## 12. 每个应用的显示设置（分支 `fix/ux`，`boot/lib/appprof.sh`，三个宿主同一份）

- **前台信号**：VeraHome `HostService` 的 TaskStackListener（任务栈一变系统就通知；兜底 1.5 / 5 / 15 秒复查和 10 秒一次的
  `getRunningTasks(1)`，都是早就有的）→ 命令 `fg <包名>`（桌面 / 我们自己的页面 = `fg home`；面板、设置、显示设置这些盖在应用上面的页面不算换应用）。
  桌面自己打开应用时在 `startActivity` 之前先发（应用画第一帧前就换好）。不跑 dumpsys、不轮询，512 MB 机型同样适用。
- **文件**：`$VD/boot/appprofiles.conf` 内置推荐（`<包名>[*] KEY=v;KEY=v`，`*` = 前缀）；`$SYS/settings.apps` 用户的
  （`<包名> KEY=v;...`，`<包名> -` = 全跟随全局；整行代替内置的；和 settings.conf 在一起，安装器不动）；
  `/dev/kfb/appprof` 合并表给桌面看（`<包名> b|u|ub <spec>`）；`$SYS/settings.app` 当前前台应用实际生效的参数（开机清掉）。
- **命令**：`fg <pkg>|home`、`appset <pkg>|<spec>`（spec 空 = 删掉用户的；`-` = 全跟随；`appset *|` = 全部清掉）。
  `appdisp home` 等同 `fg home`；老桌面的 `appdisp <pkg>|<spec>` 照旧能用。
- 键白名单同 `appdisp`；同一个包 / 结果参数相同时什么都不发。应用自己的 `KFB_MODE` 不被流畅度档位（`KFB_SMOOTH`）盖掉。
- 老机型（legacy）的显示桥没有快速滑动 / 图片灰度：表里照样能写，不起作用；桌面看 `/dev/kfb/settings` 里没有 `KFB_SCROLLDU` 就不显示这两项。
- 显示桥：`SET` 只有对比度 / 抖动 / 反色 / 浅色过滤 / 深色加深变了才整屏重画（以前每次都重画，换应用时在应用第一帧上面多一次整屏刷新）；
  `LAUNCH <ms>`：桌面打开应用 / 任务栈换到别的应用时发，<ms> 内纯色的帧（启动窗口的白屏 / 黑屏）不上屏，保留上一屏，600 ms 后在上面画“加载中”，
  第一帧有内容的画面（或时间到）结束。

### 实测（2026-11-16/17，分支 fix/ux）

- 一台测试机（PW6 5.19.5，线上 0.95，改动前基线；改动后没在真机上测）：冷启动时纯色启动窗口在屏上停留
  EinkBro 约 2.0 s、KOReader 约 1.6 s（fb0 每 250 ms 采样，gzip 后约 2 KB = 只有状态栏）；微信读书 0.7–6.9 s 是它自己的 logo 页（有内容，不该挡）；
  每次从桌面打开应用都多一次整屏 REAGL（`appdisp home` → SET → 重画）；`animator_duration_scale` 被设成 1 后一直是 1。
- PW6 模拟器（PW6 5.20.2 + 0.95，比真机慢 5–10 倍）：改动后 SET 不再重画（日志 `(no redraw)`）；
  从桌面打开 EinkBro / 静读天下：纯色帧被挡住，上一屏保留，约 0.6 s 后出“加载中”（模拟器上应用太慢，5 s 到时才放行）；
  KOReader 的启动窗口有 6–8 % 的行有东西（超过 6 % 阈值），照常显示。动画缩放被改成 1 后立刻回到 0。
  宿主处理 `fg` 到显示桥收到 SET：模拟器上 450–790 ms（其中 settings_load 约 150 ms；真机预计 100–200 ms，没测）。
  输入法收起：收到 HINT 后的两帧走 REAGL；模拟器上应用 3 秒后才重画的工具栏仍是 DU。
- PW4 模拟器（PW4 5.18.1，4.1 内核，490 MB，legacy 0.21 宿主 + 本分支的 appprof.sh / cmd.sh 钩子 + VeraHome 73）：
  `/dev/kfb/appprof` 发布、EinkBro 到前台 → `KFB_SCROLLDU=300`、回桌面 → 全局、`appset` 存取 / 恢复默认都正常。
  legacy 的显示桥（release/legacy-0.8.7 的 epd.c）还没有“SET 不重画”和 LAUNCH：在那里每次换配置会多一次整屏刷新，要把这两处移植过去。
- WebView（模拟器 EinkBro，经 veradroid-input 注入）：短按 5/5 触发 click、长按 1.5 s 出链接菜单、底边上划返回正常；
  没复现“返回 / 长按不灵”，真机上的手指抖动没法在模拟器上测。

## 13. 翻页滑动合并（`ANIMHOLD`，分支 `fix/apps3`，display/epd.c）

- 问题：晋江 7.1.9（32 位）翻页带滑动 / 覆盖动画，软件渲染下约 6 帧、间隔 ~80 ms。第一帧只是贴着右边（或左边）的一条
  （新页 / 阴影进来，136x1696+1120+0），显示桥“安静之后的第一帧马上画”，于是每次翻页 = 一条 DU 竖条 + 一次 REAGL 整页 +
  有时再一两块（左边阴影退出、页眉 / 页码）。一台测试机（0.95 线上显示桥 / fix/ux 显示桥，KFB_MODE 3）8 次翻页：每次 2–8 块刷新，
  轻点到面板刷完约 1.03 s。
- 做法：安静之后的第一帧，如果变化范围是一条贴边的条（几乎整高、宽不超过 2/5、贴左或右边；或者转过来的上下方向），先不画；
  后面的帧替换它，`anim_quiet_ms`（默认 180，`ANIMHOLD <ms>` / `--anim-hold`，0 = 关）内没有新帧就把最新的画面画一次
  （从第一帧起最多 1 s）。按钮、按键这类第一帧不受影响；从边上滑出来的抽屉 / 菜单也会合成一次。
- 实测（测试机，同一个二进制 ANIMHOLD 0 / 180 对比）：
  - 晋江：每次翻页 1 块 REAGL（之前 2–8 块），轻点到刷完 0.98–1.23 s（之前 1.02–1.07 s），10 次里 9 次进了合并。
  - 微信读书 / 多看（墨水屏版）/ 掌阅精选（墨水屏版）：一次也没进合并，刷新块数和时间不变（各 6 次）。

## 14. 更新前备份可选、已备份的数据（分支 `feat/backup-opt` / `feat/backup-opt-legacy`，`boot/lib/backup.sh`）

- 设置键 `UPDATE_BACKUP`（默认 `full`）：`full` 设置、阅读进度和 300 MB 以内的书（以前的做法）| `light` 只备份设置、阅读进度、笔记这些小文件 | `off` 不备份。
  不在 `settings_apply` 的键里：只能经管理请求 `updatebackup`（VeraHome 私有目录里的请求，别的应用冒充不了）改，免得别的应用悄悄把备份关掉。
  宿主每次发布设置时在 `veradroid/state/update-backup` 写一份副本（系统盘是镜像的机型，安装时镜像可能没挂上）。
- 安装器（两个 bootstrap 的 `vd_backup_mode` 块，和 backup.sh 一字不差）：环境变量 `VD_UPDATE_BACKUP` > settings.conf > 副本 > `full`。
  `off`：不备份、屏幕上说“更新出问题时无法恢复”；书库清单照样记、第一次开机照样核对（少了只能记下来）。
  完整备份放不下（剩余要够备份 + 100 MB；新机型还要够安装本身）先退到 `light`、屏幕上说，再放不下才跳过。legacy 的 emulator-only 机型 `off` 按 `light` 做。
  结果写 `veradroid/state/backup.last`（stamp / mode / kind / result=ok|off|nospace|failed|empty / file），每份备份是哪种记在 `state/backup-kinds`。
  离线更新（localupdate.sh）把设置传给包里的安装器；老安装器不认 `off`，`light` / `off` 时至少传 `VD_BACKUP_MB=0`（不备份书）。
- 管理请求：`backups`（列表）、`backupdel new|root <名字>` / `backupdel all`。只认安装器按固定格式起的名字（`user-backup-<时间>.tgz`、`cc.db.<时间>`、
  `documents-backup.tgz`、`documents-backup.restored-<时间>.tgz`、`media-keep/`），路径由宿主拼：`veradroid/backup/` 里的，或根目录里同名的
  `veradroid-<名字>`（老版本留下、vd_root_tidy 还没搬的）。不认链接、目录本身是链接也不删；KEEP 等改过名的、`vd18-keep/` 等一律不碰。
  不能删：有安装 / 离线更新在进行时全部；书库核对完之前（`state/docs-manifest` 还在）这次安装的那份备份和书库数据库。
