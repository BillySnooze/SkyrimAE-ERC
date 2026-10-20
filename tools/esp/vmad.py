"""Decoder for the VMAD (Papyrus script attachment) binary blob.

Only the parts this project needs are implemented, but the decoder walks the
whole blob so a misplaced field shows up as a parse error rather than a plugin
the game silently ignores.
"""
import struct

# Property value types used by the VMAD format.
OBJECT, STRING, INT, FLOAT, BOOL = 1, 2, 3, 4, 5


class Reader:
    def __init__(self, data):
        self.data = data
        self.off = 0

    def take(self, n):
        if self.off + n > len(self.data):
            raise ValueError(f"read past end at {self.off} + {n} > {len(self.data)}")
        out = self.data[self.off:self.off + n]
        self.off += n
        return out

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack("<H", self.take(2))[0]

    def i16(self):
        return struct.unpack("<h", self.take(2))[0]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def wstring(self):
        return self.take(self.u16()).decode("utf-8", "replace")


def parse_scripts(r):
    scripts = []
    for _ in range(r.u16()):
        name = r.wstring()
        flags = r.u8()
        props = []
        for _ in range(r.u16()):
            pname = r.wstring()
            ptype = r.u8()
            pflags = r.u8()
            props.append((pname, ptype, pflags, read_value(r, ptype)))
        scripts.append({"name": name, "flags": flags, "properties": props})
    return scripts


def read_value(r, ptype):
    """Read one property value. Only the common scalar/object cases matter here."""
    base = ptype & 0x0F
    if ptype in (OBJECT, STRING, INT, FLOAT, BOOL):
        return _scalar(r, ptype)
    if ptype in (11, 12, 13, 14, 15):  # arrays
        count = r.u32()
        return [_scalar(r, base) for _ in range(count)]
    raise ValueError(f"unsupported property type {ptype} at offset {r.off}")


def _scalar(r, t):
    if t == OBJECT:
        # Confirmed against Skyrim.esm 0002E6FF: a property pointing at the
        # quest's alias 1 is stored as u16 zero, u16 alias, u32 form id.
        zero = r.u16()
        alias = r.u16()
        formid = r.u32()
        return ("object", zero, f"{formid:08X}", alias)
    if t == STRING:
        return r.wstring()
    if t == INT:
        return struct.unpack("<i", r.take(4))[0]
    if t == FLOAT:
        return struct.unpack("<f", r.take(4))[0]
    if t == BOOL:
        return bool(r.u8())
    raise ValueError(f"unsupported scalar type {t}")


def parse_vmad(data):
    """Decode a VMAD blob.

    Field order, confirmed against vanilla quests:
      i16 version, u16 object format, u16 script count, scripts…
      u8 extra bind data version, u16 fragment count, wstring file name,
      fragments…, u16 alias block count, then per block:
        u16 zero, u16 alias id, u32 quest form id,
        i16 version, u16 object format, u16 script count, scripts…
    """
    r = Reader(data)
    out = {"version": r.i16(), "object_format": r.i16()}
    out["scripts"] = parse_scripts(r)
    out["extra_bind_data_version"] = r.u8()
    fragments = r.u16()
    out["fragment_file"] = r.wstring()
    if fragments:
        raise ValueError(f"{fragments} script fragments present; not decoded here")
    out["aliases"] = []
    for _ in range(r.u16()):
        entry = {
            "zero": r.u16(),
            "alias": r.u16(),
            "formid": f"{r.u32():08X}",
            "version": r.i16(),
            "object_format": r.i16(),
        }
        entry["scripts"] = parse_scripts(r)
        out["aliases"].append(entry)
    out["_consumed"] = r.off
    out["_size"] = len(data)
    return out
