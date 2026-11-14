# 蓝牙翻页器 / 键盘

更新：2026-11-12（分支 `feat/bt-pair`：在桌面里扫描 / 配对 / 连接；按键桥默认 auto）。2026-11-11 初版（分支 `feat/bluetooth`）。

目标：在 Kindle 上配对的蓝牙翻页器（或蓝牙键盘）能在 Android 里翻页 / 打字。

## 1. 设计

**芯片和蓝牙栈一直归 Kindle。** Kindle 自己的蓝牙栈（`btmanagerd` / `acsbtfd`，Bluedroid 分支，用 `/dev/stpbt`）一直开着；
Android 里不跑 Bluedroid，也没有 `com.android.bluetooth`。（以前试过让 Android 接管芯片：每次开机崩约 100 次，已回滚，不要再走这条路。）

数据流：

```
翻页器 ──BLE/BR──> Kindle 蓝牙栈 ──/dev/uhid──> 内核输入设备（总线 BUS_BLUETOOTH）
                                                │  vdbtkeys 独占（EVIOCGRAB）、按映射改写
                                                ▼
                     uinput 设备 veradroid-btkeys（开机就建好，常驻）──bind──> 容器 /dev/input/event3 ──> Android
键盘 ──同上──> 内核输入设备 ──vdbtkeys 独占──> uinput 克隆 veradroid-btkbd ──mknod──> 容器 /dev/input/eventN（热插拔）
```

- 容器的 `/dev` 是私有的，后来才出现的输入节点 Android 看不见，所以翻页键走一个**开机就建好**的虚拟设备 `veradroid-btkeys`，
  在 `container.sh` 里和触摸屏 / 按键一样 bind 进容器（`event3`）。这个设备只有翻页 / 方向 / 媒体键，没有字母键，
  Android 把它当“非字母键盘”（KeyboardType 1），**软键盘照常弹出**。
- 有字母键的设备（≥20 个字母键）当键盘：建一个同样能力的 uinput 克隆，把它的字符设备 `mknod` 进容器的 `/dev/input`，
  Android 的 EventHub 用 inotify 自己发现；键盘断开时删掉节点、销毁克隆。设备号从 sysfs 读，不依赖宿主上有没有节点。
  键盘在 Android 根目录就位之前连上时（开机过程中），等容器的 `/system/build.prop` 出现后再发布（这期间 poll 每 2 秒醒一次，平时无限阻塞）。
- 5.20+ 固件的 `input_manager` 会把 Kindle Remote 转发成虚拟的 `kindle-input-pt`，vdbtkeys 也接管它（`BT_KINDLE_PT=0` 可关）。
- 返回 Kindle（冻结）时 `input_release` 给 vdbtkeys 发 SIGUSR1：放开所有设备，Kindle 自己照常用；回来时 SIGUSR2 重新独占。
  `$W/frozen` / `$W/saver_frozen`（屏保冻结）存在时收到的键直接丢掉，解冻后不会连翻好几页。
- **配对 / 连接在桌面的“蓝牙翻页器”页里做**（2026-11-12 起），经宿主转给 Kindle 的蓝牙服务 `com.lab126.btfd`（lipc）。
  以前的桌面页用 Android 的 `BluetoothAdapter.startDiscovery()`：Android 不拥有蓝牙芯片、镜像里也没有 Bluetooth.apk，所以“打开扫描没有反应”。
  Kindle 自己的“设置 → 蓝牙设备”照样能用，两边配的是同一张表。

### 配对 / 连接（宿主 `bt.sh`，桌面 `BluetoothActivity`）

桌面经命令 FIFO 发一行命令，宿主在后台调 lipc，结果写回文件（桌面用 inotify 等，不轮询）：

