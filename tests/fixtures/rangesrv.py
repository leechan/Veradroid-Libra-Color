#!/usr/bin/env python3
"""Test server for tests/dl-block-test.sh: serves ROOT on 127.0.0.1, port written to PORTFILE.
   /main/<path>          the file ROOT/<path> (Range -> 206, as the live site and dl.wenjin.jp)
   /m-ok/main/<path>     mirror: same file
   /m-404/...            mirror that has nothing (404, like dl.wenjin.jp for the metadata today)
   /m-bad/main/<path>    mirror with other content of the same size (sha256 mismatch)
   /m-slow/main/<path>   mirror that waits 1 s before answering
   /m-norange/main/<p>   mirror that ignores Range (200, whole file)
Every request is logged to ROOT/../requests.log (first path component + path)."""
import http.server, os, re, sys, time
ROOT, PORTFILE = sys.argv[1], sys.argv[2]
LOG = os.path.join(os.path.dirname(os.path.abspath(ROOT)), 'requests.log')


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        p = self.path.split('?')[0]
        with open(LOG, 'a') as f:
            f.write('%s %s\n' % (p, self.headers.get('Range', '-')))
        parts = p.lstrip('/').split('/', 1)
        mode = parts[0]
        rest = parts[1] if len(parts) > 1 else ''
        if mode.startswith('m-'):
            if mode == 'm-404' or not rest.startswith('main/'):
                return self.send_error(404)
            rest = rest[len('main/'):]
            if mode == 'm-slow':
                time.sleep(1.0)
        elif mode != 'main':
            return self.send_error(404)
        f = os.path.join(ROOT, rest)
        if not rest or '..' in rest or not os.path.isfile(f):
            return self.send_error(404)
        data = open(f, 'rb').read()
        if mode == 'm-bad':
            data = bytes(b ^ 0x55 for b in data)
        start, end = 0, len(data) - 1
        m = re.match(r'bytes=(\d+)-(\d*)', self.headers.get('Range', ''))
        if m and mode != 'm-norange' and int(m.group(1)) < len(data):
            start = int(m.group(1))
            end = min(int(m.group(2)), len(data) - 1) if m.group(2) else len(data) - 1
            self.send_response(206)
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, len(data)))
        else:
            self.send_response(200)
        self.send_header('Content-Length', str(end + 1 - start))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        try:
            self.wfile.write(data[start:end + 1])
        except (BrokenPipeError, ConnectionResetError):
            pass


s = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
with open(PORTFILE + '.tmp', 'w') as f:
    f.write(str(s.server_address[1]))
os.replace(PORTFILE + '.tmp', PORTFILE)
s.serve_forever()
