#!/usr/bin/env python3
# Compare every function of two ARM32 kernel images word by word (the device kernel against a
# reference build of the closest source, to find where Amazon changed structures).
#   funccmp.py devImage devKallsyms ourImage ourSystemMap [func ...]
# Branch targets and literal-pool addresses are compared by symbol name (+offset), so code that is the
# same apart from where things were linked counts as identical. Prints a summary, then per-function lines
# "SAME|DIFF|SIZE name ndiff/nwords".  With func names: also prints the differing words of those functions.
import sys, struct, bisect
def load_map(path):
    syms = []
    for l in open(path):
        p = l.split()
        if len(p) < 3: continue
        try: a = int(p[0], 16)
        except ValueError: continue
        syms.append((a, p[1], p[2]))
    syms.sort()
    return syms
class K:
    def __init__(s, img, mp):
        s.img = open(img, 'rb').read(); s.syms = load_map(mp)
        s.base = [a for a, t, n in s.syms if n == '_text'][0]
        s.syms = [x for x in s.syms if s.base <= x[0] < s.base + len(s.img)]
        s.addrs = [a for a, t, n in s.syms]
        s.byname = {}
        for i, (a, t, n) in enumerate(s.syms):
            if t in 'tTwW': s.byname.setdefault(n, []).append(i)
    def word(s, a): return struct.unpack_from('<I', s.img, a - s.base)[0]
    def size(s, i):
        a = s.syms[i][0]; j = i + 1
        while j < len(s.syms) and s.syms[j][0] == a: j += 1
        return (s.syms[j][0] - a) if j < len(s.syms) else 0
    def name(s, a):
        i = bisect.bisect_right(s.addrs, a) - 1
        if i < 0: return '?'
        # prefer a global name at that address
        b = s.syms[i][0]; k = i
        while k > 0 and s.syms[k-1][0] == b: k -= 1
        cands = [s.syms[j] for j in range(k, i + 1)]
        n = sorted(cands, key=lambda x: (x[1].islower(), x[2]))[0][2]
        return '%s+%x' % (n, a - b)
def is_addr(w): return 0x80000000 <= w < 0xc0000000
def same(d, o, da, oa, dw, ow):
    if dw == ow: return True
    if (dw >> 25) & 7 == 5 and (ow >> 25) & 7 == 5 and dw >> 24 == ow >> 24:
        def tgt(a, w):
            off = w & 0xffffff
            if off & 0x800000: off -= 0x1000000
            return a + 8 + off * 4
        return d.name(tgt(da, dw)) == o.name(tgt(oa, ow))
    if is_addr(dw) and is_addr(ow):
        return d.name(dw) == o.name(ow)
    return False
d = K(sys.argv[1], sys.argv[2]); o = K(sys.argv[3], sys.argv[4]); want = set(sys.argv[5:])
res = {'SAME': 0, 'DIFF': 0, 'SIZE': 0}
out = []
for n, il in o.byname.items():
    if len(il) != 1 or n not in d.byname or len(d.byname[n]) != 1: continue
    oi = il[0]; di = d.byname[n][0]
    oa = o.syms[oi][0]; da = d.syms[di][0]
    os_, ds = o.size(oi), d.size(di)
    if os_ == 0 or ds == 0 or os_ > 1 << 20: continue
    nw = min(os_, ds) // 4
    bad = [k for k in range(nw) if not same(d, o, da + 4*k, oa + 4*k, d.word(da + 4*k), o.word(oa + 4*k))]
    st = 'SAME' if not bad and os_ == ds else ('SIZE' if os_ != ds else 'DIFF')
    res[st] += 1
    out.append('%s %s %d/%d %d %d' % (st, n, len(bad), nw, ds, os_))
    if n in want:
        for k in bad[:40]:
            print('  %s +%x dev %08x ours %08x' % (n, 4*k, d.word(da+4*k), o.word(oa+4*k)))
print('summary', res)
for l in sorted(out): print(l)
