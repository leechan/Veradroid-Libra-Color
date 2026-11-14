# VeraDroid SSH 诊断包

VeraDroid 出了问题、连“设置 → 上传诊断日志”都点不开时，可以用这个小工具在 Kindle 上临时开一个 SSH，
自己（或者你信任的人）连进去看日志。

**它不带任何密钥，谁能登录完全由你决定。** 不放你自己的公钥，它就不会启动。

> 旧版诊断包（`VeraDroid-SSH.zip`，2026-11 已下架）给所有人装的是同一把主机私钥，并且预置了项目维护者的公钥。
> 用过旧包的设备，第一次运行新包时会自动停掉旧的 SSH、删掉那把共享主机密钥和预置公钥。
> 如果你还留着旧包的文件，请删掉，不要再用。

## 它做什么、不做什么

- 端口 **2222**，用户 `root`，**只能用公钥登录**。没有密码登录，也没有空密码 root。
- **主机密钥在你的 Kindle 上生成**（第一次运行时），每台设备都不一样，保存在
  `veradroid/ssh/device_host_key`。压缩包里没有任何私钥。
- **允许登录的公钥只来自你放的文件** `veradroid/ssh/my-public-keys.txt`。文件不存在，或者里面没有格式正确的公钥，
  工具会拒绝启动，并在屏幕和 `status.txt` 里告诉你怎么做。
- **不改 Kindle 的系统分区**。运行时文件放在内存盘 `/var/tmp/veradroid-ssh`，另外只写 `veradroid/ssh/` 这个文件夹。
  为了让 Wi-Fi 上的电脑能连进来，会临时加一条只放行 `wlan0` 端口 2222 的防火墙规则，关闭时删掉。
- **重启 Kindle 后 SSH 就没有了**，不会自己再开；要用就再点一次。这个包不提供开机自启。
- 开着的时候 Kindle 不进屏保（否则 Wi-Fi 会断），比较费电，**用完请关**。

注意：SSH 登录进去就是 Kindle 的 root，能读写设备上的一切。只把你信任的公钥放进去，只在你信任的 Wi-Fi 下打开。

## 用法

### 1. 准备你自己的公钥（电脑上，只需一次）

在电脑的终端里执行（已经有 `~/.ssh/id_ed25519.pub` 的可以跳过）：

```
ssh-keygen -t ed25519
```

一路回车即可。然后看一下公钥，它是以 `ssh-ed25519` 开头的一整行：

```
cat ~/.ssh/id_ed25519.pub
```

Windows 10 / 11 自带同样的命令，在 PowerShell 里执行，公钥在 `C:\Users\<你>\.ssh\id_ed25519.pub`。

**公钥**（`.pub` 文件）可以放心拷到 Kindle；**私钥**（没有 `.pub` 的那个文件）永远留在电脑上，不要拷给任何人。

### 2. 拷到 Kindle

1. 解压 `VeraDroid-SSH.zip`，得到一个 `VeraDroid-SSH` 文件夹。
2. 在这个文件夹里新建文本文件 **`my-public-keys.txt`**，把上一步的公钥整行贴进去（一行一把，可以放多把；`#` 开头的行是注释）。
3. 用 USB 把整个 `VeraDroid-SSH` 文件夹拷进 Kindle 的 `documents` 文件夹，然后弹出 Kindle。

也可以把 `my-public-keys.txt` 直接放到 Kindle 盘的 `veradroid/ssh/` 文件夹（这是正式位置；两处都有时以这里为准）。
第一次点过之后，那里会有一个 `my-public-keys.example.txt` 作格式示例。

### 3. 打开

在书库里点 **“VeraDroid SSH 诊断”**。第一次会先生成这台设备的主机密钥，可能要等几十秒。成功后屏幕上显示：

```
VeraDroid SSH: ON  (key login only)
ssh -p 2222 root@<Kindle 的 IP>
host key SHA256:……
1 key(s) from my-public-keys.txt
tap again to stop; off after reboot
```

同样的内容（中文，更详细）写在 `veradroid/ssh/status.txt`：IP、端口、主机密钥指纹、允许登录的公钥、怎么关。

