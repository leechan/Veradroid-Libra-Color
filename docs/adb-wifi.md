# 无线调试（adb）和其它管理文件的办法

## 给用户的说明

### 先选一种办法

| 办法 | 适合 | 需要 |
|---|---|---|
| **传书网页**（主页右上角“传输与管理”） | 传书、传 APK、浏览 / 删除 / 下载 Android 里的文件、看日志 | 手机或电脑的浏览器，同一个 Wi-Fi |
| **USB 数据线** | Kindle 自己的书（`documents/`）、备份 | 插线时 Android 是停着的。老机型（PW2–PW4 / Voyage / Oasis / 入门款 2019）的 Android 存储在系统盘镜像 `veradroid-sys.img` 里，USB 上看不到里面的文件；新机型在 `system/veradroid/data/media/0`，但那是 Android 自己的目录（属主和权限按 Android 的应用来），不要从电脑上直接改。要给 Android 应用的文件请用传书网页或 adb |
| **无线调试（adb）** | 会用命令行的用户：批量 `adb push` / `adb pull`、`adb install`、看 `adb logcat` | 电脑上装好 adb（Android SDK Platform-Tools），同一个 Wi-Fi；新机型（PW5 / PW6 / KT5 / KT6 / Scribe 等） |
| SSH | 排查 Kindle 本身的问题 | VeraDroid-SSH 诊断包 |

老机型（PW2 / PW3 / PW4 / Voyage / Oasis / 入门款 2019）的内核没有 IPv6，Android 7.1 的 adb 在上面开不了无线调试，会提示“不支持”；请用传书网页或 USB。

### 无线调试（adb）怎么用

1. **电脑上准备 adb**：装 Android SDK Platform-Tools，在终端里运行一次 `adb devices`（第一次会生成密钥）。
2. **把电脑的公钥交给 Kindle**（只做一次）：
   - 在 Kindle 上打开“传输与管理”，手机 / 电脑浏览器打开显示的地址，输入 PIN；
   - 进“SSH 与诊断”，在“允许连接的电脑（adb 公钥）”里点“从 adbkey.pub 读取”，选电脑上的
     `~/.android/adbkey.pub`（Windows 是 `%USERPROFILE%\.android\adbkey.pub`），再输一次 PIN，点“添加公钥”。
   - 也可以插 USB，把 `adbkey.pub` 的内容放进 Kindle 盘里的 `veradroid/adb/adb_keys`（一行一台电脑）。
   - **不要**用没有 `.pub` 的 `adbkey`，那是私钥。
3. **打开**：传书网页“SSH 与诊断”里选时长，输 PIN，点“打开无线调试”；或者在 Kindle 的设置 → 存储与连接（经典界面：设置里“无线传输”下面）打开“无线调试 (adb)”（默认 30 分钟）。
4. **连接**：电脑上 `adb connect <Kindle 的地址>:5555`（地址就是传书网页显示的那个，网页上有复制按钮），然后：
   ```
   adb push 书.epub /sdcard/Books/
   adb pull /sdcard/Download/ ./
   adb install 应用.apk
   adb shell
   ```
5. **用完关掉**：网页上点“关闭”或在设置里关；到时间（15 分钟到 2 小时，按你选的）会自动关，重启 Android 后也是关的。

### 安全提醒

- 打开后，添加过公钥的电脑能**完全控制 Android**（包括 `adb root`）。只添加你自己的电脑，用完就关。
- 没有添加公钥的电脑连上来只会显示 `unauthorized`，Kindle 上不会弹“允许调试”的窗口，也没法在 Kindle 上点允许。
- 端口 5555 只在打开期间、只对同一个 Wi-Fi 放行。

## 实现（开发者）

- 宿主：`host/{pw6,k49}/boot/lib/webadmin.sh` 的 `adbstate / adbstart <分钟> / adbstop / adbkeyadd / adbkeydel`（只经过管理请求，
  见文件头：请求文件必须属于 VeraHome 的 uid）。公钥存 `/mnt/us/veradroid/adb/adb_keys`，打开时拷进 Android 的
  `/data/misc/adb/adb_keys`（system:shell 0640），关时删掉；`service.adb.tcp.port=5555` + `ctl.start adbd`；
  命名空间模式加一条 slirp 转发（自己的记录 `$W/adbfwd.id`，和传书的 `fwd.id` 互不影响），两种模式都在 Kindle 防火墙上临时放行 5555。
  到期时间 `$W/adb.until`（uptime 秒），看门狗每轮 `wa_adb_tick`；`stop.sh` 撤防火墙规则、删公钥。`$X/ctl/adb.on` 只给桌面显示开关状态。
- 公钥验证靠 `ro.adb.secure=1`。legacy 镜像里有；**PW6 / k49 的镜像里没设**（测试机实测：没设时任何电脑 `adb connect` 都直接是 `device`）。
  `adbstart` 先读，不是 1 就 `setprop ro.adb.secure 1`（ro 属性没设过时 root 能设一次，之后改不回去，Android 重启后消失），
  读回来还不是 1 就拒绝打开（`adb.error=insecure`）。下一次出镜像时应该直接在 build.prop 里设上。
  镜像里没有 SystemUI 的授权弹窗，所以只能用预先放好的公钥：测试机实测没加过的电脑是 `unauthorized`，加过的是 `device`（shell uid 2000）。
- 老机型：Android 7.1 的 `socket_inaddr_any_server`（libcutils）只建 AF_INET6 socket，没有 IPv6 的内核上 adbd 起得来但永远不监听
  （PW4 模拟器实测）。要支持得改镜像（libcutils 退回 AF_INET，和 `small-patches.py` 里 libcore 的 IPv6 补丁同一类），属于框架源码项目。
- 测试：`tests/adb-wifi-test.sh`。