| 命令 | 宿主做的事（`com.lab126.btfd`） |
|---|---|
| `bt list` | 读 `ListPaired` / `ListConnected` / `ListDiscovered`，合并写 `ctl/bt.list` |
| `bt scan` | 蓝牙关着 → `error=off`；否则 `triggerBTscan 1`，18 秒内每 3 秒重写一次 `bt.list` |
| `bt bond MAC` | `Bond`；听 `btConfirmationEvent`，来了就答 `PairUserConfirmation 1`（Android 在前台时 Kindle 的确认框弹不出来）；`PairingFailed` / `btNotConfirmed` → `error=failed`；35 秒没配好 → `error=timeout`；配好后 `Connect`（不行再 `ensureBTconnection`） |
| `bt connect MAC` / `bt disconnect MAC` | `Connect` / `Disconnect`，等表里的 `is_connected` 变 |
| `bt unbond MAC` | 连着就先 `Disconnect`，再 `Unbond`，等它从 `ListPaired` 消失 |
| `bt enable` / `bt disable` | `BTenable 1/0`（和 Kindle 设置里的开关是同一个），等 `BTstate` |
| `bt map …` / `bt swap 0\|1` / `bt bridge auto\|1\|0` | 写 settings.conf，SIGHUP 让 vdbtkeys 重读 |

- MAC 只接受大写 `^([0-9A-F]{2}:){5}[0-9A-F]{2}$`（先用 case 排除其他字符，再 grep），不经过 eval；不合格写 `error=badmac`，什么都不做。
  发给 btfd 时用 Kindle 表里原来的大小写。
- 同一时间只有一个操作（`$W/bt.op` 锁，持有者死了就接管）；忙时写 `error=busy`。
- `ctl/bt.list`：`名字<TAB>MAC<TAB>已配对<TAB>已连接`，已配对的在前；名字去掉控制字符，最多 64 字节。
- `ctl/bt.result`：`state=running|done`、`op`、`mac`、`ok`、`error`（off / busy / badmac / lipc / timeout / failed / notconnected / notpaired / unsupported）、`secs`（预计最长秒数，桌面据此显示进度）。
- `ctl/status` 里多：`btsupported`（有没有 Kindle 蓝牙栈）、`bton`（`BTstate`）、`btswap`、`btbridge`。桌面和下拉面板只在 `btsupported=1` 时显示蓝牙入口；面板的蓝牙圆钮改成“打开蓝牙翻页器页”。
- `lipc-hash-prop` 一定从标准输入喂 `{}`（选项写错会段错误）。5.19.5 的输出格式是 `Hash Index: N` 后面一行一个 `键 = "字符串"` / `键 = (整数)`，
  解析不依赖缩进：`Hash Index` 或同一个键再出现就是下一个设备。
- 5.19 上 `lipc-wait-event` 收到事件时会往控制台写一行（见 `sleep.sh` 的注释）：配对时收到过事件，结束后让显示桥整屏重画一次。

### 按键桥什么时候起（`BT_BRIDGE`）

| `BT_BRIDGE` | 行为 |
|---|---|
| `auto`（默认，新） | 开机**不等**：后台等 Android 的根目录就位，有已配对设备（`ListPaired` 非空）或已有蓝牙输入设备才起 vdbtkeys，把 `veradroid-btkeys` 的节点 mknod 进容器（`event3`，被占用就 `event10`…），EventHub 用 inotify 加上。回到 Android（`input_grab`）时、在桌面配对 / 连接成功后也会起。什么都没配对时不起任何进程 |
| `1` | 和旧版一样：开机时就起，`container.sh` bind 到 `event3` |
| `0` | 不起桥（配对页照样能用） |

晚起的节点记在 `$W/bt.node`，`bt_stop` 删掉。auto 的后台检查记在 `$W/bt.auto`，`bt_stop` 删掉它就是让检查放弃。

### 按键映射

翻页器发什么键都先归成“下一页 / 上一页”，再按 `BT_PT_MAP` 发给 Android：

| 翻页器发的键 | 方向 |
|---|---|
| PageDown、→、↓、音量-、下一曲、空格、回车 | 下一页 |
| PageUp、←、↑、音量+、上一曲 | 上一页 |
| 其他（播放/暂停、返回、Esc、菜单） | 原样 |
| 亮度+/- | 调 Kindle 前光（action.sh light） |
| 电源（Kindle Remote 的“休眠”） | 丢掉，休眠归 Kindle 的 powerd |

| `BT_PT_MAP` | 下一页 / 上一页 发成 | 说明 |
|---|---|---|
| `volume`（默认） | 音量- / 音量+ | 微信读书等阅读 App 的“音量键翻页”都认；不在阅读 App 里时 Android 会调媒体音量（无害） |
| `page` | PageDown / PageUp | 浏览器、部分阅读器 |
| `dpad` | → / ← | 少数只认方向键的 App |
| `raw` | 不改写 | 调试用 |

