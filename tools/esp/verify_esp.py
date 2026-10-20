"""Self-check for data/EldenRingCombat.esp.

Parses the generated plugin back with the same readers used on vanilla files and
asserts every field the game actually needs. Run after build_esp.py; the xEdit
load test in tools/xedit/ERC_VerifyEsp.pas is the independent second opinion.
"""
import struct
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tes5  # noqa: E402

ESP = pathlib.Path(__file__).resolve().parents[2] / "data" / "EldenRingCombat.esp"


def fail(msg):
    print(f"FAIL: {msg}")
    raise SystemExit(1)


def read_script(v, off):
    """Read one VMAD script entry; return (name, flags, property count, offset)."""
    name_len = struct.unpack_from("<H", v, off)[0]
    off += 2
    name = v[off:off + name_len].decode("utf-8")
    off += name_len
    flags = v[off]
    off += 1
    prop_count = struct.unpack_from("<H", v, off)[0]
    off += 2
    # Property values are only needed to skip them, and this plugin has none.
    return name, flags, prop_count, off


def skip_script(v, off):
    """Skip one script entry, including its properties."""
    _, _, prop_count, off = read_script(v, off)
    for _ in range(prop_count):
        name_len = struct.unpack_from("<H", v, off)[0]
        off += 2 + name_len
        ptype, _pflags = v[off], v[off + 1]
        off += 2
        fail(f"property values are not implemented (type {ptype}) - "
             "this plugin should carry no script properties")
    return off


