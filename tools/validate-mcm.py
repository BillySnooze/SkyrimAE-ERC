"""Check data/MCM/Config/EldenRingCombat against what MCM Helper 1.5 actually reads.

Written after the menu silently failed to appear in game. Two mistakes were
possible and both were real at the time, so each is checked here:

  * MCM Helper's document shape is `pages` -> `pageDisplayName` -> `content`.
    A root `content` array of `{"type": "page"}` objects is not the same thing,
    and MCM Helper skips such a file without logging anything.
  * Every option id must be `<typePrefix><name>:<Category>`, with the Category a
    section name in the paired settings.ini, and its valueOptions must carry a
    `sourceType` MCM Helper binds (ModSettingBool/Int/Float/String).

Only item types that other configs in this modlist already use are allowed, so an
unsupported type cannot slip back in.

    py tools/validate-mcm.py            # checks the repo copy
    py tools/validate-mcm.py <dir>
"""
import json
import pathlib
import sys

CONFIG = pathlib.Path(__file__).resolve().parents[1] / "data" / "MCM" / "Config" / "EldenRingCombat"
ITEM_TYPES = {
    "header", "text", "slider", "stepper", "toggle", "keymap", "enum", "menu",
    "color", "input", "empty", "hiddenToggle",
}
VALUE_TYPES = {
    "toggle": {"ModSettingBool"},
    "slider": {"ModSettingFloat", "ModSettingInt"},
    "stepper": {"ModSettingFloat", "ModSettingInt"},
    "input": {"ModSettingString"},
    "color": {"ModSettingString"},
    "keymap": {"ModSettingInt"},
}
PREFIX = {"ModSettingBool": "b", "ModSettingInt": "i", "ModSettingFloat": "f", "ModSettingString": "s"}

errors = []
warnings = []


def fail(msg):
    errors.append(msg)


def read_ini_sections(path):
    sections = {}
    current = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line[0] in ";#":
            continue
        if line.startswith("["):
            current = line.strip("[]").strip()
            sections[current] = set()
            continue
        if "=" in line and current is not None:
            sections[current].add(line.split("=", 1)[0].strip())
    return sections


def main(argv):
    root = pathlib.Path(argv[1]) if len(argv) > 1 else CONFIG
    config_path = root / "config.json"
    ini_path = root / "settings.ini"

    if not config_path.exists():
        print(f"FAIL: missing {config_path}")
        return 1
    if not ini_path.exists():
        print(f"FAIL: missing {ini_path}")
        return 1

    try:
        doc = json.loads(config_path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as exc:
        print(f"FAIL: config.json is not valid JSON: {exc}")
        return 1

    ini = read_ini_sections(ini_path)

    # --- document shape ---------------------------------------------------
    for key in ("modName", "displayName", "pages"):
        if key not in doc:
            fail(f"missing required root key '{key}'")
    if "content" in doc:
        fail("root 'content' array is present; MCM Helper reads pages from 'pages'")
    pages = doc.get("pages")
    if not isinstance(pages, list) or not pages:
        fail("'pages' must be a non-empty array")
        pages = []

    ids = set()
    for page in pages:
        if "pageDisplayName" not in page:
            fail(f"page {page!r} has no 'pageDisplayName'")
        if not isinstance(page.get("content"), list):
            fail(f"page {page.get('pageDisplayName')!r} has no 'content' array")
            continue
        for item in page["content"]:
            itype = item.get("type")
            if itype not in ITEM_TYPES:
                fail(f"unsupported item type {itype!r} on page {page.get('pageDisplayName')!r}")
                continue
            if itype in ("header", "text", "empty"):
                if not item.get("text") and itype != "empty":
                    warnings.append(f"{itype} without text on {page.get('pageDisplayName')!r}")
                continue

            oid = item.get("id", "")
            if ":" not in oid:
                fail(f"id {oid!r} has no ':Category' suffix (MCM Helper keys settings by it)")
                continue
            name, category = oid.split(":", 1)
            if oid in ids:
                fail(f"duplicate id {oid!r}")
            ids.add(oid)

            opts = item.get("valueOptions") or {}
            source = opts.get("sourceType")
            expected = VALUE_TYPES.get(itype)
            if source is None:
                fail(f"{oid}: valueOptions has no sourceType (MCM Helper would not bind it)")
                continue
            if not source.startswith("ModSetting"):
                fail(f"{oid}: sourceType {source!r} is not a ModSetting type")
                continue
            if expected and source not in expected:
                fail(f"{oid}: {itype} wants {'/'.join(sorted(expected))}, got {source}")

            prefix = PREFIX.get(source, "")
            if prefix and not name.startswith(prefix):
                fail(f"id {oid!r} should start with '{prefix}' for {source}")

            if category not in ini:
                fail(f"{oid}: category [{category}] missing from settings.ini")
            elif name not in ini[category]:
                fail(f"{oid}: '{name}' missing from [{category}] in settings.ini")

    # --- ini keys that no control would ever write -----------------------
    for section, keys in ini.items():
        for key in keys:
            if f"{key}:{section}" not in ids:
                warnings.append(f"settings.ini {section}.{key} has no MCM control")

    for warning in warnings:
        print(f"note: {warning}")
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1

    print(f"OK: {len(pages)} pages, {len(ids)} controls, all bound to settings.ini")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
