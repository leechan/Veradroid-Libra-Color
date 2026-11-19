# 老机型（legacy）线的源码在哪里

老机型（PW2 / PW3 / PW4、Voyage、Oasis 2 / 3 等，3.0 / 4.1 内核）的安装包和新机型（`pw6` / `k49`）分开发版，
有几处源码两条线各有一份。这个仓库里：

| 部分 | 新机型 | 老机型 |
|---|---|---|
| 宿主脚本 | `host/pw6`、`host/k49` | `host/legacy`（当前是老机型 0.8.13） |
| 显示桥 veradroid-epd | `display/epd.c` | `display/legacy/epd.c` |
| 输入前端 veradroid-input | `input/vinput.c` | `input/legacy/vinput.c` |
| 编译 | `tools/cross/build-epd-input.sh` | `tools/cross/build-legacy-bin.sh`（glibc 2.19，`tools/cross/Dockerfile.legacy`） |
| 安装器 | `cloud/static/bootstrap.sh` | `cloud/static/bootstrap-legacy.sh`、`cloud/static/VeraDroid-Legacy.sh` |
| 内核模块 | — | `tools/kmod/` |

桌面 VeraHome：`android/packages/VeraHome` 是新机型的版本（1.01 带的 VeraHome 87 / 0.35.1）。
老机型 0.8.13 带的 VeraHome 88（0.33.5）从老机型线自己的一份桌面源码编出来，功能比新机型的少一些
（例如没有内置 EPUB 阅读器的新排版），这里没有单独放一份；两条线合并后会只剩一份。
