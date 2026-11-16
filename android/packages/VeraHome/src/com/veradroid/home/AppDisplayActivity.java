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
    private Seg anim, contrast, flash, mode, lightf, darken, font, scroll, img;
    private boolean newHost, hasScroll;
    private java.util.Map<String, String[]> table;
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
        newHost = AppProf.host();
        // 老机型（legacy）的显示桥没有快速滑动 / 图片灰度：宿主发布的设置里没有这两个键就不显示
        hasScroll = HostLink.kv(HostLink.KFB + "settings").containsKey("KFB_SCROLLDU");
        if (newHost) table = AppProf.table();
        String src = newHost ? AppProf.lookup(table, pkg)[0] : "";
        TextView hint = Ui.text(this, (newHost
            ? (src.startsWith("u") ? "已为这个应用单独设置。" : src.equals("b") ? "现在用的是内置推荐（" + AppProf.summary(AppProf.lookup(table, pkg)[1]) + "）。" : "现在跟随全局设置。")
              + "“跟随”用全局设置；保存后马上生效，切到这个应用时自动换上。“恢复默认”回到内置推荐。"
            : "“跟随”用全局设置；改完下次打开这个应用时生效。") + "字号只在这个应用在前台时用，回到桌面恢复全局字号。", 14, false);
        hint.setTextColor(Blocks.on(this) ? Color.BLACK : Color.DKGRAY); hint.setPadding(0, dp(8), 0, dp(8)); root.addView(hint);
        // 按钮放在最上面：项目多了以后（快速滑动 / 图片灰度）放在底下会被挤出屏幕（小屏机型更是）
        LinearLayout row = new LinearLayout(this); row.setGravity(Gravity.RIGHT);
        row.addView(Ui.button(this, newHost ? "恢复默认" : "恢复跟随", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) {
                Store.prefs(AppDisplayActivity.this, "home").edit().remove("appdisp_" + pkg).commit();
                AppFont.set(AppDisplayActivity.this, pkg, 0f);
                if (newHost) AppProf.save(pkg, ""); else HostLink.cmd("appdisp home");
                finish();
            }
        }));
        row.addView(Ui.button(this, "完成", 16, true, new View.OnClickListener() {
            @Override public void onClick(View v) { save(); finish(); }
        }));
        root.addView(row);

        anim = seg(root, "翻页动画", new String[] { "跟随", "开", "关" });
        contrast = seg(root, "对比度", new String[] { "跟随", "1.0", "1.3", "1.5", "2.0", "2.5" });
        flash = seg(root, "每几页全刷", new String[] { "跟随", "每页", "3", "6", "10" });
        mode = seg(root, "刷新方式", new String[] { "跟随", "均衡", "灰度最准", "最快" });
        if (hasScroll) {
            scroll = seg(root, "快速滑动（滚动时先黑白快刷，停下再补灰度）", new String[] { "跟随", "开", "关" });
            img = seg(root, "图片灰度（漫画 / 图片用 16 级灰，不用黑白点阵）", new String[] { "跟随", "开", "关" });
        }
        lightf = seg(root, "浅色过滤（浅灰 / 米色底变纯白，闪刷少）", new String[] { "跟随", "关", "弱", "中", "强" });
        darken = seg(root, "深色加深（浅灰字变黑）", new String[] { "跟随", "关", "开" });
        font = seg(root, "字号（小 0.85 倍 · 标准 · 大 1.4 倍 · 特大 2 倍）", AppFont.LABELS);

        status = Ui.text(this, "", 13, false); status.setTextColor(Blocks.on(this) ? Color.BLACK : Color.DKGRAY);
        status.setPadding(0, dp(10), 0, dp(6)); root.addView(status);

        if (Blocks.on(this)) {
            View sh = Blocks.sheet(this, root, false);
            root.setPadding(root.getPaddingLeft(), Ui.dp(this, 14), root.getPaddingRight(), root.getPaddingBottom());
            setContentView(pageScroll(sh));
        } else
        setContentView(pageScroll(root));
        // 方块风格：整屏白底（不透明的窗口下面不画，留着上下的空会是黑的），单子在上面
        w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Blocks.on(this) ? ViewGroup.LayoutParams.MATCH_PARENT : ViewGroup.LayoutParams.WRAP_CONTENT);
        load();
    }

    /** 一屏放不下时整页翻（墨水屏上不拖动、不惯性）。 */
    private View pageScroll(View v) {
        PageScrollView sv = new PageScrollView(this);
        sv.setFillViewport(true);
        sv.addView(v, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return sv;
    }

    private Seg seg(LinearLayout root, String title, String[] labels) {
        TextView h = Ui.text(this, title, 14, true); h.setTextColor(Blocks.on(this) ? Color.BLACK : Color.DKGRAY);
        h.setPadding(0, dp(10), 0, dp(4)); root.addView(h);
        Seg s = new Seg(this, labels, 13, null);
        root.addView(s, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return s;
    }

    private void load() {
        String spec = newHost ? AppProf.lookup(table, pkg)[1] : Store.prefs(this, "home").getString("appdisp_" + pkg, "");
        java.util.Map<String, String> m = AppProf.parse(spec);
        anim.select(index(m.get("KFB_ANIM_MODE"), new String[] { "-1", "1", "0" }));
        String c = m.get("KFB_CONTRAST");
        contrast.select(c == null ? 0 : "1.0".equals(c) ? 1 : "1.3".equals(c) ? 2 : "1.5".equals(c) ? 3 : "2.0".equals(c) ? 4 : 5);
        flash.select(index(m.get("KFB_FLASH"), new String[] { "-1", "1", "3", "6", "10" }));
        mode.select(index(m.get("KFB_MODE"), new String[] { "-1", "0", "1", "2" }));
        lightf.select(index(m.get("KFB_LIGHTF"), new String[] { "-1", "0", "1", "2", "3" }));
        darken.select(index(m.get("KFB_DARKEN"), new String[] { "-1", "0", "1" }));
        if (scroll != null) { String v = m.get("KFB_SCROLLDU"); scroll.select(v == null ? 0 : "0".equals(v) ? 2 : 1); }
        if (img != null) { String v = m.get("KFB_IMG"); img.select(v == null ? 0 : "0".equals(v) ? 2 : 1); }
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
        if (scroll != null && scroll.selected() > 0) sb.append("KFB_SCROLLDU=").append(scroll.selected() == 1 ? "300" : "0").append(";");
        if (img != null && img.selected() > 0) sb.append("KFB_IMG=").append(img.selected() == 1 ? "25" : "0").append(";");
        String spec = sb.toString();
        if (spec.endsWith(";")) spec = spec.substring(0, spec.length() - 1);
        AppFont.set(this, pkg, AppFont.VALUES[Math.max(0, font.selected())]);
        if (newHost) {
            // 全选“跟随”：有内置推荐的应用存成 "-"（不然内置的会回来），没有的就删掉这一行
            AppProf.save(pkg, spec.length() > 0 ? spec : AppProf.builtin(table, pkg) ? "-" : "");
            return;
        }
        Store.prefs(this, "home").edit().putString("appdisp_" + pkg, spec).commit();
        HostLink.cmd(spec.length() == 0 ? "appdisp home" : "appdisp " + pkg + "|" + spec);
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
