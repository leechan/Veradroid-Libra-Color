#!/usr/bin/env python3
# Codegen-insensitive comparison of the struct offsets two kernels' versions of a function use.
#   fieldcmp.py devImage devMap ourImage ourMap func [func ...]
# Collects the immediates of memory operands [rN, #imm] (rN not sp/fp/pc) and of "add rX, rN, #imm"
# (address of a field) in each function; prints them as multisets and the difference. Register allocation,
# stack layout and literal-pool placement do not matter, so this still works where funccmp sees noise.
import os, sys, subprocess, re, collections
TC = os.environ.get('OBJDUMP', os.environ.get('AOSP_WORK', '.') + '/src/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-objdump')
def symtab(path):
    s = []
    for l in open(path):
        p = l.split()
        if len(p) >= 3 and len(p[0]) == 8:
            try: s.append((int(p[0], 16), p[2]))
            except ValueError: pass
    s.sort(); return s
def rng(tab, f):
    for i, (a, n) in enumerate(tab):
        if n == f:
            j = i + 1
            while j < len(tab) and tab[j][0] == a: j += 1
            return a, tab[j][0]
    return None
MEM = re.compile(r'\[(r\d+|ip|lr|sl), #(-?\d+)\]')
ADD = re.compile(r'^\s*(add|sub)\w*\s+\w+, (r\d+|ip|lr|sl), #(\d+)')
def offs(img, tab, f):
    r = rng(tab, f)
    if not r: return None
    out = subprocess.run([TC, '-D', '-b', 'binary', '-marm', '--adjust-vma=0x80008000', '--start-address=%#x' % r[0],
                          '--stop-address=%#x' % r[1], img], capture_output=True, text=True).stdout
    c = collections.Counter()
    for l in out.splitlines():
        if '\t' not in l: continue
        ins = l.split('\t', 2)[-1]
        for m in MEM.finditer(ins): c[int(m.group(2))] += 1
        m = ADD.match(ins)
        if m: c[('+' if m.group(1) == 'add' else '-') + m.group(3)] += 1
    return c
di, dm, oi, om = sys.argv[1:5]
dt, ot = symtab(dm), symtab(om)
for f in sys.argv[5:]:
    a = offs(di, dt, f); b = offs(oi, ot, f)
    if a is None or b is None: print('%-28s missing' % f); continue
    if a == b: print('%-28s SAME-OFFSETS %s' % (f, sorted(map(str, a.elements()))[:30])); continue
    print('%-28s DIFF dev-only %s ours-only %s' % (f, sorted(map(str, (a - b).elements())), sorted(map(str, (b - a).elements()))))
