# 系统瘦身 / 低内存模式 / Kindle 界面处置（feat/slim，2026-11-11）

所有数字都在 eink-emulator 上测得（`kt5-5192`、`pw5-5192`：485 MB 内存、2 核、4.9 内核、32 位 binder、VeraDroid 0.94）。
模拟器比真机慢约 8–25 倍，而且开机时间随宿主机负载在 83–188 秒之间漂移（同一配置！），**只有同一时间段、同一台机器的对比才有意义，
小于约 10 % 的开机时间差别这里分辨不出来**。真机（PW6）数字只引用任务书给的那几个，没有在真机上做任何操作。

## 1. 结论（先看这个）

| 项目 | 需要重编？ | 实测效果 | 状态 |
|---|---|---|---|
| Android 运行期间停掉 Kindle 的 Java 框架 + 书库程序（`KINDLE_UI=stop`，512 MB 机型自动） | 否 | **MemAvailable +60～70 MB**（kt5：211–218 → 284 MB；pw5：219 → 280 MB），交换区多空出 30–80 MB；Kindle 侧常驻 77 → 35 MB | 已实现，模拟器上电源键 / 屏保 / 返回 / 再进 / 崩溃恢复都验证过 |
| 不起 media.codec / media.drm / media.extractor（init） | 否 | 进程 22 → 19，**常驻约 −5.5 MB**（2.2 + 1.9 + 1.4），binder 服务少 3 个 | 已实现、已测 |
| bootanim 换成 `/system/bin/true` | 否 | 开机少装载一次 Android 运行时；时间差在噪声内 | 已实现、已测 |
| `config.disable_*` 7 个属性 + `ro.zygote.disable_gl_preload` | 否 | system_server 的 binder 服务 103 → 93；system_server PSS 无可见变化（49.0 vs 49.1 MB）；不再每次开机 “Auto-enabling Bluetooth” 绑定失败 | 已实现、已测 |
| 挪走 4 个用不上的系统应用（CtsShim×2、WallpaperBackup、BackupRestoreConfirmation） | 否 | 系统包 19 → 15，扫描时间差在噪声内 | 已实现、已测 |
| 关掉开机 / 挂载时的整盘媒体扫描（MediaScannerReceiver） | 否 | 开机后少一轮全盘扫描的 CPU（没有单独量出数字） | 已实现，`pm disable` 生效已确认 |
| 以上几项合计的开机时间 | 否 | 同机安静时段：kt5 90.0 → 82.6 s（−8 %），pw5 96.5 → 95.6 s（−1 %）；并行对照 4 组里 3 组 slim 略快。**不能算确证的提速** | — |
| 精简 preloaded-classes（4165 → 3898 个类，去掉电话 / 蓝牙 / NFC / 相机 / 音视频 / 打印 / OpenGL 等） | 是 | boot*.art 合计 10.50 → 10.09 MB（−0.4 MB）；运行效果未测（见 4） | 补丁在分支里，已编过（BUILD-EXIT=0），未装机验证 |
| LocationManagerService 不再因为没有 fused provider 中止初始化 | 是 | 去掉每次开机的 “BOOT FAILURE Notifying Location Service running” wtf；是修正不是提速 | 同上 |

诚实的总评：**这个镜像本来就配得不差**（boot 镜像和所有系统应用都是 speed 预编译 + PIC、已经用 compiled-classes 限制、`ro.config.low_ram`、
堆参数按机型改），Android 这一侧不重写框架能再挤出来的只有几 MB 和几个进程。512 MB 机型上真正的大头在 Kindle 那一侧：
Android 运行时 Kindle 的 Java 框架（cvm）还占着 38 MB 常驻 + 58 MB 交换区，把它停掉比 Android 侧所有裁剪加起来大十倍。

另外发现两件和瘦身无关、但应该让大家知道的事：
- **构建机源码树里的 `device/veradroid/kindle/overlay/.../config.xml` 被蓝牙那边的改动整个换掉了**，
  `config_enableWallpaperService=false` 没了（现在只有 `config_bluetooth`）。从共享树重新编出来的镜像会回到“WindowManager 等壁纸 30 秒才开机”。
  仓库里的版本是对的；合并蓝牙的 overlay 时要两项都留。
- `sleep_watch` 每秒一次的 `lipc-get-prop com.lab126.powerd state` 没带 `-s`，Kindle 的 syslog 里每秒两行
  “Property found but with a differnt type / LIPC access error”。加 `-s` 就没有了（没改，属于 sleep.sh）。

## 2. 清单

判定：需要 / 不需要（阅读器用不上）/ 不确定（留着）。常驻内存是 kt5 开机后 90 秒的 `dumpsys meminfo` PSS。

### 2.1 原生守护进程

| 进程 | PSS | 判定 | 原因 / 处置 |
|---|---|---|---|
| init | 1.2 MB | 需要 | |
| zygote | 18.7–19.7 MB | 需要 | 预加载的类和资源，所有应用共享 |
| system_server | 47–49 MB | 需要 | 见 2.2 |
| surfaceflinger | 13.6–21 MB | 需要 | 软件合成，帧缓冲占大头 |
| servicemanager | 0.5 MB | 需要 | |
| logd | 1.3 MB | 需要 | 诊断日志、开机进度条都读它 |
| installd | 0.6 MB | 需要 | 安装 APK |
| netd | 1.3 MB | 需要 | 以太网服务、DNS |
| vold + sdcard | 1.4 + 1.4 MB | 需要 | MountService 靠 vold 挂 /storage/emulated（FUSE）；0.94 里它们在跑，和早期笔记“没有 vold”不一样 |
| keystore | 0.9 MB | 需要 | TLS 客户端证书、应用的 AndroidKeyStore |
| audioserver | 2.3 MB | 需要 | 没有它 AudioService 永远等 `media.audio_policy` |
| lmkd | 0.6 MB | 需要 | 512 MB 机型靠它（和内核 LMK）的阈值 |
| healthd | 0.4 MB | 需要 | BatteryService 的数据来源 |
| gatekeeperd | 0.7 MB | 不确定，留着 | LockSettingsService 会找它；省 0.7 MB 不值得冒险 |
| debuggerd (+signaller) | 0.3 + 0.3 MB | 不确定，留着 | 应用崩溃的 tombstone，排障要用 |
| **media.codec** | 1.4 MB | 不需要 | 只有通过 mediaserver 才用得上，而 mediaserver 早就 disabled → **slim 停掉** |
| **mediadrmserver** | 2.2 MB | 不需要 | 同上 → **slim 停掉** |
| **media.extractor** | 1.9 MB | 不需要 | 同上 → **slim 停掉** |
| cameraserver / drmserver / mediaserver / perfprofd | — | 不需要 | 已经 disabled（init.kindle.rc） |
| bootanimation | — | 不需要 | 每次开机被 SurfaceFlinger 拉起来再退出 → **slim 换成 true** |
| ueventd | — | 不需要 | 已经 `stop ueventd` |
| 以后要做蓝牙音频 / 听书的话 | | | mediaserver + 上面三个要一起放回来（`SLIM=0`，或者从 slim.sh 的 rc 块里去掉） |

