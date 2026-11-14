// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
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
        final String t = token();
        status.setText("正在下载 " + a.name + " …");
        new Thread(new Runnable() {
            @Override public void run() {
                File out = null; String err = null;
                try {
                    if (a.pkg == null || !a.pkg.matches("[A-Za-z0-9._]{1,128}")) throw new Exception("包名不对");   // 包名会进文件名和宿主的安装命令
                    File dir = Transfer.tmpDir();
                    if (!dir.isDirectory() && !dir.mkdirs()) throw new Exception("无法创建下载目录");
                    out = new File(dir, "store." + a.pkg + "." + a.versionCode + ".apk");
                    out.delete();   // same name left by an older install (other uid): replace, do not overwrite
                    MessageDigest md = MessageDigest.getInstance("SHA-256");
                    HttpURLConnection h = (HttpURLConnection) new URL(a.download + "?device_id="
                        + enc(Update.deviceId(StoreActivity.this)) + "&token=" + enc(t)).openConnection();
                    h.setConnectTimeout(20000); h.setReadTimeout(180000);
                    h.setRequestProperty("User-Agent", "VeraDroid/Store");
                    int code = h.getResponseCode();
                    if (code != 200) throw new Exception(readError(h, code));
                    InputStream in = new BufferedInputStream(h.getInputStream(), 65536);
                    FileOutputStream fo = new FileOutputStream(out);
                    byte[] buf = new byte[65536]; int n; long done = 0;
                    try {
                        while ((n = in.read(buf)) > 0) { fo.write(buf, 0, n); md.update(buf, 0, n); done += n; }
                    } finally { fo.close(); in.close(); h.disconnect(); }
                    if (a.size > 0 && done != a.size) throw new Exception("文件大小不对");
                    if (!hex(md.digest()).equalsIgnoreCase(a.sha)) throw new Exception("SHA-256 校验失败");
                    out.setReadable(true, false);
                    say("下载完成，正在安装 " + a.name + " …（大应用可能要好几分钟）");
                } catch (Exception e) { err = e.getMessage(); if (out != null) out.delete(); }
                if (err != null) {
                    final String fe = err;
                    ui.post(new Runnable() { @Override public void run() {
                        status.setText("安装失败：" + fe); VeraToast.show(StoreActivity.this, fe);
                    }});
                    return;
                }
                // 等宿主的安装结果（ctl/inst.<文件名>），显示真正的结果和原因；以前交给宿主后就再也不说了
                android.content.pm.PackageInfo want = Transfer.apkInfo(StoreActivity.this, out);
                final String r = Transfer.hostInstall(out, new Transfer.InstallProgress() {
                    @Override public void minutes(int n) { say("正在安装 " + a.name + "… 已用 " + n + " 分钟"); }
                });
                final boolean ok = r != null ? r.contains("Success") : Transfer.installedNow(StoreActivity.this, want);
                final String msg = ok ? "已安装 " + a.name
                    : r != null ? "安装失败：" + r
                    : "安装 " + a.name + " " + (Transfer.INSTALL_WAIT_MS / 60000) + " 分钟还没有结果，稍后看看应用列表";
                if (ok || r != null) out.delete();
                ui.post(new Runnable() { @Override public void run() {
                    if (ok && !isFinishing()) render();   // 按钮变成“已安装”；render 会改 status，所以结果放在它后面
                    status.setText(msg);
                    if (!isFinishing()) VeraToast.show(StoreActivity.this, ok ? "已安装" : r != null ? "安装失败" : "还没有安装结果");
                }});
            }
        }, "StoreDownload").start();
    }

    private void say(final String s) {
        ui.post(new Runnable() { @Override public void run() { status.setText(s); } });
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
        StatusBarService.setSuppressed(true);
        StatusBarService.refresh(this);
    }

    @Override protected void onPause() {
        StatusBarService.setSuppressed(false);
        StatusBarService.refresh(this);
        super.onPause();
    }
}
