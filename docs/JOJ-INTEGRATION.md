# Integrating ELDEN RING COMBAT into JOJ

This doc was rewritten after inspecting an actual JOJ install (`F:\Modlists\JOJ`).
The earlier version assumed BFCO owned the player's dodge and told you to disable
BFCO records in the Creation Kit. **That was wrong** — BFCO is JOJ's *attack*
framework, and the roll belongs to a separate stack. Don't disable BFCO records
on the strength of the old instructions.

---

## What already provides the ELDEN RING feel in JOJ

JOJ ships a complete ER-style dodge. Every piece is enabled in the
`Journals of Jyggalag` profile:

| Mod | Role | Values in the shipped install |
|---|---|---|
| **TK Dodge RE** 0.55-rc3 | Script-free SKSE plugin: the roll itself, 4 directions, stamina, attack-cancel | `DodgeHotkey = 56` (Left Alt), `DodgeStamina = 10`, `EnableDodgeAttackCancel = true`, `StepDodge = false`, `defaultDodgeEvent = TKDodgeBack` |
| **IFrame Generator RE AE** | Actual invincibility frames | driven by TK Dodge's `iFrameDuration = 0.3` |
| **TK Dodge SE** | The roll clips (`Animations\TKDodge\*.hkx`) | active |
| **Dynamic Dodge Animation** | 192 `.hkx` via OAR — weapon/state-aware roll variants | active |
| **Heavy Armor Dodge**, **Low Level dodge** | Equip-load / level-based roll variants | active |
| **TK dodge firstperson 8 ways dodge** | First-person rolls | active |
| **TK Dodge Animation Pandora Fix Patch**, **Pandora Behaviour Engine Plus**, **JOJ - Pandora Output** | Register the dodge clips into the behaviour graph | active |

The behaviour graph events are `TKDodgeForward`, `TKDodgeBack`, `TKDodgeLeft`,
`TKDodgeRight` — visible in `TK Dodge RE\Nemesis_Engine\mod\tkds\1hm_behavior\#tkds$5.txt`,
which binds `TKDodgeRight` to `Animations\TKDodge\Stepdodgeright.hkx`.

**So the dodge you asked ERC to build already exists, with real animations and
real i-frames.** ERC's job is the layer TK Dodge does not cover.

---

## What ERC owns (and what it deliberately doesn't)

| System | Owner | Notes |
|---|---|---|
| Weapon damage / scaling | **BFCO** (unchanged) | ERC never touches damage numbers. |
| Enemy AI attacks & reactions | **BFCO** (unchanged) | Leave all records as-is. |
| Player dodge roll, stamina, i-frames | **TK Dodge RE + IFrame Generator** | ERC detects TK Dodge RE and stands down. |
| Player hit-stop on impact | **ERC** | Global timescale dip when a blow lands. |
| Player stagger / guard-break tiers | **ERC** | 4-tier flinch→knockdown from `OnHit`. |
| Lock-on | **TDM** (unchanged) | Rolling direction is TK Dodge's. |

### Why ERC defers instead of competing

Three things went wrong when ERC rolled on its own in JOJ:

1. **The animation event didn't exist.** ERC called
   `PlayAnimation("ERC_Roll_Light_Front")`. Grepping every config in the install
   finds that string only in ERC's own `config.json` — no behaviour graph defines
   it, so the event plays nothing. This is why the mod appeared to "do nothing"
   even with the DLL loaded and the quest running.
2. **Both mods polled Left Alt.** TK Dodge RE's `DodgeHotkey` is 56; ERC's
   `DodgeKeyCode` defaulted to 56.
3. **Both billed stamina** — 10 from TK Dodge plus 12 from ERC on a single press.

ERC now asks `ERC_HasTKDodge()` (the DLL checks for
`Data\SKSE\Plugins\TK Dodge RE.ini`) and, when the MCM toggle
**Defer Dodge to TK Dodge RE** is on (the default), it stops polling the key,
skips its own roll and its stamina deduction, and leaves the roll alone.
It keeps the update loop, because that is what resets tap state safely if you
turn deferral off mid-game.

If TK Dodge RE is **not** installed, deferral is automatically inactive and ERC
runs its own roll — the fallback path, with the caveats in Step 3 below.

---

## Step 1 — Load order

- `EldenRingCombat.esp` after BFCO's plugins (in practice ERC adds almost no
  conflicting records — scripts, one SKSE plugin, one quest — so sensitivity is
  low). Put it in the gameplay/combat group after BFCO.
- `ERC.dll` goes in `Data/SKSE/Plugins/` and is loaded by SKSE independently of
  load order.
- ERC must load **after** TK Dodge RE in MO2 only so that nothing overwrites its
  own files; they don't share any file.

## Step 2 — Do NOT disable BFCO's dodge

There is none to disable. BFCO drives attacks/movesets (For Honor, Wo Long,
MCO/SCAR packs); the roll is TK Dodge RE. Disabling BFCO records to "give ERC the
dodge" would break the movesets and enemy combat for nothing.