### 2.2 system_server 里的服务（7.1.1 的 SystemServer.java 逐段核对）

始终需要、没有开关：Installer、ActivityManager、PowerManager、Lights、DisplayManager、PackageManager、UserManager、Battery、UsageStats、
WebViewUpdate（WebView）、SchedulingPolicy、TelephonyRegistry（应用注册 PhoneStateListener 时不能是 null）、EntropyMixer、AccountManager、
ContentService、系统 Provider、Vibrator、AlarmManager、Watchdog、InputManager、WindowManager、InputMethodManager（VeraIME）、Accessibility、
MountService（/sdcard）、UiMode、Notification（通知）、DeviceStorageMonitor、DropBox、AudioService、JobScheduler（下载）、
NetworkManagement / NetworkStats / NetworkPolicy / Connectivity / Ethernet（联网）、ShortcutService、LauncherApps、MediaSession、Restrictions。

| 开关（属性） | 跳过什么 | 用不用 | 原因 |
|---|---|---|---|
| `config.disable_bluetooth` | BluetoothService | **用**（镜像里没有 Bluetooth.apk 时） | 0.94 的 k49 镜像带了蓝牙 feature 却没有蓝牙应用，每次开机自动“打开蓝牙”再绑定失败；有 Bluetooth.apk 的镜像 slim.sh 不设它 |
| `config.disable_rtt` | Wi-Fi RTT 测距 | **用** | |
| `config.disable_mediaproj` | 录屏 / 投屏 | **用** | VeraHome 的截图走 `screencap`，不走它 |
| `config.disable_serial` | 串口服务 | **用** | |
| `config.disable_samplingprof` | 采样分析器 | **用** | |
| `config.disable_networktime` | NTP 校时 | **用** | 时间归 Kindle；容器和 Kindle 共用时钟，Android 不该去改 |
| `config.disable_otadexopt` | A/B OTA dexopt | **用** | |
| `config.disable_noncore` | LockSettings、DeviceIdle、DevicePolicy、**剪贴板**、TextServices、SearchManager、DockObserver、USB、备份、AppWidget、语音、Dreams、GraphicsStats、MediaRouter、Trust、后台 dexopt… | 不用 | 一刀砍掉剪贴板和 DevicePolicy，应用 `getSystemService` 拿到空壳会崩 |
| `config.disable_location` | LocationManager、CountryDetector | 不用 | `LocationManager` 会包着一个空 binder，应用一调就 NPE（广告 / 统计 SDK 常调） |
| `config.disable_network` / `disable_storage` | 整个网络栈 / MountService | 不用 | 必需 |
| `config.disable_systemui` / `searchmanager` / `trustmanager` / `textservices` | StatusBarManager / 搜索 / Trust / 拼写检查 | 不用 | 各省不到 1 MB，换来 null 服务的风险 |

没有开关、想跳过只能改源码的：Wi-Fi 三件套（WifiService 2.7 s、WifiP2p 0.8 s、WifiScanning——模拟器时间，真机约十分之一）、
TelecomLoader、CameraService 代理、VrManager、ConsumerIr、SoundTrigger、Print、MmsServiceBroker。**没有做**：
`WifiManager` / 这些 Manager 在服务缺席时都是包着空 binder 的对象，微信读书这类应用会调 `getConnectionInfo()`；
换来的是真机上零点几秒和 1–2 MB，不值。

### 2.3 系统应用（`pm list packages -s`，0.94 共 19 个）

| 包 | 判定 | 原因 / 处置 |
|---|---|---|
| android（framework-res）、com.android.providers.settings、com.android.shell | 需要 | |
| com.veradroid.home、com.veradroid.ime | 需要 | 桌面 33 MB / 输入法 14 MB（输入法没有预编译 odex：`system/app/VeraIME` 下没有 oat，建议在它的 Android.mk 里打开 dexpreopt） |
| com.android.webview | 需要 | 微信读书、EinkBro |
| com.android.packageinstaller | 需要 | PackageManager 要求“恰好一个安装器”，缺了开不了机 |
| com.android.defcontainer | 需要 | 安装 APK 时才起进程 |
| com.android.providers.downloads、com.android.providers.media | 需要 | 应用的 DownloadManager / MediaStore；进程 android.process.media 开机后是可回收的 cached 进程（15–19 MB） |
| android.ext.services、android.ext.shared | 需要（包必须在） | PackageManager 启动时要求这两个共享库；ext.services 的进程已经被 afterboot `pm disable-user` |
| **com.android.statementservice** | **需要（不能删！）** | 实测：挪走后 system_server 开机即崩（“There must be at least one intent filter verifier”），无限重启。已从名单里去掉，slim.sh 会自动把它放回去 |
| com.android.inputdevices | 需要 | 键盘布局（蓝牙翻页器） |
| com.android.htmlviewer | 不确定，留着 | 不常驻；本地 html 的查看器，这次还拿它当 WebView 冒烟测试 |
| **com.android.cts.ctsshim、com.android.cts.priv.ctsshim** | 不需要 | CTS 空壳 → **slim 挪走** |
| **com.android.wallpaperbackup** | 不需要 | 壁纸服务已关 → **slim 挪走** |
| **com.android.backupconfirm** | 不需要 | adb 备份确认界面（产品 mk 里的 filter-out 对继承来的包不起作用，所以它一直还在）→ **slim 挪走** |

