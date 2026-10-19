# Building ELDEN RING COMBAT

This mod has two independently-buildable halves. You can ship **both** (the full
experience) or just the Papyrus half (a working, if reduced, mod).

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/        ← Papyrus (.psc) — compiled in Creation Kit → .esp
│  │   ├─ ERC_PlayerCombat.psc
│  │   └─ ERC_Papyrus.h      (optional native decls for CK)
│  └─ SKSEPlugins/           ← drop the built ERC.dll here at runtime
├─ plugin/                   ← C++ source of the SKSE plugin (ERC.dll)
│  ├─ include/  (ERCPlugin.h, ERCMCM.h)
│  └─ src/      (ERCPlugin.cpp, ERCMCM.cpp)
└─ docs/                     ← this file + JOJ-INTEGRATION.md
```

---

## Part A — The Papyrus half (Creation Kit) → `EldenRingCombat.esp`

This is the part that always works. It compiles with no C++ toolchain at all.

1. **Open Creation Kit** for Skyrim AE and create a new plugin:
   *File → New Plugin*, name it `EldenRingCombat`, master = `Skyrim.esm`.
2. **Add the script source.** Copy `data/scripts/source/ERC_PlayerCombat.psc`
   into your CK project's `Script/` folder (the same folder that holds the
   vanilla `.psc` files). If you have more than one ERC script, also copy
   `ERC_Papyrus.h` there so CK can type-check the `native` calls.
3. **Compile.** In the *Script* tab, select `ERC_PlayerCombat` and click
   **Compile**. Fix any reported errors (the script is written to be clean;
   the only expected warnings are about the `native` functions if you did not
   add `ERC_Papyrus.h`).
4. **Do NOT attach the script in CK.** The SKSE plugin attaches `ERC_PlayerCombat`
   to the Player itself at game load (see Part B, step 5). Attaching it in CK *and*
   having the DLL attach it would run the script twice. Leave the player's script
   list empty for this mod.
5. **Save** the plugin (`.esp`) into your mod's `data/` folder.

> **Papyrus-only mode.** If you ship only the `.esp` (no `ERC.dll`), the DLL-fired
> events never arrive, so the script falls back to Skyrim's native `OnHit` event
> for **stagger / hit-reaction animations** (the 4-tier flinch→knockdown system).
> What it CANNOT do without the DLL: tap-to-dodge rolls, true i-frames, and hit-stop
> (hit-stop needs a global timescale dip — `Utility.Wait` only freezes the player,
> not the world). So Papyrus-only is a partial fallback / smoke-test, not the full
> experience. The script detects this automatically: with no DLL it never calls a
> native (which would throw) and runs the `OnHit` path instead.

---

## Part B — The SKSE plugin (C++) → `ERC.dll`

> **Read `docs/SKSE-API-NOTES.md` first.** A validation pass confirmed the C++
> here is written against a *stand-in* API (a `SKSEPlugin` base class,
> `CreateSKSEPlugin()`, `IWMCM`). It compiles cleanly with MSVC, but the official
> SKSE plugin API uses `SKSEPlugin_Version` + `SKSEPlugin_Load` and has no
> `Update()` or `IWMCM`. That document gives the exact mapping and the porting
> steps. Do that port before you expect a working `.dll`.

Requires: **SKSE SDK** for your Skyrim AE version, and a C++ compiler
(MSVC via Visual Studio, or clang-cl). Get the matching SDK from the SKSE
project's GitHub releases; the headers in `plugin/include/` assume the standard
SDK layout.

### 1. Build the DLL

Create a small CMake project (or an empty MSVC DLL project) that compiles:

```cmake
cmake_minimum_required(VERSION 3.20)
project(EldenRingCombatPlugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)

# Point these at your SKSE SDK location.
set(SKSE_SDK "C:/path/to/skse-sdk")

add_library(ERC SHARED
    src/ERCPlugin.cpp
    src/ERCMCM.cpp
    src/ERCNatives.cpp)

target_include_directories(ERC PRIVATE
    include
    ${SKSE_SDK}/skse
    ${SKSE_SDK}/skse/common
    ${SKSE_SDK}/skse/plugins
    ${SKSE_SDK}/skse/external)

# Link the SKSE common + plugin libraries your SDK provides.
target_link_libraries(ERC PRIVATE
    ${SKSE_SDK}/lib/skse_common.lib
    ${SKSE_SDK}/lib/skse_plugin_api.lib   # names vary by SDK version
    ${SKSE_SDK}/lib/bsutility.lib)

