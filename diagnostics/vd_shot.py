# SPDX-License-Identifier: GPL-3.0-or-later
import sys, zlib, struct
w, h = 1272, 1696
data = sys.stdin.buffer.read()
n = w * h
if len(data) < n: sys.exit("short read: %d" % len(data))
raw = b"".join(b"\x00" + data[y*w:(y+1)*w] for y in range(h))
def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
print("wrote", sys.argv[1], len(png))
