# 手势提示（宿主画的“方块”小牌子）

需求：上滑或别的手势时给个提示，免得被应用卡住了还不知道；风格和现在的“方块”一致。分支 `feat/gesture-hint`（基于 4d3511c）。

## 样子

白底、黑色双线直角框、右下偏移的实心投影，左边线条图标，右边一行英文小字（BACK、PANEL…）+ 粗体中文。
贴着手势开始的那条边 / 那个角出现（顶边下划 = 顶上居中，底边上划 = 底下居中，左 / 右半屏上下滑 = 左 / 右边中间，四角长按 = 那个角下面一点），不挡正文中间。

| 手势 / 动作 | 提示 |
|---|---|
| 底边上划、双指左右滑（返回键由 veradroid-input 直接发） | 返回 BACK |
| 顶边下划 / 动作 panel | 面板 PANEL |
| 动作 switch / home / back（四角长按、双指手势可绑） | 切换 / 桌面 / 返回 |
| kindle（return；左下角长按默认） | 回 Kindle |
| clear（双指轻点默认） | 清残影（整屏闪刷之后出现） |
| invert（双指长按默认） | 反色 |
| 双指左 / 右半屏上下滑 | 亮度 N% / 暖光 N%（调完后的值，按 flMaxIntensity 算百分比） |
| frontlight / wifi / screenshot / restart / stop / app.<包名> | 前光 开·关 / Wi-Fi 开·关 / 截图 / 重启 Android / 关闭 Android / 打开应用 |
| sleep | 不提示（马上进屏保） |

## 没有响应

panel / switch / home / back 是写 `ctl/act.*` 交给桌面（VeraHome 的 HostService，inotify，收到就删文件）；打开应用是 `ctl/app`。
`action.sh` 写完文件后在后台等 2 秒：文件还在 = Android 没接，换成“没有响应 NO RESPONSE”，第二行告诉怎么回 Kindle，留 3 秒，并在 `/dev/shm/veradroid-actions.log` 记一行 `no response: act.panel`。
第二行说真的绑了“回 Kindle”的宿主手势（四角长按 `G_TL..G_BR=kindle`、双指长按 / 轻点 `G_TWO_*_ACT=kindle`）。**2026-11-14 起左下角长按默认就是回到 Kindle（`G_BL=kindle`）**，所以默认显示“长按左下角回到 Kindle”（`docs/ui/hint-stuck.png`）；用户把它改掉、又没有别的回 Kindle 手势时写“Android 可能卡住了，请稍候”。

左下角长按：一根手指、在角落 160 px 内、按住 2 秒、移动不到 40 px 才算；两根以上手指（手掌）不算；1.2 秒松开不算。整个判断和动作都在宿主（veradroid-input → action.sh → `exit` → 冻结 Android、恢复 Kindle 界面），Android 卡死也能用：模拟器上把 VeraHome `kill -STOP` 之后长按左下角，2.0 s 触发，0.16 s 后“return to kindle requested”，Android 冻结、Kindle 界面回来（`docs/ui/hint-kindle-bl.png` 是触发那一刻的牌子）。误触风险：握机器时大拇指压住左下角 2 秒会回到 Kindle（冻结模式下点书库里的 VeraDroid 几秒就回来）。
底边上划返回走的是按键（不经过桌面），没法判断卡没卡。

## 设置

`GESTURE_HINT=all|stuck|off`（默认 `all`），普通宿主设置：VeraHome 用 `HostLink` 往 `/dev/kfb/ctl/settings.new` 写 `GESTURE_HINT=stuck` 一行，再往 `/dev/kfb/ctl/cmd` 发 `apply`；
`settings.sh` 白名单只收 `all` / `stuck` / `off` / `default`，存进 `settings.conf`，`/dev/kfb/settings` 里能读到当前值。`action.sh` 每个手势都重读 `settings.conf`，不用重启。

## 怎么画的

- `action.sh`：`badge <ms> <位置> <图标> "<英文>|<中文>[|<第二行>]"` → 显示桥 FIFO 一行 `BADGE ...`（显示桥没在跑就什么都不做）。
- `veradroid-epd`（`display/epd.c` 里单独一块 “gesture badge”）：字形和图标是编进程序的 1 位点阵（`display/badge_font.h`，由 `tools/gen-badge-font.py` 用 AOSP 的 Noto Sans CJK SC / Roboto Bold 生成；在 `action.sh` 的字符串里加了新字要重新生成，没字形的字跳过）。
  按当前旋转 / 反色画到面板上，用 DU 快刷（不闪），这块区域不记进“面板上是什么”；时间到了用 GL16 从当前 Android 画面把这块补回来（只改有差别的像素）。
  牌子显示期间 Android 发来的帧照常画，画完马上把牌子盖回去；整屏刷新（FULL）之后也一样。屏保 / 开机画面接管面板时直接作废。
- 不经过 Android：Android 或应用卡死、HostService 不在都照样出。

## 实测（PW6 5.19.5，VeraDroid 0.90 + 这个分支的 epd / input / action.sh / settings.sh）

- 手势识别到牌子发给面板：顶边下划 24 ms、底边上划 33 ms、亮度 +（含两次 lipc）约 100 ms；DU 刷新本身很快（面板约 120 ms 显示出来）。
- 冻住 VeraHome（`kill -STOP`）后下划：2.05 s 后出现“没有响应”，3 s 后消失；`kill -CONT` 后面板照常打开。
- 一轮手势之后整屏和开始前逐行比较完全一样（补回干净）。
