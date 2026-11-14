# 参与开发

欢迎提 issue 和 pull request。

## 提 issue

- 写清楚机型、固件版本（Kindle 设置 → 设备信息）、越狱方式、VeraDroid 安装包和版本（例如 PW6 0.92、k49 1.00、legacy 0.8.5）。
- 附上日志：Kindle 上的 `/mnt/base-us/system/veradroid/veradroid.log`（通过 USB 看到的是用户分区之外的路径，需要 SSH 或诊断功能取出）。
  **发出前请检查日志里有没有你的 Wi-Fi 名称、IP 地址、账号等个人信息。**
- 安全问题不要公开提 issue，见 `SECURITY.md`。

## 提交代码

- 一个 PR 只做一件事。说明改了什么、为什么、怎么验证的（真机型号 / 模拟器 / 静态测试）。
- 宿主脚本运行在 Kindle 自带的 busybox `sh` 上：只用 POSIX sh 语法，提交前跑 `sh -n`，并运行 `tests/` 下的相关测试（全部：`sh tests/run-static.sh`，GitHub Actions 也会跑）。
- `host/pw6/`、`host/k49/`、`host/legacy/` 下的同名文件大多应该保持一致；只改其中一套时请说明原因。
- 不覆盖 Kindle 系统分区、不改启动分区、不刷内核；会删除用户数据的改动必须有备份和回退。
- 新文件请在开头加许可标识：shell 脚本放在 shebang 后面 `# SPDX-License-Identifier: GPL-3.0-or-later`，
  C / Java 放第一行 `// SPDX-License-Identifier: GPL-3.0-or-later`。AOSP 覆盖文件沿用原文件的许可。
- 引入新的第三方代码或二进制时，同时更新 `THIRD_PARTY.md`（来源、版本、许可、源码地址）。

## 许可

提交到本仓库的代码按 GPL-3.0-or-later 授权（AOSP 覆盖文件除外）。提交即表示你有权以这个许可提供这些代码。

不要提交任何闭源产品的代码、镜像、授权文件或从中提取的内容。
