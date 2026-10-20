# ELDEN RING COMBAT (ERC)

A Skyrim **Anniversary Edition** mod that translates the *feel* of ELDEN RING player
combat into Skyrim — built for the **JOJ** (Journals of Jyggalag) modlist, where it
replaces BFCO's *player* combat while leaving damage numbers and enemy AI untouched.

> **Scope.** This is a *feel/mechanics* port, not a data port. It does **not** import
> ELDEN RING's damage values, weapon stats, or per-weapon movesets. It keeps Skyrim's
> existing damage system exactly as-is and reshapes only: dodge timing + invincibility,
> impact freeze, hit reactions, and equip-load scaling. Every tunable is exposed as an
> in-game MCM slider.

---

## Features

- **ER-style rolls with i-frames — delegated, not duplicated.** In JOJ the roll
  comes from **TK Dodge RE** (script-free SKSE plugin) plus **I-Frame Generator**
  and OAR animation packs. ERC detects TK Dodge RE and hands the roll over, so you
  get the real animations and a real 0.3 s invincibility window that are already
  in your list. See `docs/JOJ-INTEGRATION.md` for why this is the right split:
  with TK Dodge RE installed the two would poll the same key and bill the same
  roll twice.
- **ERC's own roll is the fallback.** On a list with no dodge framework, ERC polls
  the dodge key itself (tap = roll, hold = sprint) and fires the roll animation
  events through `Debug.SendAnimationEvent`. It deliberately drives the *TK Dodge*
  clips (`TKDodgeForward/Back/Left/Right`), because those are the roll events that
  exist in practice; the invented `ERC_Roll_*` names of earlier builds matched no
  behaviour graph and so rolled nothing.
- **Hit-stop is delegated to Precision.** Skyrim's `TimeScale` global scales game
  *time* (the clock and AI scheduling), not animation playback, so dipping it never
  produced a visible freeze — earlier builds did exactly that and looked broken.
  Precision implements hit-stop by scaling each actor's animation speed, and JOJ
  ships it enabled (0.07 s vs NPCs, 0.035 s otherwise, 0.1× slowdown, camera
  shake). Tune it in **MCM → Precision → Hitstop**. A native hit-stop inside ERC
  would need the same engine hook.
- **4-tier hit reactions (off by default).** Incoming hits map to flinch → stagger →
  large stagger → knockdown. Tiers come from what Skyrim's `OnHit` actually reports
  (bash, power attack, sneak attack, broken block) plus your health fraction, since
  Papyrus exposes no weapon damage. Disabled by default because Skyrim and BFCO
  already apply their own reactions, and a second one on the same hit stacks.
