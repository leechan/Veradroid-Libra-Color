# Kobo Libra Colour (N428) 移植说明

本文说明把 **Veradroid-Libra2** 从 Kobo Libra 2（N418）扩展到 **Kobo Libra Colour（N428 / N428B）** 所做的改造、验证边界与使用方法。

> 定位：这是一次**源码级设备适配**。Libra 2 与 Libra Colour 的 SoC、内核、显示控制器、电源键和 binder 协议都不同，不可能只改一个型号字符串。仓库现在同时支持两台设备，运行时按 `/mnt/onboard/.kobo/version` 自动选择机型配置。

---

## 一、两代硬件差异

| 项目 | Kobo Libra 2 (N418) | Kobo Libra Colour (N428) |
|---|---|---|
| SoC | NXP i.MX6SLL，单核 Cortex-A9 | MediaTek MT8113T，2× Cortex-A53，32 位用户态 |
| 内核 | 4.1.15 | **4.9.77** |
| 内存 | 512 MB | 1 GB（约 965 MB 可用） |
| 屏幕 | Carta 1264×1680，300 ppi | Kaleido 3 1264×1680，300 ppi 黑白 / 150 ppi 彩色 |
| 显示控制器 | i.MX EPDC v2 | **MTK hwtcon**，32 bpp，行宽 5056 |
| 触摸 | Elan，raw 1680×1264，`swap-xy` | Elan，raw 1680×1264，`swap-xy` **+ raw X 反向** |
| 翻页键 | gpio-keys：193/194 | gpio-keys：193/194（旋转信号也在 gpio-keys） |
| 电源键 | gpio-keys：116 | **独立设备 `bd71828-pwrkey`** |
| 电池 | `mc13892_bat` | **`bd71827_bat`** |
| 前光 / 色温 | `mxc_msp430.0` / `lm3630a_led` | 相同 |
| 无线 | SDIO RTL8723DS（模块可卸载） | MTK combo，**驱动内建**，无 RFKILL/MAC80211 |
| ashmem / zram | 需要外部模块 | **内核内建** |
| binder | 外部 `binder_linux.ko`（协议 7） | 内核自带 **协议 8（64 位）**；Android 7 ARM 需要另一份协议 7 模块，注册为 `binder32` |

---

## 二、为什么“直接把 Libra 2 包装到 Libra Colour”会失败

常见失败点（现在都已逐项处理）：

1. **机型被当成 libra2**：触摸 `swap-xy` 但没有反向 raw X，表现为左右镜像。
2. **内核模块不匹配**：安装包只有 4.1.15 的 `binder_linux.ko`，4.9.77 上 `insmod` 失败，启动直接停在“内核模块加载失败”。
3. **binder 协议不对**：4.9.77 内建的 `/dev/binder` 是 64 位协议 8；Android 7 的 32 位用户态需要协议 7。必须加载单独的 `binder32` 设备并把它映射成 `/dev/binder`。
4. **FBInk 不认识 N428**：旧版 FBInk 打印 `Unidentified Kobo device code`，屏幕不刷新。Libra Colour 需要 FBInk **≥ 1.25.0-544**。
5. **电源键找不到**：N428 的电源键不在 `gpio-keys`，必须额外打开 `bd71828-pwrkey`。
6. **电池/充电读不到**：路径是 `bd71827_bat`，不是 `mc13892_bat`。
7. **错误地切换 fb 位深**：原逻辑会把 fb0 切到 8 bpp 省带宽；MTK hwtcon + CFA 彩色面板必须保持 32 bpp。
8. **i.MX 专属休眠等待/唤醒过滤**：Libra Colour 没有 EPDC 9 秒 VEE 稳压等待，也不能用 i.MX 的中断名判断“真唤醒”。

---

## 三、本次改造内容

### 1. 运行时机型选择

