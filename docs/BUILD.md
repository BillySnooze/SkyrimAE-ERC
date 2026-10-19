# Building ELDEN RING COMBAT

Target runtime: **Skyrim SE/AE 1.6.1170** (the JOJ stock game at
`F:\Modlists\JOJ\Stock Game`), with **SKSE 2.2.6**.

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/ERC_PlayerCombat.psc   ← compiled in CK → .pex
│  ├─ MCM/Config/EldenRingCombat/           ← MCM Helper menu (config.json + settings.ini)
│  └─ SKSE/Plugins/                         ← drop the built ERC.dll here
├─ plugin/
│  ├─ include/  (ERCPlugin.h, erc_compat.h)
│  ├─ src/      (ERCMain.cpp, ERCPlugin.cpp, ERCNatives.cpp)
│  └─ validation/                           ← offline compile check (mock SDK)
├─ tools/validate-psc.ps1                   ← Papyrus structural check
└─ docs/
```

There are **two** build steps: the Papyrus script (Creation Kit) and the plugin
(MSVC).

---

## Part A — Papyrus → `EldenRingCombat.esp`

Requires **Creation Kit for Skyrim SE** (a separate Bethesda.net download; it is
not installed in this environment).

1. Create a new plugin: *File → New Plugin*, name `EldenRingCombat`,
   master `Skyrim.esm`.
2. Copy `data/scripts/source/ERC_PlayerCombat.psc` into CK's `Script/` folder
   (alongside the vanilla `.psc` files).
3. In the *Script* tab, select `ERC_PlayerCombat` and **Compile**.
4. Save the `.esp`.

> **Do not attach the script to the player in CK.** The SKSE plugin attaches
> `ERC_PlayerCombat` to the Player at load time (`AttachScript` in
> `ERCPlugin::Init`). Attaching it in CK as well would run it twice.

Note: there is no `ERC_Papyrus.h`. Papyrus has no `#include` of C headers, so a
hand-written header cannot type-check `native` declarations — the `native`
keyword in the `.psc` is all CK needs.

The script **requires `ERC.dll`**: every `ERC_*` call is a native implemented by
the plugin, and Papyrus throws if the DLL is absent. This is deliberate — there
is no silent half-working mode.

---

## Part B — `ERC.dll` (SKSE plugin)

Requires the **SKSE plugin SDK** for 2.2.6 (its `skse64/` headers, including the
`common/` submodule — note the source tarball inside the SKSE release does **not**
contain `common/`, so use the full SDK package).

### Build

From the repository root, in a *x64 Native Tools* prompt:

```bat
cl /nologo /std:c++17 /EHsc /O2 /LD ^
   /I plugin\include /I "%SKSE_SDK_ROOT%" ^
   plugin\src\ERCMain.cpp plugin\src\ERCPlugin.cpp plugin\src\ERCNatives.cpp ^
   /Fe:data\SKSE\Plugins\ERC.dll
```

`%SKSE_SDK_ROOT%` is the directory that *contains* `skse64/` (and
`skse64_common/`). No import library is needed: the plugin only calls through the
`SKSEInterface` function pointers, never SKSE's exported symbols directly.

Alternatively, a CMake `add_library(ERC SHARED ...)` with the same sources and
include dirs works.

### What is implemented

| Piece | State |
|---|---|
| `SKSEPlugin_Version` / `SKSEPlugin_Load` entry points | ✅ verified to compile against the genuine SKSE 2.2.6 `PluginAPI.h` |
| Papyrus native registration (`ERC_*`, class `ERC_PlayerCombat`) | ✅ implemented |
| Settings store + ini merge (plugin ini + MCM Helper ini) | ✅ implemented |
| I-frame window maths (`OnRollStarted`, `InIframeWindow`) | ✅ implemented |
| Hit-stop timing | ✅ timing implemented; applying the timescale dip is `[HOOK-2]` |
| Per-frame `Update()` | ⚠️ needs a hook to be called (see below) |
| Input hook / damage nullification | ⚠️ `[HOOK-1]` / `[HOOK-2]` — version-specific |

### Remaining version-specific work

Two things cannot be written without your game's addresses:

**`[HOOK-2]` — i-frame damage nullification + hit-stop timescale.**
`ApplyTimeScale()` in `ERCPlugin.cpp` is a marked stub. Install a hook on the
player damage path and zero physical damage while `InIframeWindow()` is true;
apply the timescale dip for hit-stop. With CommonLibSSE-NG this is a few lines;
without it you need signature scans for your exact runtime.

**`[HOOK-1]` — per-frame tick + optional gamepad input.**
`ERCPlugin::Update()` is not called by SKSE automatically. Call it from a hook
(same place as above). Dodge *input* does **not** need this hook: the script polls
a keyboard key itself, so keyboard rolls work as soon as the DLL loads.

---

## Part C — MCM

The menu is **MCM Helper** (SkyUI's MCM, driven by JSON) — no C++ menu code.

- `data/MCM/Config/EldenRingCombat/config.json` — the menu.
- `data/MCM/Config/EldenRingCombat/settings.ini` — defaults.
- At runtime MCM Helper writes `Data/MCM/Settings/EldenRingCombat.ini`.

`ERC.dll` reads that file on load and on `PostLoadGame`, stripping MCM Helper's
`f`/`i`/`b`/`s` type prefix, and merges it over
`Data/SKSE/Plugins/EldenRingCombat.ini`. So MCM choices take effect without any
extra Papyrus glue.

---

## Validating without the full toolchain

| Command | What it proves |
|---|---|
| `powershell -File tools\validate-psc.ps1 -Path data\scripts\source\ERC_PlayerCombat.psc` | Papyrus structure: no duplicate names, balanced blocks, no known non-Skyrim API or C-style syntax. |
| `plugin\validation\build-check.bat` | The C++ **compiles** (`cl /c`) against mock SKSE headers in `plugin\validation\mock-sdk\`. `.obj` only — no DLL, no link. |

Neither replaces a real build. Additionally, `ERCMain.cpp` was checked against
the **genuine** SKSE 2.2.6 headers; the Papyrus-native TU could not be, because
the SDK's `common/` submodule is missing from the distributed source tarball.

---

## Verifying in game

1. Install SKSE 2.2.6 (matching 1.6.1170) and **MCM Helper**.
2. Put `ERC.dll` in `Data/SKSE/Plugins/`, the `.esp` in `Data/`, and the
   `MCM/` folder in `Data/`.
3. Enable `EldenRingCombat.esp`, launch via `skse64_loader.exe`.
4. In the MCM, **Elden Ring Combat** should appear with Combat / Stagger /
   Movement / Animations pages.
5. In combat, **tap** the dodge key (default Left Alt) — you should roll; **hold**
   it — you should sprint (Skyrim's native sprint is untouched).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Nothing happens, Papyrus log shows "cannot call native" | `ERC.dll` not in `Data/SKSE/Plugins/`, or SKSE not loading (wrong game version). |
| MCM doesn't appear | MCM Helper not installed. |
| Tap does nothing | `DodgeKeyCode` doesn't match your bind; check the MCM value (56 = Left Alt). |
| Rolls play but you still take damage | `[HOOK-2]` not installed — i-frames are inert without it. |
| No hit-stop | Same: `[HOOK-2]` / `Update()` hook missing. |
