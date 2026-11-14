// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.FileObserver;
import android.os.Handler;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 已保存的无线网络：Kindle（com.lab126.wifid）里存过的网络，点一个就切过去。
 * 列表和切换都交给宿主（wifilist / wificonnect），这里只显示：ctl/wifi.list 一行一个，第一个字符 '*' = 当前连着的。
 * 网络名以 UTF-8 十六进制发给宿主，宿主只认已保存的名字。不轮询：用 inotify 等文件出现。
 */
public class WifiActivity extends Activity {
    private static final String LOADING = "正在读取…";
    private final Handler handler = new Handler();
    private LinearLayout list;
    private TextView status;
    private CtlWatch.Listener watch;
    private String pending;            // 正在切换的网络名
    private String lastList = null;    // 上次画出来的列表原文：没变就不重画（墨水屏）

    static void open(Context c) {
        Intent i = new Intent(c, WifiActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
        c.startActivity(i);
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        Window w = getWindow();
        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        w.setWindowAnimations(0);
        w.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setPadding(dp(18), dp(12), dp(18), dp(12));
        blk = Blocks.on(this);
        if (blk) { buildBlocks(root); return; }

        LinearLayout hd = new LinearLayout(this);
        hd.setOrientation(LinearLayout.HORIZONTAL); hd.setGravity(Gravity.CENTER_VERTICAL);
        hd.addView(Icons.bar(this, Icons.Kind.BACK, 28, new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        }));
        TextView t = Ui.text(this, "已保存的 Wi-Fi", 24, true); t.setPadding(dp(10), 0, 0, 0);
        hd.addView(t, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        hd.addView(Ui.button(this, "刷新", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) { status.setText(LOADING); HostLink.cmd("wifilist"); }
        }));
        root.addView(hd);
        root.addView(Ui.rule(this, 2, Color.BLACK));

