/*
 * VeraDroid: "hostnet" mode for Kindles whose kernel has no network namespaces (3.0.35: PW2 / PW3 / Oasis 1/2 /
 * Voyage / basic 2014-2016). Android then shares the Kindle's own network stack, so it must not run DHCP or change
 * the interface (that would take the Kindle's Wi-Fi address away). The host writes what the Kindle already has to
 * /dev/kfb/hostnet before Android starts:
 *
 *   iface=wlan0
 *   addr=192.0.2.23/24
 *   gw=192.0.2.1
 *   dns=192.0.2.1
 *   dns=223.5.5.5
 *
 * and passes androidboot.vdhostnet=1 (ro.boot.vdhostnet). EthernetNetworkFactory then tracks only that interface
 * and registers a connected network with exactly these link properties. netd's matching patches turn every
 * interface / route / iptables change into a no-op in this mode (small-patches.py).
 * On every other Kindle the property is absent and nothing here is used.
 */
package com.android.server.ethernet;

import android.net.IpPrefix;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.NetworkUtils;
import android.net.RouteInfo;
import android.os.SystemProperties;
import android.util.Log;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.net.InetAddress;

final class VdHostNet {
    private static final String TAG = "VdHostNet";
    private static final String FILE = "/dev/kfb/hostnet";

    private VdHostNet() {}

    static boolean enabled() {
        return "1".equals(SystemProperties.get("ro.boot.vdhostnet", "0"));
    }

    /** The Kindle interface to track, or null when hostnet mode is off or the host wrote nothing usable. */
    static String iface() {
        if (!enabled()) return null;
        String[] v = read();
        return v == null ? null : v[0];
    }

    /** Link properties for {@code iface} as the Kindle has them now, or null (then the normal code path runs). */
    static LinkProperties linkProperties(String iface) {
        if (!enabled() || iface == null) return null;
        String[] v = read();
        if (v == null || !iface.equals(v[0]) || v[1] == null) return null;
        try {
            LinkProperties lp = new LinkProperties();
            lp.setInterfaceName(iface);
            lp.addLinkAddress(new LinkAddress(v[1]));
            if (v[2] != null) {
                lp.addRoute(new RouteInfo((IpPrefix) null, NetworkUtils.numericToInetAddress(v[2]), iface));
            }
            if (v[3] != null) {
                for (String d : v[3].split(",")) {
                    if (!d.isEmpty()) lp.addDnsServer(NetworkUtils.numericToInetAddress(d));
                }
            }
            Log.i(TAG, "using the Kindle's network as-is: " + lp);
            return lp;
        } catch (IllegalArgumentException e) {
            Log.e(TAG, "bad " + FILE + ": " + e);
            return null;
        }
    }

    /** {iface, addr/prefix, gateway, comma-separated dns} */
    private static String[] read() {
        String iface = null, addr = null, gw = null;
        StringBuilder dns = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new FileReader(FILE))) {
            String line;
            while ((line = r.readLine()) != null) {
                int eq = line.indexOf('=');
                if (eq <= 0) continue;
                String k = line.substring(0, eq).trim(), val = line.substring(eq + 1).trim();
                if (val.isEmpty()) continue;
                switch (k) {
                    case "iface": iface = val; break;
                    case "addr": addr = val; break;
                    case "gw": gw = val; break;
                    case "dns": if (dns.length() > 0) dns.append(','); dns.append(val); break;
                    default: break;
                }
            }
        } catch (IOException e) {
            return null;
        }
        if (iface == null) return null;
        return new String[] { iface, addr, gw, dns.length() > 0 ? dns.toString() : null };
    }
}
