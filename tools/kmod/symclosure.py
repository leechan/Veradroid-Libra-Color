#!/usr/bin/env python3
"""Which kernel types provably have the same definition as on the device?

    symclosure.py <kernel tree built with KBUILD_SYMTYPES=1> <device.crcs> [type ...]

genksyms gives every exported symbol a CRC over the full expanded definition of all types reachable from
its prototype (the .symtypes files list them). When our CRC for a symbol equals the device's, every type
definition in that symbol's closure is the same on the device (up to a CRC32 collision). This collects
those "verified" definitions, then

  * for every mismatching symbol, lists the definitions in its closure that are not verified; when only
    one is left, that type must differ on the device ("certainly changed");
  * for each type given on the command line (e.g. s#task_struct s#mm_struct), says whether its layout is
    verified: the type itself and every type it embeds by value (recursively; pointers and function
    pointer parameters do not affect layout) must be verified.

device.crcs: "0xCRC<TAB>symbol" lines (tools/kmod/kcrc.py). Our CRCs come from <tree>/Module.symvers.
"""
import collections
import os
import re
import sys

REF = re.compile(r'^[sutEe]#')


def parse(path):
    defs, syms = {}, {}
    for line in open(path, errors='replace'):
        line = line.rstrip('\n')
        if not line:
            continue
        key, _, rest = line.partition(' ')
        if '#' in key and REF.match(key) or key.startswith('t#'):
            defs[key] = rest
        else:
            syms[key] = rest
    return defs, syms


def refs(text):
    return [t for t in text.split() if REF.match(t) or t.startswith('t#')]


def closure(defs, text):
    seen = {}
    todo = refs(text)
    while todo:
        k = todo.pop()
        if k in seen:
            continue
        d = defs.get(k)
        seen[k] = d
        if d:
            todo.extend(refs(d))
    return seen


def embedded(defn):
    """types a struct/union/typedef definition embeds by value"""
    toks = defn.split()
    out = []
    depth = 0
    started = False
    for i, t in enumerate(toks):
        if t == '{':
            started = True
            continue
        if t == '(':
            depth += 1
            continue
        if t == ')':
            depth -= 1
            continue
        if depth:
            continue
        if REF.match(t) or t.startswith('t#'):
            nxt = toks[i + 1] if i + 1 < len(toks) else ''
            if nxt == '*' or (nxt == '(' and i + 2 < len(toks) and toks[i + 2] == '*'):
                continue
            if started or defn.startswith('typedef'):
                out.append(t)
    return out


def load_crcs(path):
    out = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 2:
            out[p[1]] = int(p[0], 16)
    return out


def main():
    tree, devp = sys.argv[1], sys.argv[2]
    want = sys.argv[3:]
    dev = load_crcs(devp)
    ours = {}
    for line in open(os.path.join(tree, 'Module.symvers')):
        p = line.split()
        ours[p[1]] = int(p[0], 16)
    verified = set()
    mism = []          # (symbol, closure items)
    alldefs = collections.defaultdict(set)
    for root, _, files in os.walk(tree):
        for f in files:
            if not f.endswith('.symtypes'):
                continue
            defs, syms = parse(os.path.join(root, f))
            for k, d in defs.items():
                alldefs[k].add(d)
            for s, proto in syms.items():
                if s not in dev or s not in ours:
                    continue
                cl = closure(defs, proto)
                items = {(k, d) for k, d in cl.items()}
                if dev[s] == ours[s]:
                    verified |= items
                else:
                    mism.append((s, items))
    print('verified definitions: %d; mismatching symbols with a symtypes entry: %d' % (len(verified), len(mism)))
    changed = collections.Counter()
    suspects = collections.Counter()
    for s, items in mism:
        left = [k for k, d in items if (k, d) not in verified]
        for k in set(left):
            suspects[k] += 1
        if len(set(left)) == 1:
            changed[left[0]] += 1
    print('certainly changed (only unverified type in a mismatching symbol):')
    for k, c in changed.most_common():
        print('  %-40s %d symbols' % (k, c))
    print('most frequent unverified types in mismatching symbols:')
    for k, c in suspects.most_common(25):
        print('  %-40s %d' % (k, c))
    vkeys = collections.defaultdict(set)
    for k, d in verified:
        vkeys[k].add(d)
    for t in want:
        bad = []
        seen = set()
        todo = [t]
        while todo:
            k = todo.pop()
            if k in seen:
                continue
            seen.add(k)
            ds = alldefs.get(k, set())
            if not ds:
                bad.append(k + '(no definition seen)')
                continue
            full = [d for d in ds if 'UNKNOWN' not in d] or list(ds)
            ok = any(d in vkeys[k] for d in full)
            if not ok:
                bad.append(k)
            for d in full[:1]:
                todo.extend(embedded(d))
        print('%s: layout %s%s' % (t, 'VERIFIED' if not bad else 'NOT verified', '' if not bad else ' (unverified: ' + ' '.join(bad[:12]) + ')'))


if __name__ == '__main__':
    main()
