# Android 系统镜像（rootfs）：从 git 重编、两种镜像、优化（2026-11-13，release/big）

## 为什么要重编

线上 PW6 0.88 / k49 0.96 的 `rootfs.tar.gz` 不是哪一次编译的直接产物：打包一直从 0.81 / 0.89 的旧包里拿镜像，
那份镜像是 11-06 的一次编译、之后手工替换过若干文件（build.prop 指纹仍是 11-06）。所以 `android/small-patches.py` 里
后来加的源码补丁——事故三件（vold 没有 fstab 不 trim、PackageManager 准备用户存储失败绝不删用户 0、installd 递归删除不穿过挂载点）
和 WebView 正文（nullgles2 + libagl / EGL / SurfaceFlinger）——**从来没有进过任何线上镜像**。

另外构建机源码树里有两处只在树里、不在 git 里的补丁（zygote 的 fd 白名单、installd 在没有 SELinux 时不因 getfilecon 失败），
已搬进 small-patches.py；源码树的 `packages/apps/Android.mk` 还带着蓝牙分支的东西，镜像改用 git 里的 `android/packages/apps-Android.mk`。

> 2026-11-14：按硬件类别编的镜像（pw6 / k49-512 / k49-1g / a7-512 / a9-512 / a9-256，`build_rootfs.sh class <类别>`、
> 一个类别一个包、安装器按类别选）见 `docs/per-model-images.md`。下面是家族镜像（仍然打，作回退和版本比较用）。

## 两种镜像（pack.sh 打的就这两种）

| 镜像 | 产品 | binder | 给谁 |
|---|---|---|---|
| pw6 | veradroid_kindle_slim（Cortex-A53） | 64 位（协议 8） | PW6 / CS 等 5.15 内核 |
| k49 | 同一产品，`TARGET_USES_64_BIT_BINDER=false` | 32 位（协议 7） | PW5 / KT5 / KT6 / Scribe（4.9 内核） |

核对过线上：k49 镜像 = pw6 镜像换了 libbinder / servicemanager / healthd（binder 协议）、init.kindle.rc 和 build.prop 里多了 512 MB 的堆参数。
新编出的两份镜像之间的差别也正好是这几个文件（外加 default.prop 里的编译时间），libbinder 大小与线上逐字节一致（370324 / 366228）。
legacy（3.0 / 4.1 内核，Cortex-A9，veradroid_kindle32）是另一个产品、另一个打包脚本（pack-legacy.sh），这次没有重编。

## 怎么编

`AOSP_WORK=<目录> tools/build/build_rootfs.sh prepare|sync|pw6|k49`（WORK=git 检出目录，默认本仓库）：
- 私有源码树 `src-big`、输出 `out-big` / `out-big32`（src / out 的副本，文件系统支持时用 reflink），容器 `vdbuild-big`（6 核 / 14 GB / nice 12），
  拿 `$AOSP_WORK/.build.lock`，同一时间只有一个 AOSP 编译。
- `sync`：apply-patches.sh（设备配置、覆盖文件、small-patches）+ kindle32 设备目录 + VeraHome / VeraIME 源码 + apps-Android.mk。
- 每次编译前清空 `out/.../system`、`root`（等于 installclean，但不碰挂成 tmpfs 的 dex_bootjars），镜像里只有产品列出的东西。
- 打包时检查：必须有 libGLESv2_vdnull、vold、installd、services.jar、PackageInstaller、HTMLViewer；不许有 Bluetooth、CtsShim、
  WallpaperBackup、BackupRestoreConfirmation、Settings；libandroid_runtime 必须带 fd 补丁；VeraHome / VeraIME 必须有 classes.dex 和 odex。
- 输出 `$AOSP_WORK/rootfs/rootfs-<镜像>-<git>.tar.gz`（+ .sha256、文件 md5 清单）、同一次编译的 VeraHome / VeraIME APK、libandroid_runtime.so。

## 第一阶段的镜像（git 80c5bef，PW6 0.89 / k49 0.97）

| 文件 | sha256 |
|---|---|
| rootfs-pw6-80c5bef.tar.gz（128081064 字节） | `8119fb5ff826eb13db5fc6e0a13005d576a4b0b41c034c5877e337a28e62a025` |
| rootfs-k49-80c5bef.tar.gz（128079367 字节） | `dc4ec62c50757c7989be4085a4947c8ec426044e5549bca6f11e57b2fabb2d56` |
| veradroid-pw6-0.89.tar.gz | `a808a10772a9c1e9017cdea7ea6654fcab4aef7b298088a3aabd146488b88082` |
| veradroid-k49-0.97.tar.gz | `b9e605f29ba56df412e60ac8027b2d3f9093c883d2b96e7dca511512d490ee03` |

