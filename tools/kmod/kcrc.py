#!/usr/bin/env python3
# All exported-symbol CRCs (modversions) of a raw ARM kernel Image, using the device's /proc/kallsyms for
# the __ksymtab / __kcrctab bounds. These are the CRCs a module must carry to load on that kernel.
#   kcrc.py Image kallsyms  -> "0xcrc\tname" lines
import sys, struct
img = open(sys.argv[1], 'rb').read()
ks = {}
for l in open(sys.argv[2]):
    p = l.split()
    if len(p) >= 3: ks.setdefault(p[2], int(p[0], 16))
base = ks['_text']
def u32(a): return struct.unpack_from('<I', img, a - base)[0]
def cstr(a):
    o = a - base; return img[o:img.index(b'\0', o)].decode()
for t in ('', '_gpl'):
    s, e, c = ks['__start___ksymtab' + t], ks['__stop___ksymtab' + t], ks['__start___kcrctab' + t]
    for i in range((e - s) // 8):
        name = cstr(u32(s + i * 8 + 4))
        print('0x%08x\t%s' % (u32(c + i * 4), name))
