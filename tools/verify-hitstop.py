"""Verify the hit-stop mechanism against the real Skyrim.esm, without the game.

Hit-stop dips Skyrim's timescale. Two things about that are easy to get wrong and
both produced real bugs during development:

  * Skyrim's timescale is NOT an INI setting. It is a GLOB record whose EDID is
    "TimeScale", so `Utility.SetINIFloat("fTimeScale:Gameplay", ...)` is a no-op.
    This script proves the record exists, its type is GLOB, and its value is the
    documented 20.0 default (20 game minutes per real minute).
  * Papyrus timers count SCALED game time, so a restore delay computed in game
    seconds is stretched by the dip it is timing down. A 0.06 s dip at 0.15x
    needs 0.009 game seconds, which is less than one frame at 60 fps -- the
    timer would fire on the very next frame. This script demonstrates the
    arithmetic, which is why the script polls Utility.GetCurrentRealTime()
    instead.

    py tools/verify-hitstop.py [--game "F:\\path\\to\\Skyrim"]
"""
import pathlib
import struct
import sys

DEFAULT_GAME = pathlib.Path(r"F:\Modlists\JOJ\Stock Game")
EXPECTED_FORMID = 0x0000003A


def find_timescale_global(esm):
    """Walk the top-level records of an ESM and return (formid, value) or None."""
    data = esm.read_bytes()
    if data[:4] != b"TES4":
        raise SystemExit(f"not an ESM: {esm}")

    header_size = struct.unpack("<I", data[4:8])[0]
    pos = 24 + header_size

    while pos + 24 <= len(data):
        sig = data[pos:pos + 4]
        size, _, formid = struct.unpack("<III", data[pos + 4:pos + 16])
        if sig == b"GRUP":
            pos += 24 + size
            continue
        if not sig.isalpha():
            break
        if sig == b"GLOB":
            rec = data[pos + 24:pos + 24 + size]
            edid = rec.find(b"EDID")
            if edid >= 0:
                length = struct.unpack("<H", rec[edid + 4:edid + 6])[0]
                name = rec[edid + 6:edid + 6 + length].split(b"\x00")[0]
                if name == b"TimeScale":
                    fltv = rec.find(b"FLTV")
                    value = struct.unpack("<f", rec[fltv + 6:fltv + 10])[0] if fltv >= 0 else None
                    return formid, value
        pos += 24 + size
    return None


def main(argv):
    game = DEFAULT_GAME
    if "--game" in argv:
        game = pathlib.Path(argv[argv.index("--game") + 1])

    esm = game / "Data" / "Skyrim.esm"
    if not esm.exists():
        # Fall back to a Steam install if the stock game is not present.
        esm = pathlib.Path(r"F:\SteamLibrary\steamapps\common\Skyrim Special Edition\Data\Skyrim.esm")
    if not esm.exists():
        print(f"FAIL: Skyrim.esm not found (looked in {game}\\Data)")
        return 1

    found = find_timescale_global(esm)
    if not found:
        print("FAIL: no GLOB record with EDID 'TimeScale' in Skyrim.esm")
        return 1

    formid, value = found
    print(f"GLOB TimeScale: FormID 0x{formid:08X} value={value}")

    errors = []
    if formid != EXPECTED_FORMID:
        errors.append(f"FormID is 0x{formid:08X}, the script hardcodes 0x{EXPECTED_FORMID:08X}")
    if value is None:
        errors.append("record has no FLTV value")
    elif abs(value - 20.0) > 0.001:
        errors.append(f"default value is {value}, expected 20.0 -- the timescale "
                      "semantics assumed by the multiplier are wrong")

    # Show why the timer must be real-time: game-time budgets at the dip scale.
    dip, scale = 0.06, 0.15
    game_time_budget = dip * scale
    frame = 1.0 / 60.0
    print(f"\n{dip}s dip at {scale}x -> {game_time_budget:.4f} game seconds")
    print(f"one frame at 60fps is {frame:.4f} game seconds"
          f" -> budget is {game_time_budget / frame:+.2f} frames")
    if game_time_budget < frame:
        print("=> a game-time timer would fire on the NEXT frame, not after the dip.")
        print("   That is why OnUpdate polls Utility.GetCurrentRealTime() (wall clock).")

    if errors:
        for e in errors:
            print(f"FAIL: {e}")
        return 1

    print("\nOK: hit-stop can dip/report the timescale via the TimeScale global")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