### 2.4 Android 在前台时 Kindle 这一侧还在跑什么（kt5，`/proc/*/smaps` 的 PSS / Swap，容器外）

默认（keep，书库程序已停）：合计 **PSS 77 MB + 94 MB 在交换区**，90 个进程。

| 进程 | PSS | 交换区 | 说明 |
|---|---|---|---|
| cvm（Java 框架，upstart `framework`） | 38.2 MB | 58.3 MB | 最大的一块 → `KINDLE_UI=stop` 停掉 |
| veradroid-epd（我们自己的显示桥） | 10.8 MB | 0 | 帧缓冲副本 |
| pillowd | 4.3 MB | 5.8 MB | 已 disable，没停进程 |
| Xorg / awesome（SIGSTOP） | 2.9 / 2.9 MB | 2.1 / 1.0 MB | |
| dbus-daemon、init、fastmetrics、appmgrd | 1.9 / 1.5 / 1.4 / 1.3 MB | | fastmetrics 跟着框架停 |
| 其余 80 个（powerd、wifid、cmd、btmanagerd、volumd…） | 各 <1 MB | | 不动 |

`KINDLE_UI=stop` 之后：合计 **PSS 35 MB + 33 MB 在交换区**，78 个进程；MemAvailable 218 → 269（手工停）/ 284 MB（脚本完整流程）。

## 3. 不用重编的改动（宿主脚本，可以直接合）

### 3.1 `boot/lib/slim.sh`（pw6 和 k49 同一份文件）
- `slim_apply`（`zram_on` 之后、容器启动之前）：在系统盘的 `init.kindle.rc` 和 `system/build.prop` 里各维护一段
  `# >>> vd-slim … # <<< vd-slim`（内容不变不写盘，文件保持 644）；把 `SLIM_PRUNE` 里的系统应用挪到 `$SYS/slim-removed/`。
- `slim_after_boot`（afterboot 的“每个版本一次”段里）：`pm disable com.android.providers.media/.MediaScannerReceiver`。
- 设置 `SLIM=1`（默认）/ `SLIM=0`（把两段删掉、应用挪回去）。排障时也可以写 `/mnt/base-us/veradroid/slim`（0 / 1），系统盘没挂上也能改。
- 用 slim 产品编出来的镜像（`ro.vd.slim=1`）自带 rc 和属性，slim.sh 只做挪应用。

### 3.2 Kindle 界面处置：`KINDLE_UI=auto|keep|freeze|stop`（`lib/framework.sh`，pw6 和 k49 完全相同；`lib/settings.sh` 只差原有的 hostnet 段）

| 值 | 做什么 | 内存 | 返回 Kindle |
|---|---|---|---|
| keep | 以前的做法：pillow 关、awesome / volumd SIGSTOP、停 mtp stored webreader kfxreader kfxview todo tmd rcm archive scanner (statusbar) | 不变 | 快 |
| freeze | keep + SIGSTOP `FW_FREEZE_PROCS`（只有 KPPMainApp），返回前 SIGCONT | 不腾内存，CPU 也省不出可见的量 | 快（模拟器 20 秒） |
| stop | keep + 停 upstart 任务 `framework`（cvm）和 `kppmainapp`；跟着框架停掉的任务回来时逐个起回去；`bin/vdkaf` 顶替 `com.lab126.kaf` | **+60～70 MB**（kt5 / pw5 模拟器） | 模拟器上 stop.sh 102 秒返回、170 秒后书库完全就绪（真机应快得多，按“约一分钟”提示用户）；返回 = 完全退出 Android |
| auto（默认） | 低内存模式 → stop，否则 → freeze | | |

- **冻结比想象的危险**（kt5，按一下电源键到 powerd 进屏保）：什么都不冻 0.7 秒；冻 KPPMainApp 0.6 秒；
  **冻 fastmetrics 64 秒**，期间 powerd 自己的 lipc 属性全部 `lipcErrTimedOut`（它同步给 fastmetrics 报指标）；
  **冻 cvm 46 秒以上没有反应**。SIGCONT 之后都立刻恢复。所以名单里只有 KPPMainApp。任务书里列的 weblabdaemon / minerva_service /
  KindleDocumentIndexerService / KindleSyncService 在模拟器镜像里不存在，没法做同样的测试，**没有放进名单**。
  考虑到真机上 Kindle 这一侧本来就几乎不占 CPU，freeze 实际上省不出东西；PW6 想要内存只能用 stop（代价是返回要等框架重启）。
- **框架停了电源键失灵，是真的**：实测 `stop framework` 之后 `powerd_test -p` 不进屏保；`bin/vdkaf`（`tools/vdkaf/vdkaf.c`，
  自己写的，只用 liblipc 的三个公开函数，动态链接 Kindle 自己的 liblipc.so）发布 `frameworkStarted=1` 之后 2 秒内进屏保、再按唤醒。
  vdkaf 起来后有自检：2 秒后读不到 `frameworkStarted=1` 就把框架起回去；没有 vdkaf 可执行文件时 stop 退回 keep。
- 恢复只有一个入口 `framework_start`，按 `$FWD`（tmpfs）里的记录恢复，不看当时的设置：`stop.sh`、冻结返回、容器意外退出后看门狗调的 `stop.sh` 都走它。
- upstart 重启计数：`fw_clear_restart_counters` 现在覆盖固定名单 + 这次实际停掉的 + 跟着框架停掉后由我们起回去的每一个任务。

