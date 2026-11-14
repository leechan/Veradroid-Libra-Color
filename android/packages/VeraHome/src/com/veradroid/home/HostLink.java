// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.HashMap;
import java.util.Map;

/**
 * The link to the host program (the scripts on the Kindle), all through files in /dev/kfb:
 *   ctl/cmd            a FIFO the host reads one command line from: exit stop restart diag clear invert status apply
 *                      light N, warmth N, wifi 0|1.  (Writing blocks until the host reads, so it runs on its own thread.)
 *   ctl/settings.new   new settings (KEY=value lines); "apply" makes the host take them at once
 *   ctl/status         battery=NN charging=0|1 light=N lightmax=N warmth=N wifi=0|1 invert=0|1  (host -> here)
 *   settings           the host's current settings                                              (host -> here)
 *   ctl/app, ctl/act.* (host -> here) open an app / gesture actions, watched by HostService
 */
final class HostLink {
    static final String KFB = "/dev/kfb/";
    static final String CTL = KFB + "ctl/";

    private HostLink() { }

    // 一条线程按顺序发：以前每条命令一个线程，连点亮度 / 先 wifi 再 status 时到达顺序不定；
    // 宿主没在读 FIFO 时每条命令还会留下一个永远卡在 open() 的线程。
    private static final java.util.concurrent.ExecutorService SENDER = java.util.concurrent.Executors.newSingleThreadExecutor(
        new java.util.concurrent.ThreadFactory() {
            @Override public Thread newThread(Runnable r) { Thread t = new Thread(r, "hostlink"); t.setDaemon(true); return t; }
        });

    static void cmd(final String line) {
        SENDER.execute(new Runnable() {
            @Override public void run() {
                try {
                    FileOutputStream o = new FileOutputStream(CTL + "cmd");
                    o.write((line + "\n").getBytes());
                    o.close();
                } catch (Exception ignored) { }
            }
        });
    }

    /** Hand new settings to the host and make it apply them now. */
    static synchronized boolean settings(String lines) {
        // 同步 + 合并：界面线程和传书网页的线程会同时改设置。以前两次共用一个 settings.tmp，后一次改名失败（网页得到 ok:false），
        // 或者后一次把宿主还没取走的 settings.new 整个盖掉，前一次的改动就丢了。现在宿主没取走的那份留着，新的行接在后面（后面的优先）。
        try {
            File tmp = new File(CTL + "settings.tmp");
            String pending = "";
            File cur = new File(CTL + "settings.new");
            if (cur.isFile()) {
                try {
                    byte[] b = HostReq.read(cur, 65536);
                    pending = new String(b, "UTF-8");
                    if (pending.length() > 0 && !pending.endsWith("\n")) pending += "\n";
                } catch (Exception ignored) { pending = ""; }
            }
            FileWriter w = new FileWriter(tmp);
            w.write(pending + lines);
            w.close();
            if (!tmp.renameTo(new File(CTL + "settings.new"))) return false;
            cmd("apply");
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    static Map<String, String> kv(String path) {
        Map<String, String> m = new HashMap<String, String>();
        try {
            BufferedReader r = new BufferedReader(new FileReader(path));
            String line;
            while ((line = r.readLine()) != null) {
                int eq = line.indexOf('=');
                if (eq > 0) m.put(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
            }
            r.close();
        } catch (Exception ignored) { }
        return m;
    }

    static int num(Map<String, String> m, String key, int def) {
        try { return Integer.parseInt(m.get(key)); } catch (Exception e) { return def; }
    }

    /**
     * One-shot hint to the display bridge (/dev/kfb/epd.fifo, see display/epd.c HINT): for the next ms, changes of at least pct %
     * of the screen go out as REAGL instead of DU. Used when the pull-down panel opens / closes: drawn with DU, the page under it
     * shone through ("ghost text under the panel"). Non-blocking: no bridge reading the FIFO = the hint is simply dropped.
     */
    static void epdHint(final int ms, final int pct) {
        SENDER.execute(new Runnable() {
            @Override public void run() {
                java.io.FileDescriptor fd = null;
                try {
                    fd = android.system.Os.open(KFB + "epd.fifo", android.system.OsConstants.O_WRONLY | android.system.OsConstants.O_NONBLOCK, 0);
                    byte[] b = ("HINT " + ms + " " + pct + "\n").getBytes();
                    android.system.Os.write(fd, b, 0, b.length);
                } catch (Throwable ignored) {
                } finally {
                    if (fd != null) try { android.system.Os.close(fd); } catch (Throwable ignored) { }
                }
            }
        });
    }

    /** 发一行命令给显示桥的 FIFO（/dev/kfb/epd.fifo），不阻塞：桥没在读就丢掉。用于 SWIPE（方块风格的换页 / 设置单动画）。 */
    /**
     * 发一行命令给显示桥的 FIFO（/dev/kfb/epd.fifo）。直接在调用的线程上写（非阻塞打开，桥没在读就丢掉，不到 1 ms）：
     * SWIPE 必须在这一帧的“P n”之前进到 FIFO，放到别的线程上会有一半赶不上。
     */
    static void epd(String line) {
        java.io.FileDescriptor fd = null;
        try {
            fd = android.system.Os.open(KFB + "epd.fifo", android.system.OsConstants.O_WRONLY | android.system.OsConstants.O_NONBLOCK, 0);
            byte[] b = (line + "\n").getBytes();
            android.system.Os.write(fd, b, 0, b.length);
        } catch (Throwable ignored) {
        } finally {
            if (fd != null) try { android.system.Os.close(fd); } catch (Throwable ignored) { }
        }
    }

    /** Ask the panel to redraw everything with a flashing refresh (clears ghosts). Delayed so the new picture is ready. */
    static void flashSoon(android.os.Handler h) {
        h.postDelayed(new Runnable() { @Override public void run() { cmd("clear"); } }, 500);
    }
}
