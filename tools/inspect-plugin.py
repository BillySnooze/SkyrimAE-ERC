"""Inspect a plugin's TES4 header (masters) and QUST records, with checks.

Catches the two defects that silently produce a dead mod:
  * a FormID whose high byte does not match the plugin's own index (the record
    then points at a master that does not exist, and the quest never loads)
  * a GRUP whose size field disagrees with the bytes actually present
"""
import struct
import sys
import zlib


def tes4(d):
    size = struct.unpack("<I", d[4:8])[0]
    data = d[24:24 + size]
    flags = struct.unpack("<I", d[8:12])[0]
    masters = []
    pos = 0
    while pos + 6 <= len(data):
        sig = data[pos:pos + 4]
        sz = struct.unpack("<H", data[pos + 4:pos + 6])[0]
        val = data[pos + 6:pos + 6 + sz]
        if sig == b"MAST":
            masters.append(val.split(b"\x00")[0].decode("latin-1"))
        pos += 6 + sz
    return size, flags, masters


def walk_qust(d, start, end, limit=None):
    """Linear walk of QUST records in [start, end). QUST never nests groups."""
    pos = start
    n = 0
    while pos + 24 <= end:
        sig = d[pos:pos + 4]
        if sig != b"QUST":
            print(f"    ! expected QUST at {pos}, found {sig!r} - stopping")
            break
        size, flags, fid = struct.unpack("<III", d[pos + 4:pos + 16])
        rec = d[pos + 24:pos + 24 + size]
        if flags & 0x00040000:
            try:
                rec = zlib.decompress(rec[4:])
            except zlib.error:
                rec = b""
        edid = rec.find(b"EDID")
        name = ""
        if edid >= 0:
            ln = struct.unpack("<H", rec[edid + 4:edid + 6])[0]
            name = rec[edid + 6:edid + 6 + ln].split(b"\x00")[0].decode("latin-1")
        dn = rec.find(b"DNAM")
        dnam = rec[dn + 6:dn + 6 + 12] if dn >= 0 else b""
        yield pos, size, flags, fid, name, dnam
        pos += 24 + size
        n += 1
        if limit and n >= limit:
            return


def report(path, wants=(), limit=None):
    d = open(path, "rb").read()
    print(f"=== {path}  ({len(d)} bytes)")
    if d[:4] != b"TES4":
        print("  not a plugin")
        return
    size, flags, masters = tes4(d)
    self_index = len(masters)
    print(f"  TES4 flags=0x{flags:X} masters={masters} -> own FormIDs use prefix 0x{self_index:02X}")

    # Top-level groups
    pos = 24 + size
    problems = 0
    while pos + 24 <= len(d):
        sig = d[pos:pos + 4]
        if sig != b"GRUP":
            print(f"  top-level record {sig!r} at {pos} (unexpected at top level)")
            break
        gsize = struct.unpack("<I", d[pos + 4:pos + 8])[0]
        label = d[pos + 8:pos + 12]
        cstart, cend = pos + 24, pos + 24 + gsize
        exists = min(cend, len(d)) - cstart
        note = ""
        if cend > len(d):
            note = f"  <-- SIZE OVERRUN: claims {gsize}, file only has {exists}"
            problems += 1
        print(f"  GRUP {label.decode(errors='replace')} size={gsize}{note}")
        if label == b"QUST":
            for p, sz, fl, fid, name, dnam in walk_qust(d, cstart, len(d), limit):
                qf = struct.unpack("<H", dnam[:2])[0] if len(dnam) >= 2 else 0
                prio = dnam[2] if len(dnam) > 2 else None
                prefix = (fid >> 24) & 0xFF
                warn = "" if prefix == self_index else f"  <-- prefix 0x{prefix:02X} != own index 0x{self_index:02X}"
                print(f"    QUST 0x{fid:08X} '{name}' hdr=0x{fl:X} dnam=0x{qf:04X} prio={prio}{warn}")
                if prefix != self_index:
                    problems += 1
        pos = cend
    # Only report quests whose names were asked about
    if wants:
        print(f"  (filter not applied; asked for {wants})")
    print(f"  problems: {problems}")
    return problems


if __name__ == "__main__":
    args = sys.argv[1:]
    total = 0
    for a in args:
        total += report(a)
    raise SystemExit(1 if total else 0)