### 3.3 低内存模式：`LOWMEM=auto|on|off`（`lib/settings.sh` 的 `lowmem`）
- auto = MemTotal < 700 MB。生效时：`KINDLE_UI=auto` 取 stop；书库程序停掉；`RETURN_MODE` 默认 off（stop 时强制 off）；
  翻页动画默认关（用户自己设过就不动）；afterboot 的“低内存”那批 `pm disable` 和动画归零。
- 512 MB 内核上跑起来的前提（overcommit、内核 LMK / lmkd 阈值、zram 扩容、128m/192m 堆）只看实际内存，`LOWMEM=off` 也照做——它们不是“模式”。
- 状态文件 `/dev/kfb/ctl/status` 新增 `lowmem=`、`lowmem_setting=`、`kindleui=`、`memtotal_mb=`、`memavail_mb=`；
  `/dev/kfb/settings` 发布 `LOWMEM`、`KINDLE_UI`，桌面写 `ctl/settings.new` 可以改（只接受合法值）。**桌面（VeraHome）那边的显示和开关没有做。**

## 4. 需要重编的部分（补丁在分支里）

- `android/device/veradroid/kindle/slim.mk` + 产品 `veradroid_kindle_slim`、`veradroid_kindle32_slim`：
  精简的 preloaded-classes（`android/gen-slim-preloaded-classes.py` 生成，同时是 boot 镜像的 image-classes）、
  `init.kindle.slim.rc`（init.kindle.rc 顶上加了一行 `import`，普通镜像里文件不存在，init 只记一行日志）、属性。
- `android/small-patches.py`：LocationManagerService 找不到 fused provider 时记日志继续，而不是抛异常让初始化停在半路。
- 编法：用单独的源码树副本和输出目录（文件系统支持时用 reflink 副本），容器里挂到 `/aosp/src`、`/aosp/out32`，第一次就是增量编译。
- 已编：`veradroid_kindle32_slim-userdebug`，1781 步约 12 分钟，`BUILD-EXIT=0`，rootfs 包 127 MB。
  **没有装到模拟器上验证**：0.94 的 k49 系统盘不是 out32 的直接产物（另换了 libandroid_runtime.so 和 VeraHome），
  整盘替换比较的就不只是 slim 了；而且预期收益只有 boot.art −0.4 MB。要验证的话：`lunch veradroid_kindle32_slim-userdebug` 编出来，
  再用正常的打包流程把这个 rootfs 换进候选包。
- 试过、不建议做的：dex 预编译设置（已经是 speed + compiled-classes，没有可调的）、512 MB 的堆 / zygote 设置（宿主 heap_fix 已经按机型写）、
  SystemServer 跳服务的补丁（见 2.2）。
- 产品 mk 里 `PRODUCT_PACKAGES := $(filter-out …)` 对继承来的包不起作用（BackupRestoreConfirmation 一直还在镜像里就是证据），
  所以“删包”放在宿主（slim.sh 挪走）而不是 mk 里。

## 5. 测量方法和原始数据

- 测量脚本（未收入仓库）：`guest-measure.sh`（停 → 等 Kindle 界面安静 → drop_caches → 启动 → boot_completed 后 90 秒采集）、
  `ab.sh`（同一台机器 slim=1/0 交替）、`guest-hostps.sh`（Kindle 侧每个进程的 PSS / Swap）、`guest-smoke.sh`、`guest-lowmem.sh`、`guest-crash.sh`。
- 采集用的命令：`logcat -b events -d | grep boot_progress`、`ps`、`service list | wc -l`、`dumpsys -t 120 meminfo`、`/proc/meminfo`、
  `pm list packages -s/-d`、`/proc/<pid>/smaps`。

开机时间（容器启动 → `boot_progress_enable_screen`，秒）。第 2 轮正赶上宿主机上的 AOSP 编译，两台都慢了一倍：

| 轮次 | kt5-5192 | pw5-5192 |
|---|---|---|
| 1 | slim 118.1 | 原样 123.7 |
| 2（宿主机在编译） | 原样 188.0 | slim 184.2 |
| 3 | slim 82.6 | 原样 96.5 |
| 4 | 原样 90.0 | slim 95.6 |
| slim + 挪应用 + KINDLE_UI=stop | — | 96.7 |

开机后 90 秒（第 3 / 4 轮，安静时段）：

| | kt5 原样 | kt5 slim | pw5 原样 | pw5 slim | pw5 slim + stop |
|---|---|---|---|---|---|
| 容器内进程数 | 22 | 19 | 22 | 19 | 19 |
| binder 服务数 | 103 | 93 | 103 | 93 | 93 |
| used PSS（dumpsys） | 127.4 MB | 122.6 MB | 119.5 MB | 124.0 MB | 136.3 MB |
| MemAvailable | 211.0 MB | 215.3 MB | 219.1 MB | 220.5 MB | **279.9 MB** |
| SwapFree | 186.3 MB | 193.8 MB | 142.0 MB | 133.8 MB | 226.8 MB |

（PSS 不含被换出的页，所以交换区越空 PSS 反而越高：pw5 那三列不能直接比 PSS，看 MemAvailable 和 SwapFree。）

## 6. “不能坏”的清单（都只在模拟器上做，真机一项也没碰）

