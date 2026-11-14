// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;

/** Device credential survives app-data clears caused by full-image/package upgrades. */
final class Token {
    private static final File FILE = new File("/data/media/0/.veradroid/device_token");
    private Token() { }

    static String get(Context c) {
        String t = Store.prefs(c, "home").getString("device_token", "");
        if (t != null && t.length() > 0) return t;
        try {
            if (!FILE.isFile()) return "";
            byte[] b = new byte[(int) FILE.length()];
            FileInputStream in = new FileInputStream(FILE);
            int n = in.read(b); in.close();
            return n > 0 ? new String(b, 0, n, "UTF-8").trim() : "";
        } catch (Exception e) { return ""; }
    }

    static void put(Context c, String t) {
        Store.prefs(c, "home").edit().putString("device_token", t).commit();
        try {
            File dir = FILE.getParentFile();
            if (!dir.isDirectory() && !dir.mkdirs()) return;
            FileOutputStream out = new FileOutputStream(FILE);
            out.write(t.getBytes("UTF-8")); out.close();
            FILE.setReadable(false, false);
            FILE.setReadable(true, true);
        } catch (Exception ignored) { }
    }

    static void clear(Context c) {
        Store.prefs(c, "home").edit().remove("device_token").commit();
        try { FILE.delete(); } catch (Exception ignored) { }
    }
}
