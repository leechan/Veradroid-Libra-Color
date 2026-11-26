# VeraDroid for Kobo (Libra 2 / Libra Colour)

将 [VeraDroid](https://github.com/xyc0677/veradroid)（`legacy` 分支，Android 7.1.1 Cortex-A9/Cortex-A53 32 位）移植到 **Kobo Libra 2 (N418)** 与 **Kobo Libra Colour (N428)**，参考 [Koboweread](https://github.com/scokyfei/Koboweread) 的 Kobo 内核模块、硬件参数与 KOReader 插件集成方式。

运行时通过 `/mnt/onboard/.kobo/version` 自动选择 `models/<机型>.conf`；两个机型共用同一套 Android 7 ARM 镜像与 ARMv7 二进制。

## 硬件与系统适配

| 项目 | Kobo Libra 2 (N418) | Kobo Libra Colour (N428) |
|---|---|---|
| SoC / RAM | i.MX6SLL 单核 Cortex-A9，512 MB，Linux 4.1.15 | MediaTek MT8113T 双核 Cortex-A53，1 GB，Linux 4.9.77 |
| 容器隔离 | `busybox unshare -m` + 静态 `pivot_init` + `HOSTNS=1` 共用 `wlan0`（`VdHostNet`） | 相同 |
| 内核模块 | `binder_linux`、`kobo_zsmalloc`、`kobo_zram`、`kobo_madvise` | 内核内建 ashmem/zram；**协议 7 `binder32`** + `kobo_madvise` |
| 墨水屏显示 | `veradroid-epd` + FBInk `FBINK_FOR_KOBO`，i.MX EPDC v2，1264×1680 | 同一显示桥 + FBInk ≥ 1.25.0-544，MTK hwtcon 32 bpp；按区域检测色度，彩色内容走 GCC16/GLRC16 + CFA，黑白文字走快速灰度波形 |
| 触摸 / 按键 | Elan `--swap-xy`；`gpio-keys` 193/194/116 | Elan `--swap-xy --flip-y`；`gpio-keys` 193/194 + 独立 `bd71828-pwrkey` 电源键 |
| 前光 / 色温 / 电量 | `mxc_msp430.0` / `lm3630a_led` / `mc13892_bat` | 前光相同 / `bd71827_bat` |
| 宿主 UI 协同 | `framework.sh` 暂停 KOReader/Nickel、备份/恢复 `/dev/fb0`、退出后卸载镜像 | 相同；MTK 上不切 8 bpp (`FB_DEPTH_LOCK=1`) |
| 启动入口 | KOReader 插件 + NickelMenu | 同名入口（`Veradroid-LibraColour`） |

## 编译与部署

1. 使用 Zig 0.13 交叉编译静态 ARMv7 二进制（Libra 2 与 Libra Colour 通用）：
   ```sh
   ZIG=/path/to/zig FBINK_DIR=/path/to/fbink E2FSPROGS_TAR=/path/to/e2fsprogs-1.47.1.tar.xz \
     sh tools/kobo/build-kobo-bin.sh build/kobo-bin
   ```
   FBInk 必须支持 N428/Libra Colour（≥ 1.25.0-544）。
2. 部署或打包：
   ```sh
   # Libra Colour 开发部署
   KOBO_MODEL=libracolour KOBO_HOST=<KOBO_IP> KOBO_PORT=2222 \
   BIN_DIR=build/kobo-bin LEGACY_DIR=/path/to/veradroid-legacy/veradroid-pw6 \
     sh tools/kobo/deploy-kobo.sh --init-img

   # Libra Colour 发布包
   KOBO_MODEL=libracolour BIN_DIR=build/kobo-bin \
   EXTRA_BIN_DIR=/path/to/extra-kobo-bins \
   LEGACY_DIR=/path/to/veradroid-legacy/veradroid-pw6 \
     sh tools/kobo/build-release.sh dist
   ```
3. 启动 / 停止：
   - KOReader：顶部菜单 → 工具 → **VeraDroid** → **启动 (Android)**
   - NickelMenu：右下角 → **Veradroid-LibraColour (Android)**
   - SSH：
     ```sh
     sh /mnt/onboard/.adds/Veradroid-LibraColour/boot/veradroid.sh home
     sh /mnt/onboard/.adds/Veradroid-LibraColour/boot/stop.sh
     ```
   - 退出回 Kobo：长按屏幕**左下角 2 秒**，或在 VeraHome 下拉面板点击返回。

## 文档

- 完整功能清单与 Libra 2 实机基准：[`docs/kobo-libra2-optimizations.md`](../../docs/kobo-libra2-optimizations.md)
- Libra Colour 移植差异、限制与排查：[`docs/kobo-libra-colour-port.md`](../../docs/kobo-libra-colour-port.md)
- 只读硬件探针：[`diagnostics/kobo/vd-kobo-probe.sh`](../../diagnostics/kobo/vd-kobo-probe.sh)
