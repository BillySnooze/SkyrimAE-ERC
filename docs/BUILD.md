# Building ELDEN RING COMBAT

Target runtime: **Skyrim SE/AE 1.6.1170** (the JOJ stock game at
`F:\Modlists\JOJ\Stock Game`), with **SKSE 2.2.6**.

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/ERC_PlayerCombat.psc   ← Papyrus source (compiled by tools/build.ps1)
│  ├─ scripts/ERC_PlayerCombat.pex          ← build output (runtime location)
│  ├─ MCM/Config/EldenRingCombat/           ← MCM Helper menu (config.json + settings.ini)
│  └─ SKSE/Plugins/ERC.dll                  ← build output (runtime location)
├─ plugin/
│  ├─ include/  (ERCPlugin.h, erc_compat.h)
│  ├─ src/      (ERCMain.cpp, ERCPlugin.cpp, ERCNatives.cpp)
│  └─ validation/                           ← offline compile check (mock SDK)
├─ tools/
│  ├─ build.ps1                             ← builds the .pex and ERC.dll
│  └─ validate-psc.ps1                      ← Papyrus structural check
├─ skse-sdk/                                ← cloned SDK (not committed)
└─ docs/
```

After one successful build, **`data/` is a complete installable mod tree** except
for the `.esp` (Part A).

---

## One command

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

Defaults used (override with the parameters shown):

| Parameter | Default |
|---|---|
| `-GamePath` | `F:\SteamLibrary\steamapps\common\Skyrim Special Edition` |
| `-SdkPath` | `.\skse-sdk` |
| `-SkseScripts` | `.\skse64_2_02_06_gog\Data\Scripts\Source` |
| `-VsDevCmd` | `...\Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat` |

It compiles the Papyrus script, builds the SDK static libraries on first run,
links `ERC.dll`, and copies both outputs into `data/`.

Add `-SkipSdkBuild` once the SDK libraries exist.

### Verified build

| Artifact | Result |
|---|---|
| `ERC_PlayerCombat.pex` | **0 errors, 0 warnings** — PapyrusCompiler from the CK install |
| `ERC.dll` | **links clean**, exports `SKSEPlugin_Load` + `SKSEPlugin_Version` |
| SDK | `skse64_0x01064920.lib` (runtime `0x01064920` = 1.6.1170) |

---

## Part A — the `.esp` (required)

Papyrus cannot run without a plugin record that carries the script. The SKSE
plugin API has **no** `AttachScript`-style call (checked against the SDK: no such
symbol exists), so this step is done in the Creation Kit.

The script is a **quest ReferenceAlias** script (`extends ReferenceAlias`).
Skyrim's only supported way to run a script on the player is a start-game-enabled
quest whose alias is forced to the Player reference.

### Steps

1. Make sure `data/scripts/ERC_PlayerCombat.pex` is in the game's
   `Data\Scripts\` folder (the build script puts it in the repo's `data/`; copy
   the whole `data/` tree into the game, or point CK at it).
2. Open the Creation Kit. **File → Data**, tick `Skyrim.esm`, click OK.
3. **File → New Plugin**, name it `EldenRingCombat`, OK.
4. In the **Object Window → Quest**, right-click → **New**.
   - Editor ID: `ERC_PlayerCombatQuest`
   - **Quest Data** tab: tick **Start Game Enabled**, set Priority to `60`.
   - Give it a name (e.g. "Elden Ring Combat").
5. Open the **Quest Aliases** tab. Right-click the empty list → **New Alias**.
   - Alias Name: `Player`
   - Tick **Optional**? **No** — leave it unticked.
   - **Force Reference To → Specific Reference**, then pick the **Player**
     reference (`PlayerRef`, `00000014`).
6. With the alias selected, open **Scripts → Add**, choose `ERC_PlayerCombat`,
   OK.
7. **File → Save.** CK writes `EldenRingCombat.esp`.
8. Copy that `.esp` into `data/`.

> **Note on CK versions.** The CK here is 1.7.99 while the game runtime is
> 1.6.1170. The SSE form version is unchanged between them, so the plugin loads —
> but verify the quest is present in game (`sqv ERC_PlayerCombatQuest` in the
> console) on first run.

---

## Part B — `ERC.dll` (SKSE plugin)

### SDK

```bat
git clone https://github.com/Ez0n3/SKSE64AE-Plugins skse-sdk
```

That mirror is preconfigured for **runtime 1.6.1170 / SKSE 0.2.2.6 / VS2022
(v143)** and carries the full `common/` tree the source tarball inside the SKSE
release omits.

Build its static libraries once:

```bat
msbuild skse-sdk\skse64_plugins\ez_skse64ae_plugin_example\ez_skse64ae_plugin_example.sln ^
        /p:Configuration=Release /p:Platform=x64 /t:Build /m
