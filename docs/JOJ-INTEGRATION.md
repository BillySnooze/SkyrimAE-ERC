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
| Player dodge roll, stamina, i-frames | **TK Dodge RE/NG + IFrame Generator** | ERC detects TK Dodge and stands down. ERC ships the `TK Dodge RE.ini` override that makes it roll instead of step. |
| Player hit-stop on impact | **Precision** | Scales each actor's animation speed. ERC no longer dips the timescale. |
| Player stagger / guard-break tiers | **ERC** (off by default) | 4-tier flinch→knockdown from `OnHit`. |
| Bullet-time on a timed dodge | **Timed Block-Dodge and Counter** | Its `[TimedDodge]`/`[Slowmo]` block, not hit-stop. |
| Lock-on | **TDM** (unchanged) | Rolling direction is TK Dodge's. |

### Why the dodge was a step, not a roll

JOJ's `JOJ - MCM and INI Settings\SKSE\Plugins\TK Dodge RE.ini` ships:

```ini
StepDodge = true
```

That is TK Dodge's own switch for "step dodge instead of rolling dodge". With it
on, the game plays `TKDodge\StepDodge*.hkx` and never touches the roll clips
(`DodgeBack/Left/Right` + the vanilla forward roll that the *Dynamic Dodge
Animation* OAR packs replace). No amount of MCM fiddling in ERC can change that:
ERC does not own that animation.

ERC therefore ships its own copy of the file (the ERC mod is first in MO2's
priority list, so it wins) with three changes:

| Key | JOJ | ERC | Why |
|---|---|---|---|
| `StepDodge` | `true` | `false` | roll instead of step |
| `EnableDodgeInPlace` | absent (false) | `true` | dodging on the spot did nothing at all |
| `defaultDodgeEvent` | `TKDodgeBack` | `TKDodgeForward` | ER rolls forward from idle |

Everything else (sprint-key dodge, 10 stamina, 0.3 s i-frames, attack-cancel) is
unchanged. Delete `Data\SKSE\Plugins\TK Dodge RE.ini` from the ERC mod to go back
to the list's step dodge.

### Why ERC defers instead of competing

Three things went wrong when ERC rolled on its own in JOJ:

1. **The animation event didn't exist.** ERC called
   `PlayAnimation("ERC_Roll_Light_Front")`, which is both a Papyrus error on actors
   ("is an Actor, and PlayAnimation should not be used") and a name no behaviour
   graph defines. Grepping every config in the install found that string only in
   ERC's own `config.json`, so nothing played. This is why the mod appeared to "do
   nothing" even with the DLL loaded and the quest running. ERC now sends the
   `TKDodge*` events with `Debug.SendAnimationEvent` instead.
2. **Both mods polled the same key.** TK Dodge's dodge key defaults to Left Alt
   (or the sprint key, which JOJ uses via `EnableSprintKeyDodge`); ERC's
   `DodgeKeyCode` also defaulted to 56. ERC's default is now **45 (X)**. Note V
   is not free either: JOJ's Timed Block-Dodge and Counter uses `sBlockKey = V`.
3. **Both billed stamina** — 10 from TK Dodge plus 12 from ERC on a single press.

A fourth problem was pure configuration, not ERC: JOJ ships TK Dodge with
`StepDodge = true`, so "dodging" was a step-dodge animation rather than a roll.
See the section above.

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

## Step 3 — ERC's fallback roll (only if TK Dodge is absent)

If you run ERC without TK Dodge, ERC polls `ERC Dodge Key Code` itself and sends
the events on the MCM **Animations** page with `Debug.SendAnimationEvent`. The
defaults are TK Dodge's `TKDodgeForward/Back/Left/Right`, because those are the
roll events that actually exist in this install's behaviour graph (`mt_behavior.hkx`).
Note two limits of this path:

- The event only animates. TK Dodge's plugin is what applies the stamina cost,
  the i-frame window and the in-place/standstill rule, so on the pure-fallback
  path the roll has no real i-frames (ERC's plugin tracks a window but installs
  no damage hook).
- `Actor.PlayAnimation` must never be used for actors; it raises "is an Actor, and
  PlayAnimation should not be used" and plays nothing. That is what made every
  earlier build look inert.

Do not invent event names: a name no behaviour graph defines is discarded silently,
which looks identical to "the mod does nothing".

## Step 4 — Tune the roll where it actually lives

With deferral on, the roll's stamina and i-frame window come from
`Data\SKSE\Plugins\TK Dodge RE.ini` — which ERC ships a copy of (see "Why the
dodge was a step"). The keys that matter:

```ini
EnableSprintKeyDodge = true   ; dodge = tap Sprint (Left Alt); needs Classic Sprinting Redone
StepDodge = false             ; false = roll clips; true = step clips (JOJ's default)
DodgeStamina = 10
iFrameDuration = 0.3          ; needs I-Frame Generator RE
EnableDodgeAttackCancel = true
EnableDodgeInPlace = true     ; allows a roll from a standstill
defaultDodgeEvent = TKDodgeForward
```

Edit those, then restart the game (TK Dodge reads them at launch). ERC's
`Roll Stamina Cost` and `ERC Dodge Key Code` sliders are labelled "(ERC roll
only)" and do nothing while deferring — they exist for the fallback.

ERC logs what it found at load, so you can confirm the hand-off:

