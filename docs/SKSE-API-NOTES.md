# SKSE API notes — what changed in the port

The C++ plugin originally targeted a **stand-in API** (a `SKSEPlugin` base class,
a `CreateSKSEPlugin()` factory, and an `IWMCM` menu). None of those exist in the
official SKSE plugin SDK. This document records the port to the real API.

## Ported to the official API

| Before (stand-in) | Now (real SKSE 2.x) |
|---|---|
| `class ERCPlugin : public SKSEPlugin` | plain class, no base |
| `CreateSKSEPlugin()` factory | `SKSEPlugin_Version` + `SKSEPlugin_Load` exports (`ERCMain.cpp`) |
| `SKSEInterface::papyrusVM` member | `skse->QueryInterface(kInterface_Papyrus)` → `SKSEPapyrusInterface` |
| `vm->AddFunction(...)` | `papyrus->Register(ERCRegisterNatives)` + `registry->RegisterFunction(new NativeFunctionN<...>)` |
| `virtual void Update(float)` callback | **none** — must be called from a hook (see below) |
| `virtual void OnGameLoaded()` | `kInterface_Messaging` → `RegisterListener(..., "SKSE", cb)` → `kMessage_PostLoadGame` |
| `IWMCM` menu subclass (`ERCMCM.cpp`) | **MCM Helper** JSON (`data/MCM/Config/EldenRingCombat/`) |
| C++ pushes `ERC_*` events into Papyrus | removed — the VM-push path needs BSScript internals |
| `GetGameTime()` free function | wall clock (`GetTickCount64`) inside the plugin |

## Why no C++ → Papyrus events

The official plugin API has no "raise this Papyrus event" call. Doing it requires
`BSScript`/`TESObjectREFR` VM access, which is exactly why most plugins use
CommonLibSSE-NG. The port removed the event bridge instead:

- **Dodge input:** Papyrus polls the key itself (`Input.IsKeyPressed`) every
  0.03s and splits tap (roll) from hold (sprint). No C++ input hook needed for
  keyboard play.
- **I-frames:** the plugin owns the timing; Papyrus calls `ERC_RollStarted()`
  when a roll begins. (In JOJ the roll — and its i-frames via I-Frame Generator —
  belong to TK Dodge RE, so this path is the fallback.)
- **Hit-stop:** removed. It was pure Papyrus against the `TimeScale` global, and
  that turns out not to be an animation slowdown at all. See below.
- `ERC_ConsumeDodgeTap()` is still registered for a future input hook that can
  also supply a lock-on direction.

### Hit-stop — why ERC does not implement it

The original reasoning was wrong, and the in-game result proved it.

Skyrim's timescale **is** a writable global: parsing `Skyrim.esm` finds `GLOB`
FormID `0x0000003A`, EDID `TimeScale`, value `20.0`; there is no
`fTimeScale:Gameplay` game setting, so `Utility.SetINIFloat` really does nothing.
A Papyrus dip works mechanically:

```papyrus
GlobalVariable ts = Game.GetFormFromFile(0x0000003A, "Skyrim.esm") as GlobalVariable
ts.SetValue(ts.GetValue() * scale)   ; applied, then restored
```

What it does **not** do is slow animation playback. `TimeScale` scales game time —
the calendar, AI scheduling, and game-time timers — so a dip applied and restored
in 60 ms produced no visible freeze. Confirmed against the code of a plugin that
does hit-stop correctly: Precision multiplies each actor's animation `deltaTime`
inside its animation-update hook (`GetHitstopMultiplier` in `Hooks.cpp`) and never
touches the global. That is the mechanism a real implementation needs, and it
requires the version-specific hook ERC's plugin deliberately avoids.

JOJ ships Precision with hitstop enabled (0.07 s vs NPCs, 0.035 s otherwise, 0.1×
slowdown, camera shake), so ERC's MCM points there instead of duplicating it. The
old `ApplyHitStop` / `EndHitStop` / `TimeScale` code and `tools/verify-hitstop.py`
were deleted rather than left as a placebo; the script also no longer risks
stranding a low timescale in a save taken mid-dip.

The timing findings from that work are still worth keeping: every Papyrus timer
(`RegisterForSingleUpdate`, `Wait`) counts *scaled* game time, so if you ever time
anything against a slow-time effect, use `Utility.GetCurrentRealTime()`.

## Papyrus native registration (as implemented)

```cpp
// ERCNatives.cpp
registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, float, BSFixedString>(
    "ERC_GetFloat", "ERC_PlayerCombat", GetFloatNative, registry));
```