`BT_PT_SWAP=1` 反转方向。都可以在运行中改：命令 FIFO `bt map volume|page|dpad|raw`、`bt swap 0|1`（写进 `settings.conf`，SIGHUP 让 vdbtkeys 重读，节点不变）。

### 文件

| 文件 | 作用 |
|---|---|
| `host/{pw6,k49}/bin/vdbtkeys` | 桥（静态 armhf，源码 `bluetooth/vdbtkeys.c`） |
| `host/{pw6,k49}/boot/lib/bt.sh` | `bt_start / bt_release / bt_grab / bt_stop / bt_status_lines / bt_cmd` |
| `boot/lib/input.sh` | source bt.sh；`input_start` = 触摸前端 + `bt_start`；`input_release/grab/stop` 先调 `bt_*` |
| `boot/lib/container.sh` | `KFB_BTKEYS` 存在时 bind 到容器 `/dev/input/event3` |
| `boot/lib/cmd.sh` | `bt map …` / `bt swap …` |
| `boot/lib/status.sh` | `$X/ctl/status` 多三行：`bt=0/1`（桥在跑）、`btdev=kind:name,…`（当前接管的设备）、`btmap=` |

运行时：`$W/bt.pid`、`$W/bt.state`（当前设备，vdbtkeys 每次连接 / 断开重写）、`$W/bt.log`（留着做诊断）。
vdbtkeys 和 veradroid-input 一样在 `container_start` 之前起，不在 freezer 组里。`stop.sh` 经 `input_stop → bt_stop`：
SIGTERM，等它自己销毁 uinput 设备、删掉容器里的键盘节点，1 秒不走就 SIGKILL（内核随 fd 关闭销毁 uinput 设备）。

**没有蓝牙的机型什么都不做**：`bt_supported` 看 `/usr/bin/btmanagerd`、`acsbtfd`、`btfd` 有没有；都没有就直接返回，
不起进程、不写日志、`KFB_BTKEYS` 为空、容器里不多绑节点。`BT_BRIDGE=0` 关掉整个桥。

设置（`/mnt/base-us/system/veradroid/settings.conf`）：`BT_BRIDGE`、`BT_PT_MAP`、`BT_PT_SWAP`、`BT_KINDLE_PT`。

## 2. 用户怎么用

1. 在 VeraDroid 里：设置 → Wi-Fi 与蓝牙 → 蓝牙翻页器 → 打开（或下拉面板点“蓝牙”圆钮）。蓝牙关着就先点“打开蓝牙”。
2. 让翻页器进入配对模式（多数是长按开关键或配对键几秒，指示灯快闪），点右上角“扫描”，等它出现在“附近的设备”里，点它 → 配对并连接。
   也可以照旧在 Kindle 自己的“设置 → 蓝牙设备”里配对，回到 VeraDroid 后桥会自己起来。
3. 进微信读书等阅读 App，按翻页器即可（默认 = 音量键翻页；微信读书要在阅读设置里打开“音量键翻页”）。
4. 方向反了：同一页下面“方向”选“反过来”。App 不认音量键：选“翻页键”或“方向键”。
5. 长按已配对的设备 → 取消配对。点已连接的设备 → 断开。
4. 回到 Kindle 界面时翻页器自动还给 Kindle。

## 3. 模拟器里验证了什么

pw6bt-5195（PW6，固件 5.19.5，内核 5.15.41，有 btmanagerd / acsbtfd），装本分支的 `host/pw6/boot` + `bin`（系统镜像是 0.73 的旧 rootfs）。
没有真的蓝牙设备：`bluetooth/fakebt` 用 uinput 建一个 `BUS_BLUETOOTH` 的假设备（翻页器或 127 键键盘）发键，
`BtKeyTest.apk` 在 logcat 里打印收到的 `KEYCODE_*`。结果见第 5 节。

## 4. 没验证的（需要真机，固件 5.20+）

- **真实蓝牙 HID 设备**经 Kindle 的蓝牙栈出现时的总线号、名字、键位（模拟器没有蓝牙控制器，`fakebt` 只是假设 bus=BUS_BLUETOOTH）。
  特别是：有的翻页器报成“键盘”（带全键盘位图却只发两三个键），会被当成键盘克隆原样转发（不改写成音量键）——
  真机上要看实际位图，必要时改判定（比如按名字 `--name-match` 强制当翻页器）。