第二阶段（0.90 / 0.98，git 44053cd 的镜像 + 按机型属性层 52b6506 + fix/stage2-dialogs）：rootfs-pw6-44053cd `03e73b725c8540e2b106362e44d18b42e66d345c2e923a0e5f6b0feb6c27b607`、
rootfs-k49-44053cd `f816747df6f3c012e07ef0529705ffe189d3b3e6b37c54f3b4572aafad6230fb`；包 0.90 `dcf226b4…b9`、0.98 `ef277150…82`。

与线上镜像的文件差别（pw6）：少了 CtsShimPrebuilt、CtsShimPrivPrebuilt、WallpaperBackup、BackupRestoreConfirmation（slim.sh 以前每次开机挪走）；
多了 init.kindle.slim.rc、libGLESv2_vdnull.so、VeraHome / VeraIME 的 odex。其余文件同名同位置（内容是新编译的）。

## 优化（都在 slim.mk / apps-Android.mk 里，单项可撤）

1. 产品换成 veradroid_kindle_slim：精简的 preloaded-classes（也是 boot 镜像的类列表）、init.kindle.slim.rc（不起 media.codec /
   mediadrm / mediaextractor，bootanim 换成 /system/bin/true）、`config.disable_*` 七个开关、`ro.zygote.disable_gl_preload`。
   这些线上靠宿主 slim.sh 在开机前改 rc / build.prop 做到（镜像带 `ro.vd.slim=1` 时 slim.sh 只剩挪应用，而应用已经不在镜像里）。
2. 四个用不上的系统应用编译时就不装（VeraHome 的 LOCAL_OVERRIDES_PACKAGES）。StatementService 必须留（没有它 PackageManager 开机即崩）。
3. VeraHome、VeraIME 在镜像里预编译（`LOCAL_DEX_PREOPT := nostripping`：有 odex，APK 里仍保留 classes.dex），
   安装包带的就是这两个文件；安装器发现包里的 APK 和镜像里的一样时不再删 odex（bootstrap.sh），第一次开机不再在设备上编译它们。
   boot 镜像在 /data 里的重定位副本（patchoat，约 11 MB）仍会做，那是 ART 的地址随机化，没有关。
4. `persist.sys.strictmode.disable=true`：userdebug 镜像给系统应用开着 StrictMode 线程策略，主线程每次读写盘都经 binder 报给 AMS 写 dropbox
   （PW2 上桌面因此 ANR）。只关调试上报，targetSdk 24+ 的 file:// 限制不受影响。
5. 没做的：logd 缓冲区（诊断要用，省不到 1 MB）；hwui 缓存参数（我们根本不走 hwui 的 GL）；512 MB 的堆参数（宿主 memory.sh 按实际内存改 build.prop，已经在做）；
   SystemServer 跳服务的源码补丁（见 slim-android.md 2.2，风险大于收益）；rootfs 体积（webview 47 MB、icu 22 MB、boot 镜像 72 MB 都要留，压不下去）。

测量结果见下面的验收部分。

## 重编时踩到的坑（都已经在 build_rootfs.sh / 补丁里）

- 有的构建机文件系统给的是 ACL 式权限（目录 0700、文件 0705 / 0604），tar 只记权限位：容器里非 root 的服务进不了 /system/bin，
  servicemanager 退出码 127，zygote 根本起不来。打包前统一成 755 / 644，并检查 init.kindle.rc 是 644、没有组 / 其他可写的文件。
- **线上 0.88 的 PW6 镜像每次开机都把所有系统应用的数据目录删掉重建**：installd 在没有 SELinux 时 restorecon 失败 →
  PackageManager `prepareAppDataLeafLIF` 的“trying to recover”分支 destroyAppDataLeafLIF。模拟器上每次开机 76 行
  `Failed to create app data ... Recovery failed!`（uiderrors.txt）。新镜像：installd 补丁让它不再失败，PackageManager 补丁让它失败也不删。
- 镜像去掉了四个系统应用，PackageManager 第一次开机会删掉它们空的数据目录（uiderrors 里 4 行 Destroying，预期）。
- 产品指纹变了（以前所有线上镜像都是 11-06 那次编译的指纹），第一次开机走 PackageManager 的“系统升级”路径：验收里专门查了数据。

## 验收（模拟器，2026-11-13）

每台：装线上版（0.88 / 0.96）→ 微信读书 + EinkBro → 书库 ≥ 20 个文件（中文名、.sdr、.sh）、/sdcard 的 Books / Download、
五个应用数据目录里的标记文件 → 线上版自己的自动更新升到候选 → 逐项核对（文件清单 + md5、标记 + 属主、settings.conf、packages.list、android_id）
→ 第一次开机 / 重启 / last-fstrim 改成 4 天前再开 3 次 → 回 Kindle、完全停止、再开 → 截图 → （两台）卸载后全新安装。

