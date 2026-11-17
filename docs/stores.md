# 用户上传的应用 + 字体商店

用户要的：“加入一个字体商店，用户可以上传自己传输的字体；商店的话也是大家可以上传自己传输的 apk”。

## 规则

- 登录用户在网站上传 APK（最大 300 MB）或字体（.ttf / .otf / .ttc，最大 40 MB），分片上传，和“申请适配”同一套做法。
- **上传的东西先进审核队列，管理员通过以后才公开**（恶意软件、坏文件、盗版字体都靠这一步挡）。
  每条记着：上传者用户名、上传时间、SHA-256、大小。每个账号每天 3 个应用、10 个字体（JST 0 点重置，管理员不限）。
- 公开页面上每一条旁边有“举报 / 下架”，写到管理页面顶部并发邮件给管理员；管理员可以“下架”，上传者也可以自己撤回。
  不通过 / 下架 / 被新版本替换的文件从服务器删除，记录留着。
- “申请适配”（`/apps/request`，只给管理员测试、不公开）不变。

## 上传时的检查（只读文件，不执行任何东西）

APK（`apk_inspect`）：
- 二进制清单里读包名、versionCode / versionName、应用名、minSdkVersion；minSdk > 25 拒收（“VeraDroid 是 Android 7.1（API 25），装不上”）。
- `lib/<abi>/`：有原生库但没有 armeabi-v7a / armeabi 的拒收（只有 arm64 的：“这个安装包没有 32 位版本，Kindle 上无法运行”）。
- 签名证书的 SHA-256（先看 v2 / v3 签名块，再看 META-INF 的 v1 签名）；启动图标（位图的才取，矢量 / 自适应图标没有图）。
- 同包名：版本不比商店 / 队列里的高 → 拒收；比商店里的高 → 进队列，通过后替换旧版本（旧的变成“已被新版本替换”）。
  队列里会标出要留意的：`update` 同一上传者的新版本、`owner` 不是原来的上传者、`signer` 签名和现有版本不同、
  `official` 官方推荐里已有同包名（这种即使通过也不会出现在“用户上传”里，官方的优先）、`nosign` 读不出签名。

字体（`font_inspect`）：自己写的最小 sfnt 读取（表目录、name、cmap、head、maxp），不依赖别的库：
- 文件头、表有没有被截断、必需的表、字形数；family / style 名（优先简体中文名）；
- 300 个常用字里覆盖 90% 以上算“含中文”；既没中文也没英文字母的（图标字体）拒收；WOFF 拒收。
- 设备上保存用的文件名取 PostScript 名，只留字母数字 `. _ -`（它会进宿主的 `SYSTEM_FONT` 设置）。
- 装了 fontTools 的话再让它读一遍；装了 Pillow 的话用这个字体画一张预览图（中文 + 英文各一行），画不出来的拒收。
  **线上的 venv 现在两个都没有**：没有 Pillow 就没有预览图（设备上下载以后才能预览），图标也不缩放。

## 接口（设备只读）

| 接口 | 说明 |
|---|---|
| `GET /api/store/apps` | 不带 `category`：和以前一样，整份官方列表（旧版 VeraHome 读的就是这个）。 |
| `GET /api/store/apps?category=official\|user\|all&q=&page=&per=` | 一页应用，带 `categories`（两栏各多少个）、`page` / `pages` / `total`。每个应用多了 `category`、`uploader`、`reviewed`、`source`、`icon`。 |
| `GET /api/store/download/<id>` | `id >= 1000000` 是用户上传的（1000000 + uploads.id）。 |
| `GET /api/store/icon/<id>` | 应用图标（PNG / WebP），没有就 404。官方应用第一次请求时从 APK 里取出来缓存。 |
| `GET /api/fonts?q=&page=&per=` | 字体列表：name、family、style、cjk、size、sha256、file、license、uploader、preview、download、`mirrors`。 |
| `GET /api/fonts/download/<id>` | 字体文件。 |
| `GET /api/fonts/preview/<id>` | 预览图（有 Pillow 时才有）。 |

下载都是 `FileResponse`，支持 `Range`（设备的分段下载和镜像靠它）。

## 网站页面

`/store/apps`、`/store/fonts`（公开列表，搜索、翻页）、`/store/upload/apk`、`/store/upload/font`、`/store/mine`（我的上传）、
`/store/report/<id>`（举报 / 下架）、`/admin/uploads`（审核队列 + 举报）。

## 设备（VeraHome 78 / 0.32.0）

- 软件商店：上面一排“官方推荐 N / 用户上传 N / 字体商店”，列表整页翻；用户上传的每条写“用户上传 · 上传者 · 已审核”，
  点文字看完整说明。没装的应用图标从商店取（缓存在 `.vdhome/state/cache/store-img`）。
- 字体商店（`FontStoreActivity`）：从 设置 → 显示与刷新 → 更多显示设置 → 字体 → 字体商店，或软件商店的“字体商店”进。
  “商店 / 本机字体”两栏；点一条看预览（没下载的看服务器的预览图，下载了的直接用字体排字）、来源 / 许可；
  下载（分段、镜像、校验 SHA-256）→ 设为系统字体 / 设为阅读字体 / 删除。
- 字体下载到 `/data/media/0/Fonts`（宿主的 `$VD/fonts`）——原来的“系统字体”、阅读器、传书导入、“应用到所有应用”读的就是它。
  中文名字记在同目录的 `.store.json`，原来的字体选择里显示的也是这个名字。
- 测试服务器：`setprop debug.vd.storebase http://主机:端口`（和 `debug.vd.updatebase` 一样，root 才能设，重启 Android 就没了）。


## 还没做的

- 设备上不能举报（要到网站上点）；不能在设备上上传。
- 没有自动查毒：安全靠人工审核 + 签名 / 上传者变化的提示。
