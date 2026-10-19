# SKSE API notes — porting the C++ plugin before you build

This document records what the validation pass found about the C++ half and
exactly what to change before building `ERC.dll` for real.

## What the current C++ targets

`plugin/` is written against a **stand-in API** (see
`plugin/validation/mock-sdk/`): a `SKSEPlugin` base class, a
`CreateSKSEPlugin()` factory, and an `IWMCM` menu interface.

That compiles cleanly (validated with MSVC), but **none of those three things
exist in the official SKSE plugin SDK**. They are not in `PluginAPI.h`. So the
current code is a scaffold that proves the *logic* compiles — it is not yet a
drop-in plugin.

## What the real SKSE 2.x plugin API looks like

From `skse64/PluginAPI.h` (SKSE 2.2.6 source):

```cpp
// 1. Declare version data (this is what SKSE reads first).
extern "C" {
__declspec(dllexport) SKSEPluginVersionData SKSEPlugin_Version =
{
    SKSEPluginVersionData::kVersion,
    1,                          // plugin version
    "Elden Ring Combat",        // name
    "",                         // author
    "",                         // support email
    0,                          // versionIndependenceEx
    0,                          // versionIndependence
    { RUNTIME_VERSION_1_6_1170, 0 },  // compatible runtimes, zero-terminated
    0,                          // minimum SKSE version
};

// 2. The load entry point (replaces CreateSKSEPlugin()).
__declspec(dllexport) bool SKSEPlugin_Load(const SKSEInterface* skse)
{
    return ERCPlugin::Get().Init(skse);
}
}
```

Interfaces come from `skse->QueryInterface(...)`:

| Need | Interface | Cast to |
|---|---|---|
| Register Papyrus natives | `kInterface_Papyrus` | `SKSEPapyrusInterface*` |
| Post-load / save-loaded callbacks | `kInterface_Messaging` | `SKSEMessagingInterface*` |
| Trampoline memory for hooks | `kInterface_Trampoline` | `SKSETrampolineInterface*` |

### Mapping the current code

| Current (stand-in) | Real API |
|---|---|
| `class ERCPlugin : public SKSEPlugin` | plain class, no base |
| `virtual bool Init(SKSEInterface*)` | called from `SKSEPlugin_Load` |
| `virtual void Update(float)` | **no such callback** — hook a per-frame function (see below) |
| `virtual void OnGameLoaded()` | `SKSEMessagingInterface::RegisterListener(SKSE, "SKSE", cb)` then act on `kMessage_PostLoadGame` |
| `CreateSKSEPlugin()` | `SKSEPlugin_Version` + `SKSEPlugin_Load` exports |
| `vm->AddFunction(...)` | `SKSEPapyrusInterface::Register(RegisterFuncs)` + `registry->RegisterFunction(new NativeFunctionN<StaticFunctionTag, Ret, Args...>(...))` |
| `IWMCM` / `ERCMCM` | **not in the SDK** — use MCM Helper (JSON config) instead |

### Papyrus native registration (real form)

```cpp
#include "skse64/PapyrusNativeFunctions.h"

float GetFloat(StaticFunctionTag*, BSFixedString akKey);

bool RegisterFuncs(VMClassRegistry* registry)
{
    registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, float, BSFixedString>(
        "ERC_GetFloat", "ERC_PlayerCombat", GetFloat, registry));
    return true;
}
```

### Calling *into* Papyrus from C++

There is no simple "raise this event" call in the official plugin API — it needs
BSScript/`TESObjectREFR` VM access (which is why most plugins use
**CommonLibSSE-NG**). The current design pushes events (`ERC_DodgeTap`, …) from
C++ into Papyrus; for the official API the simpler alternative is **polling**:

- C++ exposes `int ERC_ConsumeDodgeTap()` (returns `-1` when nothing pending).
- Papyrus runs `RegisterForSingleUpdate(0.05)` and calls it each tick.

That removes the VM-push dependency entirely.

### Per-frame input

`Update()` does not exist. Options, in increasing order of effort:
1. Hook the game's input/update function via `SKSETrampolineInterface` +
   addresses for **your exact runtime** (fragile; needs Address Library).
2. Use CommonLibSSE-NG's `SKSE::InputEvent` / `InputEventHandler` (recommended).

Either way this is the part that must be finished against your game version.

## MCM

`IWMCM` is not part of the official SDK. The standard, version-independent way to
ship the sliders is **MCM Helper** (SkyUI MCM driven by a JSON config plus an
INI). That is what this mod should use instead of `ERCMCM.cpp`; the DLL then
reads the resulting `MCM/Settings/EldenRingCombat.ini`.

## Version caveat (important)

The SKSE build present in this workspace is **2.2.6**, built for:

- Steam `1.6.1170`
- GOG `1.6.1179`

The installed Skyrim SE reports **`1.7.104.0`**. SKSE must match the game
runtime exactly, so a 2.2.6 build for 1.6.x will not load into a 1.7.104 game.
Install the SKSE build that matches *your* runtime before testing.

## What is validated vs not

| Item | Status |
|---|---|
| Papyrus structure (no duplicate names, balanced blocks, real Skyrim APIs) | ✅ validated (`tools/validate-psc.ps1`) |
| Papyrus compiles in Creation Kit | ❌ not run — no CK in this environment |
| C++ syntax/types | ✅ compiles with MSVC against the stand-in SDK |
| C++ against the real SKSE SDK | ❌ not possible — the SDK's `common` submodule is not in the distributed source tarball |
| C++ links to a working `.dll` | ❌ requires the port above + your runtime's addresses |