- `host/kobo/models/libracolour.conf`：新增 N428 完整硬件档案（内存、显示、触摸、按键、电池、Wi-Fi、休眠策略）。
- `host/kobo/models/libra2.conf`：补充机型元数据与显式硬件开关（行为保持原样）。
- `host/kobo/boot/lib/kobo.sh`：
  - `kobo_model()` 识别 `N428*` / `N418*`，并可回退到 `/proc/device-tree/model`；
  - 电池/充电按 `BATTERY_NODES` / `CHARGER_NODES` 探测；
  - 前光路径/量程由 `FL_COLD` / `FL_WARM` / `FL_MAX` 驱动；
  - Wi-Fi 接口与模块列表按机型配置，MTK 不再尝试 `rmmod 8723ds`。
- `host/kobo/boot/lib/settings.sh`：按检测到的机型加载对应 conf，读取失败时才回退 `libra2.conf`。

### 2. 内核模块与 binder

- `host/kobo/boot/lib/kmod.sh` 重写：
  - 按 `uname -r` 找 `kmod/<kernel>/`；
  - Libra Colour：加载 `binder_linux.ko` → 从 `/sys/class/binder32/binder32/dev` 读取真实的 **major:minor（511:0）** → 创建 `/dev/binder`；
  - 不再因为内核里已有 64 位 `binder` 就跳过模块；
  - zram / ashmem 内建时自动跳过外部模块；
  - `kobo_madvise`、`uinput` 节点按需创建。
- `host/kobo/kmod/4.9.77/`：已放入在实机验证过的 4.9.77 模块（`binder_linux.ko`、`kobo_madvise.ko`、`kobo_pagecache.ko`）及 SHA-256。
- `tools/kobo/fetch-libra-colour-kmod.sh`：从固定 commit 重新下载并校验这些模块。
- `install.sh` / `localupdate.sh`：校验当前内核是否有对应模块，拒绝跨机型/跨内核升级包。

### 3. 输入与按键

- `input/legacy/vinput.c`：新增 `--keydev2`，可同时抓取 `gpio-keys` 与 `bd71828-pwrkey`；两者都参与电源键、霍尔皮套、翻页键和旋转信号处理。
- `host/kobo/boot/lib/input.sh`：从机型配置读取 `POWER_KEY_DEV`，自动追加 `--keydev2`。
- 触摸：`TOUCH_FLIP_Y=1`（在 `--swap-xy` 之后反向 raw X），对应 KOReader `Kobo_monza` 的 `touch_mirrored_y`。

### 4. 显示与电源

- `host/kobo/boot/lib/framework.sh`：`FB_DEPTH_LOCK=1` 时不再调用 `fbdepth -d 8`（MTK 彩色面板保持 32 bpp）；屏幕备份行宽按 fb 实际位深计算。
- `host/kobo/boot/lib/sleep.sh`：
  - `SUSPEND_VEE_WAIT=0` 跳过 i.MX 的 9 秒 VEE 等待；
  - `SUSPEND_TRUST_WAKE=1` 在拿不到 i.MX 中断名时，把第一次 `mem` 唤醒当作真实用户唤醒，避免被当成伪 RTC 唤醒反复重挂；
  - `SLEEP_WIFI_OFF=0`：MTK 内建 Wi-Fi 不卸载/不断开，唤醒后 SSH 与网络仍在。
- `host/kobo/boot/lib/network.sh`：`WIFI_PS_SUPPORTED=0` 时不碰 RTL8723DS 专属 `/proc/net/rtl8723ds` 与 `iwpriv`。
- `host/kobo/boot/lib/memory.sh`：CPU 调频、I/O 调度、`ro.product.*`、`ro.config.low_ram`、ZRAM 上限全部机型化；MTK 不再写入 i.MX 的 396/792 MHz `target_loads`。

### 5. 打包与入口

