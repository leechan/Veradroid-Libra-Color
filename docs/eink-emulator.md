# VeraDroid × eink-emulator 兼容矩阵

[eink-emulator](https://github.com/katadelos/eink-emulator) 运行真实 Kindle
固件内核和 rootfs，适合验证 **宿主层**，不等于验证 Android 容器或电子墨水屏。

## 能验证

- 机型/固件检测：`/proc/device-tree/compatible`、`/etc/prettyversion.txt`
- framebuffer 尺寸、`fb0` 8bpp、`/dev/input/uinput`、`/dev/vndbinder`
- bootstrap 的模型/分辨率门禁、稳定 ID、目录布局、权限
- KUAL 扩展加载路径、`documents` 启动器、`eips`/`lipc`/upstart
- 安装器清理、失败路径、重启后文件保留

## 不能验证

- Android 7.1 rootfs 能否启动（需要 binder/ashmem/命名空间/专用 init）
- VeraHome/阅读器 UI、触摸手感、电子墨水刷新/残影
- 电池、休眠、Wi-Fi 驱动边界、OTA、硬件批次差异
- QEMU TCG 会改变竞态比例

## 先做 dry-run

bootstrap 增加了只检查、不下载、不安装的模式：

```sh
VD_DRY_RUN=1 sh bootstrap.sh
VD_DRY_RUN=1 VD_EXPERIMENTAL=1 VD_MODEL=pw5 sh bootstrap.sh
```

输出示例：

```text
自检通过：model=pw5 firmware=5.19.2 framebuffer=1236,3296
未下载、未安装（VD_DRY_RUN=1）
```

## 建议矩阵

优先覆盖已经发布实验包的机型：

```sh
./eink versions --model kindle-paperwhite-5
./eink create pw5-5192 --model kindle-paperwhite-5 \
  --firmware 5.19.2 --profile production --jbsh
./eink run pw5-5192 --headless --serial-socket --qmp-socket

./eink create pw6-5186 --model kindle-paperwhite-6 \
  --firmware 5.18.6 --profile production --jbsh
./eink create pw6-5201 --model kindle-paperwhite-6 \
  --firmware 5.20.1 --profile production --jbsh
```

在 guest 里执行：

```sh
scp -O -i build/ssh/id_ed25519 -P 2222 bootstrap.sh root@127.0.0.1:/tmp/
ssh -i build/ssh/id_ed25519 -p 2222 root@127.0.0.1 \
  'VD_DRY_RUN=1 sh /tmp/bootstrap.sh'
```

KT5/KT6/Colorsoft/Scribe 用各自的 `--model` 和 `VD_MODEL`，先只跑
`VD_DRY_RUN=1`，不要直接安装。

## 老固件

项目 README 明确说 guest compatibility 面向较新固件。5.17 以前如果
`create` 报补丁失败，需要改 builder 或给上游提 PR；这不是 VeraDroid
自身能绕过的。

## 最终结论

- 模拟器适合把 **PW5/PW6/KT/CS/KS 的宿主层回归** 做成 CI 矩阵；
- 不能替代真机验证电子墨水屏、触摸、休眠和 Android 容器；
- 正式支持仍然需要一台便宜真机做最终确认。