第一阶段（0.89 / 0.97）结果：pw6bt-5202（5.20.2）、pw6-5182（5.18.2）、ks2-5202（Scribe 2 5.20.2）、kt6-517104（KT6 5.17.1 chroot）、kt5-5192（512 MB）
数据全部一致（比较用整行排序的 md5 清单；早先按路径排序时 comm 报过假的“变了”，复核为 0）；vold 墓碑 0、Destroying user 0、
create_app_data 失败 0（线上版同一台机器每次开机 76 行）；deviceLocked=0；回 Kindle 后用户存储干净、没有新的书库崩溃记录；
pw6bt 和 kt6-517104 卸载 + 全新安装后书库和 /sdcard 文件一个不少。WebView 正文在 pw6bt 上截图可见（EinkBro 打开测试页）。

开机后 90 秒（同一台机器，线上版 → 候选版第二次开机；模拟器负载每次不同，开机时间只能看大概）：

| 机器 | 容器启动 → boot_completed（秒） | system_server PSS（MB） | zygote PSS | MemAvailable（MB） | binder 服务 | 设备上编译的系统应用 |
|---|---|---|---|---|---|---|
| pw6bt-5202 | 59 → 105 | 65.3 → 63.8 | 36.3 → 34.1 | 763 → 762 | 103 → 94 | 2 → 0 |
| pw6-5182 | 158 → 204（到亮屏） | 59.4 → 57.9 | 30.3 → 25.7 | 558 → 581 | 103 → 94 | 2 → 0 |
| ks2-5202 | 284 → 304 | 61.6 → 57.4 | 33.4 → 28.7 | 706 → 722 | 103 → 94 | 2 → 0 |
| kt6-517104 | 246 → 199 | 60.3 → 57.1 | 33.4 → 31.0 | 647 → 663 | 103 → 94 | 2 → 0 |
| kt5-5192（512 MB） | 311 → 139 | 36.3 → 33.7 | 5.0 → 6.4（大半在交换区） | 223 → 303 | 103 → 94 | 1 → 0 |

rootfs 266 → 267–268 MB（多了 VeraHome / VeraIME 的 odex，少了四个应用）。StrictMode 日志行 2–6 → 0。
开机时间没有可信的提升（模拟器负载噪声比差别大），内存：system_server / zygote 各少 2–5 MB，512 MB 机型可用内存多约 80 MB
（主要是宿主侧的改动和少起的服务，不只是镜像）。

## 第二阶段（PW6 0.90 / k49 0.98，release/big，未发布）

内容：第一阶段 + main 到 d163f93（设置页 / 锁屏密码 / 屏保挑选 / k49 手势 / 角落长按 / 备份清理修复 / 书库绑定修复）+ 按机型属性层（52b6506，可单独撤）
+ fix/stage2-dialogs（安装时打断任何正在跑的 dex2oat；7.1 上 hide_error_dialogs 真的生效：AppErrors 补丁）+ 加密书库可读（下面）。
镜像 rootfs-pw6-44053cd `03e73b725c8540e2b106362e44d18b42e66d345c2e923a0e5f6b0feb6c27b607`、rootfs-k49-44053cd `f816747df6f3c012e07ef0529705ffe189d3b3e6b37c54f3b4572aafad6230fb`。

- **加密书库**：KT6 / Scribe 5.17+（`/etc/sysconfig/board_variables` 里 `DL_V1_POLICY=true`，fscrypt v1）上，Android 自己的进程
  （sdcard FUSE 守护进程、应用）没有 Kindle 的密钥，经 /sdcard 打开书得到 "Required key not available" / Permission denied；
  宿主起的 root shell 带着 Kindle 的 keyring，所以以前的检查看不出来。线上 0.88 / 0.96 / 0.89 绑的是同一个源，问题早就有。
  修法：开机完成后叠上的可写层在这些机型上改用 Kindle 的解密视图 `/mnt/us/documents`（fuse.fsp）；开机期间的只读层不变；
  PW6（5.15，fscrypt v2，谁都能用密钥）照旧。kt6-5202-mac 实测：EinkBro 的 uid / 附加组 / 挂载命名空间里列目录、读（md5 与 Kindle 一致）、写、改名、删除都行。chroot 模式的分支写了没跑。
- 验收工具新增：android_id 升级前后一致；经 veradroid-input 的测试管道注入触摸（点按到达 Android 输入分发、底边上滑 = 返回、
  顶边下滑打开面板 VeraPanel）；以应用身份经 /sdcard 读书库。