- 新增 `Veradroid-LibraColour` 的 NickelMenu 入口与 KOReader 插件。
- `tools/kobo/build-release.sh` 支持 `KOBO_MODEL=libra2|libracolour`，输出：
  - `Veradroid-Libra2-<ver>-full.zip` / `-upgrade.zip`
  - `Veradroid-LibraColour-<ver>-full.zip` / `-upgrade.zip`
- 每个安装包只带自己机型的 `models/<model>.conf`；装错机型会在 `install.sh` 直接报错。
- 安装包内附 `diagnostics/kobo/vd-kobo-probe.sh` 只读硬件探针。

### 6. 诊断

在 Kobo 上用 SSH 运行：

```sh
sh /mnt/onboard/.adds/Veradroid-LibraColour/diagnostics/kobo/vd-kobo-probe.sh --save
```

报告包含：机型/内核、framebuffer 参数、FBInk `-e` 输出、输入设备与 ABS 范围、前光/电池节点、`/sys/class/binder32` 的真实设备号、模块 vermagic、网络、休眠能力和 VeraDroid 日志尾部。排查“黑屏 / 触摸镜像 / 电源键无效 / 不刷新”时先看这份报告。

---

## 四、构建与安装

### 1. 编译 ARMv7 二进制

Libra Colour 是 32 位用户态（AArch32），现有 Cortex-A9/NEON 二进制可直接运行；建议用 **支持 N428 的 FBInk**：

```sh
ZIG=/path/to/zig \
FBINK_DIR=/path/to/FBInk \
E2FSPROGS_TAR=/path/to/e2fsprogs-1.47.1.tar.xz \
  sh tools/kobo/build-kobo-bin.sh build/kobo-bin
```

FBInk 需包含 Libra Colour（`Kobo_monza` / N428）支持；构建脚本会检查源码里是否出现相关标识，缺失时给出警告。

> **必须重新编译 `veradroid-epd`**：显示桥把 FBInk 静态链接进二进制，只替换宿主 shell 脚本不会让旧 `veradroid-epd` 认识 N428。`fbink` / `fbdepth` / `fbink-img` 也应使用同一版 FBInk 构建（或使用 KOReader 附带的新版 `fbink`，但 `veradroid-epd` 仍必须重编）。

### 2. 构建 Libra Colour 发布包

```sh
KOBO_MODEL=libracolour \
BIN_DIR=build/kobo-bin \
EXTRA_BIN_DIR=/path/to/extra-kobo-bins \
LEGACY_DIR=/path/to/veradroid-legacy/veradroid-pw6 \
  sh tools/kobo/build-release.sh dist
```

`KMOD_DIR` 默认就是仓库内的 `host/kobo/kmod`，因此 4.9.77 模块开箱即用。若 Kobo 固件升级换了内核，必须用新内核源码重新编译模块，再放进 `host/kobo/kmod/<新内核版本>/`。

### 3. 安装

与 Libra 2 相同：把 `Veradroid-LibraColour-<ver>-full.zip` 里的 `.adds` 合并到 Kobo 根目录，然后从 NickelMenu 或 KOReader 启动。首次启动会创建 2 GB 的 `veradroid-sys.img`。

> 如果你之前装过 Libra 2 包并启动失败，旧目录可以保留（两个包使用不同目录与入口，不会互相覆盖），但请确认启动的是 `Veradroid-LibraColour` 入口；旧包的 4.1.15 模块在 N428 上本来就会失败。

> 安装前建议先用探针确认内核是 `4.9.77`。如果 Kobo 已升级到其它内核，安装器会拒绝安装，这是预期行为。

---

## 五、已知限制与验证清单

### 限制

