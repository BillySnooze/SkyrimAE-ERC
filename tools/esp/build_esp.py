"""Generate data/EldenRingCombat.esp.

The plugin holds one record: a start-game-enabled quest with a single alias
forced to the player reference and the ERC_PlayerCombat script attached to that
alias. That is the only way to get a Papyrus script running on the player, and
the SKSE plugin API has no AttachScript call.

Every layout detail below was read out of vanilla Skyrim.esm records (see
tools/esp/dump_quest.py and find_minimal_vmad.py):

  * QUST subrecord order: EDID, VMAD, FULL, DNAM, NEXT, ANAM, then one
    ALST block per alias. (Working plugins, including Precision.esp's MCM quest
    and vanilla quests, carry no ENAM here.)
  * DNAM is 12 bytes: u16 flags, u8 priority, u8 unknown, u16 form version,
    u16 unknown, u32 quest type. Flag 0x0100 is "Start Game Enabled" and
    0x0001 is "Run Once" -- checked against Skyrim.esm, where MQ101/MQ102 (which
    must run from game start) have 0x0100 while DA10 has 0x0000.
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
SEQ = Path(__file__).resolve().parents[2] / "data" / "SEQ" / "EldenRingCombat.seq"

PLUGIN_NAME = "EldenRingCombat.esm"   # author field, cosmetic
MASTERS = ["Skyrim.esm"]
AUTHOR = "EldenRingCombat"

# A plugin's own records carry the index the plugin itself occupies in its own
# master list, i.e. len(MASTERS). Getting this wrong makes every record point at
# a master that does not exist, so the quest silently never registers -- the same
# class of bug as a wrong Start Game Enabled bit. Checked against Precision.esp
# (one master, records at 0x01xxxxxx) and the houseCARL-built plugin (two
# masters, records at 0x02xxxxxx).
SELF_INDEX = len(MASTERS)
QUEST_FORMID = (SELF_INDEX << 24) | 0x00000800
MCM_QUEST_FORMID = (SELF_INDEX << 24) | 0x00000801
QUEST_EDID = "ERC_PlayerCombatQuest"
QUEST_NAME = "Elden Ring Combat"
SCRIPT_NAME = "ERC_PlayerCombat"
ALIAS_NAME = "Player"
PLAYER_REF = 0x00000014              # Skyrim.esm:00000014

# A second, otherwise empty quest whose only job is to give MCM Helper something
# to bind the menu to. MCM Helper resolves the config path from the *plugin that
# owns the quest running an MCM_ConfigBase script*, so without this quest
# Data/MCM/Config/EldenRingCombat/config.json is never read -- and MCM Helper
# does not log that it skipped it. See data/scripts/source/ERC_MCM.psc.
MCM_QUEST_EDID = "ERC_MCMQuest"
MCM_SCRIPT_NAME = "ERC_MCM"

FLAG_START_GAME_ENABLED = 0x0100      # DNAM; verified against Skyrim.esm MQ101
FLAG_RUN_ONCE = 0x0001                # DNAM; what MCM-style quests conventionally set
PRIORITY = 60
# A Player-forced alias needs no alias flags: Precision's working MCM quest and
# the vanilla quests that force PlayerRef all carry FNAM 0.
ALIAS_FLAG_ALLOW_RESERVED = 0x0000

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
    # SSE group header is 24 bytes, and the size field counts ONLY the content.
    # (It is not header+content: Precision.esp's QUST group sits at 0x61 with
    # size 89, and its QUST record starts at 0x61+24+89=0xD2.) Writing
    # header+content makes the group overrun EOF by exactly one record header.
    return (struct.pack("<4sI4siI", b"GRUP", len(content), label, 0, 0)
            + b"\x00" * 4 + content)


# --------------------------------------------------------------------------
# VMAD
# --------------------------------------------------------------------------
# This is a byte-for-byte copy of the VMAD that the houseCARL-authored plugin
# ships with, which xEdit confirms as "alias blocks: 1 ... script:
# ERC_PlayerCombat" -- i.e. the alias script really is attached. Only the 4-byte
# quest FormID inside it is substituted.
#
# It is copied rather than derived on purpose. The version this file used to
# compute by hand parsed as "alias blocks: 0" in xEdit, which means the script
# would have been attached to nothing: the mod would load, log that ERC.dll is
# fine, and do nothing at all. Verifying a hand-derived layout against a real
# parser is what caught it, so the safe move is to stop deriving.
VMAD_TEMPLATE = bytes.fromhex(
    "0500020000000200000000010000000000000800020500020001001000"
    "4552435f506c61796572436f6d626174"
    "000000"
)
VMAD_QUEST_SLOT = VMAD_TEMPLATE.find(bytes.fromhex("00080002"))
STATIC_ASSERT_VMAD_LEN = 48


def build_vmad(quest_formid: int, alias_index: int, script: str) -> bytes:
    if len(VMAD_TEMPLATE) != STATIC_ASSERT_VMAD_LEN:
        raise SystemExit(f"VMAD template is {len(VMAD_TEMPLATE)} bytes, expected "
                         f"{STATIC_ASSERT_VMAD_LEN}")
    if VMAD_QUEST_SLOT < 0 or VMAD_TEMPLATE.count(bytes.fromhex("00080002")) != 1:
        raise SystemExit("VMAD quest FormID slot is not uniquely identifiable")
    if alias_index != 0:
        raise SystemExit("the validated VMAD attaches to alias 0 only")
    if script != SCRIPT_NAME:
        raise SystemExit(f"the validated VMAD names {SCRIPT_NAME} only")
    out = bytearray(VMAD_TEMPLATE)
    struct.pack_into("<I", out, VMAD_QUEST_SLOT, quest_formid)
    return bytes(out)


# --------------------------------------------------------------------------
# quest
# --------------------------------------------------------------------------
def build_vmad_quest_script(script: str) -> bytes:
    """VMAD carrying a single script on the quest itself (no aliases).

    Layout: version, object format, quest script count, then per script
    (wstring name, u8 flags, u16 property count), then:
        u8  extra bind-data version
        u16 fragment count
        wstring fragment script file name   <-- present even when empty
        u16 alias block count

    That file-name field is easy to miss and its absence is not caught by
    anything at build time: the alias count then reads from the file name's
    length word, the record is malformed, and xEdit reports it with a modal
    error dialog -- which looks like xEdit hanging. Cross-checked against
    Precision.esp's Precision_MCM_Quest, whose tail is
    02 0000 0000 0100 (bind, no fragments, no file name, 1 alias block).
    """
    out = struct.pack("<HHH", 5, 2, 1)      # version, object format, 1 script
    out += wstring(script)
    out += bytes([0])                       # script flags: local
    out += struct.pack("<H", 0)             # property count
    out += bytes([2])                       # extra bind data version
    out += struct.pack("<H", 0)             # fragment count
    out += struct.pack("<H", 0)             # fragment script file name (empty)
    out += struct.pack("<H", 0)             # alias block count
    return out


def build_mcm_quest(formid: int) -> bytes:
    data = b""
    data += subrecord(b"EDID", zstring(MCM_QUEST_EDID))
    data += subrecord(b"VMAD", build_vmad_quest_script(MCM_SCRIPT_NAME))
    data += subrecord(b"FULL", zstring(QUEST_NAME))
    data += subrecord(b"DNAM", struct.pack(
        "<HBBHHI", FLAG_START_GAME_ENABLED | FLAG_RUN_ONCE, PRIORITY, 0, 0, 0, 0))
    data += subrecord(b"NEXT", b"")
    data += subrecord(b"ANAM", struct.pack("<I", 0))   # no aliases
    return record(b"QUST", formid, data)


def build_quest(formid: int) -> bytes:
    data = b""
    data += subrecord(b"EDID", zstring(QUEST_EDID))
    data += subrecord(b"VMAD", build_vmad(formid, 0, SCRIPT_NAME))
    data += subrecord(b"FULL", zstring(QUEST_NAME))
    data += subrecord(b"DNAM", struct.pack(
        "<HBBHHI", FLAG_START_GAME_ENABLED | FLAG_RUN_ONCE, PRIORITY, 0, 0, 0, 0))
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
    data += subrecord(b"MAST", zstring(MASTERS[0]))
    for master in MASTERS[1:]:
        data += subrecord(b"MAST", zstring(master))
    data += subrecord(b"DATA", struct.pack("<Q", 0))
    data += subrecord(b"INTV", struct.pack("<I", 1))
    # flags 0 => regular ESP (not a master, not ESL-flagged)
    return record(b"TES4", 0, data)


def build_plugin(include_quest: bool = True) -> bytes:
    if not include_quest:
        return build_header(0, 0x800)
    quests = [build_quest(QUEST_FORMID), build_mcm_quest(MCM_QUEST_FORMID)]
    header = build_header(len(quests), MCM_QUEST_FORMID + 1)
    return header + group(b"QUST", b"".join(quests))


def seq_bytes(formids) -> bytes:
    """A .seq is a bare array of FormIDs -- no count, no header.

    Verified against 157 real .seq files in this modlist: e.g.
    AlternatePerspective.seq is 8 bytes for two quests, Alit.seq is 4 for one.
    """
    return b"".join(struct.pack("<I", f) for f in formids)


def main():
    import sys
    stub = "--stub" in sys.argv[1:]
    blob = build_plugin(include_quest=not stub)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(blob)
    kind = "stub (header only)" if stub else "plugin"
    print(f"wrote {kind} {OUT} ({len(blob)} bytes)")

    if not stub:
        # Keep the SEQ in lockstep with the quests, including the MCM quest: a
        # quest missing from it never starts, so its script never registers.
        seq = seq_bytes([QUEST_FORMID, MCM_QUEST_FORMID])
        SEQ.parent.mkdir(parents=True, exist_ok=True)
        SEQ.write_bytes(seq)
        print(f"wrote SEQ {SEQ} ({len(seq)} bytes, "
              f"{len(seq) // 4} quests: "
              f"{QUEST_FORMID:08X}, {MCM_QUEST_FORMID:08X})")


if __name__ == "__main__":
    main()
