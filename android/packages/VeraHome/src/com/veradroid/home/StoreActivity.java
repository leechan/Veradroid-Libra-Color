// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

/**
 * App store: lists APKs uploaded by the admin. Open to every device (no account binding or
 * authorization since 2026-11-07); a bound device still sends its token so the server can update
 * last_seen. Installation uses the host's existing pm install path, so no package-installer UI is needed.
 */
public class StoreActivity extends Activity {
    private static final String BASE = "https://veradroid.wenjin.jp";
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final List<App> apps = new ArrayList<App>();
    private LinearLayout list;
    private TextView status;
    // 一次只下载 / 安装一个，进度和结果放在静态字段里（Scribe 用户：商店装微信读书“失败”，同一个 APK 侧载能装）：
    //  - 以前下载线程只往开着的那个界面上写字：用户离开商店（或界面被系统重建）以后，进度和失败原因谁也看不到；
    //  - 再点一次“安装”会再起一条线程，两条线程往同一个文件里写，SHA-256 必然失败；
    //  - 127 MB 要下好几分钟，Kindle 10 分钟没碰就进屏保，宿主在屏保时冻结 Android，下载就断在那里。
    private static volatile String jobPkg;      // 正在处理的包名，null = 没有
    private static volatile String jobMsg;      // 当前进度 / 最近一次的结果（重新打开商店时显示）
    private static StoreActivity live;          // 正在前台的商店界面（进度写到它上面），只在主线程读写

    static final class App {
        int id, versionCode;
        long size;
        String name, pkg, versionName, description, sha, download;
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        getWindow().setWindowAnimations(0);

        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(Color.WHITE);
        page.setPadding(dp(16), dp(8), dp(16), dp(8));
        setContentView(page);

        // Deliberately no toolbar: this is a plain list, like an APK install sheet.
        TextView title = Ui.text(this, "软件商店", 30, true);
        title.setPadding(0, dp(8), 0, dp(4));
        page.addView(title);

        status = Ui.text(this, "正在同步…", 15, false);
        status.setPadding(0, dp(2), 0, dp(6));
        page.addView(status);

        ScrollView scroll = new ScrollView(this);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(list, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        page.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, dp(6), 0, dp(2));
        actions.addView(Ui.button(this, "返回", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        }), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        actions.addView(Ui.button(this, "同步", 16, true, new View.OnClickListener() {
            @Override public void onClick(View v) { load(); }
        }), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        actions.addView(Ui.button(this, "应用更新", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) { Update.now(StoreActivity.this); }
        }), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        page.addView(actions);
        Blocks.restyle(this, page, title, actions, "Store / e-ink apps");

        load();
    }

    private String token() {
        return Token.get(this);
    }

    private void load() {
        final String t = token();
        status.setText("正在同步…");
        list.removeAllViews();
        new Thread(new Runnable() {
            @Override public void run() {
                String err = null;
                try {
                    JSONObject j = get(BASE + "/api/store/apps?device_id=" + enc(Update.deviceId(StoreActivity.this))
                        + "&token=" + enc(t));
                    JSONArray arr = j.optJSONArray("apps");
                    apps.clear();
                    if (arr != null) for (int i = 0; i < arr.length(); i++) {
                        JSONObject o = arr.getJSONObject(i);
                        App a = new App();
                        a.id = o.optInt("id"); a.name = o.optString("name");
                        a.pkg = o.optString("package"); a.versionCode = o.optInt("version_code");
                        a.versionName = o.optString("version_name"); a.description = o.optString("description");
                        a.size = o.optLong("size"); a.sha = o.optString("sha256");
                        a.download = o.optString("download");
                        apps.add(a);
                    }
                } catch (Exception e) { err = e.getMessage(); }
                final String fe = err;
                ui.post(new Runnable() { @Override public void run() { if (fe != null) showError(fe); else render(); } });
            }
        }, "StoreSync").start();
    }

