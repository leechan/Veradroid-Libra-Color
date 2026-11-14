#!/usr/bin/env python3
"""Native veradroid-input test (driven by tests/vinput-test.sh, needs Linux: gcc + linux/input.h).

Feeds synthetic touch streams in three source protocols into a natively built veradroid-input through fakeevdev.so
(LD_PRELOAD: the touch device is a FIFO, uinput writes go to files) and checks:
  - every gesture fires its action / key, for protocol B (goodix-ts gtx8 framing), A (with and without
    ABS_MT_TRACKING_ID) and single touch (where a gesture needs only one finger);
  - normal one-finger taps / swipes reach the virtual touch screen with the same contacts as with a B panel, and the
    touch-down is forwarded no later than the existing two-finger decision window (+ one 10 ms poll tick + slack);
  - with --base OLD_BINARY: for protocol B the new binary's output (touch + key events + actions) is identical to the
    old one's, event for event.
usage: run.py NEW_BINARY SHIM.so [--base OLD_BINARY]
"""
import os, struct, subprocess, sys, tempfile, time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, SYN_MT_REPORT = 0, 2
BTN_TOUCH = 0x14a
ABS_X, ABS_Y = 0, 1
SLOT, MAJOR, PX, PY, TID, PRES = 0x2f, 0x30, 0x35, 0x36, 0x39, 0x3a
KEY_BACK = 158
EVFMT = 'llHHi'
EVSZ = struct.calcsize(EVFMT)
UDEV_SZ = 80 + 8 + 4 + 64 * 4 * 4          # struct uinput_user_dev
WINDOW = 40
ARGS = ['--w', '1272', '--h', '1696', '--edge', '120', '--window', str(WINDOW), '--edge-hold', '60', '--edge-swipe', '80',
        '--edge-back', '1', '--corner-ms', '2000']


class Encoder:
    """turns a list of fingers [(fid, x, y), ...] per frame into what a driver of that protocol sends"""
    def __init__(self, proto):
        self.p = proto; self.prev = {}; self.btn = 0; self.slot = -1; self.stx = self.sty = None; self.n = 0

    def frame(self, fingers):
        ev = []
        cur = {f: (x, y) for f, x, y in fingers}
        if self.p == 'B':                       # goodix_ts_report_finger after the input core's filtering
            if cur and not self.btn: ev.append((EV_KEY, BTN_TOUCH, 1))
            if not cur and self.btn: ev.append((EV_KEY, BTN_TOUCH, 0))
            for s in range(10):
                if s in self.prev and s not in cur:
                    if self.slot != s: ev.append((EV_ABS, SLOT, s)); self.slot = s
                    ev.append((EV_ABS, TID, -1))
                elif s in cur:
                    old = self.prev.get(s)
                    vals = []
                    if old is None: vals.append((TID, s))
                    if old is None or old[0] != cur[s][0]: vals.append((PX, cur[s][0]))
                    if old is None or old[1] != cur[s][1]: vals.append((PY, cur[s][1]))
                    if old is None: vals.append((MAJOR, 30))
                    if vals and self.slot != s: ev.append((EV_ABS, SLOT, s)); self.slot = s
                    ev += [(EV_ABS, c, v) for c, v in vals]
        elif self.p in ('A', 'AID'):
            self.n += 1                         # protocol A has no order: send the contacts reversed every other frame
            for f, (x, y) in sorted(cur.items(), reverse=self.n % 2 == 0):
                if self.p == 'AID': ev.append((EV_ABS, TID, 100 + f))
                ev += [(EV_ABS, PX, x), (EV_ABS, PY, y), (EV_ABS, MAJOR, 30), (EV_SYN, SYN_MT_REPORT, 0)]
            if not cur: ev.append((EV_SYN, SYN_MT_REPORT, 0))
            if cur and not self.btn: ev.append((EV_KEY, BTN_TOUCH, 1))
            if not cur and self.btn: ev.append((EV_KEY, BTN_TOUCH, 0))
        else:                                   # ST: one finger only
            if cur:
                x, y = list(cur.values())[0]
                if x != self.stx: ev.append((EV_ABS, ABS_X, x)); self.stx = x
                if y != self.sty: ev.append((EV_ABS, ABS_Y, y)); self.sty = y
            if cur and not self.btn: ev.append((EV_KEY, BTN_TOUCH, 1))
            if not cur and self.btn: ev.append((EV_KEY, BTN_TOUCH, 0))
        self.btn = 1 if cur else 0
        self.prev = cur
        ev.append((EV_SYN, SYN_REPORT, 0))
        return ev