| 项目 | keep | freeze（KPPMainApp） | stop | 说明 |
|---|---|---|---|---|
| 电源键 → 屏保 → 再按唤醒（Android 在前台） | 通过（kt5） | 通过：2 秒内进屏保、再按唤醒（kt5；第一版名单带 fastmetrics 时要 12 秒） | 通过：2 秒内进屏保，Android 冻结 / 解冻日志正常（kt5） | 用 `powerd_test -p` 模拟按键，测试时临时把模拟器的 preventScreenSaver 置 0 |
| 返回 Kindle | 通过 | 通过，23 秒，没有进程留在 T 状态（kt5） | 通过：stop.sh 102 秒返回，170 秒书库就绪；跟着框架停掉的任务全部回来（前后 `initctl list` 无差别）（kt5） | 都是模拟器时间 |
| 再次进入 Android | 通过 | 通过 | 通过（kt5 连续两轮，pw5 一轮） | |
| Wi-Fi | 通过 | 通过 | 通过：wifid / wifim / cmd 没动；Android 里 ping 外网通（kt5、pw5） | 模拟器上 `cmState` 一直是 PENDING（进 Android 之前就是），真机要看一眼 |
| 电量 / 充电 | 通过 | 通过 | 通过：`battLevel` / `isCharging` 读得到，状态文件正常 | 没法在模拟器上插拔充电器 |
| upstart 重启计数 | 通过 | 通过 | 通过：Android 运行期间 `*.restarts` 文件为空；返回后只有 stored 的 1（和以前一样，下次进出时清） | 新增的每个任务都走 `fw_clear_restart_counters` |
| Android 崩溃（kill -9 容器 init） | 未单独测（路径相同） | 未单独测（路径相同） | 通过：看门狗发现后自己 stop.sh，vdkaf 退出、框架和书库程序回来、没有进程留在 T 状态（pw5，396 秒） | |
| 宿主脚本自己被 kill -9（看门狗也死了） | 未测 | 未测 | 未测 | 和以前一样没有兜底：pillow / awesome 那一批也会停着，重启 Kindle 恢复 |
| Kindle 关机 / 重启时（`--shutdown`） | 未测 | 未测 | 未测 | 代码里加了 `vdkaf_stop`，没有跑过 |
| PW6（5.15 内核、64 位 binder）上的任何一项 | 未测 | 未测 | 未测 | 我的两台模拟器都是 4.9 / k49。pw6 的脚本和 k49 同一份 framework.sh，但没有在 PW6 模拟器或真机上跑过 |

## 7. 512 MB 机型的“微信读书很卡”：LOWMEM / KINDLE_UI 实测（2026-11-12，进行中）

背景：PW5（512 MB、4.9 内核）用户报告 VeraDroid 能开、微信读书能装，但“几乎没法用，很卡”。
机器：eink-emulator `pw5-5192`、`kt5-5192`（485 MB、2 核、4.9 内核），宿主脚本 = 本分支合并 main 之后的 `host/k49`。
**模拟器比真机慢 3–5 倍以上，而且这次宿主机上同时跑着另外 3 台模拟器（load 7–15），时间数字噪声很大；
缺页数、交换次数、直接回收次数、被杀进程数不受这个影响，比时间可信。**

### 7.1 测量方法上的一个坑

`am start -W` 的 WaitTime（以前记的“约 11–13 秒”）其实是 **AMS 10 秒启动超时**（输出里 `Status: timeout`）：
微信读书先起 `LauncherActivity`，再起 `WeReadFragmentActivity`，`-W` 等不到就按超时返回。真实时间改用 events 日志
（`am_create_activity` LauncherActivity → `am_on_resume_called` WeReadFragmentActivity，同一单调时钟）。

### 7.2 结果：同一台 pw5-5192，LOWMEM=off + KINDLE_UI=keep 对 LOWMEM=on + KINDLE_UI=stop

冷启动（每种配置重启 Android 两次、每次清缓存冷启动 3 次，共 6 次；数字是模拟器秒数，kB 换算成 MB = /1024）：

| pw5-5192 | LOWMEM=off, KINDLE_UI=keep | LOWMEM=on, KINDLE_UI=stop |
|---|---|---|
| 到主界面 onResume（6 次） | 310 / 141 / 180 / 217 / 165 / 131 s，**中位 173 s** | 186 / 136 / 68 / 81 / 97 / 70 s，**中位 89 s** |
| 主 Activity 创建 | 33–72 s，中位 42 s | 28–52 s，中位 39 s |
| 启动后 30 s 微信读书主缺页（majflt） | 3708–7999，中位 4753 | 1470–2661，中位 2007（−58 %） |
| 同期全系统主缺页 | 6628–12884，中位 8596 | 2095–3899，中位 2587（−70 %） |
| 启动后 30 s SwapFree | 41–58 MB | 179–210 MB |

3 分钟脚本操作（`guest-weread.sh`：切 4 个底栏标签、上滑、回桌面、再打开，6 轮；keep 第 3 轮被 90 分钟总超时截断，只有 2 轮完整）：

| pw5-5192 | keep（2 轮） | stop（3 轮） |
|---|---|---|
| 主界面后 60 s：MemAvailable | 150 / 221 / 221 MB | 213 / 254 / 255 MB |
| 主界面后 60 s：SwapFree | 101 / 48 / 44 MB | 222 / 179 / 178 MB |
| 操作完：SwapFree | **34 / 34 MB**（256 MB zram 几乎用满） | 171 / 171 / 171 MB |
| 每轮全系统 换入页 / 直接回收次数 / 主缺页 | 13943 / 1444 / 65521；15243 / 1728 / 62445 | 2774 / 716 / 15827；2023 / 414 / 9759；1370 / 382 / 8310 |
| 每轮结束时微信读书累计主缺页 | 23852 / 21420 | 7958 / 4880 / 4253 |
| 被杀 / ANR | 第 1 轮 **VeraIME 因后台 ANR 被杀**，ANR 2 次 | 0 |
| 内核 LMK / OOM | 0 | 0 |

结论：在 512 MB 上 keep 模式的问题不是“进程被杀”，而是 **一直在换页**：交换区满、每轮操作几万次主缺页、上千次直接回收，
输入法都会 ANR——这正是“卡”。stop 把 Kindle 的 Java 框架那 ~60 MB 让出来以后，换入少 5–10 倍、主缺页少 4–7 倍、直接回收少 2–4 倍，
冷启动中位数快一倍。

### 7.3 其他便宜的调整

