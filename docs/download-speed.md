# 下载提速：分段并行 + 镜像

国内用户反映商店和首次安装 / 更新下载很慢。原因：站点在 Cloudflare 免费版后面（国内线路差，单条连接慢）。

## 客户端怎么下

安装器（`cloud/static/bootstrap.sh` 的 `vd_fetch` / `vd_download`）、老机型安装器（`bootstrap-legacy.sh`，同一段代码）、
自动更新（`host/*/boot/lib/auto-update.sh` 下载并运行最新的 bootstrap.sh，所以自动用上新的下载方式）、
商店（VeraHome `Dl.java`，`StoreActivity` 调用）都一样：

1. **候选源**：元数据里的 `"mirrors"`（基地址列表，有顺序）+ 主站。元数据里没有这一项时用默认的 `https://dl.wenjin.jp`
   （同一台服务器，不经过 Cloudflare 直连；每 IP 最多 8 条连接）；`"mirrors": []` = 不用镜像。
   安装器另外认 `network.conf` 里的 `VD_MIRROR=https://…`（排在最前）。
   文件在镜像上的地址 = 基地址 + 主站地址的路径（去掉域名和 `?` 后面）：`bundles/<文件>`、`static/offline/<zip>`、
   `api/store/download/<id>`。基地址里写 `{name}` 时换成文件名（GitHub Releases 这种没有目录的）。
   商店只给主站地址带 device_id / token，镜像只拿到路径。
2. **测速选源**：每个候选先下前 256 KB（Range）计时，最快的那个用；镜像必须回 206，主站回 200 也行（那就不分段）。
   都测不通时直接用主站（让真正的下载去报错）。增量更新的小部件 10 分钟内沿用同一个选择，不逐个测。
3. **分段并行**：8 MB 以上的文件分 4 段（安装器 `VD_SEGS` 可设 1–6；不超过 6 是为了 dl.wenjin.jp 每 IP 8 条的限制），
   每段一条 Range 连接同时下，存在 `<文件>.seg/N`；断了 / 卡住时外层照旧重试，各段从自己的断点接着下（换了源也能接）。
   全部下完按顺序拼进第 0 段（拼一段删一段，不多占一份空间）。
4. **校验**：照旧整体核对 SHA-256；不对时清掉镜像，只从主站重下一次。

