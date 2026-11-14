#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Aggregate bench.sh output: median per label. usage: agg.py < raw.txt"""
import sys, statistics, collections
rows = collections.OrderedDict()
for line in sys.stdin:
    p = line.split()
    if len(p) < 4 or p[0] != 'R': continue
    d = dict(x.split('=', 1) for x in p[3:] if '=' in x)
    rows.setdefault(p[1], []).append(d)
def med(rs, k):
    v = [float(r[k]) for r in rs if r.get(k, '-') not in ('-', '')]
    return ('%.0f' % statistics.median(v)) if v else '-'
print('%-26s %4s %6s %6s %6s %4s %6s %5s %5s %5s %5s %5s %5s %6s' % ('scenario', 'runs', 'first', 'last', 'done', 'n', 'frames', 'area%', 'app', 'sf', 'ss', 'epd', 'busy%', 'majflt'))
for lab, rs in rows.items():
    print('%-26s %4d %6s %6s %6s %4s %6s %5s %5s %5s %5s %5s %5s %6s' % (lab, len(rs), med(rs, 'first'), med(rs, 'last'), med(rs, 'done'), med(rs, 'n'), med(rs, 'frames'), med(rs, 'area'), med(rs, 'app'), med(rs, 'sf'), med(rs, 'ss'), med(rs, 'epd'), med(rs, 'busy'), med(rs, 'majflt')))