Registered names: `ERC_GetFloat`, `ERC_GetInt`, `ERC_GetBool`, `ERC_GetString`,
`ERC_SetFloat`, `ERC_ConsumeDodgeTap`, `ERC_HasTKDodge`, `ERC_RollStarted`.

`ERC_HasTKDodge` is how the script decides whether to own the roll: the plugin
checks for `Data\SKSE\Plugins\TK Dodge RE.ini` at load. Since TK Dodge RE's
`DodgeHotkey` defaults to the same scan code ERC polled, and ERC's roll animation
events exist in no behaviour graph, deferring is both the correct behaviour and
the fix for the double stamina deduction.

`NativeFunctionN<StaticFunctionTag, ...>` sets the native's isStatic flag from
`IsStaticType<StaticFunctionTag>::value`, which is 1 (`skse-sdk/.../PapyrusArgs.h`).
A native registered that way only binds to a **`global`** Papyrus function; a
plain `native` function is a *member* function and the VM refuses the pairing:

```
Native static function ERC_GetFloat could find no matching static function on
linked type ERC_PlayerCombat. Function will not be bound.
```

That is not a warning — every call then throws `Unbound native function`, and
because `OnInit()` calls `RefreshSettings()` first, the quest alias aborts before
it ever reaches `RegisterForSingleUpdate()`, so the whole mod goes quiet. The
declarations in `ERC_PlayerCombat.psc` are therefore `global native`, and calls
are written `ERC_PlayerCombat.ERC_GetFloat("...")` (`tools/qualify-natives.py`
enforces the qualification, and `build.ps1` runs it).

The two `ERC_GetTimeScale` / `ERC_SetTimeScale` stubs were registered but never
declared by any script, which produced the same error for them; they were
removed rather than declared, since they only ever returned 1.0.

## Still version-specific

| Item | Where | Why |
|---|---|---|
| Per-frame tick | `ERCPlugin::Update()` | SKSE calls nothing automatically |
| I-frame damage nullification | `[HOOK-2]` | needs the player damage path address |
| Native hit-stop | animation-update hook | must scale actor animation `deltaTime` (what Precision does); `TimeScale` does not work |
| Gamepad dodge input | `[HOOK-1]` | Papyrus `Input` is keyboard only |

## Script attachment (why the script extends `ReferenceAlias`)

There is no way to attach a script to the player from code:

- The SKSE plugin SDK has **no** `AttachScript` symbol (searched the whole SDK).
- Skyrim's Papyrus has no runtime attach call.

So `ERC_PlayerCombat` is a **quest ReferenceAlias** script, attached to an alias
forced to the Player reference in a start-game-enabled quest. `Alias` provides
`RegisterForSingleUpdate`, so the polling loop works unchanged; all actor calls go
through `GetActorReference()`. See `docs/BUILD.md`, Part A.

## Validation status

| Item | Result |
|---|---|
| All three C++ TUs vs the **genuine SDK** | ✅ compile |
| `ERC.dll` link against the SDK static libs | ✅ links, exports `SKSEPlugin_Load` + `SKSEPlugin_Version` |
| All three C++ TUs vs mock SDK | ✅ compiles (`build-check.bat`) |
| Papyrus compiled with the real compiler | ✅ **0 errors, 0 warnings** |
| Papyrus structure | ✅ `tools/validate-psc.ps1` |
| `.esp` (quest + player alias) | ⚠️ Creation Kit step — see `docs/BUILD.md`, Part A |

## Two API corrections found by compiling

| Wrong | Right | Why |
|---|---|---|
| `weapon.GetWeight()` | `GetActorValue("InventoryWeight") / GetActorValue("CarryWeight")` | Skyrim's `Form` has **no** `GetWeight()` — it exists nowhere in 13,898 base scripts |
| `w.GetDamage()` | `OnHit`'s `abPowerAttack` / `abSneakAttack` / `abBashAttack` / `abHitBlocked` | `Weapon` has **no** `GetDamage()` |

Both were caught by compiling against the real script sources, not by inspection.
A third, C++-side: native return types must be `SInt32`, because the SDK
specialises `PackValue<UInt32>/<SInt32>` but not `PackValue<int>`.

## Runtime version

The JOJ stock game is **1.6.1170**, which matches the bundled **SKSE 2.2.6**
(Steam 1.6.1170). The SDK's `RUNTIME_VERSION_1_6_1170` is `0x01064920` (not
`0x01061170` — the version digits are decimal), and `ERC.dll` records that value
in `SKSEPlugin_Version`, so SKSE will accept it.
