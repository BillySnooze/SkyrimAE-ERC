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
- **Lock-on-aware roll variants.** Directional roll animations exist (`_Back/_Left/_Right`),
  but Papyrus can't read TDM's target bearing — so the current keyboard polling always uses
  the front variant. Directional rolls need the `[HOOK-1]` input hook (see `docs/BUILD.md`).
- **Full MCM tuning.** Dodge key, sprint-hold time, stamina costs, i-frame fraction,
  hit-stop duration/strength, stagger thresholds, equip-load cuts, roll durations, animation
  names, and feature toggles — all live.

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
| **Creation Kit** | compiling the `.esp` | Compiles `ERC_PlayerCombat.psc`. |
| **SKSE plugin SDK + MSVC** | building `ERC.dll` | See `docs/BUILD.md`. |

> **Both halves are required.** The Papyrus script calls `ERC_*` natives, so without
> `ERC.dll` it throws on the first call — there is no silent partial mode. Build the
> `.esp` in CK and `ERC.dll` with MSVC; see `docs/BUILD.md`.

## Install

1. **Build** (see `docs/BUILD.md`):
   - Compile `data/scripts/source/ERC_PlayerCombat.psc` in CK → save `EldenRingCombat.esp` into `data/`.
   - Build the C++ plugin → `ERC.dll` into `data/SKSE/Plugins/`.
2. **Install** the `data/` contents (`scripts/`, `MCM/`, `SKSE/Plugins/ERC.dll`, the `.esp`)
   into your mod manager as a normal mod, placed after BFCO in load order.
3. **Integrate with JOJ** — follow `docs/JOJ-INTEGRATION.md`: disable BFCO's *player*
   dodge + hit-reaction records (verify each in CK), point ERC at your moveset's animation
   event names, and match the dodge key to JOJ's binding.
4. **Launch via `skse_loader.exe`**, open the MCM (`~` → Elden Ring Combat), and tune.

## Repository layout

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/ERC_PlayerCombat.psc   ← combat logic (compile in CK)
│  ├─ MCM/Config/EldenRingCombat/           ← MCM Helper menu + defaults
│  └─ SKSE/Plugins/                         ← drop the built ERC.dll here
├─ plugin/                                  ← C++ source of ERC.dll
│  ├─ include/  (ERCPlugin.h, erc_compat.h)
│  ├─ src/      (ERCMain.cpp, ERCPlugin.cpp, ERCNatives.cpp)
│  └─ validation/                           ← mock SDK + build-check.bat
├─ tools/
│  └─ validate-psc.ps1                      ← Papyrus structural validator
└─ docs/
   ├─ BUILD.md                              ← CK + SKSE SDK build steps
   ├─ SKSE-API-NOTES.md                     ← the SKSE API port and what remains
   └─ JOJ-INTEGRATION.md                    ← replacing BFCO player combat in JOJ
```

## Honest status: source vs compiled

This repository contains **source code and documentation**, not prebuilt binaries:

- ✅ **Ported to the real SKSE plugin API:** `SKSEPlugin_Version` /
  `SKSEPlugin_Load` entry points, `SKSEPapyrusInterface` native registration, and
  MCM Helper for the menu. `ERCMain.cpp` was compiled against the **genuine**
  SKSE 2.2.6 `PluginAPI.h`; all three TUs compile against the mock SDK
  (`plugin/validation/build-check.bat`).
- ⚠️ **Two version-specific hooks remain** (`[HOOK-1]` per-frame tick/gamepad,
  `[HOOK-2]` i-frame damage nullification + timescale), because they need your
  exact runtime's addresses. See `docs/SKSE-API-NOTES.md`.
- ✅ **Structurally validated:** the Papyrus script passes
  `tools/validate-psc.ps1` (no duplicate names, balanced blocks, no non-Skyrim APIs).
  It has **not** been compiled in Creation Kit — no CK is installed here.
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
