#!/usr/bin/env python3
"""Unpack a Kindle kernel for inspection (no device needed).

    kimage.py <boot.img | zImage> <out-prefix>

Writes <out>.Image (the raw kernel, loaded at 0x80008000) and <out>.config (CONFIG_IKCONFIG), and prints
the version banner. Kindle 4.1 kernels are Android boot images holding an LZO-compressed zImage; the LZO1X
decompressor is pure Python so nothing has to be installed on the build machine.
"""
import gzip
import struct
import sys


def lzo1x(src, dlen):
    out = bytearray(); ip = 0; n = len(src)
    def cp_match(mpos, cnt):
        dist = len(out) - mpos
        if dist <= 0: raise ValueError('bad dist')
        if dist >= cnt: out.extend(out[mpos:mpos+cnt])
        else:
            for k in range(cnt): out.append(out[mpos+k])
    t = src[ip]
    state = 'loop'
    if t > 17:
        ip += 1; t -= 17
        if t < 4:
            state = 'match_next'
        else:
            out.extend(src[ip:ip+t]); ip += t; state = 'first_literal_run'
    while True:
        if state == 'loop':
            t = src[ip]; ip += 1
            if t >= 16: state = 'match'; continue
            if t == 0:
                while src[ip] == 0: t += 255; ip += 1
                t += 15 + src[ip]; ip += 1
            out.extend(src[ip:ip+t+3]); ip += t+3
            state = 'first_literal_run'; continue
        if state == 'first_literal_run':
            t = src[ip]; ip += 1
            if t >= 16: state = 'match'; continue
            mpos = len(out) - (1 + 0x800) - (t >> 2) - (src[ip] << 2); ip += 1
            cp_match(mpos, 3); state = 'match_done'; continue
        if state == 'match':
            if t >= 64:
                mpos = len(out) - 1 - ((t >> 2) & 7) - (src[ip] << 3); ip += 1
                t = (t >> 5) - 1
                cp_match(mpos, t+2); state = 'match_done'; continue
            elif t >= 32:
                t &= 31
                if t == 0:
                    while src[ip] == 0: t += 255; ip += 1
                    t += 31 + src[ip]; ip += 1
                mpos = len(out) - 1 - ((src[ip] | (src[ip+1] << 8)) >> 2); ip += 2
            elif t >= 16:
                mpos = len(out) - ((t & 8) << 11)
                t &= 7
                if t == 0:
                    while src[ip] == 0: t += 255; ip += 1
                    t += 7 + src[ip]; ip += 1
                mpos -= (src[ip] | (src[ip+1] << 8)) >> 2; ip += 2
                if mpos == len(out): return bytes(out)
                mpos -= 0x4000
            else:
                mpos = len(out) - 1 - (t >> 2) - (src[ip] << 2); ip += 1
                cp_match(mpos, 2); state = 'match_done'; continue
            cp_match(mpos, t+2); state = 'match_done'; continue
        if state == 'match_done':
            t = src[ip-2] & 3
            if t == 0: state = 'loop'; continue
            state = 'match_next'; continue
        if state == 'match_next':
            out.extend(src[ip:ip+t]); ip += t
            t = src[ip]; ip += 1
            state = 'match'; continue

def kernel_of(raw):
    if raw[:8] != b'ANDROID!':
        return raw
    ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from('<8I', raw, 8)
    return raw[ps:ps + ks]


raw = kernel_of(open(sys.argv[1], 'rb').read()); outp = sys.argv[2]
M = b'\x89LZO\x00\r\n\x1a\n'
# the decompressor stub contains the magic too (in an error string): the real header has version 0x10xx
i = raw.find(M)
while i >= 0 and raw[i+9] != 0x10: i = raw.find(M, i+1)
assert i >= 0, 'no LZO payload (only LZO zImages are handled)'
d = raw[i:]
p = 9
ver, libver = struct.unpack_from('>HH', d, p); p += 4
if ver >= 0x0940: p += 2
method = d[p]; p += 1
if ver >= 0x0940: p += 1
flags = struct.unpack_from('>I', d, p)[0]; p += 4
if flags & 0x800: p += 4
p += 4 + 4
if ver >= 0x0940: p += 4
nl = d[p]; p += 1 + nl
p += 4
img = bytearray()
while True:
    dl = struct.unpack_from('>I', d, p)[0]; p += 4
    if dl == 0: break
    sl = struct.unpack_from('>I', d, p)[0]; p += 4
    if flags & 1: p += 4
    if flags & 0x100: p += 4
    if sl < dl:
        if flags & 2: p += 4
        if flags & 0x200: p += 4
        blk = lzo1x(d[p:p+sl], dl)
        assert len(blk) == dl, (len(blk), dl)
        img += blk
    else:
        img += d[p:p+sl]
    p += sl
open(outp + '.Image', 'wb').write(img); print('Image', len(img))
s = img.find(b'IKCFG_ST')
if s >= 0:
    e = img.find(b'IKCFG_ED', s)
    open(outp + '.config', 'wb').write(gzip.decompress(bytes(img[s+8:e]))); print('config extracted')
else: print('no IKCONFIG')
i = img.find(b'Linux version'); print(bytes(img[i:img.find(b'\n', i)]).decode(errors='replace'))
