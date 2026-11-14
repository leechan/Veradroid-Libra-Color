# 没有 GPU 时 WebView 网页正文空白（EinkBro、微信读书的协议页……）

## 现象

用系统 WebView 的应用（EinkBro、微信读书里的“用户协议”等网页、任何内嵌 WebView 的应用）只显示应用自己的标题栏 / 工具栏，
网页正文永远是一片白（连 `http://127.0.0.1:8080/` 这种本机页面也一样）。和 HWC 开关无关。

## 原因

1. 我们的应用窗口本来就**不是**硬件加速：`ThreadedRenderer.isAvailable()` / `create()` 在 `small-patches.py` 里恒为 false，
   所有 View 都由 CPU 画在软件画布上（`debug.hwui.renderer=skia` 对 7.1 不起作用）。所以“让应用改用软件绘制”这条路已经走到头了。
2. 系统 WebView 是 Chromium 52（`external/chromium-webview` 预编译 APK）。它在软件画布上也能画（`onDraw` →
   `DemandDrawSw`，CPU 直接把网页画进应用的画布），但前提是渲染进程建了 **同步合成器**（`SynchronousCompositorOutputSurface`）。
   Chromium 52 只在 GPU 线程拿到 GLES2 上下文时才建它（`content/renderer/render_widget.cc` `CreateOutputSurface`：
   `use_software` 时直接返回给浏览器用的 `DelegatedCompositorOutputSurface`，WebView 永远收不到帧）。后来的版本（61、72）也是一样，
   换新 WebView 解决不了。
3. 以前为了不崩，`afterboot.sh` 给 WebView 写的是 `--skip-gpu-data-loading --disable-gpu` → 走的正是上面那条“没有同步合成器”的路 → 空白。
   去掉 `--disable-gpu` 也不行：libagl 只有 GLES1 配置（`No suitable EGL configs found`），而且 GPU 线程会去探测
   MediaCodec（我们没有 mediaserver）→ `cannot get MediaCodecList` → 整个应用崩。

## 办法（系统级）

给 WebView 一个“能建起来、但什么都不画”的 GLES2：网页仍然完全由 CPU 画在软件画布上，GL 上下文只是让 Chromium 走对路径。

- `android/device/veradroid/kindle/nullgles2/`：`libGLESv2_vdnull.so`，按 GLES2 驱动的样子回答（对象 id、各种上限、着色器编译 / 链接成功、
  帧缓冲完整），所有绘制都是空操作。
- `android/small-patches.py`：
  - libagl（`opengl/libagl/egl.cpp`）多两个**只支持 ES2** 的 RGBA8888 配置（id 8、9）。
  - EGL 加载器（`opengl/libs/EGL/Loader.cpp`）：装了 `libGLESv2_vdnull.so` 就用它填 GLESv2 分发表。
  - EGL 包装层（`opengl/libs/EGL/eglApi.cpp`）：只有建在“只支持 ES2”配置上的上下文用 GLESv2 表；其他上下文一律用 GLESv1 表
    （libagl）。以前两张表都从 libagl 按同一份函数名填，内容完全一样，所以 SurfaceFlinger 和其他用 EGL 的进程行为不变。
  - SurfaceFlinger（`RenderEngine.cpp`）先找 ES1 配置再找 ES2（保险：它永远不会拿到空 GLES2）。
- `host/*/boot/lib/afterboot.sh`：镜像里有 `libGLESv2_vdnull.so` 时，WebView 命令行改成
  `--skip-gpu-data-loading --disable-accelerated-video-decode --disable-webrtc-hw-encoding --disable-webrtc-hw-decoding --disable-accelerated-2d-canvas --disable-webgl --disable-gpu-rasterization`
  （不再 `--disable-gpu`；不探测视频编解码；canvas、WebGL、光栅化都不走 GL——空 GLES2 画不出东西，网页会自己用软件 canvas、
  `getContext('webgl')` 返回 null）。旧镜像没有这个库时仍写原来的 `--disable-gpu`，至少不崩。

副作用：别的应用如果要 ES2 上下文（`GLSurfaceView` + `setEGLContextClientVersion(2)` 之类），以前是找不到配置直接崩，现在能建起来但画面是空的。
墨水屏阅读器里几乎没有这种应用。

## 验证（模拟器 pw6-5186，0.99.4 + 只换了这 4 个库）

- EinkBro 打开 `http://127.0.0.1:8080/`（传书页）：改前正文全白；改后整页显示。动态页面（每秒改字 + position:fixed）随时更新，
  手指上划能滚动，canvas 2D 正常，`webgl: no`。微信读书启动正常、登录页正常，点“用户协议”：改前白页（只有标题），改后正文完整。
  HTMLViewer 打开静态网页能显示、能滚动。
- 桌面、书库、SurfaceFlinger 用的还是 libagl 的 ES1 配置（日志 `OpenGL ES-CM 1.0`，config 0x2，和以前一样）。
- 顺带发现：旧版传书页（0.99.4 的 VeraHome）登录层用的是 `inset:0`，Chromium 52 不认（87 才支持），所以登录框只占左上角——
  这是网页本身的问题，不是渲染问题；当前 `web.html` 里的 4 处 `inset:0` 已在本分支改成 `top:0;right:0;bottom:0;left:0`（未重新编 VeraHome 验证）。

没在真机上验证。