| 项目 | 结果 | 处理 |
|---|---|---|
| read_ahead 4 vs 128（4.9 内核） | 上一轮（同一台 pw5，旧树）：启动后 60 s 微信读书 majflt，keep 14818 / 15288 / 15539 → 1083 / 2904；stop 14313 / 14217 / 13795 → 1705 / 1826 / 1884（**约 8 倍少**）。本轮确认 `readahead_on` 在 4.9 上把 mmcblk0 / loop0 / loop1 都改成了 128。模拟器的“磁盘”在宿主机页缓存里，缺页几乎不花时间，所以模拟器上看不出时间差；真机 eMMC 上每次缺页是一次真实读盘（PW6 真机实测冷启动 −30 %） | main 已有，不动 |
| zram 算法 | 内核只有 lzo / deflate，lzo 已是快的那个 | 不动 |
| zram 大小 | 已扩到 256 MB；stop 时操作完还空 171 MB，keep 时满 | 不动 |
| `extra_free_kbytes` | 这个内核没有；对应的是 `watermark_scale_factor`（默认 10） | 加了实验开关 `VM_WATERMARK`（默认不动），没来得及测 |
| swappiness 40 vs 100（kt5，stop，各 3 轮） | 每轮微信读书主缺页 s40：3127 / 3641 / 3284 → s100：2526 / 2557 / 2286（−25 %）；每轮全系统直接回收 817 / 826 / 489 → 388 / 314 / 323；全系统主缺页 5381 / 6761 / 5670 → 4368 / 5443 / 4847 | 见 7.4 |
| Java 堆（heap_fix 8m/128m/192m） | 微信读书前台时 PSS 83–92 MB，没有碰到上限，也没有 OOM；改它没有依据 | 不动 |
| 前台阅读时其他进程 | stop 模式下：VeraHome（persistent）15–16 MB、VeraIME 6 MB、android.process.media（cached）5–6 MB、system_server 34–41 MB。VeraHome 是 persistent，宿主没法把它请出内存；改它要动 VeraHome 本身 | 不动（记一笔） |
| 微信读书的编译方式 | 镜像 `pm.dexopt.install` 和 `bg-dexopt` 都是 interpret-only：装好的应用永远靠解释器 + JIT。kt5（stop）上 `cmd package compile -m speed-profile`：冷启动到 onResume 114 / 58 / 93 → 83 / 56 / 64 s，启动期间微信读书 CPU 99 / 68 / 82 → 52 / 47 / 46 s（−40 %）；编一次 556 s（模拟器），odex 80 MB | 新增 `slim_aot`（见 7.4） |

### 7.4 改了什么（宿主脚本，pw6 / k49 两棵树相同）

- **512 MB 机型 swappiness 40 → 100**（`lib/memory.sh`，`lowmem_ram` 判定；PW6 不变；`VM_SWAPPINESS` 仍可覆盖）。依据：kt5 上 3 轮脚本操作，
  微信读书主缺页 −25 %、直接回收减半；pw5 上冷启动到 onResume 81 / 97 / 70 s → 62 / 65 / 45 s（同一时段，宿主机负载略低，打折看）。
  真机上这个方向只会更有利：模拟器里文件页缺页几乎不花钱（磁盘在宿主机缓存里），真机 eMMC 上每次都是读盘，而 zram 解压是内存操作。
- ~~`slim_aot`~~：我先在本分支写了一个“用过的第三方应用开机 5 分钟后 speed-profile 编译一次”的 `slim_aot`，kt5 上走真实路径验证过
  （开机 5 分钟后自动编，interpret-only → speed-profile）。合并 main 时发现 main 已经有更完整的 `lib/compile.sh`（APP_COMPILE，
  speed 过滤器、电量 / 内存 / 冻结门槛、桌面进度显示），**两者会抢着编同一个应用，所以 slim_aot 删掉了，用 main 的**。
  上面 kt5 的 speed-profile 数据（启动 CPU −40 %）可以作为 compile.sh 在 512 MB 机型上也该开的旁证；speed 和 speed-profile 在 512 MB
  上谁更合适（speed 的 odex 更大、dex2oat 峰值约 200 MB）没有对比测。
- `VM_WATERMARK` 实验开关（`watermark_scale_factor`，默认不动），没有测。

### 7.5 KINDLE_UI=stop 的边界情况（`guest-edge.sh`，每台 3 轮进出 + 3 次崩溃）

每轮：开 Android → 确认框架停了、vdkaf 应答 → 电源键进屏保（Android 冻结）→ 再按唤醒（解冻、Android 应答）→ 返回 Kindle →
书库回来、开机前在跑的 upstart 任务全部回来、没有 T 状态进程。崩溃：开 Android → `kill -9` 容器 init → 看门狗自己把 Kindle 界面恢复。

| | pw5-5192 | kt5-5192 |
|---|---|---|
| 3 轮进出（每轮 9 项） | 27 / 27 通过；屏保 2.4 s、唤醒 6.3 s、返回后书库就绪 43–70 s | 22 / 27：5 项失败全在电源键 / 冻结的计时检查上（见下），返回 Kindle、任务恢复、无 T 进程 9 / 9 |
| 3 次崩溃（每次 5 项） | 15 / 15 通过；Kindle 自己回来 146 / 155 / 265 s | 15 / 15 通过；248–948 s（宿主机上同时跑着 9 台模拟器） |
| 低电量 | 模拟器没法模拟电量（`powerd_test` 只能按电源键），**没测** | 同左 |

kt5 的 5 项失败：第 2、3 轮 kt5 的开机要 540–800 s（宿主机负载 14–16，9 台模拟器），powerd 自己的 `state` 属性读超时（`lipcErrTimedOut`），
按键后 30 s 才进屏保，检查时 Android 还没冻；唤醒后冻结组要等 watchdog 线程放开 4 s 才解冻，检查只等了 4 s。为了分清是 stop 模式的问题还是负载，
在 kt5 上单独按了 5 次（`guest-pk.sh stop 5`）：第 1 次 12 s 进屏保（之后才冻结），第 2–5 次 0.8–3.9 s 进屏保、Android 冻结、0.4–0.7 s 唤醒、3 s 后解冻，
没有 lipc 超时。同一时段 pw5 上 **keep 模式**（vdkaf.bad 之后）也出现了同样的 powerd 超时、26 s 才进屏保。所以判断是模拟器负载，不是 stop 模式；
keep 的 5 次对照因为 kt5 ssh 连不上没有跑成。另外：stop 时 powerd 每次按键都向 `com.lab126.minervad` 报指标，对方不在（ServiceUnknown，立即返回，不阻塞）。