def path(points, ms, steps=12):
    """one finger moving from points[0] to points[1] in ms: list of (t_ms, x, y)"""
    (x1, y1), (x2, y2) = points
    return [(ms * i // steps, x1 + (x2 - x1) * i // steps, y1 + (y2 - y1) * i // steps) for i in range(steps + 1)]


def scenario(name):
    """-> list of (t_ms, fingers) frames; the last one is all-up"""
    S = {}
    S['tap'] = [(0, [(0, 500, 800)]), (60, [(0, 500, 800)]), (80, [])]
    S['swipe'] = [(t, [(0, x, y)]) for t, x, y in path(((900, 800), (200, 820)), 300)] + [(320, [])]
    S['vswipe'] = [(t, [(0, x, y)]) for t, x, y in path(((600, 1200), (610, 400)), 300)] + [(320, [])]
    S['edge_back'] = [(t, [(0, x, y)]) for t, x, y in path(((636, 1680), (636, 1450)), 80, 4)] + [(100, [])]
    S['edge_back_slow'] = [(t, [(0, x, y)]) for t, x, y in path(((636, 1680), (636, 1450)), 150, 6)] + [(170, [])]
    S['edge_panel'] = [(t, [(0, x, y)]) for t, x, y in path(((636, 10), (636, 300)), 150, 6)] + [(170, [])]
    S['edge_tap'] = [(0, [(0, 636, 1660)]), (40, [(0, 636, 1660)]), (60, [])]
    # corner long press with frames every 200 ms, outside the top / bottom edge strips (--edge 120 < corner 160)
    S['corner'] = [(t, [(0, 50, 140)]) for t in range(0, 2400, 200)] + [(2450, [])]
    # corner long press starting INSIDE an edge strip (fix/corner-in-edge): the finger is held still, so after the
    # touch-down the driver sends nothing until the release -- only the poll tick can see the 2 s run out
    for c, (x, y) in {'tl': (50, 50), 'tr': (1222, 50), 'bl': (50, 1650), 'br': (1222, 1650)}.items():
        S['corner_strip_' + c] = [(0, [(0, x, y)]), (2450, [])]
    S['corner_strip_moving'] = [(t, [(0, 50 + (t // 200) % 2, 1650)]) for t in range(0, 2400, 200)] + [(2450, [])]
    # an edge swipe that starts in a corner is still back / panel; a tap in a corner inside the strip still reaches
    # Android; a long press in the strip outside the corners is not a gesture
    S['corner_swipe_back'] = [(t, [(0, x, y)]) for t, x, y in path(((60, 1680), (60, 1450)), 80, 4)] + [(100, [])]
    S['corner_swipe_panel'] = [(t, [(0, x, y)]) for t, x, y in path(((1212, 10), (1212, 300)), 150, 6)] + [(170, [])]
    S['corner_strip_tap'] = [(0, [(0, 50, 1650)]), (40, [(0, 50, 1650)]), (60, [])]
    S['strip_long'] = [(0, [(0, 636, 1650)]), (2450, [])]
    S['two_tap'] = [(0, [(0, 400, 800), (1, 800, 800)]), (80, [(0, 401, 800), (1, 800, 801)]), (150, [])]
    S['two_stagger'] = [(0, [(0, 400, 800)]), (20, [(0, 400, 800), (1, 800, 800)]), (150, [])]
    S['two_long'] = [(t, [(0, 400, 800), (1, 800, 800)]) for t in range(0, 2400, 200)] + [(2450, [])]
    S['two_back'] = [(t, [(0, 300 + 500 * i // 10, 800), (1, 300 + 500 * i // 10, 1000)]) for i, t in
                     enumerate(range(0, 220, 20))] + [(240, [])]
    S['two_light'] = [(t, [(0, 300, 1200 - 50 * i), (1, 400, 1200 - 50 * i)]) for i, t in
                      enumerate(range(0, 220, 20))] + [(240, [])]
    S['two_warmth'] = [(t, [(0, 900, 600 + 50 * i), (1, 1000, 600 + 50 * i)]) for i, t in
                       enumerate(range(0, 220, 20))] + [(240, [])]
    # every two-finger gesture off: two fingers go to Android (pinch); finger 0 moves left, finger 1 right
    S['pinch'] = [(t, [(0, 600 - 30 * i, 800), (1, 700 + 30 * i, 820)]) for i, t in enumerate(range(0, 220, 20))] + [(240, [])]
    # one of two fingers lifts, the other keeps moving (pinch off -> Android): the right one must keep its slot
    S['pinch_lift'] = ([(t, [(0, 400, 800), (1, 800 + 10 * i, 800)]) for i, t in enumerate(range(0, 100, 20))] +
                       [(t, [(1, 850 + 10 * i, 800)]) for i, t in enumerate(range(100, 200, 20))] + [(220, [])])
    return S[name]


EXPECT = {   # name -> (actions in the log, keys, touch reaches Android)
    'tap': ([], [], True), 'swipe': ([], [], True), 'vswipe': ([], [], True), 'edge_tap': ([], [], True),
    'edge_back': ([], [KEY_BACK], False), 'edge_back_slow': ([], [KEY_BACK], 'cancel'), 'edge_panel': (['panel'], [], False),
    'corner': (['tl'], [], 'cancel'),
    'corner_strip_tl': (['tl'], [], 'cancel'), 'corner_strip_tr': (['tr'], [], 'cancel'),
    'corner_strip_bl': (['bl'], [], 'cancel'), 'corner_strip_br': (['br'], [], 'cancel'),
    'corner_strip_moving': (['bl'], [], 'cancel'),
    'corner_swipe_back': (['hint back'], [KEY_BACK], False), 'corner_swipe_panel': (['panel'], [], False),
    'corner_strip_tap': ([], [], True), 'strip_long': ([], [], True),
    'two_tap': (['clear'], [], False), 'two_stagger': (['clear'], [], False), 'two_long': (['invert'], [], False),
    'two_back': ([], [KEY_BACK], False), 'pinch': ([], [], True), 'pinch_lift': ([], [], True), 'two_light': (['light +'], [], False), 'two_warmth': (['warmth -'], [], False),
}
ONE = ['tap', 'swipe', 'vswipe', 'edge_tap', 'edge_back', 'edge_back_slow', 'edge_panel', 'corner',
       'corner_strip_tl', 'corner_strip_tr', 'corner_strip_bl', 'corner_strip_br', 'corner_strip_moving',
       'corner_swipe_back', 'corner_swipe_panel', 'corner_strip_tap', 'strip_long']
# behaviour this branch changes on purpose: the base binary fires nothing for these (corner check only in PASS)
CHANGED = {'corner_strip_tl', 'corner_strip_tr', 'corner_strip_bl', 'corner_strip_br', 'corner_strip_moving'}
PINCH = ['pinch', 'pinch_lift']
TWO = ['two_tap', 'two_stagger', 'two_long', 'two_back', 'two_light', 'two_warmth']


def read_events(fn, skip_udev):
    if not os.path.exists(fn): return []
    b = open(fn, 'rb').read()
    if skip_udev: b = b[UDEV_SZ:]
    return [struct.unpack(EVFMT, b[i:i + EVSZ]) for i in range(0, len(b) - EVSZ + 1, EVSZ)]


def decode_mt(evs):
    """virtual protocol-B stream -> list of frames, each a sorted tuple of (x, y) of the active contacts"""
    slots, cur, frames = {}, 0, []
    for _, _, t, c, v in evs:
        if t == EV_ABS and c == SLOT: cur = v
        elif t == EV_ABS and c == TID:
            if v < 0: slots.pop(cur, None)
            else: slots[cur] = [None, None]
        elif t == EV_ABS and c in (PX, PY) and cur in slots: slots[cur][c - PX] = v
        elif t == EV_SYN and c == SYN_REPORT:
            f = tuple(sorted(tuple(p) for p in slots.values()))
            if not frames or frames[-1] != f: frames.append(f)
    return frames


def run(binary, shim, proto, name):
    d = tempfile.mkdtemp(prefix='vt-')
    fifo = os.path.join(d, 'touch'); os.mkfifo(fifo)
    log = os.path.join(d, 'log')
    gconf = os.path.join(d, 'gestures')
    two = 0 if name in PINCH else 1
    open(gconf, 'w').write('G_EDGE_BACK=1\nG_EDGE_PANEL=1\n' + ''.join('%s=%d\n' % (k, two) for k in ('G_TWO_TAP', 'G_TWO_LONG', 'G_TWO_BACK', 'G_TWO_SLIDE')))
    env = dict(os.environ, LD_PRELOAD=shim, VT_SRC=fifo, VT_CAPS=proto, VT_OUT=d)
    p = subprocess.Popen([binary, fifo, log, '', '--gconf', gconf] + ARGS, env=env, stderr=subprocess.PIPE)
    w = open(fifo, 'wb', buffering=0)
    time.sleep(0.3)
    enc = Encoder('ST' if proto == 'ST' else proto)
    t0 = time.monotonic(); sent = []
    for t, fingers in scenario(name):
        dt = t0 + t / 1000 - time.monotonic()
        if dt > 0: time.sleep(dt)
        now = time.monotonic()
        sec, usec = int(now), int((now - int(now)) * 1e6)
        w.write(b''.join(struct.pack(EVFMT, sec, usec, a, b, c) for a, b, c in enc.frame(fingers)))
        sent.append((now, fingers))
    time.sleep(0.4)
    w.close(); p.wait(timeout=5)
    touch = read_events(os.path.join(d, 'uinput0'), True)
    keys = read_events(os.path.join(d, 'uinput1'), True)
    acts = [l.split('] action ', 1)[1].strip() for l in open(log) if '] action ' in l and 'poke' not in l]
    return dict(touch=touch, keys=[c for _, _, t, c, v in keys if t == EV_KEY and v == 1], acts=acts, sent=sent, dir=d)


fails = 0
def check(cond, msg):
    global fails
    print(('  ok   ' if cond else '  FAIL ') + msg)
    if not cond: fails += 1


def main():
    new, shim = sys.argv[1], sys.argv[2]
    base = sys.argv[sys.argv.index('--base') + 1] if '--base' in sys.argv else None
    ref = {}
    for proto in ['B', 'A', 'AID', 'ST']:
        print(f'== source protocol {proto}')
        for name in ONE + (TWO + PINCH if proto != 'ST' else []):
            r = run(new, shim, proto, name)
            acts, keys, fwd = EXPECT[name]
            check(r['acts'] == acts and r['keys'] == keys, f'{name}: actions {r["acts"]} keys {r["keys"]}')
            frames = decode_mt(r['touch'])
            if fwd is True:
                # the contacts Android sees: one finger, following the same path as the source (positions per frame)
                want = []
                for _, fingers in r['sent']:
                    f = tuple(sorted((x, y) for _, x, y in fingers))
                    if not want or want[-1] != f: want.append(f)
                check(frames == want, f'{name}: virtual touch screen got the same contacts ({len(frames)} frames)')
                downs = [e for e in r['touch'] if e[2] == EV_ABS and e[3] in (PX, TID)]
                if downs:
                    lat = (downs[0][0] + downs[0][1] / 1e6 - r['sent'][0][0]) * 1000
                    lim = (60 if name.startswith('edge') or 'strip' in name else WINDOW) + 25
                    check(lat <= lim, f'{name}: touch-down forwarded after {lat:.0f} ms (limit {lim})')
                if name in PINCH:          # each finger stays in its own slot: per slot x only ever moves one way
                    xs, cur = {}, 0
                    for e in r['touch']:
                        if e[2] == EV_ABS and e[3] == SLOT: cur = e[4]
                        if e[2] == EV_ABS and e[3] == PX: xs.setdefault(cur, []).append(e[4])
                    mono = all(v == sorted(v) or v == sorted(v, reverse=True) for v in xs.values())
                    check(len(xs) == 2 and mono, f'{name}: each finger kept its slot {xs}')
                if proto == 'B': ref[name] = frames
                elif name in ref: check(frames == ref[name], f'{name}: same as protocol B')
            elif fwd is False:
                check(all(f == () for f in frames), f'{name}: nothing reached Android ({len(frames)} frames)')
            else:
                check(frames[-1:] == [()], f'{name}: Android got the touch and then its cancel')
            if proto == 'B' and base and name in CHANGED:
                o = run(base, shim, proto, name)
                check(o['acts'] == [] and o['keys'] == [], f'{name}: the old binary fired nothing here ({o["acts"]}) -- the intended change')
            elif proto == 'B' and base:
                o = run(base, shim, proto, name)
                same = [e[2:] for e in o['touch']] == [e[2:] for e in r['touch']] and o['keys'] == r['keys'] and o['acts'] == r['acts']
                check(same, f'{name}: identical to the old binary ({len(r["touch"])} touch events)')
            if '-k' not in sys.argv:
                subprocess.call(['rm', '-rf', r['dir']])
    print('FAILED: %d' % fails if fails else 'all passed')
    sys.exit(1 if fails else 0)


main()