### 4. 连接

电脑和 Kindle 连同一个 Wi-Fi，然后：

```
ssh -p 2222 root@<屏幕上的 IP>
```

第一次连接时电脑会显示这台设备的主机密钥指纹（`SHA256:…`），**和 Kindle 屏幕 / `status.txt` 里的一致再输入 `yes`**。
以后如果电脑警告“主机密钥变了”，而你并没有删过 `device_host_key`，就不要继续连。

注意：Kindle 插着 USB 线（传文件模式）时 Wi-Fi 不通，要先拔线。

### 5. 关闭

下面任何一种都可以：

- 再点一次“VeraDroid SSH 诊断”（屏幕显示 `VeraDroid SSH: OFF`）；
- 点“VeraDroid SSH 停止”；
- 重启 Kindle。

## 没有启动？

屏幕显示 `VeraDroid SSH: NOT started`，原因写在 `veradroid/ssh/status.txt`：

| 提示 | 怎么办 |
| --- | --- |
| 找不到你的公钥 | 按上面第 2 步放 `my-public-keys.txt`。文件名要完全一致（Windows 记事本可能存成 `my-public-keys.txt.txt`）。 |
| 找到了文件但没有格式正确的公钥行 | 每把公钥必须是完整的一行，以 `ssh-ed25519`、`ssh-rsa` 或 `ecdsa-sha2-…` 开头；不要贴私钥；带 `command=` 之类选项前缀的行不接受。 |
| 找不到 dropbear | 要把整个 `VeraDroid-SSH` 文件夹（包括里面的 `dropbear`）一起拷进 `documents`。 |
| 无法生成主机密钥 | 设备上既没有 `dropbearkey` 也没有可用的 `openssl`，请到社区反馈机型和固件版本。 |
| 启动失败 | `status.txt` 里有 dropbear 的输出；最常见的是端口 2222 已被别的程序（比如 KOReader 的 SSH 插件）占用，先把它关掉。 |

连不上（超时）时依次检查：Kindle 是否进了屏保、Wi-Fi 是否还连着、电脑和 Kindle 是否在同一个网络、路由器是否开了“AP 隔离”。

## 文件一览

| 位置 | 内容 |
| --- | --- |
| `documents/VeraDroid-SSH/VeraDroid-SSH.sh` | 书库里的“VeraDroid SSH 诊断”：点一次开，再点一次关 |
| `documents/VeraDroid-SSH/VeraDroid-SSH-Stop.sh` | 书库里的“VeraDroid SSH 停止” |
| `documents/VeraDroid-SSH/dropbear` | SSH 服务程序（KOReader 的 dropbear 构建）。设备上已有 dropbear 时也可以不带 |
| `veradroid/ssh/my-public-keys.txt` | **你放的**：允许登录的公钥 |
| `veradroid/ssh/device_host_key`、`.pub` | 这台设备自己的主机密钥（本机生成；删掉后下次启动会重新生成，电脑会提示主机密钥变了） |
| `veradroid/ssh/status.txt` | 当前状态 |
| `veradroid/ssh/ssh.log` | 开 / 关记录 |

想彻底删除：先关掉 SSH，再删掉 `documents/VeraDroid-SSH` 和 `veradroid/ssh` 两个文件夹。

## 给开发者

- 源文件在 `diagnostics/ssh/`，`sh diagnostics/ssh/build.sh [输出.zip]` 打包；打包脚本发现任何密钥文件会直接失败。
- 主机密钥的生成顺序：设备上（或包里）有 `dropbearkey` 就用它生成 ed25519；否则用系统自带的 `openssl` 生成 RSA-2048 并转成 dropbear 的格式。
- dropbear 的参数：`-s -g`（禁用密码登录）、`-D /var/tmp/veradroid-ssh`（只读整理过的那份公钥）、`-r` 指向本机生成的主机密钥。绝不使用 `-n` / `-B`。
- Kindle 的用户分区是 FAT，文件权限形同虚设，所以公钥在启动时被过滤后拷到内存盘（目录 700、文件 600），dropbear 只读那一份；改了 `my-public-keys.txt` 要关掉再开才生效。
