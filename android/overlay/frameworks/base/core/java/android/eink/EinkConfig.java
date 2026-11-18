package android.eink;

import android.os.SystemProperties;
import android.text.TextUtils;

/**
 * System-side e-ink policies (VeraDroid), all read from properties so the host / settings can change them without
 * a new image. Used by WindowManagerService (starting windows) and ActivityManagerService (OOM cap).
 * @hide
 */
public final class EinkConfig {
    private EinkConfig() { }

    /**
     * Starting windows (the theme-coloured "splash" a launch shows before the app's first frame) cost one extra
     * full-screen panel update per launch on e-ink.
     * None, except for packages in persist.vd.splash.allow (comma list). persist.vd.splash=1 restores stock Android.
     */
    public static boolean allowStartingWindow(String pkg) {
        if (SystemProperties.getBoolean("persist.vd.splash", false)) return true;
        return pkg != null && inList(SystemProperties.get("persist.vd.splash.allow", ""), pkg);
    }

    /**
     * Highest OOM adj for a package's main process, -1 = no cap.
     * persist.vd.oomcap = "pkg:adj,pkg:adj"; default keeps the input method perceptible (200) without making it
     * persistent. "none" turns the cap off.
     */
    public static int oomCap(String pkg) {
        if (pkg == null) return -1;
        String v = SystemProperties.get("persist.vd.oomcap", "com.veradroid.ime:200");
        if (TextUtils.isEmpty(v) || "none".equals(v)) return -1;
        for (String e : v.split(",")) {
            int i = e.indexOf(':');
            if (i > 0 && pkg.equals(e.substring(0, i).trim())) {
                try {
                    int adj = Integer.parseInt(e.substring(i + 1).trim());
                    return adj >= 0 && adj <= 999 ? adj : -1;
                } catch (NumberFormatException x) {
                    return -1;
                }
            }
        }
        return -1;
    }

    static boolean inList(String list, String pkg) {
        if (TextUtils.isEmpty(list)) return false;
        for (String e : list.split(",")) if (pkg.equals(e.trim())) return true;
        return false;
    }
}
