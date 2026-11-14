# 打包、安装、在线更新与机型边界

> 本文默认设备已经越狱并开启 SSH（能 root 登录）。越狱步骤不在本文范围内。

## 1. 产物

| 文件 | 作用 | 签名 |
|---|---|---|
| `VeraHome.apk` | 桌面、图书馆、阅读器、传书、Google Drive、更新客户端 | platform |
| `VeraIME.apk` | 中文拼音 + English 输入法 | platform |
| `veradroid-rootfs.tar.gz` | 精简 Android 根文件系统（另外构建） | 无（由宿主校验） |
| `boot/`、`display/`、`input/` | Kindle 宿主脚本、显示桥、触摸前端 | 无 |

VeraHome 在 AOSP 里带 `LOCAL_DEX_PREOPT := false` 的同类 APK 仍可能被系统构建剥掉 `classes.dex`；当前流程是把 `out/target/common/obj/APPS/VeraHome_intermediates/classes.dex` 塞回 `VeraHome.apk`，再用 `signapk.jar` 以 platform key 重签。VeraIME 已设置 `LOCAL_DEX_PREOPT := false`，构建产物本身带 dex。

## 2. 构建

```sh
# 构建机（$AOSP_WORK/src = AOSP 源码树，见 README“构建”）
cd "$AOSP_WORK"
rsync -a <local>/android/packages/VeraHome/ src/packages/apps/VeraHome/
rsync -a <local>/android/packages/VeraIME/ src/packages/apps/VeraIME/
docker run --rm -v "$AOSP_WORK":/aosp vdaosp:7.1 bash -c 'cd /aosp/src && source build/envsetup.sh && lunch veradroid_kindle-userdebug && make -j8 VeraHome VeraIME'
```

资源限制保持 8 核 / 20 GB / `nice 12`。

## 3. 安装到已运行的 VeraDroid

数据应用（VeraHome 是覆盖安装的 launcher；保留 `/data`）：

```sh
# 在 Kindle 宿主上
adb_sh() { nsenter -t "$(cat /dev/shm/veradroid/pid)" -m -u -i -n -p -r -w/ /system/bin/sh -c "export PATH=/system/bin:/system/xbin ANDROID_ROOT=/system ANDROID_DATA=/data; $*"; }
adb_sh 'pm install -r -d /data/local/tmp/VeraHome.apk'
adb_sh 'ime enable com.veradroid.ime/.VeraImeService; ime set com.veradroid.ime/.VeraImeService'
```

`cmd package install -S` 在本机的 Android 7.1 上出现过 PackageManager 卡住；`pm install` 更稳定，宿主脚本和 OTA 都走 `pm install`。

## 4. 在线安装 / 在线更新

### APK 在线安装（已装好 VeraDroid 的机器）

```sh
curl -fsSL https://veradroid.wenjin.jp/install.sh | sh
```

脚本从 `/api/latest` 取最新版本，下载到 `/data/local/tmp`，再通过宿主 `pm install` 安装 VeraIME 和 VeraHome。只更新 APK，不碰系统分区。

### 自动更新

`Update.java` 在 Home 启动时（6 小时节流）请求：

```
GET https://veradroid.wenjin.jp/api/ota/check
    ?package=com.veradroid.home
    &version_code=7
    &version_name=0.7
    &device_id=<Android ID>
    &model=<Build.MODEL>
```

返回较高 versionCode 时，应用下载 APK、校验 `sha256`，写入 `/data/media/0/.upload/ota.apk`，再发宿主命令 `install ota.apk`。宿主已有的 `cmd.sh` 用 `pm install -r -d` 覆盖安装。安装后 launcher 由系统重新拉起。

已验证：0.4 → 0.5 实际自动下载、SHA 校验、宿主安装成功；随后 0.7 通过 `install.sh` 在线安装，版本和输入法均保持。

### 发布新版本

登录 `/admin`，在“上传新版本”里填：

- package：`com.veradroid.home` 或 `com.veradroid.ime`
- versionCode：必须大于设备当前
- versionName、notes、stable/beta
- APK 文件

服务端计算 SHA-256，存 SQLite 和 `data/releases/`；`/admin` 可切换启用/停用。下载地址为 `/downloads/<package>-<code>-<channel>.apk`。

## 5. 首次安装 / 在线安装的真实边界

Kindle 的启动链是锁定的。**没有越狱和 SSH 的机器不能从网页一键装 VeraDroid**；本文默认设备已经越狱并开启 SSH。当前路径：

1. 确认已越狱、SSH 可用；
2. 备份 Kindle；
3. 把 rootfs + 宿主程序放到 `/mnt/base-us/veradroid/`；
4. 执行 `veradroid.sh home`；
5. 后续 APK 用 `install.sh` / 自动更新。

不能承诺“任意 Kindle 扫码安装”。这既不是技术事实，也会带来法律和支持风险。

## 6. 其他 Kindle 机型

| 机型 | 现状 |
|---|---|
| PaperWhite 6（2024） | 完整验证；1272×1696、fts_ts、当前宿主脚本 |
| PaperWhite 5 / 4 / Oasis / 基础款 | 未验证；分辨率、触摸控制器、内核、分区不同，需要单独适配显示桥和输入 |
| 其他 Android 设备 | 不适用；依赖 Kindle 的墨水屏刷新和宿主脚本 |

通用化至少需要：屏幕分辨率/刷新 ioctl、触摸设备与坐标、内核 binder/ashmem、分区布局、启动链、平台签名。不要直接刷 PW6 镜像到别的机型。

## 7. 签名与分发

- APK 必须与设备上的 VeraDroid 使用同一 platform key；否则覆盖安装会失败。
- 对外分发时不要把 platform private key 打进安装包或仓库；发布服务器只存已签名的 APK。
- 如果未来做多机型，建议每个产品线使用独立 release key，并保留升级路径。
