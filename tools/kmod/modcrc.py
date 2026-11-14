#!/usr/bin/env python3
"""Inspect or rewrite the modversion table (__versions) of a 32-bit little-endian kernel module.

    modcrc.py show  <module.ko>
    modcrc.py check <module.ko> <device.crcs>
    modcrc.py set   <module.ko> <device.crcs> <out.ko> <symbol> [<symbol> ...]

device.crcs: "0xCRC<TAB>symbol" lines taken from the device kernel itself (tools/kmod/kcrc.py reads them
out of the kernel image's __kcrctab, so every exported symbol is covered).

check: prints every symbol the module imports with OK (same CRC as the device) or DIFF/MISSING.
set:   copies the module and gives the named symbols the device CRC. Use it only for symbols whose
       types were verified to have the same layout on the device; a CRC is the kernel's
       only guard against loading a module built against different structures.
"""
import struct
import sys


def sections(d):
    shoff = struct.unpack_from('<I', d, 0x20)[0]
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x2e)
    sh = [struct.unpack_from('<IIIIIIIIII', d, shoff + i * shentsize) for i in range(shnum)]
    stro = sh[shstrndx][4]
    return {d[stro + s[0]:d.index(b'\0', stro + s[0])].decode(): s for s in sh}


def versions(d):
    s = sections(d)['__versions']
    off, size = s[4], s[5]
    for i in range(0, size, 64):
        crc = struct.unpack_from('<I', d, off + i)[0]
        name = d[off + i + 4:off + i + 64].split(b'\0')[0].decode()
        yield off + i, crc, name


def load_crcs(path):
    out = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 2:
            out[p[1]] = int(p[0], 16)
    return out


def main():
    cmd, ko = sys.argv[1], sys.argv[2]
    d = bytearray(open(ko, 'rb').read())
    if cmd == 'show':
        for _, crc, name in versions(d):
            print('0x%08x\t%s' % (crc, name))
        return 0
    dev = load_crcs(sys.argv[3])
    if cmd == 'check':
        bad = 0
        for _, crc, name in versions(d):
            if name not in dev:
                st = 'MISSING'
            elif dev[name] == crc:
                st = 'OK'
            else:
                st = 'DIFF'
            bad += st != 'OK'
            print('%-7s %s' % (st, name))
        print('mismatched: %d' % bad)
        return 1 if bad else 0
    if cmd == 'set':
        out, want = sys.argv[4], set(sys.argv[5:])
        done = set()
        for off, crc, name in versions(d):
            if name in want:
                if name not in dev:
                    sys.exit('%s: not exported by the device kernel' % name)
                struct.pack_into('<I', d, off, dev[name])
                done.add(name)
        if want - done:
            sys.exit('not imported by the module: %s' % ' '.join(sorted(want - done)))
        open(out, 'wb').write(d)
        print('set %d CRCs' % len(done))
        return 0
    sys.exit(__doc__)


if __name__ == '__main__':
    sys.exit(main())