Likewise, leave TK Dodge RE, IFrame Generator, and the OAR dodge packs enabled —
they are the animations you want.

## Step 3 — ERC's fallback roll (only if TK Dodge RE is absent)

If you run ERC without TK Dodge RE, ERC polls `DodgeKeyCode` itself and calls
`PlayAnimation` with the names on the MCM **Animations** page. Those names must
exist in the behaviour graph or nothing plays. The shipped defaults
(`ERC_Roll_Light_Front`, `ERC_Roll_Medium_Front`, `ERC_Roll_Heavy_Front`) are
**placeholders that no installed mod defines**, so on the fallback path you must
either:

- point them at clips that do exist (e.g. `TKDodgeForward` if you have TK Dodge's
  behaviour patches without the TK Dodge RE plugin), or
- add your own clips via OAR/DAR/Pandora under a `TKDodge`-style folder and name
  the events accordingly, or
- install TK Dodge RE and let deferral take over (recommended).

Directional variants are derived by appending `_Back` / `_Left` / `_Right` to the
base name, and only when **Enable Lock-On Rolls** is on.

## Step 4 — Tune the roll where it actually lives

With deferral on, the roll's stamina and i-frame window come from
`Data\SKSE\Plugins\TK Dodge RE.ini`:

```ini
DodgeHotkey = 56          ; 56 = Left Alt
DodgeStamina = 10
iFrameDuration = 0.3      ; needs I-Frame Generator RE
EnableDodgeAttackCancel = true
```

Edit those, then restart the game (TK Dodge RE reads them at launch). ERC's
`Roll Stamina Cost`, `I-Frame Fraction` and `Dodge Key Code` sliders are labelled
"(ERC roll only)" and do nothing while deferring — they exist for the fallback.

ERC logs what it found at load, so you can confirm the hand-off:

```
[ERC] TK Dodge RE detected (hotkey 56, stamina 10, i-frames 0.3s) - ERC defers the roll to it
```

That line goes to `OutputDebugString`, i.e. it shows in DebugView and in MO2's
SKSE plugin log capture, not in `Papyrus.0.log`.

## Step 5 — Tune ERC via the MCM

Open **Elden Ring Combat** in the MCM:

- **Combat page:** Defer Dodge to TK Dodge RE, sprint-hold time, hit-stop duration
  and timescale, and the feature toggles. (Roll stamina / i-frame / key are
  fallback-only.)
- **Stagger page:** the knockdown health fraction.
- **Movement page:** equip-load cuts and per-tier roll durations (fallback only).
- **Animations page:** stagger and roll animation event names.

MCM Helper persists choices to `Data/MCM/Settings/EldenRingCombat.ini`, which
`ERC.dll` merges over `Data/SKSE/Plugins/EldenRingCombat.ini` on load and on game
load.

## Step 6 — Animation names for the stagger tiers

`OnHit`-driven reactions call `PlayAnimation` with
`AnimFlinch` / `AnimStagger` / `AnimLargeStagger` / `AnimKnockdown`. The defaults
(`HitReaction_Flinch` etc.) are **unverified placeholders** — the same class of
mistake as `ERC_Roll_*`. If stagger reactions don't visibly play, set these to
events your install actually defines (check the moveset/OAR mods' behaviour
configs), or turn off **Enable Guard Break** until you have names that exist.

---

## Conflict checklist

| Potential conflict | Resolution |
|---|---|
| TK Dodge RE vs ERC both rolling on Left Alt | Handled: ERC defers by default. If you turn deferral off while TK Dodge RE is installed, you will roll twice and pay both stamina costs. |
| Two hit-stop mods | JOJ has none that dip the global timescale — `Timed Block-Dodge and Counter` freezes only the attacker's animation, and Valhalla's slow-time is scoped to timed blocks, so ordinary hits do not overlap. If you add a global-timescale hit-stop mod, disable one of them: ERC restores its own saved value, which would clobber the other's dip. |
| Stagger double-playing (BFCO hit-reactions + ERC) | If both fire, unset ERC's stagger names or disable **Enable Guard Break**; BFCO's moveset reactions are animation-authored and usually look better. |
| `iFrameDuration` ignored | I-Frame Generator RE must be installed (it is, in JOJ) — TK Dodge RE does not provide i-frames itself. |

## Testing in JOJ

1. `skse64.log` (or DebugView) shows the `[ERC] TK Dodge RE detected …` line.
2. Papyrus log shows no `Unbound native function` from `ERC_PlayerCombat`.
3. MCM shows **Elden Ring Combat** with Combat / Stagger / Movement / Animations.
4. Tap Left Alt → one roll, one stamina cost (10, not 22), with i-frames.
5. Take a hit → a brief world freeze (hit-stop), then flinch/stagger per your
   configured names. Hit-stop is ERC's, so turning off **Enable Hit-Stop** should
   remove the freeze without affecting the roll or stagger.
6. I-frame *damage* nullification still needs `[HOOK-2]`; in JOJ the roll's
   invincibility comes from I-Frame Generator, so it works regardless.