```

Products land in
`skse-sdk\skse64_plugins\ez_skse64ae_plugin_example\Builds\Release\`:

| Library | Provides |
|---|---|
| `skse64_0x01064920.lib` | `Heap_Allocate`, `StringCache`, `PackValue`, `GetTypeID`, Papyrus natives |
| `common_vc14.lib` | SKSE `common/` support (logging, streams, …) |
| `skse64_common.lib` | `RelocationManager` |

### Compile + link

Two details matter, and both are easy to get wrong:

1. **`/FI"common/IPrefix.h"`** — SKSE's headers *require* this forced include
   (`UInt32`, `STATIC_ASSERT`, `Windows.h`). Without it you get a wall of
   `missing type specifier` / `InterlockedDecrement` errors.
2. **Link the three static libs.** Registering Papyrus natives pulls in
   `PackValue`/`GetTypeID`/`Heap_Allocate`, so an "only function pointers" link is
   not enough (this is exactly what `tools/build.ps1` does).

```bat
cl /nologo /std:c++17 /EHsc /O2 /LD /D_CRT_SECURE_NO_WARNINGS ^
   /FI"common/IPrefix.h" ^
   /I plugin\include /I skse-sdk /I skse-sdk\skse64 ^
   /I skse-sdk\skse64\skse64 /I skse-sdk\skse64\skse64_common ^
   plugin\src\ERCMain.cpp plugin\src\ERCPlugin.cpp plugin\src\ERCNatives.cpp ^
   /Fe:data\SKSE\Plugins\ERC.dll ^
   /link /MACHINE:X64 /LTCG ^
   "skse-sdk\skse64_plugins\ez_skse64ae_plugin_example\Builds\Release\skse64_0x01064920.lib" ^
   "skse-sdk\skse64_plugins\ez_skse64ae_plugin_example\Builds\Release\common_vc14.lib" ^
   "skse-sdk\skse64_plugins\ez_skse64ae_plugin_example\Builds\Release\skse64_common.lib"
```

> **`SInt32`, not `int`.** The SDK specialises `PackValue<UInt32>/<SInt32>` but
> not `PackValue<int>`, so native return types are declared `SInt32`. Using `int`
> compiles and then fails to link with one unresolved `PackValue<int>`.

The `.lib`/`.exp` the linker drops next to the DLL are intermediates; delete them.

### What is implemented

| Piece | State |
|---|---|
| `SKSEPlugin_Version` / `SKSEPlugin_Load` entry points | ✅ built against the genuine headers |
| Papyrus native registration (`ERC_*`, class `ERC_PlayerCombat`) | ✅ built + exported |
| Settings store + ini merge (plugin ini + MCM Helper ini) | ✅ implemented |
| I-frame window maths (`OnRollStarted`, `InIframeWindow`) | ✅ implemented |
| Hit-stop timing | ✅ timing implemented; applying the timescale dip is `[HOOK-2]` |
| Per-frame `Update()` | ⚠️ needs a hook to be called (see below) |
| Input hook / damage nullification | ⚠️ `[HOOK-1]` / `[HOOK-2]` — version-specific |

### Remaining version-specific work

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

## Validation without the game

| Command | What it proves |
|---|---|
| `powershell -File tools\validate-psc.ps1 -Path data\scripts\source\ERC_PlayerCombat.psc` | Papyrus structure: no duplicate names, balanced blocks, no known non-Skyrim API or C-style syntax. |
| `plugin\validation\build-check.bat` | The C++ compiles (`cl /c`) against mock SKSE headers. `.obj` only — no DLL, no link. |
| `powershell -File tools\build.ps1` | The real thing: real Papyrus compiler + real SDK headers + full link. |

---

## Verifying in game

1. Install SKSE 2.2.6 (matching 1.6.1170) and **MCM Helper**.
2. Put the built `data/` contents into the game / your mod manager:
   `ERC.dll` in `Data/SKSE/Plugins/`, the `.pex` in `Data/Scripts/`,
   the `MCM/` folder in `Data/`, and `EldenRingCombat.esp` in `Data/`.
3. Enable `EldenRingCombat.esp`, launch via `skse64_loader.exe`.
4. In the console: `sqv ERC_PlayerCombatQuest` — the quest should be running and
   the `Player` alias filled.
5. In the MCM, **Elden Ring Combat** should appear with Combat / Stagger /
   Movement / Animations pages.
6. In combat, **tap** the dodge key (default Left Alt) — you should roll; **hold**
   it — you should sprint (Skyrim's native sprint is untouched).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Nothing happens, Papyrus log shows "cannot call native" | `ERC.dll` not in `Data/SKSE/Plugins/`, or SKSE not loading (wrong game version). |
| MCM doesn't appear | MCM Helper not installed. |
| Rolls never fire, no Papyrus errors | The quest alias is empty — check `sqv ERC_PlayerCombatQuest`, and that the alias is force-filled with the Player. |
| Tap does nothing | `DodgeKeyCode` doesn't match your bind; check the MCM value (56 = Left Alt). |
| Rolls play but you still take damage | `[HOOK-2]` not installed — i-frames are inert without it. |
| No hit-stop | Same: `[HOOK-2]` / `Update()` hook missing. |
