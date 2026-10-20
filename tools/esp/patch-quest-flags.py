"""Repair the two defects that made EldenRingCombat.esp silently do nothing.

Both were wrong *assumptions in our own tooling*, and both are checkable against
working plugins, so this script is the correction of record.

1. Start Game Enabled is DNAM bit 0x0100, not 0x0001.
   Ground truth from Skyrim.esm (parsed, not assumed):
       MQ101  hdrflags=0x0000  dnam=0x0100   <- must run from game start
       MQ102  hdrflags=0x0000  dnam=0x0100
       DA10   hdrflags=0x0000  dnam=0x0000   <- ordinary, not auto-started
   and Precision.esp's MCM quest (which works in this load order) = 0x0101
   (0x0100 | 0x0001). Ours was 0x0001, so the quest never started, the alias
   script never ran, and OnUpdate/OnHit never fired -- no rolls, no hit-stop.
   bit 0x0001 is "Run Once", which is what MCM-style quests conventionally set.

2. A GRUP's size field EXCLUDES its 24-byte header. We wrote header+content,
   claiming 247 bytes where only 223 existed, so the group overran EOF by
   exactly one record header. Verified against Precision.esp: group at 0x61 with
   size 89, next record at 0x61+24+89=0xD2, which is exactly where its QUST is.

Idempotent: running it twice changes nothing the second time.

    py tools/esp/patch-quest-flags.py data/EldenRingCombat.esp
"""
import struct
import sys

RECORD_SIGS = {
    b"TES4", b"QUST", b"ALFR", b"VMAD", b"GLOB", b"FLST", b"KYWD", b"LCTN",
    b"REFR", b"ACHR", b"NPC_", b"ARMO", b"WEAP", b"SPEL", b"MGEF", b"BOOK",
}

FLAG_START_GAME_ENABLED = 0x0100


def align4(n):
    return n + ((-n) % 4)


def patch_quest(data):
    """OR Start Game Enabled into a QUST's DNAM flags. Returns (data, changed)."""
    pos = data.find(b"DNAM")
    if pos < 0:
        return data, False
    off = pos + 4 + 2  # past 'DNAM' and the u16 payload length
    flags = struct.unpack_from("<H", data, off)[0]
    if flags & FLAG_START_GAME_ENABLED:
        return data, False
    new = flags | FLAG_START_GAME_ENABLED
    data = bytearray(data)
    struct.pack_into("<H", data, off, new)
    print(f"    DNAM flags 0x{flags:04X} -> 0x{new:04X} (Start Game Enabled set)")
    return bytes(data), True


def patch(buf):
    buf = bytearray(buf)
    changed = False
    pos = 0
    n = len(buf)
    while pos + 24 <= n:
        sig = bytes(buf[pos:pos + 4])
        if sig == b"GRUP":
            claimed = struct.unpack_from("<I", buf, pos + 4)[0]
            label = bytes(buf[pos + 8:pos + 12])
            start = pos + 24
            # Walk the records inside; they are self-describing by size.
            q = start
            while q + 24 <= n:
                rsig = bytes(buf[q:q + 4])
                if rsig == b"GRUP" or rsig not in RECORD_SIGS:
                    break
                rsize = struct.unpack_from("<I", buf, q + 4)[0]
                body_start, body_end = q + 24, q + 24 + rsize
                if body_end > n:
                    raise SystemExit(f"record {rsig!r} at {q} overruns EOF")
                if rsig == b"QUST":
                    body, ch = patch_quest(bytes(buf[body_start:body_end]))
                    if ch:
                        buf[body_start:body_end] = body
                        changed = True
                q = body_end
            actual = q - start
            if claimed != actual:
                struct.pack_into("<I", buf, pos + 4, actual)
                print(f"    GRUP {label.decode(errors='replace')} size "
                      f"{claimed} -> {actual} (header is not counted)")
                changed = True
            pos = q
            continue
        if sig not in RECORD_SIGS:
            break
        size = struct.unpack_from("<I", buf, pos + 4)[0]
        if sig == b"QUST":
            body_start, body_end = pos + 24, pos + 24 + size
            body, ch = patch_quest(bytes(buf[body_start:body_end]))
            if ch:
                buf[body_start:body_end] = body
                changed = True
        pos += 24 + size
    return bytes(buf), changed


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    with open(path, "rb") as fh:
        original = fh.read()

    print(f"{path}: {len(original)} bytes")
    patched, changed = patch(original)

    if not changed:
        print("  already correct, nothing to do")
    else:
        if len(patched) != len(original):
            raise SystemExit("refusing to write: size changed (would invalidate offsets)")
        with open(path, "wb") as fh:
            fh.write(patched)
        print(f"  wrote {len(patched)} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