### 7.6 vdkaf 失败路径（`guest-fallback.sh`：把 bin/vdkaf 换成立刻退出的脚本）

pw5-5192 一共 4 轮（第 1 轮 + 3 轮重复），结果一致：
- 自检 12 秒后记 `vdkaf is not answering … falls back to keep`，模式记成 stopfail，`vdkaf.bad` 写入 `Kindle 5.19.2 … 52`（固件 + 文件大小），
  框架重新起来（cvm 新 pid）；**Android 仍在前台**（截图是 VeraHome，Kindle 界面没有盖上来），MemAvailable 210 MB。
- **框架重启期间电源键无效**：回退后马上按电源键，4 / 4 次 25–27 秒内都没有进屏保——重启的框架还没发布 `frameworkStarted=1`（读到 0），
  和“框架停着”是同一个原因。框架报“已启动”（回退后再等 3–77 s，模拟器）以后按：3 / 3 次 3.6–5.2 s 进屏保、Android 冻结，3.5–5.4 s 唤醒。
  真机框架冷启动约半分钟到一分钟，这段时间电源键不灵；只在某个固件第一次回退时发生一次（之后 vdkaf.bad → keep）。
- 返回 Kindle：4 / 4 次书库回来（49–285 s，模拟器），没有 T 进程，开机前在跑的任务都回来了（第 1 次少一个 framework_setup——它是框架起来后跑完就退出的 task，不是缺失）。
- 再进 Android：2 / 2 次看到 `vdkaf.bad` → 直接 keep，电源键 5.2 s / 26.6 s（后一次 powerd 读超时，负载）进屏保、能唤醒，返回正常。
- kt5-5192 3 轮：回退检测 + 框架重启 3 / 3；回退后马上按电源键 3 / 3 无效（23–26 s 无反应），框架报“已启动”（再等 9–69 s）后 3 / 3 正常
  （3.2–4.3 s 进屏保）；之后 keep 1 / 1 正常（2.5 s）。返回 Kindle：第 3 轮正常；第 1 轮的 stop.sh 在宿主机负载 15 时 20 分钟没跑完，被测试脚本的超时截断，
  **而那个 stop.sh 进程还活着，和下一轮刚启动的 Android 重叠**：它最后执行的 `framework_start` / `rm -rf $W/kfb` 删掉了新一轮的 `$W/fw`，
  结果第 2 轮返回时 `framework_start` 认为“没暂停”，awesome / volumd 留在 SIGSTOP，webreader archive statusbar tmd todo rcm 六个任务
  一直停着（手工 `start` 恢复）。这是测试把 stop / start 叠在一起造成的，但说明 **stop.sh 和 veradroid.sh 之间没有互斥**：
  建议 stop.sh 记一个 `$W/stop.pid`，veradroid.sh 启动前等它结束（没有做，没有测）。

### 7.7 swappiness 100 在 pw5 上的复核

装上合并后的树（512 MB 自动 swappiness=100，`APP_COMPILE=off` 免得后台编译干扰），同一个脚本：90 分钟里只跑完 1 轮（宿主机上 9 台模拟器，负载 14–16）。
这一轮全系统 换入 / 直接回收 / 主缺页 = 2268 / 177 / 7018（swappiness 40 的 on1 三轮：2774 / 716 / 15827、2023 / 414 / 9759、1370 / 382 / 8310），
微信读书操作后累计主缺页 3386（40 时 7958 / 4880 / 4253），方向和 kt5 一致；时间不可比。VeraIME 因“start timeout”被 AMS 杀了一次（负载）。

### 7.8 建议

- **512 MB 机型发 LOWMEM=auto（MemTotal < 700 MB 自动开），KINDLE_UI=auto（= stop）。** stop 是 512 MB 上“卡”的主要解药：交换区不再被
  Kindle 的 Java 框架占满，主缺页 / 换入 / 直接回收少几倍，冷启动中位数快一倍，3 分钟操作里没有 ANR / 被杀。电源键、屏保冻结、返回、
  崩溃自恢复在两台机器上通过（pw5 42 / 42，kt5 37 / 42，失败都是负载下的计时检查）。vdkaf 失效时的回退能用：只损失一次（框架重启那几十秒电源键不灵），
  之后自动 keep。判定只看 MemTotal（PW5 / KT5 / KT6 512 MB → 开；Scribe / PW6 → 不开）。
- swappiness 100（512 MB）已改；read_ahead 128 已在 main。
- 应用预编译用 main 的 compile.sh；512 MB 上 speed 与 speed-profile 的取舍没测。
- 只在模拟器上验证：全部数字。真机要看：stop 模式下电源键 / 屏保 / 返回（尤其 vdkaf 在真机固件上的自检）、冷启动真实秒数、低电量关机。


### 7.9 真机复测（PW6 5.19.5，2026-11-13，`LOWMEM=on KINDLE_UI=stop`，脚本思路同 `guest-edge.sh` / `guest-fallback.sh`）

