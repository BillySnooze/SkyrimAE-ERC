"""Find QUST VMAD blobs that have no quest-level scripts.

Those show the minimal layout a generated plugin needs: header, fragment
section, alias blocks -- with nothing else to get in the way.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tes5  # noqa: E402

DATA = pathlib.Path(r"F:\Modlists\JOJ\Stock Game\Data\Skyrim.esm")


def main(limit=8):
    buf = tes5.load(DATA)
    found = 0
    for rec in tes5.iter_records(buf):
        if rec.sig != b"QUST":
            continue
        d = rec.sub(b"VMAD")
        if not d or len(d) < 24:
            continue
        if d[0:6] == b"\x05\x00\x02\x00\x00\x00":
            print(f"{rec.formid:08X} {rec.zstring(b'EDID')} len={len(d)}")
            print("   ", " ".join(f"{b:02X}" for b in d[:64]))
            print("   ", " ".join(chr(b) if 32 <= b < 127 else "." for b in d[:64]))
            found += 1
            if found >= limit:
                break
    print("found", found)


if __name__ == "__main__":
    main()
