# Integrating ELDEN RING COMBAT into JOJ

JOJ (Journals of Jyggalag) already overhauls combat with **BFCO** (Better Fighting
and Combat Overhaul), For Honor / Wo Long movesets, **True Directional Movement**,
and stamina-based dodge rolling. This mod's job is to take over the *player's*
combat feel from BFCO — adding ER-style tap-to-roll i-frames, hit-stop, and
4-tier stagger reactions — while leaving BFCO's damage numbers and enemy AI alone.

> **Honesty note.** I built this against the public JOJ overview page, not your
> installed list. The exact record/form IDs that BFCO uses for *player* dodge and
> hit-reactions are internal to BFCO and I cannot see them from here. Wherever this
> doc says "verify in CK," it means: open the relevant BFCO plugin in Creation Kit,
> find the specific record, and confirm before you disable it. Do not bulk-disable
> BFCO records on faith — that will break enemy combat.

---

## What ERC replaces (and what it doesn't)

| System | Owner after integration | Notes |
|---|---|---|
| Weapon damage / scaling | **BFCO** (unchanged) | ERC never touches damage numbers, per your requirement. |
| Enemy AI attacks & reactions | **BFCO** (unchanged) | Leave all enemy records as-is. |
| Player dodge roll + i-frames | **ERC** | Tap-to-roll with invincibility window. Disable BFCO's player roll. |
| Player hit-stop on impact | **ERC** | Global timescale dip when a blow lands. |
| Player stagger / guard-break tiers | **ERC** | 4-tier flinch→knockdown, driven by incoming damage vs thresholds. |
| Lock-on strafing | **TDM** (unchanged) | TDM owns lock-on; ERC only picks facing-preserving roll variants. |
| Movement / sprint | **BFCO/TDM** (unchanged) | Holding dodge = sprint stays as BFCO defines it. |

The cleanest mental model: **ERC is a thin "player feel" layer on top of JOJ's
existing combat.** It does not replace the movesets or damage — it reshapes timing,
dodge invincibility, impact freeze, and hit reactions for the player character only.

---

## Step 1 — Load order

- **`EldenRingCombat.esp`** loads **after BFCO's plugin(s)** so that, where a record
  is shared, ERC's version wins for the player. (In practice ERC adds almost no
  conflicting records — it's mostly scripts + one SKSE plugin — so load-order
  sensitivity is low. Place it in the "gameplay/combat" group after BFCO.)
- **`ERC.dll`** lives in `Data/SKSE/Plugins/` and is loaded by SKSE independently of
  the `.esp` load order. It must be present for the full experience (see BUILD.md).

In Wabbajack/MO2, add the mod as a normal profile entry; the DLL ships inside the
mod's `Data/SKSE/Plugins/` folder and is picked up automatically.

## Step 2 — Disable BFCO's *player* dodge & hit-reactions (verify in CK)

This is the part that actually "replaces" BFCO for the player. In Creation Kit,
open the BFCO plugin(s) and:

1. **Player dodge roll.** Find the record/form that defines the *player's* dodge/roll
   action (BFCO typically rebinds the dodge key to a custom roll animation + script).
   Disable it for the player only. *(Do NOT disable enemy dodge records.)*
2. **Player hit-reactions / stagger.** Find BFCO's player flinch/stagger/knockdown
   animations or the script that triggers them, and disable for the player. ERC now
   owns these via its `OnHit` path.
3. **Leave everything else** (damage, enemy AI, movement, sprint) enabled.

> If BFCO's player combat is driven by a single master script/form rather than many
> records, disabling that one form may be enough — check what it references first.
> The goal is: the player no longer uses BFCO's roll/stagger; ERC does. Enemies keep
> using BFCO untouched.

## Step 3 — Point ERC at JOJ's moveset animations (MCM / ini)

ERC plays animation *events* by name. Its defaults (`HitReaction_Flinch`,
`ERC_Roll_Light_Front`, …) are placeholders. Set them to the **actual event names**
that JOJ's For Honor / Wo Long movesets provide:

- In CK, open the moveset plugin and read each roll / hit-reaction animation's
  **event name** (the string the engine matches on).
- Enter those strings on the MCM **Animations** page, or in
  `Data/SKSE/Plugins/EldenRingCombat.ini` under the keys
  `AnimFlinch`, `AnimStagger`, `AnimLargeStagger`, `AnimKnockdown`,
  `RollLightFront`, `RollMediumFront`, `RollHeavyFront`. (Directional variants are
  derived by appending `_Back/_Left/_Right`.)

If a name is wrong, ERC degrades gracefully — that specific animation simply doesn't
play (no crash). So you can iterate: set a name, test in-game, adjust.

## Step 4 — Match the dodge key to JOJ's binding

Dodge input is detected **in Papyrus** by polling a DirectInput scan code every
0.03s (`Input.IsKeyPressed`), then splitting tap (roll) from hold (sprint). Set
`DodgeKeyCode` in the MCM to whatever JOJ binds dodge to.

- Default is **56 = Left Alt** (tap = roll, hold = Skyrim's native sprint).
- Other common codes: `57` = Space, `42` = Left Shift, `29` = Left Ctrl.

Gamepad is **not** covered by Papyrus (it has no gamepad query). Controller users
need the C++ input hook (`[HOOK-1]` in BUILD.md), which also supplies a lock-on
direction. Until then, rolls on a controller won't trigger.

## Step 5 — Tune via the MCM

Once running under `skse_loader.exe`, open the **Elden Ring Combat** MCM and tune:

- **Combat page:** dodge key code, sprint-hold time, roll stamina cost, i-frame
  fraction, hit-stop duration + timescale, and the feature toggles.
- **Stagger page:** the three reaction thresholds (flinch / stagger / large).
- **Movement page:** equip-load weight cuts and per-tier roll durations
  (heavier = longer/slower).
- **Animations page:** the animation event names to match JOJ's moveset.

Defaults are ER-derived starting points; adjust to taste. MCM Helper persists
choices to `Data/MCM/Settings/EldenRingCombat.ini`, which `ERC.dll` merges over
`Data/SKSE/Plugins/EldenRingCombat.ini` on load and on game load.

---

## Conflict checklist (things that can fight each other)

| Potential conflict | Resolution |
|---|---|
| BFCO player roll vs ERC roll both firing | Disable BFCO's *player* dodge record (Step 2). Enemies unaffected. |
| BFCO player stagger vs ERC stagger double-playing | Disable BFCO's *player* hit-reaction trigger (Step 2). ERC owns it now. |
| TDM lock-on vs ERC directional rolls | No conflict, but note: Papyrus cannot read TDM's target bearing, so with the current keyboard polling every roll uses the front variant. Directional rolls need the `[HOOK-1]` input hook. |
| Two mods setting `fTimeScale` (hit-stop) | If another mod also dips timescale, hit-stops can stack/override. ERC saves & restores the prior value, so it's well-behaved — but avoid running two hit-stop mods at once. |
| Stamina cost double-deduction | BFCO may already deduct stamina for its roll. Since you disable BFCO's player roll (Step 2), only ERC deducts. If you keep both, lower one of the costs to avoid a double drain. |

## Testing in JOJ

1. Confirm `ERC.dll` loads (SKSE log / MCM present).
2. In combat, tap dodge → expect an ER-style roll with i-frames (attacks whiff during it).
3. Land a hit on an enemy → expect a brief world freeze (hit-stop).
4. Take hits of varying size → expect flinch / stagger / large-stagger / knockdown in order.
5. Verify enemies still behave exactly as BFCO intended (you only changed the player).