| 项目 | 结果 |
|---|---|
| vdkaf 自检 | 通过：框架停掉、`com.lab126.kaf frameworkStarted=1` 由 vdkaf 回答（mode=stop），7 / 7 次启动 |
| 开机（到 boot_completed） | 13.7–20.9 s |
| 电源键（`powerd_test -p`，在 Kindle 上发）→ 屏保 | 1.1 s（2 / 2）；Android 冻结 2.1–2.2 s；再按一次 1.1 s 回到 active、1.1–2.1 s 解冻，Android 应答 |
| 返回 Kindle | stop.sh 16.7–18.4 s，书库可用 39–45 s；90 个 upstart 任务全部回来，没有 T 状态进程，$SYS 下没有残留挂载 |
| stop 后马上 start（互斥） | 3 / 3：新的启动等上一个 stop.sh 12–13 s 后才开始，26–34 s 开机完成，运行目录完好；之后返回 31–32 s |
| kill -9 容器 init | 2 / 2：Kindle 界面 55–60 s 自己回来，任务齐全，无 T 进程 |
| vdkaf 失效回退（换成立刻退出的假 vdkaf，1 次） | 12 s 判定、记 vdkaf.bad、框架重启，Android 仍在前台；**回退后马上按电源键 31 s 无反应**（和模拟器一样，框架还没报“已启动”），框架 17 s 后报已启动，再按 1.4 s 进屏保、Android 冻结；返回 34 s、任务齐全；第二次启动读 vdkaf.bad 直接 keep，电源键 1.1 s；真 vdkaf 已换回 |
| 屏保图（main 73dd36f） | 用户没放图时轮到 `/usr/share/blanket/screensaver/bg_ss02.png`、`bg_ss03.png`（日志 `screensaver: …`）。**发现**：通配 `*.png` 把 `bg_kids_ss*`（儿童模式）和纯黑的 `bg_kcblackbackground.png` 也排进了轮换 → 改成只取 `bg_ss*`（三棵树） |
| **书库程序崩溃转储** | **问题**：每次进 Android（LOWMEM / stop 模式要停 kppmainapp）书库里多一份约 3.6 MB 的 `KPPMainAppV2_*_crash_*.tgz/.txt/.sdr`，20 分钟 10 份。手工复现：pillow、awesome 都正常时 `stop kppmainapp` 1 s 退出、无转储；只关 pillow 5 s、只冻 awesome 6 s，都有转储（退出卡住被当成挂死）。改：要停书库程序时先停它，再关 pillow、冻 awesome / volumd（framework.sh）。改后 3 次进出：2 次 700 ms 退出、无转储；1 次仍要 4 s、有 1 份转储（原因没查清，可能是刚从 stop 模式回来、书库程序还在忙）。之前每次都有 |

## 8. 按机型（第二阶段，2026-11-13，release/big）

> 2026-11-14 后续：按硬件类别各编一个产品，见 `docs/per-model-images.md`（这一节的结论大多仍成立：pw6 / k49 之间指令集没有差别；新的是 Oasis 2 / 3 的 A7 类、legacy 改用 slim 产品、512 / 256 MB 不预加载 drawable）。

镜像还是只有两种（pw6 / k49，`tools/build/build_rootfs.sh`），按机型不同的东西全是数据，开机前由宿主按机型 / 内存档选：

- 机制：`host/{pw6,k49}/boot/lib/props.sh` 的 `props_apply`（`slim_apply` 之后、容器启动之前）。来源（同一个键后者优先）：
  `models/ram-<256|512|1024>.conf`（按 MemTotal：< 400 MB / < 700 MB / 其余）→ `models/<机型>.conf`。格式和 legacy 那边
  共用：文件里的 `# >>> android props` … `# <<< android props` 段，每行 `#@prop 键=值`。
  直接改系统盘 `build.prop` 里的那一行（ro.* 是“第一次定义生效”，追加没用），原值记在 `$SYS/props.orig`；机型文件里删掉的键会恢复原值；
  换了镜像（`ro.vd.image` 变了）从头来。堆大小 / 密度 / max_starting_bg 归宿主键（memory.sh）管，这里拒收。

| 项目 | 结论 | 依据 |
|---|---|---|
| 指令集变体（dex2oat `--instruction-set-variant`） | **不需要按机型**：pw6 / k49 的目标全是 Cortex-A53 | 真机 PW6 survey `CPU part 0xd03`、features 带 `idiva idivt`；eink-emulator 的 PW6 / PW5 / KT5 / KT6 / Scribe 2 都是 `mediatek,mt8110 mediatek,mt8512`、0xd03。镜像本来就按 cortex-a53 编（boot 镜像、框架、系统应用）。Cortex-A9（PW2 / PW3 / Voyage，没有硬件除法）和 A7（4.1 系）是 legacy / imx41 镜像，那个产品本来就是 cortex-a9 |
| 屏幕密度 | 不需要：这些机型都是 300 ppi（PW6 1272x1696 6.8"、PW5 1236x1648、KT5 / KT6 1072x1448、Scribe 1860x2480 / 1872） | 和镜像里的 `ro.sf.lcd_density=300` 一致；只有 legacy 的 PW2（212 ppi）、入门款 2019（167 ppi）要改，归 legacy 机型文件 |
| 堆 / low_ram / 后台进程上限 | 已经按 MemTotal 做（宿主 `memory.sh` 的 heap_fix：< 700 MB 用 128m / 192m、low_ram、max_starting_bg 2），不重复 | |
| hwui 缓存 | 不需要：我们的应用窗口根本不走 hwui 的 GL（ThreadedRenderer 关着），这些缓存不会被分配 | small-patches.py |
| zygote 预加载开关（≤ 512 MB） | 不做：7.1 的 zygote 没有“主 zygote 延迟预加载”的开关（只有第二个 zygote 用 `--enable-lazy-preload`）；关预加载 = 每个应用自己加载框架类，512 MB 上更费内存 | |
| 512 MB 档（ram-512.conf） | `ro.logd.size=64K`、`dalvik.vm.dex2oat-threads=1`、`dalvik.vm.image-dex2oat-threads=1` | logd 每个缓冲区默认 256K；两线程 dex2oat 在 2 核 512 MB 上编微信读书时峰值内存翻倍（第一阶段 kt5-5192 上，live 0.96 装微信读书时 system_server 被拖垮重启过一次）。实测见下 |
| 低内存机型多砍内容（按内存档换 preloaded-classes / 去服务） | 不做：preloaded-classes 就是 boot 镜像的类列表，按档换就得多出镜像；服务 / 提供者的开关 SystemServer 里没有（见 2.2），宿主的 LOWMEM 已经按 MemTotal 停 Kindle 框架、pm disable 一批 | |