# Output the dll straight into the mod's runtime folder.
set_target_properties(ERC PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/../data/SKSEPlugins")
```

Configure + build in **Release** (x64). The result is `ERC.dll` — copy it to
`data/SKSEPlugins/`. SKSE loads any `.dll` in that folder automatically.

> If your SDK's library names differ, adjust the three `target_link_libraries`
> entries. The source itself does not depend on those names.

### 2. Wire HOOK-1 — per-frame dodge-button read

In `ERCPlugin.cpp`, the function `ReadDodgeButton()` is a stub that returns
`false`. Replace its body with a read of your SDK's input manager so it reports
whether the **dodge/roll** button is currently down. Two approaches:

- **(a) Raw button state.** Read the gamepad `B` / keyboard `Space` (or whatever
  key JOJ binds dodge to — check BFCO/TDM's binding) from your SDK's input
  manager each frame.
- **(b) Hook the dodge action** (more robust): hook the function the engine calls
  when the dodge *action* fires and set a flag `ReadDodgeButton()` returns.

This is the only place you need to know your exact SKSE version's input API.
Everything downstream (tap vs hold, roll triggering) is already written.

### 3. Wire HOOK-2 — i-frame damage nullification (optional but core to the feel)

In `OnGameLoaded()`, install a hook on the player's damage path (e.g.
`BGSLivingProcess::ApplyDamage` / `BGSActor::TakeHit`). When it fires, call:

```cpp
CancelIframeHit(&g_ercPlugin, /*abIsPhysical=*/ true);   // for physical hits
```

The decision logic in `CancelIframeHit()` is already complete — if we're inside
the i-frame window and the hit is physical, your hook should make it apply **no
damage** (zero the damage value / return early). The exact mechanism depends on
which function you hook. If you skip this hook, rolls still play but do not
grant true invincibility — they fall back to whatever protection your dodge
animation already has.

### 4. Verify the Papyrus bridge + native registration

`ERCNatives.cpp::RegisterNatives()` wires every `ERC_*` native into the VM, and
the three `CallPapyrus*` helpers in `ERCPlugin.cpp` invoke functions on the
player's script via `GetFunctionByName` + `CallFunction`. Both use stable SKSE
APIs. If your SDK version names any of these calls differently (`AddFunction`,
`GetPlayerScript`, `GetFunctionByName`, `CallFunction`, `StackFrame::Push`),
adjust only those lines — the logic is complete and version-independent.

The events the bridge must deliver:

| Function | Args | When |
|---|---|---|
| `ERC_OnPluginAttached()` | — | once, one frame after the script is attached (sets `m_pluginLoaded`, syncs settings) |
| `ERC_DodgeTap(int)` | direction 0–3 | a dodge tap is detected (HOOK-1) |
| `ERC_SettingsChanged()` | — | an MCM slider/toggle changed |
| `ERC_RollStarted(float)` | duration seconds | a roll begins |
| `ERC_RollEnded()` | — | a roll ends |

> **Attaching the script.** `OnGameLoaded()` calls `vm->AttachScript(player, "ERC_PlayerCombat")`
> (marked `[VERSION-SPECIFIC]`) and sets `_attachPending`; `Update()` then fires
> `ERC_OnPluginAttached()` one frame later so the freshly-attached script is resolvable.
> If your SDK names `AttachScript` differently, adjust that one line — do **not** also
> attach it in CK (double-run).

If a VM call fails, the plugin logs it and continues — native behaviour
(i-frames, hit-stop) is independent of Papyrus, so a bridge mismatch never
crashes the game.

---

## Validating without the full toolchain

Two checks run without Creation Kit or the SKSE SDK:

| Command | What it proves |
|---|---|
| `powershell -File tools\validate-psc.ps1 -Path data\scripts\source\ERC_PlayerCombat.psc` | Papyrus structure: no duplicate event/function names, balanced `Event`/`EndEvent` and `Function`/`EndFunction` blocks, and no known non-Skyrim API or C-style syntax. |
| `plugin\validation\build-check.bat` | The C++ **compiles** (`cl /c`) against mock SKSE headers in `plugin\validation\mock-sdk\` — catching typos, type errors and missing symbols. Produces `.obj` only; no DLL, no link. |

Neither replaces a real build: the Papyrus still needs compiling in CK, and the DLL
still needs linking against the real SKSE SDK. They just catch errors early.

## Verifying the build

1. Drop `ERC.dll` into `<game>/SKSEPlugins/` (or your MO2 profile's override).
2. Launch via **skse_loader.exe**.
3. In-game, press the MCM key (default `~`) → **Elden Ring Combat** should appear.
4. Open the *Combat* page — move a slider; confirm it persists to
   `SKSEPlugins/EldenRingCombat.ini`.
5. Tap dodge in combat: you should see a roll with an i-frame window and a
   brief hit-stop when your attacks land.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| MCM doesn't appear | `ERC.dll` not in `SKSEPlugins/`, or launched via plain `Skyrim.exe` instead of `skse_loader.exe`. |
| Sliders work but nothing changes in-game | Papyrus bridge (step 4) not wired — events aren't reaching the script. |
| Rolls don't trigger | HOOK-1 (`ReadDodgeButton`) still returns `false`, or the dodge key you read isn't the one JOJ binds. |
| i-frames don't protect | HOOK-2 not installed (rolls play but damage gets through). |
| CK compile errors on `native` lines | Add `ERC_Papyrus.h` to your CK `Script/` folder, or remove the `native` keyword if you're Papyrus-only. |
