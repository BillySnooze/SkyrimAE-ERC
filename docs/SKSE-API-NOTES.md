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
- **I-frames / hit-stop:** the plugin owns the timing; Papyrus calls
  `ERC_RollStarted()` when a roll begins.
- `ERC_ConsumeDodgeTap()` is still registered for a future input hook that can
  also supply a lock-on direction.

## Papyrus native registration (as implemented)

```cpp
// ERCNatives.cpp
registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, float, BSFixedString>(
    "ERC_GetFloat", "ERC_PlayerCombat", GetFloatNative, registry));
```

Registered names: `ERC_GetFloat`, `ERC_GetInt`, `ERC_GetBool`, `ERC_GetString`,
`ERC_SetFloat`, `ERC_ConsumeDodgeTap`, `ERC_RollStarted`, `ERC_TriggerHitStop`,
`ERC_GetTimeScale`, `ERC_SetTimeScale`.

## Still version-specific

| Item | Where | Why |
|---|---|---|
| Per-frame tick | `ERCPlugin::Update()` | SKSE calls nothing automatically |
| I-frame damage nullification | `[HOOK-2]` | needs the player damage path address |
| Hit-stop timescale apply | `ApplyTimeScale()` stub | needs the game timescale accessor |
| Gamepad dodge input | `[HOOK-1]` | Papyrus `Input` is keyboard only |

## Validation status

| Item | Result |
|---|---|
| `ERCMain.cpp` vs **genuine** SKSE 2.2.6 `PluginAPI.h` | ✅ compiles |
| All three C++ TUs vs mock SDK | ✅ compiles (`build-check.bat`) |
| `ERCNatives.cpp` vs genuine SDK | ⚠️ cannot compile here — SKSE's `common/` submodule is absent from the distributed source tarball |
| Papyrus structure | ✅ `tools/validate-psc.ps1` |
| Papyrus compiled in CK | ❌ no Creation Kit installed |

## Runtime version

The JOJ stock game is **1.6.1170**, which matches the bundled **SKSE 2.2.6**
(Steam 1.6.1170). `ERC.dll` records `RUNTIME_VERSION_1_6_1170` in
`SKSEPlugin_Version`, so SKSE will accept it.
