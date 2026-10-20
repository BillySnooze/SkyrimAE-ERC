"""Verify the VMAD decoder against vanilla records.

If the decoder consumes exactly the subrecord bytes and reports the scripts the
game knows about, the same layout can be used for writing.
"""
import sys
import pathlib
import pprint

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import tes5  # noqa: E402
import vmad  # noqa: E402

DATA = pathlib.Path(r"F:\Modlists\JOJ\Stock Game\Data\Skyrim.esm")
OUT = pathlib.Path(r"C:\Users\Billy\EldenRingCombat\build\vmad-parse.txt")

TARGETS = {0x0010EC61: "MQGreybeardCall", 0x0010D9F4: "JailQuest"}


def main():
    buf = tes5.load(DATA)
    lines = []
    for formid, name in TARGETS.items():
        rec = tes5.find_quest(buf, formid)
        payload = rec.sub(b"VMAD")
        try:
            parsed = vmad.parse_vmad(payload)
        except Exception as exc:
            lines.append(f"{name}: PARSE FAILED: {exc}")
            continue
        lines.append(f"===== {name} =====")
        lines.append(f"  size={len(payload)} consumed={parsed['_consumed']} "
                     f"version={parsed['version']} objfmt={parsed['object_format']}")
        lines.append(f"  quest scripts: "
                     f"{[s['name'] for s in parsed['scripts']]}")
        for i, al in enumerate(parsed["aliases"]):
            lines.append(f"  alias block {i}: formid={al['formid']} "
                         f"alias={al['alias']} ver={al['version']} "
                         f"fmt={al['object_format']} "
                         f"scripts={[s['name'] for s in al['scripts']]}")
            for s in al["scripts"]:
                lines.append(f"    props: "
                             f"{[(p[0], p[1]) for p in s['properties']]}")
        lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
