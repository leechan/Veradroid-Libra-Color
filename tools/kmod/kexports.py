#!/usr/bin/env python3
"""Every exported symbol and its modversions CRC from a raw 32-bit ARM kernel Image built WITHOUT
CONFIG_KALLSYMS (PW5 / KT5 / KT6 / Scribe 4.9.77-lab126: /proc/kallsyms is empty, kimgsyms.py has
nothing to read).

    kexports.py <Image> [load-address]   -> "0xcrc<TAB>name" lines (same format as kcrc.py)

load-address defaults to 0xc0008000 (PAGE_OFFSET 0xc0000000 + TEXT_OFFSET 0x8000).

How: struct kernel_symbol is {value, name} (two pointers). In RO_DATA the linker puts __ksymtab,
__ksymtab_gpl (each SORT()ed by name, 4.9), the empty unused / gpl_future tables, then __kcrctab and
__kcrctab_gpl (one u32 per entry, same order), then __ksymtab_strings. We take the longest run of
8-byte entries whose name pointer lands on an identifier string inside __ksymtab_strings, split it
where the name order restarts (ksymtab -> ksymtab_gpl), and read the CRCs that follow the run.
Checks: the CRC block must end exactly where the names start (allowing alignment padding).
"""
import re
import struct
import sys

IDENT = re.compile(rb'[A-Za-z_][A-Za-z0-9_.$]*\0')


def main():
    img = open(sys.argv[1], 'rb').read()
    base = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0xc0008000
    n = len(img)
    top = base + n

    def name_at(va):
        if not (base <= va < top):
            return None
        o = va - base
        m = IDENT.match(img, o)
        if not m or m.end() - o > 128:
            return None
        return img[o:m.end() - 1]

    best = (0, 0)
    for align in (0, 4):
        p = align; run_start = None; cnt = 0
        while p + 8 <= n:
            v, nm = struct.unpack_from('<II', img, p)
            ok = name_at(nm) is not None   # values can be anything (absolute symbols, 0 for weak ones)
            if ok:
                if run_start is None:
                    run_start, cnt = p, 0
                cnt += 1
            else:
                if run_start is not None and cnt > best[1]:
                    best = (run_start, cnt)
                run_start = None
            p += 8
    s, N = best
    if N < 1000:
        sys.exit('ksymtab not found (longest run %d)' % N)
    ents = [struct.unpack_from('<II', img, s + 8 * i) for i in range(N)]
    names = [name_at(e[1]) for e in ents]
    # sorted tables: the gpl table starts where the order restarts
    splits = [i for i in range(1, N) if names[i] < names[i - 1]]
    if len(splits) > 1:
        sys.exit('more than one order restart in the run: %s' % splits[:5])
    n1 = splits[0] if splits else N
    strings_start = min(e[1] for e in ents) - base
    crc0 = s + 8 * N
    # try pad 0/4 between kcrctab and kcrctab_gpl, the block must reach the strings (<= 16 bytes pad)
    for pad in (0, 4):
        end = crc0 + 4 * N + pad
        if 0 <= strings_start - end < 16 and not img[end:strings_start].strip(b'\0'):
            break
    else:
        sys.exit('CRC block does not end at __ksymtab_strings (crc0 %#x, strings %#x, N %d)' % (crc0, strings_start, N))
    out = []
    for i, nm in enumerate(names):
        o = crc0 + 4 * i + (pad if i >= n1 else 0)
        out.append('0x%08x\t%s\n' % (struct.unpack_from('<I', img, o)[0], nm.decode()))
    sys.stdout.write(''.join(out))
    sys.stderr.write('ksymtab %#x: %d + %d gpl, pad %d\n' % (base + s, n1, N - n1, pad))


if __name__ == '__main__':
    main()
