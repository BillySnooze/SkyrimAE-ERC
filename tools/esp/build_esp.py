"""Generate data/EldenRingCombat.esp.

The plugin holds one record: a start-game-enabled quest with a single alias
forced to the player reference and the ERC_PlayerCombat script attached to that
alias. That is the only way to get a Papyrus script running on the player, and
the SKSE plugin API has no AttachScript call.

Every layout detail below was read out of vanilla Skyrim.esm records (see
tools/esp/dump_quest.py and find_minimal_vmad.py):

  * QUST subrecord order: EDID, VMAD, FULL, DNAM, ENAM, NEXT, ANAM, then one
    ALST block per alias.
  * DNAM is 12 bytes: u16 flags, u8 priority, u8 unknown, u16 form version,
    u16 unknown, u32 quest type. Bit 0 of the flags is "Start Game Enabled".
  * ANAM is the "next alias id" count (u32).
  * Alias block: ALST(u32 id), ALID(zstring name), FNAM(u32 flags),
    ALFR(u32 forced ref), VTCK(u32), ALED(empty). FNAM bit 9 is Allow Reserved.
  * VMAD: u16 version 5, u16 object format 2, u16 quest script count, then a
    u8 bind-data version and u16 fragment count, then u16 alias block count,
    and per alias block: u16 zero, u16 alias index, u32 quest form id,
    u16 version 5, u16 object format 2, u16 script count, then scripts.
    A script is: u16-prefixed UTF-8 name, u8 flags, u16 property count.

Generation is deterministic: same inputs, same bytes, no timestamps.
"""
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "data" / "EldenRingCombat.esp"

PLUGIN_NAME = "EldenRingCombat.esm"   # author field, cosmetic
MASTER = "Skyrim.esm"
AUTHOR = "EldenRingCombat"

QUEST_FORMID = 0x00000800
QUEST_EDID = "ERC_PlayerCombatQuest"
QUEST_NAME = "Elden Ring Combat"
SCRIPT_NAME = "ERC_PlayerCombat"
ALIAS_NAME = "Player"
PLAYER_REF = 0x00000014              # Skyrim.esm:00000014

FLAG_START_GAME_ENABLED = 0x0001
PRIORITY = 60
ALIAS_FLAG_ALLOW_RESERVED = 0x0200

RECORD_FORM_VERSION = 44             # SSE-era record version


# --------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------
def subrecord(sig: bytes, payload: bytes) -> bytes:
    return sig + struct.pack("<H", len(payload)) + payload


def zstring(text: str) -> bytes:
    return text.encode("utf-8") + b"\x00"


def wstring(text: str) -> bytes:
    raw = text.encode("utf-8")
    return struct.pack("<H", len(raw)) + raw


def record(sig: bytes, formid: int, data: bytes, flags: int = 0) -> bytes:
    return (struct.pack("<4sIIIIHH", sig, len(data), flags, formid, 0,
                        RECORD_FORM_VERSION, 0) + data)


def group(label: bytes, content: bytes) -> bytes:
    # SSE group header is 24 bytes: size covers the header plus content.
    return (struct.pack("<4sI4siI", b"GRUP", 24 + len(content), label, 0, 0)
            + b"\x00" * 4 + content)


# --------------------------------------------------------------------------
# VMAD
# --------------------------------------------------------------------------
def build_vmad(quest_formid: int, alias_index: int, script: str) -> bytes:
    out = struct.pack("<HHH", 5, 2, 0)          # version, object format, no quest scripts
    out += bytes([2])                            # extra bind data version
    out += struct.pack("<H", 0)                  # fragment count
    out += struct.pack("<H", 1)                  # alias script block count
    out += struct.pack("<HHIHHH", 0, alias_index, quest_formid, 5, 2, 1)
    out += wstring(script)
    out += bytes([0])                            # script flags: local
    out += struct.pack("<H", 0)                  # property count
    return out


# --------------------------------------------------------------------------
# quest
# --------------------------------------------------------------------------
def build_quest(formid: int) -> bytes:
    data = b""
    data += subrecord(b"EDID", zstring(QUEST_EDID))
    data += subrecord(b"VMAD", build_vmad(formid, 0, SCRIPT_NAME))
    data += subrecord(b"FULL", zstring(QUEST_NAME))
    data += subrecord(b"DNAM", struct.pack(
        "<HBBHHI", FLAG_START_GAME_ENABLED, PRIORITY, 0, 0, 0, 0))
    data += subrecord(b"ENAM", b"SCPT")          # generic quest event code
    data += subrecord(b"NEXT", b"")
    data += subrecord(b"ANAM", struct.pack("<I", 1))   # next alias id

    # the single alias, forced to PlayerRef and carrying the script
    data += subrecord(b"ALST", struct.pack("<I", 0))
    data += subrecord(b"ALID", zstring(ALIAS_NAME))
    data += subrecord(b"FNAM", struct.pack("<I", ALIAS_FLAG_ALLOW_RESERVED))
    data += subrecord(b"ALFR", struct.pack("<I", PLAYER_REF))
    data += subrecord(b"VTCK", struct.pack("<I", 0))
    data += subrecord(b"ALED", b"")

    return record(b"QUST", formid, data)


# --------------------------------------------------------------------------
# plugin
# --------------------------------------------------------------------------
def build_header(num_records: int, next_object_id: int) -> bytes:
    hedr = struct.pack("<fII", 1.7, num_records, next_object_id)
    data = subrecord(b"HEDR", hedr)
    data += subrecord(b"CNAM", zstring(AUTHOR))
    data += subrecord(b"MAST", zstring(MASTER))
    data += subrecord(b"DATA", struct.pack("<Q", 0))
    data += subrecord(b"INTV", struct.pack("<I", 1))
    # flags 0 => regular ESP (not a master, not ESL-flagged)
    return record(b"TES4", 0, data)


def build_plugin(include_quest: bool = True) -> bytes:
    header = build_header(1 if include_quest else 0,
                          QUEST_FORMID + 1 if include_quest else 0x800)
    if not include_quest:
        return header
    return header + group(b"QUST", build_quest(QUEST_FORMID))


def main():
    import sys
    stub = "--stub" in sys.argv[1:]
    blob = build_plugin(include_quest=not stub)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(blob)
    kind = "stub (header only)" if stub else "plugin"
    print(f"wrote {kind} {OUT} ({len(blob)} bytes)")


if __name__ == "__main__":
    main()