- 5.20+ 的 `kindle-input-pt`（Kindle Remote 经 input_manager 转发）：模拟器的 5.19.5 没有这个设备；5.20 真机上 input_manager
  已经独占原始设备，vdbtkeys 独占 `kindle-input-pt`，此时它原来 bind 到容器 event2 的那一路收不到键（被改写后从 event3 出来）——要真机确认 Kindle 自己的物理翻页键（Oasis）也没问题。
- 休眠唤醒后蓝牙重连、翻页器省电断开再连（热插拔路径在模拟器里用 fakebt 销毁 / 重建测过）。
- 功耗：vdbtkeys 空闲时 poll 无限阻塞，没有定时器；真机上没测电流。
- 4.9 内核机型（k49）的脚本改动和 pw6 相同，只在 pw6 模拟器上跑过；KT5 / KT6 / PW5 有没有可用的蓝牙 HID 也没确认。
- 桌面（VeraHome）还没有显示 `bt=` / `btdev=` 和 `bt map/swap` 的界面。

## 5. 测试记录（2026-11-11，pw6bt-5195）

测试覆盖主流程，以及开机前已连键盘、`BT_BRIDGE=0` 两种情况。

| 项目 | 结果 | 怎么看的 |
|---|---|---|
| vdbtkeys 随 Android 启动，`veradroid-btkeys` 在容器里是 `/dev/input/event3` | 通过 | 宿主日志 `bt: bridge up`；容器里 `getevent -p` |
| InputReader 认成键盘类、非字母（KeyboardType 1），用 Generic.kl | 通过 | `dumpsys input` |
| 翻页器 8 个键（PageDown/Up、→/←、音量-/+、下/上一曲）→ App 收到 VOLUME_DOWN/UP 交替 | 通过 | BtKeyTest 的 logcat |
| `bt map page` → PAGE_DOWN / PAGE_UP；`bt swap 1` 反向（不重启、节点不变） | 通过 | 同上 |
| `status` 里有 `bt=1`、`btmap=`、`btdev=` | 通过 | `$X/ctl/status` |
| 键盘热插：克隆节点出现在容器、InputReader 加上；断开后节点和设备都消失 | 通过 | 容器 `ls /dev/input`、`dumpsys input` |
| 键盘在 Android 开机前就连着：先挂起，根目录就位后发布；宿主 `/dev/input` 节点一个不少 | 通过 | `bt.log`、宿主 sysfs 对照 `/dev/input` |
| 返回 Kindle（冻结）：桥放开设备，按键不转发，Kindle 侧能读到翻页器 | 通过 | `bt.log` 的 release、evdump |
| 解冻回来：没有积压的键被补发；再按一下能收到 | 通过 | logcat |
| `saver_frozen` 存在时按键丢弃 | 通过 | logcat（只测了标志文件，没有真的进屏保） |
| `BT_BRIDGE=0`：不起进程、容器里没有 event3、`bt=0` | 通过 | `pgrep`、容器 `getevent -p` |
| `stop.sh` 后：没有 vdbtkeys 进程、没有 btkeys / btkbd 输入设备、没有容器挂载、没有 pid / state 文件 | 通过 | `pgrep`、`/proc/bus/input/devices`、`/proc/mounts` |
| 全程 btmanagerd / acsbtfd 的 pid 不变；Android 里没有 `com.android.bluetooth` | 通过 | `pidof`、`ps` |

主流程一共跑了 4 遍。每一遍桥的行为都对；各有一项因为测试脚本本身的问题记了 FAIL，修脚本后该项通过：
dumpsys 的匹配写错（第 1 遍）、连发三条命令后 3 秒就读 status（第 2 遍，模拟器里 lipc 很慢）、键盘节点出现后立刻查 dumpsys（第 3 遍）。
第 4 遍第一下按键 App 收到 3 次 down：模拟器卡顿把 down/up 间隔拉到了 500ms 以上，Android 自己合成了长按重复，
`bt.log` 里桥只转发了 8 次；脚本现在折叠相邻重复后再比。**修完最后这一处之后没有再完整重跑**，所以没有一遍是“脚本原样、全部 PASS”的记录。
真机上按住翻页器不放同样会连翻，这是预期行为。

模拟器不稳定的情况这次没遇到（没有自己重启，/mnt/base-us 没有变只读）。guest 里原来的 0.73 `boot/` + `bin/` 备份在
`/mnt/base-us/veradroid-bak-btport-202611111454.tgz`，现在装的是本分支的脚本，`autoupdate` 已写 0。

