// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLDecoder;
import java.util.Map;

/** Generic HTTP download used by the transfer page's "paste a link" box. No cloud accounts. */
final class Cloud {
    private Cloud() { }

    interface Progress { void update(long done, long total); }

    private static HttpURLConnection open(String url, Map<String, String> headers) throws Exception {
        HttpURLConnection h = (HttpURLConnection) new URL(url).openConnection();
        h.setInstanceFollowRedirects(false);
        h.setConnectTimeout(20000);
        h.setReadTimeout(40000);
        h.setRequestMethod("GET");
        h.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 7.1.1) VeraDroid");
        if (headers != null) for (Map.Entry<String, String> e : headers.entrySet()) h.setRequestProperty(e.getKey(), e.getValue());
        return h;
    }

    private static String readAll(InputStream in) throws Exception {
        java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
        byte[] b = new byte[8192];
        int n;
        while (in != null && (n = in.read(b)) > 0) { bo.write(b, 0, n); if (bo.size() > 4 * 1024 * 1024) break; }
        return bo.toString("UTF-8");
    }

    /** Download url into dir (redirects allowed; never forwards auth headers to a different host). */
    static File download(String url, Map<String, String> headers, File dir, String nameHint, Progress p) throws Exception {
        String cur = url;
        Map<String, String> hdr = headers;
        String firstHost = new URL(url).getHost();
        for (int hop = 0; hop < 10; hop++) {
            HttpURLConnection h = open(cur, hdr);
            int code = h.getResponseCode();
            if (code >= 300 && code < 400 && h.getHeaderField("Location") != null) {
                String next = new URL(new URL(cur), h.getHeaderField("Location")).toString();
                h.disconnect();
                if (!new URL(next).getHost().equals(firstHost)) hdr = null;
                cur = next;
                continue;
            }
            if (code != 200) {
                String b = readAll(h.getErrorStream());
                h.disconnect();
                throw new Exception("HTTP " + code + (b.length() > 0 ? " " + b.substring(0, Math.min(120, b.length())) : ""));
            }
            String type = h.getContentType() == null ? "" : h.getContentType().toLowerCase();
            String name = nameFrom(h.getHeaderField("Content-Disposition"), nameHint, cur);
            if (type.startsWith("text/html") && !name.toLowerCase().endsWith(".html")) {
                h.disconnect();
                throw new Exception("对方返回的是网页，不是文件（链接可能没有公开，或需要登录）");
            }
            long total = h.getContentLength();
            File out = Transfer.uniqueFile(dir, name);
            InputStream in = new BufferedInputStream(h.getInputStream(), 65536);
            FileOutputStream fo = new FileOutputStream(out);
            byte[] buf = new byte[65536];
            long done = 0;
            int n;
            try {
                while ((n = in.read(buf)) > 0) { fo.write(buf, 0, n); done += n; if (p != null) p.update(done, total); }
            } catch (Exception e) {
                try { fo.close(); } catch (Exception ignored) { }
                out.delete();   // 下载中断：不留半个文件
                throw e;
            } finally { fo.close(); in.close(); h.disconnect(); }
            return out;
        }
        throw new Exception("重定向太多次");
    }

    private static String nameFrom(String disposition, String hint, String url) {
        try {
            if (disposition != null) {
                int i = disposition.toLowerCase().indexOf("filename*=");
                if (i >= 0) {
                    String v = disposition.substring(i + 10).split(";")[0].trim();
                    int q = v.indexOf("''");
                    if (q >= 0) v = v.substring(q + 2);
                    return Transfer.cleanName(URLDecoder.decode(v.replace("\"", ""), "UTF-8"));
                }
                i = disposition.toLowerCase().indexOf("filename=");
                if (i >= 0) {
                    String v = disposition.substring(i + 9).split(";")[0].trim().replace("\"", "");
                    return Transfer.cleanName(new String(v.getBytes("ISO-8859-1"), "UTF-8"));
                }
            }
        } catch (Exception ignored) { }
        if (hint != null && hint.length() > 0) return Transfer.cleanName(hint);
        try {
            String path = new URL(url).getPath();
            String last = path.substring(path.lastIndexOf('/') + 1);
            if (last.length() > 0) return Transfer.cleanName(URLDecoder.decode(last, "UTF-8"));
        } catch (Exception ignored) { }
        return "download-" + System.currentTimeMillis();
    }
}
