#!/usr/bin/env python3
"""Checks the output of tests/vinput/emu-replay.sh: python3 emu-check.py OUTDIR"""
import os, sys
O = sys.argv[1]
SLOT, PX, PY, TID = 0x2f, 0x35, 0x36, 0x39
EXPECT = {'tap': ([], [], 'fwd'), 'swipe': ([], [], 'fwd'), 'edge_back': ([], [158], 'none'), 'edge_panel': (['panel'], [], 'none'),
          'corner': (['tl'], [], 'cancel'), 'two_tap': (['clear'], [], 'none'), 'two_long': (['invert'], [], 'none'),
          'two_back': ([], [158], 'none'), 'two_light': (['light +'], [], 'none'), 'two_warmth': (['warmth -'], [], 'none')}
fails = 0
for P in [p for p in ['B', 'A', 'AID', 'ST'] if os.path.exists(f'{O}/src.{p}')]:
    starts = [(float(l.split()[2]), l.split()[1]) for l in open(f'{O}/src.{P}') if l.startswith('start ')]
    ev = [l.split() for l in open(f'{O}/touch.{P}')]
    ev = [(float(a), int(b), int(c), int(d)) for a, b, c, d in ev]
    keys = [(float(a), int(c)) for a, b, c, d in (l.split() for l in open(f'{O}/keys.{P}')) if int(b) == 1 and int(d) == 1]
    acts = [l.strip() for l in open(f'{O}/act.{P}')] if os.path.exists(f'{O}/act.{P}') else []
    acts = [a for a in acts if a != 'poke']
    log = open(f'{O}/vi.{P}.log').read()
    print(f'== {P}: ' + ('converted (' + log.split('source is ')[1].split(':')[0] + ')' if 'source is' in log else 'protocol B path'))
    want_acts = []
    for i, (t0, name) in enumerate(starts):
        t1 = starts[i + 1][0] if i + 1 < len(starts) else 1e18
        seg = [e for e in ev if t0 <= e[0] < t1]
        k = [c for t, c in keys if t0 <= t < t1]
        slots, cur, frames = {}, 0, []
        for t, ty, c, v in seg:
            if ty == 3 and c == SLOT: cur = v
            elif ty == 3 and c == TID: (slots.pop(cur, None) if v < 0 else slots.__setitem__(cur, [None, None]))
            elif ty == 3 and c in (PX, PY) and cur in slots: slots[cur][c - PX] = v
            elif ty == 0 and c == 0: frames.append(tuple(sorted(tuple(p) for p in slots.values())))
        ea, ek, fwd = EXPECT[name]
        want_acts += ea
        ok = k == ek
        if fwd == 'fwd':
            ok = ok and frames and frames[-1] == () and all(len(f) <= 1 for f in frames) and len(frames) >= 2
            lat = (seg[0][0] - t0) * 1000 if seg else -1
            ok = ok and 0 <= lat <= 40 + 30
            detail = f'{len(frames)} frames to Android, first {frames[0] if frames else None}, down forwarded after {lat:.0f} ms'
        elif fwd == 'none':
            ok = ok and all(f == () for f in frames); detail = f'{len(frames)} touch frames to Android'
        else:
            ok = ok and frames and frames[-1] == (); detail = f'press then cancel ({len(frames)} frames)'
        print(('  ok   ' if ok else '  FAIL ') + f'{name}: keys {k}; {detail}')
        fails += not ok
    ok = acts == want_acts
    print(('  ok   ' if ok else '  FAIL ') + f'actions in order: {acts}')
    fails += not ok
print('FAILED %d' % fails if fails else 'all passed')
sys.exit(1 if fails else 0)