```
[ERC] TK Dodge RE detected (hotkey 56, stamina 10, i-frames 0.3s) - ERC defers the roll to it
```

That line goes to `OutputDebugString`, i.e. it shows in DebugView and in MO2's
SKSE plugin log capture, not in `Papyrus.0.log`.

## Step 5 — Tune ERC via the MCM

Open **Elden Ring Combat** in the MCM:

- **Combat page:** Defer Dodge to TK Dodge RE, ERC's dodge key, sprint-hold time,
  roll stamina cost, directional rolls, and the hit-reaction toggle. (The key,
  stamina and sprint controls are fallback-only.)
- **Stagger page:** the knockdown health fraction.
- **Movement page:** equip-load cuts and per-tier roll lockout durations (fallback only).
- **Animations page:** the roll animation events (`TKDodge*` by default) and the
  hit reaction events (vanilla `Stagger_*` by default).

Hit-stop is **not** on this menu: it belongs to Precision, under **MCM → Precision
→ Hitstop**.

MCM Helper persists choices to `Data/MCM/Settings/EldenRingCombat.ini`, which
`ERC.dll` merges over `Data/SKSE/Plugins/EldenRingCombat.ini` on load and on game
load.

## Step 6 — Animation names for the stagger tiers

`OnHit`-driven reactions send `AnimFlinch` / `AnimStagger` / `AnimLargeStagger` /
`AnimKnockdown` via `Debug.SendAnimationEvent`. The old defaults
(`HitReaction_Flinch` etc.) were **unverified placeholders** — the same class of
mistake as `ERC_Roll_*`, and they existed in no behaviour graph. The defaults are
now the vanilla events (`Stagger_Small`, `StaggerForward`, `Stagger_Large`,
`Stagger_Large`), checked against the shipped animation data. Enable
**Enable ERC Hit Reactions** only if you want a second reaction on top of BFCO's;
it ships OFF.

---

## Step 7 — Hit-stop lives in Precision, and how to tell it apart from bullet-time

Three different "freezes" exist in this list and only one is hit-stop:

| What you see | What it is | Where |
|---|---|---|
| A 0.05–0.09 s crunch when a blow connects | **Precision hit-stop** | MCM → Precision → Hitstop |
| ~0.3 s of heavy slow-motion + blur after a *well-timed* dodge | **Timed Block-Dodge and Counter** timed-dodge slowmo | `TimedBlockDodgeCounter.ini` `[TimedDodge] fSlomoDuration / fSlomoSpeed`, `[Slowmo]` |
| A ~0.1 s freeze of the *attacker* after a timed block | Timed Block's `[Hitstop]` (attacker only) | same file, `[Hitstop]` |

Precision's per-hit hit-stop is the only one that fires on ordinary hits, and its
shipped durations (0.07 s vs NPCs, 0.035 s otherwise at 0.1× speed) are easy to
mistake for "nothing". ERC does not implement hit-stop — dipping `TimeScale` only
scales game time and never shows on screen.

### Conflict checklist

| Potential conflict | Resolution |
|---|---|
| TK Dodge vs ERC both rolling on the same key | Handled: ERC defers by default, and ERC's own dodge key is **X (45)**. V is also taken — Timed Block-Dodge and Counter uses it for timed block. |
| Dodge is a step, not a roll | `StepDodge = true` in TK Dodge's ini. ERC ships an override with it false; see "Why the dodge was a step". |
| Freeze only happens when dodging | That is Timed Block-Dodge and Counter's timed-dodge slowmo (`[TimedDodge]`), not hit-stop. Set `fSlomoDuration = 0` there to disable it. |
| Two hit-stop mods | ERC no longer implements hit-stop, so there is nothing to conflict with. JOJ's Precision owns it (MCM → Precision → Hitstop). |
| Stagger double-playing (BFCO hit-reactions + ERC) | ERC's reactions are OFF by default. If you enable them and it stacks, set the event names to `""` or turn **Enable ERC Hit Reactions** back off; BFCO's moveset reactions are animation-authored and usually look better. |
| `iFrameDuration` ignored | I-Frame Generator RE must be installed (it is, in JOJ) — TK Dodge RE does not provide i-frames itself. |

## Testing in JOJ

1. `skse64.log` (or DebugView) shows the `[ERC] TK Dodge RE detected …` line.
2. Papyrus log shows no `Unbound native function` from `ERC_PlayerCombat`.
3. MCM shows **Elden Ring Combat** with Combat / Stagger / Movement / Animations.
4. Tap Sprint (Left Alt) → one TK Dodge **roll** with i-frames and a 10-stamina
   cost. If it is still a step, the `SKSE\Plugins\TK Dodge RE.ini` override is not
   winning — check MO2 that ERC is at the top of the left pane.
   (With deferral OFF instead, tap **X** → ERC sends the `TKDodge*` event itself.)
5. Hit an enemy → a short crunch from **Precision** (MCM → Precision → Hitstop),
   *not* ERC. Dodging well still gives Timed Block's 0.3 s bullet-time, which is a
   different mod.
6. I-frame *damage* nullification still needs `[HOOK-2]`; in JOJ the roll's
   invincibility comes from I-Frame Generator, so it works regardless.
7. Papyrus log must show **no** `is an Actor, and PlayAnimation should not be used`
   from `ERC_PlayerCombat` — that error meant the roll and stagger clips were
   silently doing nothing.