- **彩色输出按区域混合**：`display/legacy/epd.c` 检测每个更新区域是否含真实色度；含彩色内容（封面、插图、彩色高亮）的区域以 RGBA + `GCC16/GLRC16` + CFA 发送，纯黑白文字区域继续使用快速灰度波形。这样微信读书文字翻页保持速度，彩色封面/插图显示彩色。色饱和度仍受 Kaleido 3 面板本身限制。
- **仅验证内核 4.9.77 / 固件 4.42.23303 的模块**：其它固件版本没有匹配模块，不能混用。
- **深度休眠与唤醒过滤是保守策略**：MTK 没有 i.MX 的中断命名，`SUSPEND_TRUST_WAKE=1` 优先保证“按电源键能醒”，代价是极少数 RTC 伪唤醒可能点亮一次屏幕。可据实机日志再调。
- **REAGL/翻页动画未做 MTK 专项调优**：默认 `KFB_ANIM_MODE=0`，使用 FBInk 的 hwtcon 刷新路径；残影表现可在 `libracolour.conf` 中调 `KFB_FLASH` / `KFB_ECLIPSE` / `KFB_HEAVY_FLASH`。
- **本仓库无法替代实机验证**：显示、触摸、休眠、Wi-Fi 重连都必须在真机上跑一遍。首次启动后请保存探针报告与 `/mnt/onboard/.adds/Veradroid-LibraColour/logs/veradroid.log`。

### 首次启动检查

1. `fbink -e` 是否显示 `Kobo Libra Colour` 或 N428，而不是 `Unidentified Kobo device code`。
2. 屏幕是否正常刷新（不是全黑/全白）。
3. 触摸方向是否正确（点左上角应命中左上角，不是右上角）。
4. 上/下翻页键、电源键短按休眠/唤醒、霍尔皮套是否正常。
5. 前光亮度与色温滑动是否生效。
6. Wi-Fi 是否仍能联网（启动后不要求重新连接）。
7. `/sys/class/binder32/binder32/dev` 是否为 `511:0`，`/dev/binder` 是否为对应的字符设备，Android 是否起来。

---

## 六、主要改动文件索引

| 文件 | 作用 |
|---|---|
| `host/kobo/models/libracolour.conf` | N428 硬件档案 |
| `host/kobo/boot/lib/kobo.sh` | 机型识别、电池/充电、前光、Wi-Fi HAL |
| `host/kobo/boot/lib/settings.sh` | 按机型加载配置 |
| `host/kobo/boot/lib/kmod.sh` | binder32 / 4.9.77 模块加载 |
| `host/kobo/boot/lib/input.sh` | `--keydev2`、触摸变换 |
| `input/legacy/vinput.c` | 第二按键设备支持 |
| `host/kobo/boot/lib/framework.sh` | 禁止 MTK 上切 8 bpp |
| `host/kobo/boot/lib/sleep.sh` | MTK 休眠/唤醒策略 |
| `host/kobo/boot/lib/network.sh` | MTK Wi-Fi 省电兼容 |
| `host/kobo/boot/lib/memory.sh` | 机型化内存/调频/IO |
| `host/kobo/kmod/4.9.77/` | 实机验证内核模块 + 校验和 |
| `tools/kobo/fetch-libra-colour-kmod.sh` | 可复现下载模块 |
| `host/kobo/koplugin/Veradroid-LibraColour.koplugin/` | KOReader 入口 |
| `host/kobo/nm/Veradroid-LibraColour` | NickelMenu 入口 |
| `diagnostics/kobo/vd-kobo-probe.sh` | 只读硬件探针 |

---

## 七、模块来源与许可

- 内核源码：Rakuten Kobo 公开的 [Kobo-Reader / hw/mt8113-libraC_vision7](https://github.com/kobolabs/Kobo-Reader/tree/master/hw/mt8113-libraC_vision7)。
- 模块构建配方与协议 7 binder 源码：[lyoe/Koboweread-Colour · src/kmod-mtk](https://github.com/lyoe/Koboweread-Colour/tree/main/src/kmod-mtk)（GPL-2.0）。
- 这些 `.ko` 是 Linux 内核模块，按 **GPL-2.0** 分发；仓库其余部分仍为 GPL-3.0-or-later。详见 `host/kobo/kmod/4.9.77/README.md`。