def main():
    buf = ESP.read_bytes()
    sig, size, flags, formid, _vc, _fv, _vc2 = tes5.HEADER.unpack_from(buf, 0)
    if sig != b"TES4":
        fail(f"expected TES4, got {sig}")
    if flags & 0x1:
        fail("plugin is marked as a master; expected a regular ESP")

    header = tes5.Record(sig, flags, formid, buf[24:24 + size])
    hdr = {}
    masters = []
    for s, payload in header.subrecords():
        hdr[s] = payload
        if s == b"MAST":
            masters.append(payload.split(b"\x00")[0].decode("ascii"))
    version, num_records, next_id = struct.unpack("<fII", hdr[b"HEDR"])
    print(f"header: version={version} records={num_records} next={next_id:#x} "
          f"masters={masters}")
    if not masters or masters[0] != "Skyrim.esm":
        fail(f"first master is {masters[0] if masters else 'missing'}, "
             "expected Skyrim.esm")
    if num_records < 1:
        fail("header claims no records")
    if num_records != 1:
        # Advisory only: Skyrim.esm's own HEDR says 920181 for 869688 records,
        # so nothing reads this number. Mutagen counts one extra here.
        print(f"note: header record count is {num_records}, for 1 record")

    quests = [r for r in tes5.iter_records(buf) if r.sig == b"QUST"]
    if len(quests) != 1:
        fail(f"expected 1 QUST, found {len(quests)}")
    quest = quests[0]
    print(f"quest: {quest.zstring(b'EDID')} formid={quest.formid:08X} "
          f"name={quest.zstring(b'FULL')}")

    # A plugin stores its own records with the master count in the high byte
    # (Update.esm, with one master, holds 01002ECE). The loader replaces that
    # byte with the plugin's own load-order index at runtime.
    expected_id = (len(masters) << 24) | 0x800
    if quest.formid != expected_id:
        fail(f"record formid {quest.formid:08X}, expected {expected_id:08X} "
             f"({len(masters)} masters + 0x800)")

    # --- subrecords in the order the engine expects ------------------------
    # ENAM (quest event) is optional and absent here: Mutagen leaves it out when
    # no event is set, and the CK does the same for a script-only quest.
    order = [s.decode("latin-1") for s, _ in quest.subrecords()]
    expected = ["EDID", "VMAD", "FULL", "DNAM", "NEXT", "ANAM",
                "ALST", "ALID", "FNAM", "ALFR", "VTCK", "ALED"]
    if order != expected:
        fail(f"subrecord order {order} != {expected}")

    # --- quest data --------------------------------------------------------
    dnam = quest.sub(b"DNAM")
    if len(dnam) != 12:
        fail(f"DNAM is {len(dnam)} bytes, expected 12")
    qflags, priority = struct.unpack_from("<HB", dnam, 0)
    print(f"DNAM: flags={qflags:#06x} priority={priority}")
    if not qflags & 0x1:
        fail("Start Game Enabled bit not set")
    if priority != 60:
        fail(f"priority {priority} != 60")

    # --- alias -------------------------------------------------------------
    if struct.unpack("<I", quest.sub(b"ALST"))[0] != 0:
        fail("alias id is not 0")
    if quest.sub(b"ALID").split(b"\x00")[0] != b"Player":
        fail("alias name is not Player")
    alfr = struct.unpack("<I", quest.sub(b"ALFR"))[0]
    print(f"alias: name=Player forced_ref={alfr:08X}")
    if alfr != 0x00000014:
        fail("forced reference is not PlayerRef")
    fnam = struct.unpack("<I", quest.sub(b"FNAM"))[0] if quest.sub(b"FNAM") else 0
    print(f"alias flags: FNAM=0x{fnam:08X}")
    # Vanilla quests that force the PlayerRef alias use FNAM 0 as often as not
    # (FreeformRiften10, NN01, BQ01 …), so a clean alias carries no flags. Bit 9
    # (Allow Reserved) is what a reserved-reference alias needs, and this one
    # only names the player explicitly; bit 0 (Reserved) would pin the alias
    # outside the running quest for no benefit.
    if fnam & 0x201:
        fail(f"unexpected alias flags 0x{fnam:08X}")
    if struct.unpack("<I", quest.sub(b"ANAM"))[0] != 1:
        fail("ANAM (next alias id) is not 1")

    # --- VMAD --------------------------------------------------------------
    # Layout, confirmed against vanilla quests (Skyrim.esm 0002E6FF has one
    # quest script and one alias block, 000B113D's alias block names alias 4):
    #   i16 version, u16 object format, u16 quest script count, scripts…
    #   u8 extra bind data version, u16 fragment count, wstring file name…
    #   u16 alias block count, then per block:
    #     u16 zero, u16 alias id, u32 quest form id,
    #     i16 version, u16 object format, u16 script count, scripts…
    v = quest.sub(b"VMAD")
    ver, fmt, script_count = struct.unpack_from("<HHH", v, 0)
    off = 6
    for _ in range(script_count):  # quest scripts; a zero count is the norm here
        off = skip_script(v, off)
    bind_version = v[off]
    off += 1
    fragment_count = struct.unpack_from("<H", v, off)[0]
    off += 2
    file_len = struct.unpack_from("<H", v, off)[0]
    off += 2 + file_len
    if fragment_count:
        fail(f"expected no script fragments, found {fragment_count}")
    alias_count = struct.unpack_from("<H", v, off)[0]
    off += 2
    print(f"VMAD: version={ver} fmt={fmt} quest_scripts={script_count} "
          f"bind={bind_version} fragments={fragment_count} "
          f"alias_blocks={alias_count}")
    if (ver, fmt) != (5, 2):
        fail(f"unexpected VMAD header version/format {ver}/{fmt}")
    if script_count != 0:
        fail(f"the quest itself should carry no scripts, it carries {script_count}")
    if alias_count != 1:
        fail(f"expected 1 alias block, found {alias_count}")

    zero, alias_index, quest_id = struct.unpack_from("<HHI", v, off)
    off += 8
    aver, afmt, scount = struct.unpack_from("<HHH", v, off)
    off += 6
    if zero != 0:
        fail("alias block leading word should be 0")
    if alias_index != 0:
        fail("script is not attached to alias 0")
    if quest_id != quest.formid:
        fail(f"alias block points at {quest_id:08X}, not this quest")
    if (aver, afmt, scount) != (5, 2, 1):
        fail("unexpected alias block header")
    name, sflags, prop_count, off = read_script(v, off)
    print(f"  alias block: alias={alias_index} quest={quest_id:08X} "
          f"ver={aver} fmt={afmt} scripts={scount} "
          f"-> {name} (flags={sflags}, props={prop_count})")
    if name != "ERC_PlayerCombat":
        fail(f"script name is {name!r}")
    if prop_count != 0:
        fail("script should have no properties")
    if off != len(v):
        fail(f"VMAD has {len(v) - off} trailing bytes")

    print("OK: plugin structure verified")


if __name__ == "__main__":
    main()