    private void render() {
        status.setText(apps.isEmpty() ? "商店里还没有应用。" : "共 " + apps.size() + " 个应用 · 点安装后由宿主完成");
        if (jobMsg != null) status.setText(jobMsg);   // 正在下载 / 安装，或者上一次的结果（包括失败原因）
        list.removeAllViews();
        for (final App a : apps) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(10), dp(12), dp(10));
            card.setBackgroundColor(Color.WHITE);
            LinearLayout head = new LinearLayout(this);
            head.setOrientation(LinearLayout.HORIZONTAL);
            head.setGravity(Gravity.CENTER_VERTICAL);
            TextView n = Ui.text(this, a.name, 20, true);
            head.addView(n, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            int installed = installed(a.pkg);
            String label = installed <= 0 ? "安装" : (installed < a.versionCode ? "更新" : "重新安装");
            head.addView(Ui.button(this, label, 15, true, new View.OnClickListener() {
                @Override public void onClick(View v) { install(a); }
            }));
            card.addView(head);
            TextView meta = Ui.text(this, a.pkg + " · " + a.versionName + " · " + (a.size / 1024 / 1024) + " MB"
                + (installed > 0 ? " · 已装 " + installed : ""), 12, false);
            meta.setTextColor(Color.DKGRAY);
            card.addView(meta);
            if (a.description.length() > 0) {
                TextView d = Ui.text(this, a.description, 14, false);
                d.setPadding(0, dp(4), 0, 0);
                card.addView(d);
            }
            list.addView(card);
            list.addView(Blocks.sep(this));
        }
    }

    private void showError(String e) {
        status.setText("同步失败");
        list.removeAllViews();
        TextView t = Ui.text(this, e, 16, false);
        t.setPadding(0, dp(12), 0, dp(12));
        list.addView(t);
        list.addView(Ui.button(this, "重新同步", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) { load(); }
        }));
    }

    private int installed(String pkg) {
        try { return getPackageManager().getPackageInfo(pkg, 0).versionCode; }
        catch (Exception e) { return 0; }
    }

    private void install(final App a) {
        if (jobPkg != null) {
            String m = "正在处理另一个应用，等它下载 / 安装完再点" + (jobMsg != null ? "：" + jobMsg : "");
            status.setText(m); VeraToast.show(this, "上一个还没装完");
            return;
        }
        final String t = token();
        jobPkg = a.pkg;
        say("正在下载 " + a.name + " …");
        final Context app = getApplicationContext();
        new Thread(new Runnable() {
            @Override public void run() {
                Thread awake = keepAwake();
                try { job(a, t, app); }
                catch (Throwable e) { jobDone("安装失败：" + reason(e), false); }   // 任何意外（OOM 之类）都要说出来，不能让线程悄悄死掉
                finally { awake.interrupt(); jobPkg = null; }
            }
        }, "StoreDownload").start();
    }

    /** Ping the host every minute while a download / install runs: "poke" resets the Kindle's screensaver timer (the same
     * thing a touch does), so the Kindle does not go to the screensaver - which freezes Android - in the middle of it. */
    private static Thread keepAwake() {
        Thread k = new Thread(new Runnable() {
            @Override public void run() {
                try { while (true) { HostLink.cmd("poke"); Thread.sleep(60000); } } catch (InterruptedException e) { }
            }
        }, "StoreAwake");
        k.setDaemon(true); k.start();
        return k;
    }

    /** The end of a job: remember the result for a store screen opened later, show it on the one in front. */
    private static void jobDone(final String msg, final boolean ok) {
        jobMsg = msg;
        new Handler(Looper.getMainLooper()).post(new Runnable() { @Override public void run() {
            StoreActivity s = live;
            if (s == null || s.isFinishing()) return;
            if (ok) s.render();      // 按钮变成“已安装”；render 会显示 jobMsg
            s.status.setText(msg);
            VeraToast.show(s, msg.length() > 60 ? msg.substring(0, 60) + "…" : msg);
        }});
    }

    /** A readable reason for a failed download (the exception's own message is often empty or English jargon). */
    static String reason(Throwable e) {
        String m = e.getMessage();
        if (e instanceof java.net.UnknownHostException) return "域名解析失败（DNS）：连不上 veradroid.wenjin.jp，检查 Wi-Fi 或换个网络";
        if (e instanceof java.net.SocketTimeoutException) return "网络太慢，" + (m != null && m.contains("connect") ? "连接服务器超时" : "1 分钟没有收到数据") + "。再点一次安装会从断点继续";
        if (e instanceof java.net.ConnectException) return "连不上服务器（连接被拒绝 / 被拦截）：换个网络再试";
        if (e instanceof javax.net.ssl.SSLException) return "安全连接（HTTPS）失败：检查 Kindle 的日期时间，或换个网络（" + m + "）";
        if (e instanceof OutOfMemoryError) return "内存不够：重启 VeraDroid 后再试";
        if (m != null && (m.contains("ENOSPC") || m.contains("No space left"))) return "存储空间不够：设置 → 存储空间 里扩大系统盘，或删掉一些应用 / 书";
        if (m != null && (m.contains("reset") || m.contains("unexpected end of stream") || m.contains("closed"))) return "网络连接中断（" + m + "）。再点一次安装会从断点继续";
        if (m == null || m.length() == 0) return e.getClass().getSimpleName();
        return m;
    }

    private void job(final App a, final String t, final Context ctx) throws Exception {
        File out = null; String err = null;
        try {
            if (a.pkg == null || !a.pkg.matches("[A-Za-z0-9._]{1,128}")) throw new Exception("包名不对");   // 包名会进文件名和宿主的安装命令
            File dir = Transfer.tmpDir();
            if (!dir.isDirectory() && !dir.mkdirs()) throw new Exception("无法创建下载目录");
            out = new File(dir, "store." + a.pkg + "." + a.versionCode + ".apk");
            // 同名文件：上次没下完的留着续传（自己写的、比完整的小）；别的（旧安装留下的、别的 uid 的）先删掉
            if (out.isFile() && !(out.canWrite() && a.size > 0 && out.length() < a.size)) out.delete();
            // 空间：下载的 APK 和安装时 PackageManager 的副本同时在系统盘上（约 2 倍 + 编译结果）。镜像机型（PW5 / KT5 / KT6 /
            // Scribe）的系统盘不够时宿主的看门狗会自动扩（每 20 秒看一次），等它一会儿再判断。
            waitSpace(dir, a.size, out.isFile() ? out.length() : 0);
            // 下载：断了 / 卡住就从断点接着下（Range），最多试 8 次。以前一次读超时或连接被重置，127 MB 的微信读书就整个失败
            // （Scribe 用户：商店装微信读书失败，同一个 APK 侧载能装）。
            download(a, t, out);
            if (a.size > 0 && out.length() != a.size) throw new Exception("文件大小不对（" + out.length() + " / " + a.size + "）");
            say("正在核对下载的文件…");
            if (!hex(sha256(out)).equalsIgnoreCase(a.sha)) throw new Exception("SHA-256 校验失败（下载的文件损坏，请重试）");
            out.setReadable(true, false);
            say("下载完成，正在安装 " + a.name + " …（大应用可能要好几分钟）");
        } catch (Exception e) {
            err = reason(e);
            // 下了一半的留着（再点安装从断点继续）；校验失败 / 大小不对的删掉
            if (out != null && (err == null || !err.startsWith("下载失败"))) out.delete();
        }
        if (err != null) { jobDone("安装失败：" + err, false); return; }
        // 等宿主的安装结果（ctl/inst.<文件名>），显示真正的结果和原因；以前交给宿主后就再也不说了
        android.content.pm.PackageInfo want = Transfer.apkInfo(ctx, out);
        final String r = Transfer.hostInstall(out, new Transfer.InstallProgress() {
            @Override public void minutes(int n) { say("正在安装 " + a.name + "… 已用 " + n + " 分钟"); }
        });
        final boolean ok = r != null ? r.contains("Success") : Transfer.installedNow(ctx, want);
        final String msg = ok ? "已安装 " + a.name
            : r != null ? "安装失败：" + r
            : "安装 " + a.name + " " + (Transfer.INSTALL_WAIT_MS / 60000) + " 分钟还没有结果，稍后看看应用列表";
        if (ok || r != null) out.delete();
        jobDone(msg, ok);
    }

    /** Download a.download into out, resuming with Range after a broken / stalled connection (up to 8 tries). */
    private void download(App a, String t, File out) throws Exception {
        String url = a.download + "?device_id=" + enc(Update.deviceId(getApplicationContext())) + "&token=" + enc(t);
        Exception last = null;
        for (int attempt = 1; attempt <= 8; attempt++) {
            long have = out.isFile() ? out.length() : 0;
            if (a.size > 0 && have == a.size) return;
            HttpURLConnection h = null;
            try {
                h = (HttpURLConnection) new URL(url).openConnection();
                h.setConnectTimeout(20000); h.setReadTimeout(60000);
                h.setRequestProperty("User-Agent", "VeraDroid/Store");
                if (have > 0) h.setRequestProperty("Range", "bytes=" + have + "-");
                int code = h.getResponseCode();
                boolean append = have > 0 && code == 206;
                if (code != 200 && code != 206) throw new Exception(readError(h, code));
                if (!append) have = 0;   // server ignored the Range: start again from zero
                InputStream in = new BufferedInputStream(h.getInputStream(), 65536);
                FileOutputStream fo = new FileOutputStream(out, append);
                byte[] buf = new byte[65536]; int n; long done = have, shown = -1;
                try {
                    while ((n = in.read(buf)) > 0) {
                        fo.write(buf, 0, n); done += n;
                        long pct = a.size > 0 ? done * 100 / a.size : -1;
                        if (pct != shown && pct >= 0) { shown = pct; say("正在下载 " + a.name + " … " + pct + "%（" + (done >> 20) + " / " + (a.size >> 20) + " MB）"); }
                    }
                } finally { fo.close(); in.close(); }
                if (a.size <= 0 || out.length() == a.size) return;
                if (out.length() > a.size) { out.delete(); throw new Exception("文件大小不对"); }
                last = new Exception("连接中断（" + (out.length() >> 20) + " / " + (a.size >> 20) + " MB）");
            } catch (java.io.IOException e) {
                last = e;
            } finally { if (h != null) h.disconnect(); }
            say("网络中断，正在从断点继续下载（第 " + (attempt + 1) + " 次）…");
            try { Thread.sleep(Math.min(30000, 3000L * attempt)); } catch (InterruptedException ie) { throw ie; }
        }
        throw new Exception("下载失败：" + (last != null ? reason(last) : "网络不稳定") + "。再点一次安装会从断点继续");
    }

    /** Free space in the staging folder for a download of size bytes plus the installer's copy; waits up to 90 s for the
     * host's automatic system-disk growth (image models), then fails with a readable reason. */
    private void waitSpace(File dir, long size, long partial) throws Exception {
        if (size <= 0) return;
        long need = size * 2 + (64L << 20) - partial;   // a partial download from an earlier try is already on the disk
        for (int i = 0; ; i++) {
            long have = new android.os.StatFs(dir.getAbsolutePath()).getAvailableBytes();
            if (have >= need) return;
            if (i >= 30) throw new Exception("存储空间不够：需要约 " + (need >> 20) + " MB，现在剩 " + (have >> 20) + " MB（设置 → 存储空间 可以扩大系统盘）");
            if (i == 0) say("存储空间不够，等系统盘自动扩大…");
            Thread.sleep(3000);
        }
    }

    private static byte[] sha256(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        InputStream in = new java.io.FileInputStream(f);
        try { byte[] b = new byte[65536]; int n; while ((n = in.read(b)) > 0) md.update(b, 0, n); } finally { in.close(); }
        return md.digest();
    }

    private static void say(final String s) {
        jobMsg = s;
        new Handler(Looper.getMainLooper()).post(new Runnable() { @Override public void run() {
            StoreActivity a = live;
            if (a != null && !a.isFinishing()) a.status.setText(s);
        }});
    }

    private static String readError(HttpURLConnection h, int code) {
        try {
            InputStream in = h.getErrorStream();
            if (in == null) return "HTTP " + code;
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] b = new byte[2048]; int n;
            while ((n = in.read(b)) > 0) bo.write(b, 0, n);
            in.close();
            JSONObject j = new JSONObject(bo.toString("UTF-8"));
            return j.optString("error", "HTTP " + code);
        } catch (Exception e) { return "HTTP " + code; }
    }

    private static JSONObject get(String url) throws Exception {
        HttpURLConnection h = (HttpURLConnection) new URL(url).openConnection();
        h.setConnectTimeout(15000); h.setReadTimeout(30000);
        h.setRequestProperty("User-Agent", "VeraDroid/Store");
        int code = h.getResponseCode();
        InputStream in = code >= 400 ? h.getErrorStream() : h.getInputStream();
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        byte[] b = new byte[8192]; int n;
        while (in != null && (n = in.read(b)) > 0) bo.write(b, 0, n);
        if (in != null) in.close();
        h.disconnect();
        JSONObject j = new JSONObject(bo.toString("UTF-8"));
        if (code >= 400) throw new Exception(j.optString("error", "HTTP " + code));
        return j;
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder(b.length * 2);
        for (byte x : b) sb.append(String.format("%02x", x & 0xff));
        return sb.toString();
    }

    private static String enc(String s) throws Exception { return URLEncoder.encode(s == null ? "" : s, "UTF-8"); }
    private int dp(int v) { return Ui.dp(this, v); }

    @Override protected void onResume() {
        super.onResume();
        live = this;
        if (jobMsg != null && status != null) status.setText(jobMsg);
        StatusBarService.setSuppressed(true);
        StatusBarService.refresh(this);
    }

    @Override protected void onDestroy() {
        if (live == this) live = null;
        super.onDestroy();
    }

    @Override protected void onPause() {
        StatusBarService.setSuppressed(false);
        StatusBarService.refresh(this);
        super.onPause();
    }
}