## 6. 桌面配对（feat/bt-pair，2026-11-12）

### 真机 PW6 5.20.2（只读 + 扫描，没有配对）

- `com.lab126.btfd` 的属性和 5.19.5 一样多一个 `BTkeepOnInFlightMode`；`kindle-input-pt` 常驻（总线 0006，没配对任何东西时也在）。
  auto 模式只看 `ListPaired` 和总线 0005 的设备，`kindle-input-pt` 不会让桥起来。
- 在宿主上单独跑本分支的 `bt_scan` / `bt_list_write`（不改安装）：解析、列表文件都对。
- **5.20.2 的 `triggerBTscan` 是 Kindle 的“BTCH 向导”**：最多 3 轮“发现约 10 秒 → 自动配对它认可的设备”。
  `BtDiscoveryFilter` 只收 Kindle Remote 的 VID/PID、UUID 匹配（HID / 音频）或 A2DP 的设备，其余 `rejected`，不进 `ListDiscovered`。
  实测一次扫描后它自动对附近的一个音箱发了配对（对方不在配对模式，失败），`ListDiscovered` 里只有这个音箱。
  所以 5.20.2 上：页面里的“扫描” = Kindle 设置里的扫描（行为相同，包括自动配对）；翻页器能不能被列出来取决于 btfd 的过滤（`pageTurnerEnabled`），要真翻页器验证。
  扫描在向导还在跑（`isBtchRunning=1`）时最多等 45 秒。

### 模拟器（假 btfd：`bluetooth/fakebtfd.sh` + `fakebtdev`）

| 机器 | 测试 | 结果 |
|---|---|---|
| pw6bt-5195（5.19.5，装 0.89 + 本分支 bt.sh / cmd.sh / VeraHome 0.27.0） | 主流程 3 遍（扫描、配对、按键、映射 / 方向切换、断开、重连、回 Kindle 不转发 + Kindle 侧掉线重连后回来、屏保期间丢键 + 醒来重连、需确认的设备、取消配对）+ 键盘一次 | 两次完整运行都是 76/76 |
| 同上 | 反例 3 遍（8 种坏 MAC / 注入、缺参数、多余参数、未知子命令、坏映射值、蓝牙关着扫描 / 配对、关开蓝牙、拒绝配对、不存在的设备超时、忙、未配对就连接） | 最终代码 66/66（之前两次的失败是测试脚本的时序问题和“按循环次数算超时”在慢模拟器上超过 70 秒，已改成按墙上时间）|
| 同上 | auto / 0 / 1 开机行为、Kindle 侧配对后回 Android 起桥、stop.sh 无残留 | 14/14 |
| 同上 | 真 acsbtfd（模拟器无控制器，蓝牙关）：空列表、扫描 / 配对 error=off、坏 MAC、状态、btfd 不受影响 | 6/6 |
| pw6bt-5202（5.20.2） | 第 1 遍：扫描、配对、桥起来、Android 看到 btkeys 通过；之后客户机卡住（这台模拟器本次 kcompactd 内核崩溃过一次、重启后 dbus / lab126 没自己起来，手动起的） | 环境问题，不计 |

屏保：模拟器里 powerd 进不了屏保（`powerd_test -p` / `powerButton` 都不行），按 sleep.sh 的做法用 `saver_frozen` 标志模拟。

## 7. 真机 PW6 5.19.5（2026-11-13）

- `bt enable`：BTstate 1，1 s 内完成。`bt scan` 两轮：附近只有一台陌生设备（一台 LG 电视），正确列出。
- **问题**：第一次扫描时 Kindle 的 BTCH 向导在第 12 秒**自己配对并连上了这台电视**（系统日志 `acebt_pair` → `bondState:2`），
  列表里显示已配对、已连接。当场用 `bt disconnect` / `bt unbond` 撤掉（各 1 次成功，之后 ListPaired 为空）。
- 修：`bt_scan` 记下扫描前已配对的设备，扫描中和结束时发现新冒出来的已配对设备就断开并取消配对（`bt_undo_autopair`），
  配对只在用户点“配对”（`bt bond`）时发生。改后又扫了 2 次：向导没再配对，列表 0 已配对。撤销那条路径这两次没有被触发过。
