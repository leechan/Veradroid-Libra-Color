package com.veradroid.home;

import java.util.Calendar;
import java.util.TimeZone;

/**
 * 农历和二十四节气，全部在本机算，不联网。
 * 农历用系统自带的 ICU 中国历法（android.icu.util.ChineseCalendar，Android 7.0 起有），按北京时间当天中午换算；
 * 节气按太阳视黄经每 15° 一个，太阳黄经用低精度公式（Meeus《天文算法》第 25 章，误差约 0.01°，合十几分钟），
 * 只用来判断“节气落在哪一天”，够用。
 */
final class Lunar {
    private Lunar() { }

    private static final TimeZone CN = TimeZone.getTimeZone("Asia/Shanghai");
    private static final String[] MONTHS = { "正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊" };
    private static final String[] TERMS = { "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑", "白露",
        "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至", "小寒", "大寒", "立春", "雨水", "惊蛰" };

    /** 北京时间 y-m-d（m 从 1 起）当天 h 点的毫秒。 */
    static long at(int y, int m, int d, int h) {
        Calendar c = Calendar.getInstance(CN);
        c.clear();
        c.set(y, m - 1, d, h, 0, 0);
        return c.getTimeInMillis();
    }

    /** 农历月日，例如 {"十月", "廿四"}；闰月写成“闰四月”。算不出来返回 null。 */
    static String[] lunar(int y, int m, int d) {
        try {
            android.icu.util.ChineseCalendar cc = new android.icu.util.ChineseCalendar(android.icu.util.TimeZone.getTimeZone("Asia/Shanghai"),
                android.icu.util.ULocale.CHINA);
            cc.setTimeInMillis(at(y, m, d, 12));
            int mon = cc.get(android.icu.util.ChineseCalendar.MONTH);
            int day = cc.get(android.icu.util.ChineseCalendar.DAY_OF_MONTH);
            boolean leap = cc.get(android.icu.util.ChineseCalendar.IS_LEAP_MONTH) == 1;
            return new String[] { (leap ? "闰" : "") + MONTHS[Math.max(0, Math.min(11, mon))] + "月", dayName(day) };
        } catch (Throwable t) { return null; }
    }

    static String dayName(int d) {
        String[] n = { "一", "二", "三", "四", "五", "六", "七", "八", "九", "十" };
        if (d <= 10) return "初" + n[d - 1];
        if (d < 20) return "十" + n[d - 11];
        if (d == 20) return "二十";
        if (d < 30) return "廿" + n[d - 21];
        return "三十";
    }

    /** 这一天（北京时间）有节气就返回它的名字，没有返回 null。 */
    static String term(int y, int m, int d) {
        double a = sunLongitude(at(y, m, d, 0)), b = sunLongitude(at(y, m, d, 0) + 86400000L);
        int ka = (int) Math.floor(a / 15), kb = (int) Math.floor(b / 15);
        if (ka == kb) return null;
        return TERMS[((kb % 24) + 24) % 24];
    }

    /** 太阳视黄经（度，0..360）。 */
    static double sunLongitude(long utcMillis) {
        double jd = utcMillis / 86400000.0 + 2440587.5;
        double t = (jd - 2451545.0) / 36525.0;
        double l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
        double mm = Math.toRadians(357.52911 + 35999.05029 * t - 0.0001537 * t * t);
        double c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * Math.sin(mm) + (0.019993 - 0.000101 * t) * Math.sin(2 * mm) + 0.000289 * Math.sin(3 * mm);
        double om = Math.toRadians(125.04 - 1934.136 * t);
        double lon = l0 + c - 0.00569 - 0.00478 * Math.sin(om);
        lon %= 360;
        return lon < 0 ? lon + 360 : lon;
    }

    /** 日历格子里的小字：节气优先，初一写月份，其余写农历日。 */
    static String cellLabel(int y, int m, int d) {
        String t = term(y, m, d);
        if (t != null) return t;
        String[] l = lunar(y, m, d);
        if (l == null) return "";
        return "初一".equals(l[1]) ? l[0] : l[1];
    }
}
