# 进度画面（方块风格）：安装、更新、开机、回到 Kindle、网络诊断

需求（2026-11-14）：系统更新显示下载进度，下载进度和一开始的安装也用同样的显示风格；
“主要现在完全是盲等”；“有的人在国内，网络不好，根本不知道是自己机子的问题还是网络的问题”。

## 一份代码，三个地方用

`host/pw6/boot/lib/progress.sh`（唯一来源）：`vp_*` 函数用 FBInk 命令行画方块风格的画面——白底、双线黑框 + 右下实心投影、
黑底白字标题条、英文小字在中文粗体标题上面、一排方格（完成的涂黑）、粗体数字；字体全是 Kindle 自带的（华文黑体粗 / 中、Amazon Ember Bold）。
`tools/sync-progress.sh` 把它拷到 k49 / legacy 宿主，并替换 `cloud/static/bootstrap.sh` 里 `# BEGIN vd_progress … # END vd_progress` 之间的那份
（安装器在 Android 装好之前就要用，只能内嵌）。改 progress.sh 后必须跑一次。

| 地方 | 画什么 | 代码 |
|---|---|---|
| 书库里点安装 / 离线安装 / 桌面“检查并更新”（Android 停了以后） | 整屏：标题框、当前步骤框（步骤名、百分比、方格、MB / 速度 / 剩余时间、说明）、步骤列表、页脚（日志位置、卡住怎么办） | bootstrap.sh 的 `ui_*`、`vd_download` |
| 开机画面 | 原来的标题和诗句不变，底部换成方块进度框：阶段、百分比、方格、已用时间（每 5 秒走）、正在优化第几个应用、慢了怎么办 | splash.sh 的 `sp_*`、bootwatch.sh 的 `boot_tick` |
| 回到 Kindle（Kindle 界面要冷启动，stop 模式） | 整屏：“正在恢复 Kindle 界面”，已用时间每 5 秒走，方格按一分钟估，超过 3 分钟怎么办 | framework.sh 的 `fw_wait_screen` |

刷新：整屏闪刷只在画面第一次出现时一次；换步骤时只刷步骤框和列表里变了的几行；进度只补新涂黑的格子；文字至少 5 秒才刷一次（局部 GL16，不闪）。
kt6 模拟器一次完整的全新安装（建系统盘 → 检查网络 → 下载 135 MB → 校验 → 解压 → 备份书库 → 安装系统 → 首次开机）共 33 次刷新。

### 没有 FBInk / FBInk 不能用时

- 全新安装的 Kindle 上没有我们的 FBInk；越狱带的 `/mnt/us/libkh/bin/fbink` 在 KT6 上段错误。新的整包把
  `bin/fbink` 放在 tar 的第一个，下载了 3 MB 安装器就把它解出来，从 eips 换成整屏画面（`vp_upgrade`）。旧整包里它在最后，解压以后才换。
- 刷新被驱动拒绝（Scribe：FBInk 不认识的 MTK 机型，见 fix/cs-ks-detect）时 `vp_screen` 检查 `fbink -s` 的返回值，退回 eips。
- eips 只有 ASCII 字形（中文它画不出来：`paint_char> character not available`），退路全用英文：`[3/8] DOWNLOAD`、`[#####-----] 37%`、速度 / 剩余时间、
  英文的错误原因（`vp_en_err`）。
- 自动更新（`VD_AUTOUPDATE=1`，用户在看书）什么都不画，只写状态文件。

## 网络检查和错误代码

下载前一步“检查网络”：Wi-Fi（默认路由 / 网卡地址）→ 域名解析（`curl -w time_namelookup`）→ 服务器（HTTPS HEAD，耗时）；速度用真实下载的头几秒算。
只连 `$VD_BASE`（veradroid.wenjin.jp），不找第三方测速站。

下载：`curl -C -` 断点续传，`--speed-limit 1024 --speed-time 30` 判卡住；curl 退出后自动从断点重试，连续 5 次没进展才放弃（画面“正在重试（2/5）”）。
慢（< 50 KB/s 超过 20 秒，或预计超过 20 分钟）、卡住（15 秒没数据）时画面上直说“不是机器的问题”和怎么办。SHA-256 不对自动重下一次。

| 代码 | 意思 | 谁的问题 |
|---|---|---|
| 11 | 没连 Wi-Fi | 网络 |
| 12 | Wi-Fi 连上了但上不了网（DNS 失败） | 网络 |
| 13 | 连不上 VeraDroid 服务器（被墙 / 维护） | 网络 / 服务器 |
| 14 | 下载太慢超时 | 网络 |
| 15 | 文件校验失败（重下过一次） | 网络传输 |
| 21 | 空间不够 | Kindle 存储 |
| 30–32 | 机器这边（解压、写入、建系统盘……） | 机器，附日志位置 |

安装器以这个代码退出（书库脚本显示“代码 N”），详细原因在 `veradroid-install.log` / `veradroid-install-detail.log`。

## 给 VeraHome 的状态文件（`/dev/kfb/ctl/`，KEY=value，值里的换行写成 `\n`，先写 .tmp 再 mv，最多一秒一次）

| 文件 | 谁写 | 键 |
|---|---|---|
| `update.status` | bootstrap.sh、localupdate.sh、cmd.sh `fullupdate` | state（checking / downloading / verifying / unpacking / installing / booting / done / error）、step、label、index、steps、pct、line1、line2、code、mode（manual / auto / local）、elapsed、time |
| `apkinst.status` | cmd.sh `install`、afterboot.sh（apps 文件夹） | state（installing / done / error）、name、start、result |
| `compile.status` | compile.sh（原有） | state、pkg、index、total |
| `netdiag.status` | cmd.sh `netdiag` → progress.sh `vp_netdiag` | state、step、lines、verdict（ok / slow / offline / nodns / noserver）、conclusion、speed |

VeraHome 的 `TaskCards`（分支 feat/progress-ui-home）只经 `CtlWatch` 收文件变化：设备与关于（系统更新整卡，步骤 下载 → 校验 → 解压 → 安装）、
我的（后台更新 / 装应用 / 优化应用的小卡片）、存储与连接（网络诊断按钮和结果）。一张卡片最多 2 秒重画一次、只改变了的字；进行中每 5 秒走已用时间。
