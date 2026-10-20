"""Minimal TES5/SSE plugin reader used to extract byte-level QUST layouts.

xEdit tells us the logical structure of a record; this tells us the exact
subrecord bytes, which is what a writer needs (field sizes, ordering, the
VMAD binary blob). Kept dependency-free on purpose.
"""
import struct
import zlib

HEADER = struct.Struct("<4sIIIIHH")        # sig,size,flags,formid,vc,formver,vc2
RECORD_HDR = struct.Struct("<4sIIII")      # sig,size,flags,formid,vc
GRUP_HDR = struct.Struct("<4sI4siI")       # sig,size,label,type,vc
FLAG_COMPRESSED = 0x00040000


class Record:
    __slots__ = ("sig", "flags", "formid", "data")

    def __init__(self, sig, flags, formid, data):
        self.sig = sig
        self.flags = flags
        self.formid = formid
        self.data = data

    def subrecords(self):
        """Yield (signature, payload) for each subrecord."""
        off = 0
        n = len(self.data)
        while off + 6 <= n:
            sig = self.data[off:off + 4]
            size = struct.unpack_from("<H", self.data, off + 4)[0]
            off += 6
            yield sig, self.data[off:off + size]
            off += size

    def sub(self, sig):
        for s, payload in self.subrecords():
            if s == sig:
                return payload
        return None

    def zstring(self, sig):
        payload = self.sub(sig)
        if payload is None:
            return None
        return payload.split(b"\x00")[0].decode("utf-8", "replace")


def iter_records(buf, start=0, end=None):
    """Yield every Record at this nesting level (groups are descended into)."""
    if end is None:
        end = len(buf)
    off = start
    while off + 24 <= end:
        sig = buf[off:off + 4]
        if sig == b"GRUP":
            _, size, _label, _type, _vc = GRUP_HDR.unpack_from(buf, off)
            # SSE group header is 24 bytes total; trust the size field.
            yield from iter_records(buf, off + 24, off + size)
            off += size
            continue

        _, size, flags, formid, _vc, _fv, _vc2 = HEADER.unpack_from(buf, off)
        data = buf[off + 24:off + 24 + size]
        if flags & FLAG_COMPRESSED:
            (raw_size,) = struct.unpack_from("<I", data, 0)
            data = zlib.decompress(data[4:])
            assert len(data) == raw_size, (len(data), raw_size)
        yield Record(sig, flags, formid, data)
        off += 24 + size


def load(path):
    with open(path, "rb") as fh:
        return fh.read()


def find_quest(buf, formid):
    for rec in iter_records(buf):
        if rec.sig == b"QUST" and rec.formid == formid:
            return rec
    return None
