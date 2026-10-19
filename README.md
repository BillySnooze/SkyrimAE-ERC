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

- **Tap-to-dodge rolls with i-frames.** Tap the dodge button to roll; hold it to sprint.
  During the invincible portion of a roll, incoming *physical* hits are nullified —
  exactly like ELDEN RING's dodge i-frames. (Magic/spells still get through.)
- **Hit-stop on impact.** When a blow lands, both attacker and target freeze for a few
  frames via a global timescale dip — the "impact crunch" that makes ER hits feel weighty.
- **4-tier hit reactions.** Incoming damage maps to flinch → stagger → large stagger →
  knockdown, with thresholds you tune in the MCM.
- **Equip-load-scaled rolls.** Light / medium / heavy load (from weapon + armour weight)
  selects a roll variant; heavier loads roll longer and slower.
- **Lock-on-aware rolls.** While locked on, directional rolls preserve your facing toward
  the target (works with True Directional Movement in JOJ).
- **Full MCM tuning.** Stamina costs, i-frame fraction, hit-stop duration/strength,
  stagger thresholds, equip-load cuts, roll durations, and feature toggles — all live.

## What it is NOT

- Not a damage overhaul — Skyrim's numbers are unchanged.
- Not an animation pack — it *triggers* the moveset animations your list already ships
  (For Honor / Wo Long via BFCO in JOJ); you point it at their event names.
- Not a standalone combat system — it layers on top of your existing combat mods.

---

## Requirements

| Component | Needed for | Notes |
|---|---|---|
| Skyrim AE (full, with Creation Club) | everything | JOJ's baseline requirement. |
| SKSE (matching your AE version) | the full experience | Loads `ERC.dll`. |
| **Creation Kit** | compiling the `.esp` | Compiles `ERC_PlayerCombat.psc`. |
| **SKSE SDK + C++ compiler** | building `ERC.dll` | MSVC/Visual Studio or clang-cl. See `docs/BUILD.md`. |

> **Two build paths.** You can ship just the Papyrus half (compile the `.esp` in CK) for a
> partial mod — stagger reactions only, no rolls/i-frames/hit-stop. The full experience
> needs both the `.esp` and the compiled `ERC.dll`. See `docs/BUILD.md` for exact steps.

## Install

1. **Build** (see `docs/BUILD.md`):
   - Compile `data/scripts/source/ERC_PlayerCombat.psc` in CK → save as `EldenRingCombat.esp` into `data/`.
   - Build the C++ plugin (`plugin/`) → `ERC.dll` into `data/SKSEPlugins/`.
2. **Install** the whole `EldenRingCombat/` folder (i.e. its `data/` contents) into your
   mod manager as a normal mod, placed after BFCO in load order.
3. **Integrate with JOJ** — follow `docs/JOJ-INTEGRATION.md`: disable BFCO's *player*
   dodge + hit-reaction records (verify each in CK), point ERC at your moveset's animation
   event names, and match the dodge key to JOJ's binding.
4. **Launch via `skse_loader.exe`**, open the MCM (`~` → Elden Ring Combat), and tune.

## Repository layout

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/
│  │   ├─ ERC_PlayerCombat.psc    ← core combat logic (compile in CK)
│  │   └─ ERC_Papyrus.h           ← native decls for CK type-checking
│  └─ SKSEPlugins/                ← drop the built ERC.dll here at runtime
├─ plugin/                        ← C++ source of ERC.dll
│  ├─ include/  (ERCPlugin.h, ERCMCM.h, ERCNatives.h)
│  ├─ src/      (ERCPlugin.cpp, ERCMCM.cpp, ERCNatives.cpp)
│  └─ validation/                 ← mock SDK + build-check.bat (offline compile check)
├─ tools/
│  └─ validate-psc.ps1            ← Papyrus structural validator
└─ docs/
   ├─ BUILD.md                     ← CK + SKSE SDK build steps
   ├─ SKSE-API-NOTES.md            ← porting the C++ to the real SKSE plugin API
   └─ JOJ-INTEGRATION.md           ← how it replaces BFCO player combat in JOJ
```

## Honest status: source vs compiled

This repository contains **source code and documentation**, not prebuilt binaries:

- ✅ **Compiles cleanly (validated):** the C++ plugin sources build with MSVC
  (`cl /c`, C++17) against the stand-in SKSE headers in
  `plugin/validation/mock-sdk/` — run `plugin/validation/build-check.bat`.
  This proves syntax and type correctness.
- ⚠️ **Not yet a real plugin:** that stand-in API is **not** the official SKSE
  plugin API. The port (`SKSEPlugin_Version`/`SKSEPlugin_Load`, Papyrus native
  registration, MCM Helper instead of `IWMCM`) is specified step-by-step in
  `docs/SKSE-API-NOTES.md`. Do it before expecting a loadable `.dll`.
- ✅ **Structurally validated:** the Papyrus script passes
  `tools/validate-psc.ps1` (no duplicate names, balanced blocks, no non-Skyrim APIs).
  It has **not** been compiled in Creation Kit — no CK is installed here.
- ✅ **Complete logic, needs your SDK to build:** all combat logic
  (settings store, i-frame window math, hit-stop, tap detection) is implemented.
  Three parts are marked (`[HOOK-1]`, `[HOOK-2]`, `[VERSION-SPECIFIC]`) because they
  depend on *your* SKSE SDK and game version.
- ✅ **Documentation:** build steps, JOJ integration guide, API notes, conflict checklist.

So: you get a complete, validated, well-documented mod to finish building against
your own toolchain — not a drop-in prebuilt `.esp`/`.dll`.

## Credits & license

- Combat *feel* reference: [ELDEN-RING-Combat-Rewrite](https://github.com/Funny-Bones/ELDEN-RING-Combat-Rewrite)
  (Rust/Bevy sandbox by Funny-Bones, MIT). This mod ports its mechanics/timing concepts;
  it contains no ELDEN RING game files.
- Target list: [JOJ — Journals of Jyggalag](https://www.themoddingbordello.com/modlists/joj/overview) (The Modding Bordello).

Code in this repository is provided under the **MIT License** (see `LICENSE.md`). It grants
nothing over ELDEN RING, Skyrim, or any third-party mod it integrates with.