        TextView hint = Ui.text(this, "这里列出在 Kindle 上连过并保存的网络，点一个就切换过去。要加新网络，请回到 Kindle 的设置里连接一次。", 14, false);
        hint.setTextColor(Color.DKGRAY); hint.setPadding(0, dp(8), 0, dp(4));
        root.addView(hint);
        status = Ui.text(this, LOADING, 15, false); status.setPadding(0, dp(6), 0, dp(6));
        root.addView(status);

        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        PageScrollView sv = new PageScrollView(this);
        sv.addView(list, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(sv, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(root);
        startWatch();
    }

    /** 方块风格：页头 + 说明 + 分页列表（一页整数行，翻页条），每行一个已保存的网络。 */
    private boolean blk;
    private Blocks.PagedList paged;
    private final List<String> names = new ArrayList<String>();
    private String current;

    private void buildBlocks(LinearLayout root) {
        root.setPadding(0, Blocks.statusInset(this), 0, dp(10));
        root.addView(Blocks.activityHead(this, "Network / saved", "已保存的 Wi-Fi", Blocks.button(this, "刷新", false, new View.OnClickListener() {
            @Override public void onClick(View v) { status.setText(LOADING); HostLink.cmd("wifilist"); }
        })));
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(16), 0, dp(16), 0);
        TextView hint = Ui.text(this, "这里列出在 Kindle 上连过并保存的网络，点一个就切换过去。要加新网络，请回到 Kindle 的设置里连接一次。", 13, false);
        body.addView(hint);
        status = Ui.text(this, LOADING, 15, true);
        status.setPadding(0, dp(8), 0, dp(8));
        body.addView(status);
        paged = new Blocks.PagedList(this, 64, new Blocks.PagedList.Rows() {
            @Override public int count() { return names.size(); }
            @Override public View row(int i) {
                final String n = names.get(i);
                boolean on = n.equals(current);
                View right = on ? Blocks.chip(WifiActivity.this, "已连接") : Blocks.button(WifiActivity.this, "切换", false, new View.OnClickListener() {
                    @Override public void onClick(View v) { connect(n); }
                });
                return Blocks.listRow(WifiActivity.this, Icons.Kind.WIFI, n, on ? "当前网络" : null, right);
            }
        });
        paged.setEmpty(Blocks.empty(this, Icons.Kind.WIFI, "没有读到已保存的网络", "先在 Kindle 的设置里连一次 Wi-Fi", false));
        body.addView(paged, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        root.addView(body, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(root);
        startWatch();
    }

    private void startWatch() {
        watch = new CtlWatch.Listener() {
            @Override public void onCtl(final String path) {
                if (!"wifi.list".equals(path) && !"wifi.result".equals(path)) return;
                handler.post(new Runnable() { @Override public void run() { changed(path); } });
            }
        };
        CtlWatch.add(watch);
        new java.io.File(HostLink.CTL + "wifi.result").delete();
        HostLink.cmd("wifilist");
        // 宿主没回（旧版宿主没有这条命令）：几秒后就按“没有列表”显示，不让人一直等
        handler.postDelayed(new Runnable() { @Override public void run() { if (lastList == null) render(read("wifi.list")); } }, 5000);
    }

    @Override protected void onDestroy() {
        if (watch != null) CtlWatch.remove(watch);
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    private void changed(String file) {
        if (isFinishing()) return;
        if ("wifi.list".equals(file)) { render(read("wifi.list")); return; }
        Map<String, String> m = HostLink.kv(HostLink.CTL + "wifi.result");
        String name = unhex(m.get("essid"));
        if (name == null) name = pending == null ? "" : pending;
        if ("1".equals(m.get("ok"))) status.setText("已连接：" + name);
        else {
            String e = m.get("error");
            String why = "timeout".equals(e) ? "30 秒内没有连上（不在范围内或密码已变）"
                : "not saved".equals(e) ? "Kindle 里没有这个已保存的网络" : "网络名无法处理";
            status.setText("切换失败：" + why);
        }
        pending = null;
    }

    private String read(String name) {
        StringBuilder sb = new StringBuilder();
        try {
            BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(HostLink.CTL + name), "UTF-8"));
            String l;
            while ((l = r.readLine()) != null) sb.append(l).append('\n');
            r.close();
        } catch (Exception ignored) { }
        return sb.toString();
    }

    private void render(String raw) {
        // 只清掉“正在读取…”；切换结果（宿主先写结果、再重写列表）要留着给人看
        if (LOADING.equals(status.getText().toString())) status.setText("");
        if (raw.equals(lastList)) return;
        lastList = raw;
        if (blk) {
            names.clear(); current = null;
            for (String l : raw.split("\n")) {
                if (l.length() < 2) continue;
                String n = l.substring(1);
                if (l.charAt(0) == '*') current = n;
                if (!names.contains(n)) names.add(n);
            }
            paged.refresh();
            return;
        }
        list.removeAllViews();
        List<String> names = new ArrayList<String>();
        String current = null;
        for (String l : raw.split("\n")) {
            if (l.length() < 2) continue;
            String n = l.substring(1);
            if (l.charAt(0) == '*') current = n;
            if (!names.contains(n)) names.add(n);
        }
        if (names.isEmpty()) {
            TextView e = Ui.text(this, "没有读到已保存的网络。", 17, false);
            e.setPadding(0, dp(16), 0, dp(16));
            list.addView(e);
            return;
        }
        for (final String n : names) {
            final boolean on = n.equals(current);
            LinearLayout r = new LinearLayout(this);
            r.setOrientation(LinearLayout.HORIZONTAL);
            r.setGravity(Gravity.CENTER_VERTICAL);
            r.setPadding(dp(4), dp(14), dp(4), dp(14));
            r.addView(new Icons.IconView(this, Icons.Kind.WIFI), new LinearLayout.LayoutParams(dp(28), dp(28)));
            TextView tn = Ui.text(this, n, 19, on);
            tn.setPadding(dp(12), 0, dp(8), 0);
            tn.setSingleLine(true);
            tn.setEllipsize(android.text.TextUtils.TruncateAt.END);
            r.addView(tn, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            TextView st = Ui.text(this, on ? "已连接" : "切换", 16, on);
            r.addView(st);
            if (!on) r.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { connect(n); }
            });
            list.addView(r);
            list.addView(Ui.rule(this, 1, Color.LTGRAY));
        }
    }

    private void connect(String name) {
        if (pending != null) { status.setText("正在切换到 " + pending + "，请稍等…"); return; }
        String hex = hex(name);
        if (hex == null) { status.setText("这个网络名太长或含有特殊字符，无法切换"); return; }
        pending = name;
        status.setText("正在切换到 " + name + "…（最多 30 秒）");
        HostLink.cmd("wificonnect " + hex);
        // 宿主没写回 wifi.result（老宿主、宿主出错）时别一直卡在“请稍等”：45 秒后放开
        final String asked = name;
        handler.postDelayed(new Runnable() {
            @Override public void run() {
                if (isFinishing() || pending == null || !pending.equals(asked)) return;
                pending = null;
                status.setText("切换到 " + asked + " 没有回音，可以再试一次");
            }
        }, 45000);
    }

    /** UTF-8 字节的小写十六进制；宿主最多接受 32 字节（SSID 上限），控制字符不发。 */
    static String hex(String s) {
        try {
            byte[] b = s.getBytes("UTF-8");
            if (b.length == 0 || b.length > 32) return null;
            StringBuilder sb = new StringBuilder();
            for (byte x : b) {
                int v = x & 0xff;
                if (v < 0x20 || v == 0x7f) return null;
                sb.append(Character.forDigit(v >> 4, 16)).append(Character.forDigit(v & 15, 16));
            }
            return sb.toString();
        } catch (Exception e) { return null; }
    }

    static String unhex(String h) {
        if (h == null || h.length() % 2 != 0) return null;
        try {
            byte[] b = new byte[h.length() / 2];
            for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(h.substring(2 * i, 2 * i + 2), 16);
            return new String(b, "UTF-8");
        } catch (Exception e) { return null; }
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
