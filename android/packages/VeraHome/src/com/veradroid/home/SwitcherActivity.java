// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;

import java.util.List;

/** Switch between the apps that are running (recent tasks), or go to the home screen. */
public class SwitcherActivity extends Activity {
    /** 包名 -> 名称 / 图标，进程内缓存。应用更新后名称图标可能变：装卸应用时 HomeActivity 会清掉。 */
    static final java.util.Map<String, String> LABELS = new java.util.HashMap<String, String>();
    static final java.util.Map<String, android.graphics.drawable.Drawable.ConstantState> ICONS = new java.util.HashMap<String, android.graphics.drawable.Drawable.ConstantState>();

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        Window w = getWindow();
        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        w.setWindowAnimations(0);
        w.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND);   // no dark shade behind (e-ink: it would show as a gray block)
        setFinishOnTouchOutside(true);

        LinearLayout root = new LinearLayout(this);
        this.root = root;
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setPadding(Ui.dp(this, 18), Ui.dp(this, 14), Ui.dp(this, 18), Ui.dp(this, 14));
        LinearLayout hd = new LinearLayout(this);
        hd.setOrientation(LinearLayout.HORIZONTAL);
        hd.setGravity(Gravity.CENTER_VERTICAL);
        hd.addView(new Icons.IconView(this, Icons.Kind.SWITCH), new LinearLayout.LayoutParams(Ui.dp(this, 30), Ui.dp(this, 30)));
        android.widget.TextView ht = Ui.text(this, "切换应用", 22, true);
        ht.setPadding(Ui.dp(this, 10), 0, 0, 0);
        hd.addView(ht);
        root.addView(hd);
        root.addView(Ui.rule(this, 2, Color.BLACK));
        blk = Blocks.on(this);
        if (blk) {   // 方块风格：整张单子是双线框 + 投影，标题上面一行英文小字，标题下面一条粗黑线
            hd.removeView(ht);
            hd.addView(Blocks.titled(this, "Switch apps", "切换应用", 22, true));
            ((LinearLayout.LayoutParams) hd.getChildAt(0).getLayoutParams()).rightMargin = Ui.dp(this, 10);
        }

        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        ScrollView sv = blk ? new PageScrollView(this) : new ScrollView(this);
        sv.addView(list);
        root.addView(sv, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        fill();
        if (blk) {   // 方块风格：单子左右留出边，框和投影整个看得见；单子以外是透明的（下面的应用照旧）
            setContentView(Blocks.sheet(this, root));
        } else
        setContentView(root);
        Perf.measure(root, "switcher");
        w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout list;
    private View root;
    private boolean blk;

    /** 正在运行的应用 + “桌面”。每次打开都重新取（任务会变），窗口和外框留着复用。 */
    private void fill() {
        list.removeAllViews();
        final PackageManager pm = getPackageManager();
        final ActivityManager am = (ActivityManager) getSystemService(ACTIVITY_SERVICE);
        int n = 0;
        try {
            @SuppressWarnings("deprecation")
            List<ActivityManager.RecentTaskInfo> tasks = am.getRecentTasks(12, ActivityManager.RECENT_IGNORE_UNAVAILABLE);
            for (final ActivityManager.RecentTaskInfo t : tasks) {
                if (t.baseIntent == null) continue;
                ComponentName cn = t.baseIntent.getComponent();
                if (cn == null) continue;
                String pkg = cn.getPackageName();
                if (pkg.equals(getPackageName())) continue;
                String label = LABELS.get(pkg);
                android.graphics.drawable.Drawable icon = null;
                android.graphics.drawable.Drawable.ConstantState cs = ICONS.get(pkg);
                if (label == null || cs == null) {
                    // 第一次见到这个应用才去问 PackageManager、解码图标；之后用进程里缓存的（切换器每次打开都要快）
                    try {
                        label = String.valueOf(pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)));
                        icon = pm.getApplicationIcon(pkg);
                        LABELS.put(pkg, label);
                        if (icon.getConstantState() != null) ICONS.put(pkg, icon.getConstantState());
                    } catch (Exception ignored) { if (label == null) label = pkg; }
                } else icon = cs.newDrawable(getResources());
                final Intent open = new Intent(t.baseIntent).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                final int id = t.id;
                final String tpkg = pkg;
                list.addView(item(label, null, icon, new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        // 和桌面点图标一样：先让宿主换好这个应用的显示参数 / 显示密度、显示桥挡住纯色的启动窗口，再把任务调到前面
                        // （以前只靠任务栈通知，宿主晚 0.1–5 秒才知道；多看要换密度，阅读页会先按旧密度重建一次、再重建一次）
                        if (AppProf.host()) { HostService.launchedPkg = tpkg; AppProf.launching(tpkg); }
                        try {
                            if (id >= 0) am.moveTaskToFront(id, 0);
                            else startActivity(open);
                        } catch (Exception e) { startActivity(open); }
                        finish();
                    }
                }));
                n++;
            }
        } catch (Throwable ignored) { }
        if (n == 0) {
            android.widget.TextView none = Ui.text(this, "没有正在运行的应用", 18, false);
            none.setPadding(0, Ui.dp(this, 20), 0, Ui.dp(this, 20));
            list.addView(none);
        }
        list.addView(item("桌面", Icons.Kind.GRID, null, new View.OnClickListener() {
            @Override public void onClick(View v) {
                Intent i = new Intent(SwitcherActivity.this, HomeActivity.class);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                startActivity(i);
                finish();
            }
        }));
    }

    /** 切换器常驻（singleInstance）：关掉时把它的任务放到后面，下次打开回到这个实例，只重新填列表。 */
    @Override public void finish() {
        if (!moveTaskToBack(true)) super.finish();
    }

    @Override protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        Perf.measure(root, "switcher (reused)");
        fill();
    }

    private View item(String label, Icons.Kind kind, android.graphics.drawable.Drawable icon, View.OnClickListener l) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(0, Ui.dp(this, 12), 0, Ui.dp(this, 12));
        if (kind != null) {
            r.addView(new Icons.IconView(this, kind), new LinearLayout.LayoutParams(Ui.dp(this, 40), Ui.dp(this, 40)));
        }
        if (icon != null) {
            ImageView iv = new ImageView(this);
            iv.setImageDrawable(icon);
            r.addView(iv, new LinearLayout.LayoutParams(Ui.dp(this, 48), Ui.dp(this, 48)));
        }
        android.widget.TextView t = Ui.text(this, label, blk ? 20 : 22, blk);
        t.setPadding(Ui.dp(this, (icon != null || kind != null) ? 16 : 0), 0, 0, 0);
        r.addView(t);
        r.setOnClickListener(l);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.addView(r);
        box.addView(blk ? Blocks.hair(this) : Ui.rule(this, 1, Color.LTGRAY));
        if (blk) { r.setClickable(true); Blocks.fast(r); }
        return box;
    }
}
