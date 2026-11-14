// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Per-app display overrides; "跟随" clears the override and uses the global display settings. */
public class AppDisplayActivity extends Activity {
    private String pkg, label;
    private Seg anim, contrast, flash, mode, lightf, darken, font;
    private TextView status;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        pkg = getIntent().getStringExtra("pkg");
        label = getIntent().getStringExtra("label");
        if (pkg == null) pkg = "";
        if (label == null || label.length() == 0) label = pkg;
        Window w = getWindow();
        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        w.setWindowAnimations(0);
        w.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setPadding(dp(18), dp(12), dp(18), dp(16));
        LinearLayout hd = new LinearLayout(this);
        hd.setOrientation(LinearLayout.HORIZONTAL); hd.setGravity(Gravity.CENTER_VERTICAL);
        hd.addView(Icons.bar(this, Icons.Kind.BACK, 28, new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); }
        }));
        TextView t = Ui.text(this, label + " · 显示效果", 23, true); t.setPadding(dp(10), 0, 0, 0);
        hd.addView(t); root.addView(hd);
        View hdRule = Ui.rule(this, 2, Color.BLACK);
        root.addView(hdRule);
        Blocks.restyleTop(this, root, hd, hdRule, "Display / per app", label + " · 显示效果", null);
        TextView hint = Ui.text(this, "“跟随”用全局设置；改完下次打开这个应用时生效。字号只在这个应用在前台时用，回到桌面恢复全局字号。", 14, false);
        hint.setTextColor(Blocks.on(this) ? Color.BLACK : Color.DKGRAY); hint.setPadding(0, dp(8), 0, dp(8)); root.addView(hint);

        anim = seg(root, "翻页动画", new String[] { "跟随", "开", "关" });
        contrast = seg(root, "对比度", new String[] { "跟随", "1.0", "1.3", "1.5", "2.0", "2.5" });
        flash = seg(root, "每几页全刷", new String[] { "跟随", "每页", "3", "6", "10" });
        mode = seg(root, "整页刷新", new String[] { "跟随", "均衡", "灰度", "最快" });
        lightf = seg(root, "浅色过滤（浅灰 / 米色底变纯白，闪刷少）", new String[] { "跟随", "关", "弱", "中", "强" });
        darken = seg(root, "深色加深（浅灰字变黑）", new String[] { "跟随", "关", "开" });
        font = seg(root, "字号（小 0.85 倍 · 标准 · 大 1.4 倍 · 特大 2 倍）", AppFont.LABELS);

        status = Ui.text(this, "", 13, false); status.setTextColor(Blocks.on(this) ? Color.BLACK : Color.DKGRAY);
        status.setPadding(0, dp(10), 0, dp(6)); root.addView(status);

        LinearLayout row = new LinearLayout(this); row.setGravity(Gravity.RIGHT);
        row.addView(Ui.button(this, "恢复跟随", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) {
                Store.prefs(AppDisplayActivity.this, "home").edit().remove("appdisp_" + pkg).commit();
                AppFont.set(AppDisplayActivity.this, pkg, 0f);
                HostLink.cmd("appdisp home");
                finish();
            }
        }));
        row.addView(Ui.button(this, "完成", 16, true, new View.OnClickListener() {
            @Override public void onClick(View v) { save(); finish(); }
        }));
        root.addView(row);
        if (Blocks.on(this)) {
            View sh = Blocks.sheet(this, root, false);
            root.setPadding(root.getPaddingLeft(), Ui.dp(this, 14), root.getPaddingRight(), root.getPaddingBottom());
            setContentView(sh);
        } else
        setContentView(root);
        // 方块风格：整屏白底（不透明的窗口下面不画，留着上下的空会是黑的），单子在上面
        w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Blocks.on(this) ? ViewGroup.LayoutParams.MATCH_PARENT : ViewGroup.LayoutParams.WRAP_CONTENT);
        load();
    }

    private Seg seg(LinearLayout root, String title, String[] labels) {
        TextView h = Ui.text(this, title, 14, true); h.setTextColor(Blocks.on(this) ? Color.BLACK : Color.DKGRAY);
        h.setPadding(0, dp(10), 0, dp(4)); root.addView(h);
        Seg s = new Seg(this, labels, 13, null);
        root.addView(s, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return s;
    }

    private void load() {
        String spec = Store.prefs(this, "home").getString("appdisp_" + pkg, "");
        java.util.Map<String, String> m = new java.util.HashMap<String, String>();
        for (String p : spec.split(";")) {
            int eq = p.indexOf('=');
            if (eq > 0) m.put(p.substring(0, eq), p.substring(eq + 1));
        }
        anim.select(index(m.get("KFB_ANIM_MODE"), new String[] { "-1", "1", "0" }));
        String c = m.get("KFB_CONTRAST");
        contrast.select(c == null ? 0 : "1.0".equals(c) ? 1 : "1.3".equals(c) ? 2 : "1.5".equals(c) ? 3 : "2.0".equals(c) ? 4 : 5);
        flash.select(index(m.get("KFB_FLASH"), new String[] { "-1", "1", "3", "6", "10" }));
        mode.select(index(m.get("KFB_MODE"), new String[] { "-1", "0", "1", "2" }));
        lightf.select(index(m.get("KFB_LIGHTF"), new String[] { "-1", "0", "1", "2", "3" }));
        darken.select(index(m.get("KFB_DARKEN"), new String[] { "-1", "0", "1" }));
        font.select(AppFont.index(AppFont.get(this, pkg)));
    }

    private int index(String v, String[] vals) {
        if (v == null) return 0;
        for (int i = 0; i < vals.length; i++) if (vals[i].equals(v)) return i;
        return 0;
    }

    private void save() {
        StringBuilder sb = new StringBuilder();
        int a = anim.selected();
        if (a > 0) sb.append("KFB_ANIM_MODE=").append(a == 1 ? "1" : "0").append(";");
        String[] cs = { "", "1.0", "1.3", "1.5", "2.0", "2.5" };
        if (contrast.selected() > 0) sb.append("KFB_CONTRAST=").append(cs[contrast.selected()]).append(";");
        String[] fs = { "", "1", "3", "6", "10" };
        if (flash.selected() > 0) sb.append("KFB_FLASH=").append(fs[flash.selected()]).append(";");
        String[] ms = { "", "0", "1", "2" };
        if (mode.selected() > 0) sb.append("KFB_MODE=").append(ms[mode.selected()]).append(";");
        if (lightf.selected() > 0) sb.append("KFB_LIGHTF=").append(lightf.selected() - 1).append(";");
        if (darken.selected() > 0) sb.append("KFB_DARKEN=").append(darken.selected() - 1).append(";");
        String spec = sb.toString();
        if (spec.endsWith(";")) spec = spec.substring(0, spec.length() - 1);
        Store.prefs(this, "home").edit().putString("appdisp_" + pkg, spec).commit();
        AppFont.set(this, pkg, AppFont.VALUES[Math.max(0, font.selected())]);
        HostLink.cmd(spec.length() == 0 ? "appdisp home" : "appdisp " + pkg + "|" + spec);
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
