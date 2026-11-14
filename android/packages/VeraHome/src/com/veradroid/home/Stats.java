// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.BatteryManager;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** Small local usage ledger: battery samples and reading time/pages. */
final class Stats {
    private static final String P = "usage_stats";

    private Stats() { }

    private static SharedPreferences p(Context c) { return Store.prefs(c, P); }
    private static String day() { return new SimpleDateFormat("yyyyMMdd", Locale.US).format(new Date()); }

    static void sampleBattery(Context c) {
        int pct = -1; boolean charging = false;
        try {
            BatteryManager bm = (BatteryManager) c.getSystemService(Context.BATTERY_SERVICE);
            if (bm != null) {
                pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
                charging = bm.isCharging();
            }
        } catch (Throwable ignored) { }
        sampleBattery(c, pct, charging);
    }

    static void sampleBattery(Context c, int pct, boolean charging) {
        if (pct < 0) return;
        SharedPreferences sp = p(c);
        String d = day();
        long now = System.currentTimeMillis();
        int start = sp.getInt("batt." + d + ".start", -1);
        long startTs = sp.getLong("batt." + d + ".startTs", 0);
        if (charging) {
            start = -1;
            startTs = 0;
        } else if (start < 0) {
            start = pct;
            startTs = now;
        }
        sp.edit()
          .putInt("batt." + d + ".start", start)
          .putLong("batt." + d + ".startTs", startTs)
          .putInt("batt." + d + ".last", pct)
          .putLong("batt." + d + ".lastTs", now)
          .putBoolean("batt." + d + ".charging", charging)
          .apply();
    }

    static String[] batteryLines(Context c) {
        int pct = -1; boolean charging = false;
        try {
            BatteryManager bm = (BatteryManager) c.getSystemService(Context.BATTERY_SERVICE);
            if (bm != null) {
                pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
                charging = bm.isCharging();
            }
        } catch (Throwable ignored) { }
        sampleBattery(c, pct, charging);
        SharedPreferences sp = p(c);
        String d = day();
        int start = sp.getInt("batt." + d + ".start", -1);
        long startTs = sp.getLong("batt." + d + ".startTs", 0);
        int last = sp.getInt("batt." + d + ".last", pct);
        long lastTs = sp.getLong("batt." + d + ".lastTs", 0);
        String drain = "今天还没有耗电记录";
        String rate = "插电时暂停统计";
        if (!charging && start >= 0 && last >= 0 && lastTs > startTs) {
            int used = Math.max(0, start - last);
            double hours = (lastTs - startTs) / 3600000.0;
            drain = "今日耗电 " + used + "%（从 " + start + "% 到 " + last + "%）";
            if (hours >= 0.15) rate = "约 " + String.format(Locale.US, "%.1f", used / hours) + "% / 小时";
        }
        return new String[] {
            pct >= 0 ? "当前电量 " + pct + "%" : "当前电量未知",
            charging ? "正在充电 · 耗电统计暂停" : "使用中",
            drain, rate
        };
    }

    static void addReading(Context c, long ms, int pages) {
        if (ms <= 0 && pages <= 0) return;
        SharedPreferences sp = p(c);
        String d = day();
        long todayMs = sp.getLong("read." + d + ".ms", 0) + Math.max(0, ms);
        int todayPages = sp.getInt("read." + d + ".pages", 0) + Math.max(0, pages);
        sp.edit()
          .putLong("read." + d + ".ms", todayMs)
          .putInt("read." + d + ".pages", todayPages)
          .putLong("read.total.ms", sp.getLong("read.total.ms", 0) + Math.max(0, ms))
          .putInt("read.total.pages", sp.getInt("read.total.pages", 0) + Math.max(0, pages))
          .apply();
    }

    static String[] readingLines(Context c) {
        SharedPreferences sp = p(c);
        String d = day();
        long todayMs = sp.getLong("read." + d + ".ms", 0);
        int todayPages = sp.getInt("read." + d + ".pages", 0);
        long weekMs = 0; int weekPages = 0;
        SimpleDateFormat f = new SimpleDateFormat("yyyyMMdd", Locale.US);
        long now = System.currentTimeMillis();
        for (int i = 0; i < 7; i++) {
            String k = f.format(new Date(now - i * 86400000L));
            weekMs += sp.getLong("read." + k + ".ms", 0);
            weekPages += sp.getInt("read." + k + ".pages", 0);
        }
        return new String[] {
            "今日 " + duration(todayMs) + " · " + todayPages + " 页",
            "本周 " + duration(weekMs) + " · " + weekPages + " 页",
            "累计 " + duration(sp.getLong("read.total.ms", 0)) + " · " + sp.getInt("read.total.pages", 0) + " 页"
        };
    }

    static String duration(long ms) {
        long min = Math.max(0, ms) / 60000L;
        if (min < 60) return min + " 分钟";
        return (min / 60) + " 小时 " + (min % 60) + " 分";
    }

    /** 最近 days 天（含今天）的阅读毫秒数（方块主页“本周阅读时长”、“我的”页本月）。 */
    static long readingMs(Context c, int days) {
        SharedPreferences sp = p(c);
        SimpleDateFormat f = new SimpleDateFormat("yyyyMMdd", Locale.US);
        long now = System.currentTimeMillis(), ms = 0;
        for (int i = 0; i < days; i++) ms += sp.getLong("read." + f.format(new Date(now - i * 86400000L)) + ".ms", 0);
        return ms;
    }

    /** 本周（周一起）的阅读毫秒数。 */
    static long weekMs(Context c) {
        java.util.Calendar cal = java.util.Calendar.getInstance();
        int dow = (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7;   // 周一 = 0
        return readingMs(c, dow + 1);
    }

    /** 本月的阅读毫秒数。 */
    static long monthMs(Context c) { return readingMs(c, java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_MONTH)); }

    /** “12h 19m” 这种短写法（方块风格的统计格）。 */
    static String shortDuration(long ms) {
        long min = Math.max(0, ms) / 60000L;
        return min < 60 ? min + "m" : (min / 60) + "h " + (min % 60) + "m";
    }

    /** 所有书的书签总数（阅读器存在 reader 偏好的 bm:<路径>，分号隔开）。 */
    static int bookmarkCount(Context c) {
        int n = 0;
        try {
            for (java.util.Map.Entry<String, ?> e : Store.prefs(c, "reader").getAll().entrySet())
                if (e.getKey().startsWith("bm:") && e.getValue() instanceof String)
                    for (String x : ((String) e.getValue()).split(";")) if (x.length() > 0) n++;
        } catch (Throwable ignored) { }
        return n;
    }
}
