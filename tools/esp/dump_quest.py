"""Dump the raw subrecords of two vanilla quests, to use as layout templates.

  MQGreybeardCall -- has a Player alias, no alias scripts (the alias block we
                     need to reproduce, minus the script).
  JailQuest       -- has a scripted Player alias (the VMAD alias block format).
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tes5  # noqa: E402

DATA = pathlib.Path(r"F:\Modlists\JOJ\Stock Game\Data\Skyrim.esm")
OUT = pathlib.Path(r"C:\Users\Billy\EldenRingCombat\build\quest-bytes.txt")

TARGETS = {
    0x0010EC61: "MQGreybeardCall",
    0x0010D9F4: "JailQuest",
}

# Subrecords whose payload is a link or tiny enum -- always show fully.
SHORT = {b"DNAM", b"ENAM", b"NEXT", b"ANAM", b"ALST", b"FNAM", b"ALFR", b"ALED",
         b"ALID", b"EDID", b"FULL"}


def hexdump(data, limit=64):
    head = data[:limit]
    s = " ".join(f"{b:02X}" for b in head)
    if len(data) > limit:
        s += f" ... ({len(data)} bytes)"
    return s


def main():
    buf = tes5.load(DATA)
    lines = []

    for formid, name in TARGETS.items():
        rec = tes5.find_quest(buf, formid)
        if rec is None:
            lines.append(f"!! {name} [{formid:08X}] not found")
            continue
        lines.append(f"===== {name} [{formid:08X}] =====")
        lines.append(f"flags={rec.flags:08X} dataSize={len(rec.data)}")
        off = 0
        while off + 6 <= len(rec.data):
            sig = rec.data[off:off + 4]
            size = int.from_bytes(rec.data[off + 4:off + 6], "little")
            payload = rec.data[off + 6:off + 6 + size]
            limit = 64 if sig not in SHORT else 128
            lines.append(f"  {sig.decode('latin-1')} size={size:5d}  "
                         f"{hexdump(payload, limit)}")
            off += 6 + size
        lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
