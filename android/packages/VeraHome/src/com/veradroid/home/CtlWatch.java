package com.veradroid.home;

import android.os.FileObserver;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * 宿主控制目录（/dev/kfb/ctl）的唯一监听者。Android 7.1 的 FileObserver 对同一进程里同一路径只有一个 inotify 句柄：
 * 第二个 FileObserver 会顶掉第一个，它 stopWatching 时整个目录就没人监听了。以前 Wi-Fi / 蓝牙 / 系统设置页各自
 * new 一个，退出这些页面后 HostService 就收不到宿主的手势（下拉面板、切换应用、回桌面全失灵）。
 * 现在只有这里一个 FileObserver，开了就不关；各处只是登记 / 注销回调（在监听线程上调用，自己 post 到主线程）。
 */
final class CtlWatch {
    interface Listener { void onCtl(String name); }

    private static final CopyOnWriteArrayList<Listener> listeners = new CopyOnWriteArrayList<Listener>();
    private static FileObserver observer;

    static synchronized void add(Listener l) {
        if (!listeners.contains(l)) listeners.add(l);
        if (observer == null) {
            observer = new FileObserver(HostLink.CTL, FileObserver.CLOSE_WRITE | FileObserver.MOVED_TO) {
                @Override public void onEvent(int event, String path) {
                    if (path == null) return;
                    for (Listener x : listeners) {
                        try { x.onCtl(path); } catch (Throwable t) { android.util.Log.w("VeraHome", "ctl " + path + ": " + t); }
                    }
                }
            };
            observer.startWatching();
        }
    }

    static void remove(Listener l) { listeners.remove(l); }
}
