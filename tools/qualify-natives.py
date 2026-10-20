"""Qualify the script's native calls with the script name.

The natives are `global native` (see the block at the bottom of the .psc), and
Papyrus requires a global function to be called through its owning script. This
rewrites bare calls such as `ERC_GetFloat("x")` into
`ERC_PlayerCombat.ERC_GetFloat("x")`.

Declarations (`... global native`) and comments are skipped line by line, so a
declaration can never be rewritten into nonsense.

    py tools/qualify-natives.py           # rewrite in place
    py tools/qualify-natives.py --check   # exit 1 if any call is unqualified
"""
import pathlib
import re
import sys

PSC = pathlib.Path(__file__).resolve().parents[1] / "data" / "scripts" / "source" / "ERC_PlayerCombat.psc"
SCRIPT = "ERC_PlayerCombat"

CALLS = (
    (r'(?<![\w.])(ERC_GetFloat\()', None),
    (r'(?<![\w.])(ERC_GetInt\()', None),
    (r'(?<![\w.])(ERC_GetBool\()', None),
    (r'(?<![\w.])(ERC_GetString\()', None),
    (r'(?<![\w.])(ERC_SetFloat\()', None),
    (r'(?<![\w.])(ERC_ConsumeDodgeTap\()', None),
    (r'(?<![\w.])(ERC_RollStarted\()', None),
    (r'(?<![\w.])(ERC_TriggerHitStop\()', None),
)


def is_declaration(line):
    stripped = line.strip()
    return stripped.startswith(";") or " global native" in line or not stripped


def qualify(text):
    out = []
    for line in text.splitlines(keepends=True):
        if not is_declaration(line):
            for pattern, _ in CALLS:
                line = re.sub(pattern, rf"{SCRIPT}.\1", line)
            line = line.replace(f"{SCRIPT}.{SCRIPT}.", f"{SCRIPT}.")
        out.append(line)
    return "".join(out)


def main():
    text = PSC.read_text(encoding="utf-8")
    new = qualify(text)

    # The rewrite must not have produced a qualified declaration.
    for line in new.splitlines():
        if " global native" in line and f"{SCRIPT}." in line:
            print(f"FAIL: rewrite damaged a declaration: {line.strip()}")
            return 1

    if "--check" in sys.argv:
        if new != text:
            print("FAIL: native calls are not qualified (run tools/qualify-natives.py)")
            return 1
        print("OK: native calls are qualified")
        return 0

    if new != text:
        PSC.write_text(new, encoding="utf-8", newline="")
        print(f"qualified native calls in {PSC.name}")
    else:
        print("nothing to do")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