- **Equip-load-scaled rolls.** Light / medium / heavy load — the ratio of carried
  weight (`InventoryWeight`) to max carry weight (`CarryWeight`), the same measure
  ELDEN RING uses — selects how long ERC waits before the next roll.
  (With TK Dodge RE installed, JOJ's Heavy Armor Dodge / Low Level dodge packs
  already provide the variants; ERC's version applies on the fallback path.)
- **Full MCM tuning.** Dodge deferral, dodge key, sprint-hold time, stamina cost,
  roll durations, equip-load cuts, knockdown health fraction, every roll and hit
  reaction animation event, and feature toggles. Sliders carry MCM Helper
  `formatString` values, so fractional settings display as `0.15` rather than `0`.

## What it is NOT

- Not a damage overhaul — Skyrim's numbers are unchanged.
- Not an animation pack — it *triggers* the moveset animations your list already ships
  (For Honor / Wo Long via BFCO in JOJ); you point it at their event names.
- Not a standalone combat system — it layers on top of your existing combat mods.

---

## Requirements

| Component | Needed for | Notes |
|---|---|---|
| Skyrim AE **1.6.1170** | everything | The JOJ stock game (`F:\Modlists\JOJ\Stock Game`). |
| **SKSE 2.2.6** (for 1.6.1170) | loading `ERC.dll` | Must match the runtime exactly. |
| **MCM Helper** | the settings menu | Ships with JOJ. |
| **TK Dodge RE + I-Frame Generator** | the animated roll | Ships with JOJ. Detected automatically; ERC stands down from its own roll when present. |
| **Creation Kit** | Papyrus compilation | Compiles `ERC_PlayerCombat.psc` and `ERC_MCM.psc`. The `.esp` itself is built by a Python writer. |
| **SKSE plugin SDK + MSVC** | building `ERC.dll` | See `docs/BUILD.md`. |

> **Both halves are required.** The Papyrus script calls `ERC_*` natives, so without
> `ERC.dll` it throws on the first call — there is no silent partial mode.
>
> **The MCM needs a quest, not just a JSON file.** MCM Helper reads
> `Data/MCM/Config/<plugin>/config.json` only for a *running quest in that plugin
> whose script derives from `MCM_ConfigBase`*. `ERC_MCMQuest` + `ERC_MCM.psc` is
> that quest; without it the menu is skipped silently (no log line at all). See
> `docs/BUILD.md`.

## Install

1. **Build** — one command (see `docs/BUILD.md`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\build.ps1
   ```
   This produces `data/scripts/ERC_PlayerCombat.pex`, `data/scripts/ERC_MCM.pex`,
   `data/SKSE/Plugins/ERC.dll`, `data/EldenRingCombat.esp` and
   `data/SEQ/EldenRingCombat.seq` — a complete mod.
2. **Install** the `data/` contents (`scripts/`, `MCM/`, `SKSE/Plugins/ERC.dll`, the
   `.esp` and `SEQ/`) into your mod manager as a normal mod, placed after BFCO in
   load order.
3. **Integrate with JOJ** — follow `docs/JOJ-INTEGRATION.md`: leave TK Dodge RE and
   I-Frame Generator enabled (ERC defers the roll to them automatically), and match
   the stagger animation event names to what your install defines.
4. **Launch via `skse64_loader.exe`**, open the MCM (`~` → Elden Ring Combat), and tune.

## Repository layout

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/ERC_PlayerCombat.psc   ← combat logic (extends ReferenceAlias)
│  ├─ scripts/source/ERC_MCM.psc            ← MCM registration quest script (extends MCM_ConfigBase)
│  ├─ MCM/Config/EldenRingCombat/           ← MCM Helper menu + defaults
│  └─ SKSE/Plugins/                         ← built ERC.dll goes here
├─ plugin/                                  ← C++ source of ERC.dll
│  ├─ include/  (ERCPlugin.h, erc_compat.h)
│  ├─ src/      (ERCMain.cpp, ERCPlugin.cpp, ERCNatives.cpp)
│  └─ validation/                           ← mock SDK + build-check.bat
├─ tools/
│  ├─ build.ps1                             ← builds .pex + ERC.dll + the .esp
│  ├─ esp/                                  ← ESP generator + byte-level verifier
│  ├─ vendor/mcm-helper/                    ← MCM Helper public base scripts (compile only)
│  ├─ housecarl/                            ← the quest record spec (JSON)
│  ├─ mcp/                                  ← stdio MCP client used by the build
│  ├─ xedit/                                ← headless xEdit verifier
│  └─ validate-psc.ps1                      ← Papyrus structural validator
└─ docs/
   ├─ BUILD.md                              ← build steps, the ESP pipeline, SDK setup
   ├─ SKSE-API-NOTES.md                     ← the SKSE API port and what remains
   └─ JOJ-INTEGRATION.md                    ← replacing BFCO player combat in JOJ
```

## Honest status: source vs compiled

This repository contains **source code and documentation**, not prebuilt binaries
(`.gitignore` excludes them — run `tools/build.ps1` to produce them):

- ✅ **Papyrus compiles clean:** `ERC_PlayerCombat.psc` → `.pex` with **0 errors,
  0 warnings** using the Creation Kit's own `PapyrusCompiler.exe`, against the
  real base-game and SKSE source scripts.
- ✅ **`ERC.dll` builds and links** against the genuine SKSE 2.2.6 SDK
  (`Ez0n3/SKSE64AE-Plugins`, runtime `0x01064920`), exporting
  `SKSEPlugin_Load` + `SKSEPlugin_Version`.
- ✅ **The `.esp` builds too.** Skyrim has no API to attach a script to the player
  and the SKSE plugin API has no `AttachScript` call, so the script needs a
  start-game-enabled quest with a Player alias — and `tools\build.ps1` authors
  that plugin headlessly through the houseCARL MCP server, writes its `.seq`, and
  verifies it with three independent parsers (own byte reader, esper, xEdit).
  `docs\BUILD.md` Part A documents the record and the two byte-level details that
  are easy to get wrong.
- ❌ **Not a hit-stop implementation.** An earlier build dipped the `TimeScale`
  global and looked broken, because that global scales game time rather than
  animation playback. JOJ's Precision already does hit-stop properly; ERC points at
  it instead of competing with it.
- ⚠️ **One version-specific hook remains** (`[HOOK-1]` per-frame tick/gamepad),
  because it needs your exact runtime's addresses. See `docs/SKSE-API-NOTES.md`.
  Note that i-frames in JOJ come from **TK Dodge RE / IFrame Generator**, not from
  ERC — ERC's plugin tracks a window but installs no damage hook, so it cannot
  block a hit. Use the defer path for real invincibility.
- ⚠️ **No ELDEN RING animation data ships here, by design.** ER animations are
  Havok 2016/2018 `.hkx` inside `.anibnd.dcx` on FromSoft's skeleton; Skyrim SE
  needs Havok 2010 `.hkx` on the `NPC …` rig plus a behaviour-graph entry, and
  redistribution of FromSoftware's clips isn't something this project does. The
  animated roll comes from TK Dodge RE / OAR packs already in the modlist.
- ✅ **Documentation:** build steps, JOJ integration guide, API notes, conflict checklist.

So: every artifact (`.pex`, `.dll`, `.esp`, `.seq`) is produced by one command
from source — no binaries are committed, and nothing needs the Creation Kit UI.

## Credits & license

- Combat *feel* reference: [ELDEN-RING-Combat-Rewrite](https://github.com/Funny-Bones/ELDEN-RING-Combat-Rewrite)
  (Rust/Bevy sandbox by Funny-Bones, MIT). This mod ports its mechanics/timing concepts;
  it contains no ELDEN RING game files.
- Target list: [JOJ — Journals of Jyggalag](https://www.themoddingbordello.com/modlists/joj/overview) (The Modding Bordello).

Code in this repository is provided under the **MIT License** (see `LICENSE.md`). It grants
nothing over ELDEN RING, Skyrim, or any third-party mod it integrates with.
