"""Dump a plugin's TES4 header and the subrecord order of every QUST record.

Byte-level, not xEdit-level: subrecord order is one of the things a plugin has
to get right for the game to accept it, and only the raw bytes show it.

    py tools/esp/dump_esp.py data/EldenRingCombat.esp
"""
import struct
import sys

import tes5


def dump_header(buf):
    sig, size, flags, formid, _vc, fv, _vc2 = tes5.HEADER.unpack_from(buf, 0)
    print(f"TES4 sig={sig} size={size} flags=0x{flags:08X} formid={formid:06X} "
          f"formver={fv}")
    data = buf[24:24 + size]
    off = 0
    while off + 6 <= len(data):
        s = data[off:off + 4]
        n = struct.unpack_from("<H", data, off + 4)[0]
        off += 6
        payload = data[off:off + n]
        off += n
        text = payload.split(b"\x00")[0]
        if s == b"HEDR":
            ver, num, nxt = struct.unpack_from("<fII", payload, 0)
            print(f"  HEDR version={ver:.2f} records={num} next={nxt:#x}")
        elif s in (b"MAST", b"CNAM", b"SNAM", b"EDID", b"LNAM"):
            print(f"  {s.decode()} = {text.decode('utf-8', 'replace')}")
        else:
            print(f"  {s.decode('latin-1')} ({n} bytes)")


def dump_quest(rec):
    print(f"\nQUST {rec.formid:06X} flags=0x{rec.flags:08X} "
          f"(data {len(rec.data)} bytes)")
    for sig, payload in rec.subrecords():
        note = ""
        if sig in (b"EDID", b"FULL"):
            note = payload.split(b"\x00")[0].decode("utf-8", "replace")
        elif sig == b"DNAM":
            flags, prio = struct.unpack_from("<HB", payload, 0)
            note = f"flags=0x{flags:04X} priority={prio}"
        elif sig in (b"ANAM", b"NEXT", b"ALST", b"ALFR"):
            note = " ".join(f"{b:02X}" for b in payload)
        elif sig == b"FNAM":
            note = f"0x{struct.unpack_from('<I', payload, 0)[0]:08X}"
        elif sig == b"VMAD":
            note = f"{len(payload)} bytes, head={payload[:12].hex(' ')}"
        print(f"  {sig.decode('latin-1')} ({len(payload)}) {note}")


def main(path):
    buf = tes5.load(path)
    dump_header(buf)
    for rec in tes5.iter_records(buf):
        if rec.sig == b"QUST":
            dump_quest(rec)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/EldenRingCombat.esp")
