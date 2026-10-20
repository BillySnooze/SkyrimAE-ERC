# Building ELDEN RING COMBAT

Target runtime: **Skyrim SE/AE 1.6.1170** (the JOJ stock game at
`F:\Modlists\JOJ\Stock Game`), with **SKSE 2.2.6**.

```
EldenRingCombat/
├─ data/
│  ├─ scripts/source/ERC_PlayerCombat.psc   ← Papyrus source (compiled by tools/build.ps1)
│  ├─ scripts/ERC_PlayerCombat.pex          ← build output (runtime location)
│  ├─ MCM/Config/EldenRingCombat/           ← MCM Helper menu (config.json + settings.ini)
│  ├─ SKSE/Plugins/ERC.dll                  ← build output (runtime location)
│  ├─ EldenRingCombat.esp                   ← build output (authored by the houseCARL MCP)
│  └─ SEQ/EldenRingCombat.seq               ← build output (starts the quest)
├─ plugin/
│  ├─ include/  (ERCPlugin.h, erc_compat.h)
│  ├─ src/      (ERCMain.cpp, ERCPlugin.cpp, ERCNatives.cpp)
│  └─ validation/                           ← offline compile check (mock SDK)
├─ tools/
│  ├─ build.ps1                             ← builds the .pex, ERC.dll and the .esp
│  ├─ esp/                                  ← ESP authoring/verification (see Part A)
│  ├─ housecarl/                            ← the quest record spec (JSON)
│  ├─ mcp/                                  ← stdio MCP client used by the build
│  ├─ xedit/                                ← headless xEdit verifier
│  └─ validate-psc.ps1                      ← Papyrus structural check
├─ skse-sdk/                                ← cloned SDK (not committed)
└─ docs/
```

After one successful build, **`data/` is a complete installable mod tree**.

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
| `-Mo2Path` | `F:\Modlists\JOJ` (where the ESP is authored) |

It compiles the Papyrus scripts (`ERC_PlayerCombat.psc` and `ERC_MCM.psc`), builds
the SDK static libraries on first run, links `ERC.dll`, generates
`EldenRingCombat.esp` and its `.seq` with `tools\esp\build_esp.py`, and verifies
the plugin with two independent parsers.

Add `-SkipSdkBuild` once the SDK libraries exist, `-SkipEsp` to leave the plugin
alone.

### Verified build

| Artifact | Result |
|---|---|
| `ERC_PlayerCombat.pex` | **0 errors, 0 warnings** — PapyrusCompiler from the CK install |
| `ERC_MCM.pex` | compiles against MCM Helper's public base scripts (vendored in `tools\vendor\mcm-helper`) |
| `ERC.dll` | **links clean**, exports `SKSEPlugin_Load` + `SKSEPlugin_Version` |
| SDK | `skse64_0x01064920.lib` (runtime `0x01064920` = 1.6.1170) |
| `EldenRingCombat.esp` | 484 bytes, **two** quests; parsed identically by this repo's byte reader and xEdit |

---

## Part A — the `.esp`

Papyrus cannot run without a plugin record that carries the script. The SKSE
plugin API has **no** `AttachScript`-style call (checked against the SDK: no such
symbol exists), so the script hangs off a **quest ReferenceAlias** — Skyrim's only
supported way to run a script on the player is a start-game-enabled quest whose
alias is forced to the Player reference.

`tools\esp\build_esp.py` writes it deterministically — no Creation Kit, no MCP
server, no network:

```powershell
py tools\esp\build_esp.py        # writes data\EldenRingCombat.esp and data\SEQ\EldenRingCombat.seq
py tools\esp\verify_esp.py       # byte-level check of the result
```

(The older `tools\esp\build_esp.ps1` + houseCARL path still exists for reference,
but `tools\build.ps1` now calls the Python writer.)

| Stage | Tool | What it guarantees |
|---|---|---|
| Author | `tools\esp\build_esp.py` | Emits the whole plugin from constants: header, quest group, VMAD, `.seq`. |
| Verify | `tools\esp\verify_esp.py` | Byte-level: subrecord order, DNAM flags, ALFR link, VMAD layout and byte-exact tail. |
| Verify | `tools\esp\patch-quest-flags.py` + `inspect-plugin.py` | Independent re-read of GRUP sizes and quest flags. |
| Verify | `tools\xedit\ERC_VerifyEsp.pas` | xEdit's own parser, the closest thing to the game's loader. Needs Skyrim closed — xEdit will not start a script run while the game holds the plugin files. |

### What the plugin contains

| Part | Value |
|---|---|
| Quest 0 | `ERC_PlayerCombatQuest` "Elden Ring Combat", Start Game Enabled, priority 60 |
| Alias 0 | `Player`, forced reference `Skyrim.esm:00000014` (`PlayerRef`) |
| VMAD | `ERC_PlayerCombat` attached to alias 0, no properties |
| Quest 1 | `ERC_MCMQuest`, Start Game Enabled — exists only to host `ERC_MCM` |
| VMAD | `ERC_MCM` attached to the quest itself (quest-level script, no aliases) |

Quest 1 is what makes the MCM appear. MCM Helper does **not** scan
`Data/MCM/Config`; `ConfigStore::ReadConfigs` walks SkyUI's already-registered
config list and reads `Data/MCM/Config/<plugin name>/config.json` for each entry.
A JSON file nobody claims is skipped without a log line. Registration comes from
the base scripts: `SKI_ConfigBase.OnInit` → `OnGameReload` →
`SKICP_configManagerReady` → `RegisterMod`, which is why `ERC_MCM` overrides no
events at all (overriding `OnInit` would suppress that chain, since Papyrus does
not call parent events).

Three byte-level details that look wrong but are not, and cost hours if assumed
otherwise:

- **The record's high byte is the master count**, not zero: this plugin has one
  master (`Skyrim.esm`), so its records are `0x01xxxxxx` in the file. The loader
  swaps that byte for the plugin's load-order index at runtime, which is why the
  console and xEdit show a different prefix.
- **The alias block in VMAD is `u16 zero, u16 alias id, u32 quest form id`** —
  `u16 zero` first. Skyrim.esm `000B113D` (alias block naming alias 4) proves the
  order; reading the FormID first makes every block parse one field early.
- **A VMAD that only carries a quest script still has a fragment file name.** The
  tail is `u8 bind version, u16 fragment count, wstring script file name, u16
  alias block count` — the empty file name is a real `0000` field, confirmed
  against `Precision.esp`'s `Precision_MCM_Quest` (`02 0000 0000 0100`). Omit it
  and the alias count is read two bytes early, so the record misparses with
  nothing in the build to warn you; `verify_esp.py` now checks that tail
  byte-exactly (`bind=2 fragments=0 fragment_file_len=0 alias_blocks=0`).

### Installing the plugin

The build leaves `data\EldenRingCombat.esp`, `data\SEQ\EldenRingCombat.seq` and
`data\scripts\ERC_MCM.pex` in the repo. Copy `data\` into your mod folder (or use
`tools\deploy.ps1` if present). The `.seq` must sit at
`<mod>\SEQ\EldenRingCombat.seq` (or `Data\SEQ\`) or both quests — and so both
scripts — silently never start.

> **Note on CK versions.** The CK here is 1.7.99 while the game runtime is
> 1.6.1170. The SSE form version is unchanged between them, so the plugin loads —
> but check in game that **both** quests are running (`sqv ERC_PlayerCombatQuest`
> and `sqv ERC_MCMQuest`) on first run.
>
> `sqv ERC_PlayerCombatQuest` listing no variables is **not** an error: the
> player script lives on the quest's *alias*, not on the quest, so `sqv` has
> nothing to print for it. The proof is the Papyrus log line
> `ERC: TK Dodge RE present - deferring the roll`, which only the alias script
> writes.

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
| I-frame window maths (`OnRollStarted`, `InIframeWindow`) | ✅ implemented (fallback roll only), diagnostic — nothing consumes it |
| Hit-stop | ❌ removed: dipping `TimeScale` scales game time, not animation playback. Use Precision (JOJ ships it enabled) |
| Per-frame `Update()` | ⚠️ needs a hook to be called (see below) |
| Input hook / i-frame damage nullification | ⚠️ `[HOOK-1]` / `[HOOK-2]` — version-specific |

### Remaining version-specific work

**`[HOOK-2]` — i-frame damage nullification.** Install a hook on the player
damage path and zero physical damage while `InIframeWindow()` is true. With
CommonLibSSE-NG this is a few lines; without it you need signature scans for your
exact runtime.

**Hit-stop, if you ever want it inside ERC.** It cannot be done from Papyrus:
`TimeScale` (the global the console's `set timescale` writes) scales game *time* —
the clock and AI scheduling — not animation playback, so a dip is applied and
restored correctly yet never freezes the screen. Precision's approach is the
correct one: scale each actor's animation `deltaTime` in a hook (see
`GetHitstopMultiplier` in Precision's `Hooks.cpp`). Until ERC grows that hook, the
MCM points at **Precision → Hitstop**, which JOJ ships at 0.07 s / 0.1× with
camera shake.

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

The JSON shape is MCM Helper 1.5's, not the older SkyUI one:

```json
{
  "modName": "EldenRingCombat",
  "displayName": "Elden Ring Combat",
  "minMcmVersion": 9,
  "pages": [
    { "pageDisplayName": "Combat", "content": [
      { "id": "fRollStaminaCost:Combat", "type": "slider", "text": "...",
        "valueOptions": { "min": 0, "max": 50, "step": 1,
                          "sourceType": "ModSettingFloat", "defaultValue": 12 } }
    ] }
  ]
}
```

The id splits into the settings key (`fRollStaminaCost`) and the `settings.ini`
section (`Combat`); the `f` prefix is what makes MCM Helper store it as a float,
and `ERC.dll` strips it again when reading. Get either half wrong and the menu
either does not appear or appears with dead controls — hence `tools/validate-mcm.py`.

---

## Validation without the game

| Command | What it proves |
|---|---|
| `powershell -File tools\validate-psc.ps1 -Path data\scripts\source\ERC_PlayerCombat.psc` | Papyrus structure: no duplicate names, balanced blocks, no known non-Skyrim API or C-style syntax. |
| `plugin\validation\build-check.bat` | The C++ compiles (`cl /c`) against mock SKSE headers. `.obj` only — no DLL, no link. |
| `py tools\validate-mcm.py` | The MCM document uses MCM Helper 1.5's schema: `pages`/`pageDisplayName`, `:Category` ids, `sourceType` on every `valueOptions`, and every id present in `settings.ini`. |
| `py tools\qualify-natives.py --check` | Every native call is `ERC_PlayerCombat.ERC_X(...)`, matching the `global native` declarations. |
| `powershell -File tools\build.ps1` | The real thing: real Papyrus compiler + real SDK headers + full link + a freshly authored, twice-verified `.esp`. |
| `powershell -File tools\esp\build_esp.ps1 -XEditVerify` | The plugin alone, re-parsed by xEdit as well. |

---

## Verifying in game

1. Install SKSE 2.2.6 (matching 1.6.1170) and **MCM Helper**.
2. Put the built `data/` contents into the game / your mod manager:
   `ERC.dll` in `Data/SKSE/Plugins/`, the `.pex` in `Data/Scripts/`,
   the `MCM/` folder in `Data/`, `EldenRingCombat.esp` in `Data/`, and
   `EldenRingCombat.seq` in `Data/SEQ/`.
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
| The mod appears in MO2, `ERC.dll` logs "loaded correctly", but nothing happens in game **and** there is no MCM entry | The quest never started. `EldenRingCombat.esp` had Start Game Enabled as `0x0001` instead of `0x0100`. Start Game Enabled is DNAM bit `0x0100` — checked against `Skyrim.esm`, where `MQ101`/`MQ102` (which must run from game start) carry `0x0100` with a clean record header while `DA10` has `0x0000`. With the wrong bit the alias script never attaches to the player, so `OnInit`/`OnUpdate`/`OnHit` never fire: no rolls, no hit reactions, and no MCM. `tools/esp/patch-quest-flags.py` repairs it and `build.ps1` runs it every build. |
| Plugin suspiciously small / a group runs past the end of the file | A `GRUP` size field counts **only** its content, not the 24-byte header. Writing header+content overruns EOF by exactly one record header (a 351-byte file claiming a 247-byte group with 223 bytes present). Check with `py tools/inspect-plugin.py data\EldenRingCombat.esp`. |
| No Papyrus log at all | Papyrus logging is off by default. With MO2's profile-local INIs the live file is `profiles\<profile>\skyrim.ini`, not `Documents\My Games\...`. Set `bEnableLogging=1` and `bLoadDebugInformation=1` in `[Papyrus]`. |
| Papyrus logs `Native static function ERC_X could find no matching static function on linked type ERC_PlayerCombat`, then `Unbound native function "ERC_GetFloat" called` from `OnInit` | The script declared a native as a member function while `ERC.dll` registered it as static. Declarations must be `global native` and calls `ERC_PlayerCombat.ERC_GetFloat(...)`. `build.ps1` enforces this via `tools/qualify-natives.py`. This failure stops `OnInit` before `RegisterForSingleUpdate`, so the mod is completely silent — no rolls, no hit reactions. |
| MCM appears but sliders don't move settings | `settings.ini` section/key doesn't match the `:Category` in the id, or the id lacks its `f`/`i`/`b`/`s` prefix. Check with `py tools/validate-mcm.py`: the document needs `pages` → `pageDisplayName` → `content`, ids of the form `fRollStaminaCost:Combat`, and a `sourceType` in every `valueOptions`. A root `content` array holding `{"type": "page"}` objects is silently ignored. |
| Quest never runs, alias never fills, no log line | `Data\SEQ\EldenRingCombat.seq` is missing — a start-game-enabled quest in an `.esp` does not start on an existing save without it. |
| Tap does nothing | `ERC Dodge Key Code` doesn't match your bind; check the MCM value (45 = X by default). Left Alt belongs to TK Dodge's sprint-key dodge and V belongs to Timed Block-Dodge and Counter. |
| Dodge is a step, not a roll | `StepDodge = true` in `Data\SKSE\Plugins\TK Dodge RE.ini`. ERC ships an override with it false; if the step is still there, ERC is not top priority in MO2, or another mod's copy of the ini is overriding this one. |
| A freeze happens only when dodging | That is Timed Block-Dodge and Counter's timed-dodge bullet-time (`[TimedDodge]` `fSlomoDuration`/`fSlomoSpeed` in `TimedBlockDodgeCounter.ini`), not hit-stop. Set `fSlomoDuration = 0` to disable. |
| Rolls play but you still take damage | I-frame damage nullification is `[HOOK-2]` — not implemented. In JOJ the roll's i-frames come from I-Frame Generator, not ERC. |
| ERC's own roll does nothing | Check `Papyrus.0.log` for `is an Actor, and PlayAnimation should not be used` — if present you are running an old `.pex`. Also confirm the roll event names on the Animations page exist in your behaviour graph (`TKDodge*` ship with TK Dodge in JOJ). |
| No hit-stop | ERC does not implement hit-stop. Use MCM → Precision → Hitstop (JOJ enables it: 0.07 s vs NPCs, 0.035 s otherwise, 0.1× slowdown). If Precision's freeze is invisible, raise the durations or lower `fHitstopSlowdownTimeMultiplier`. |
| Hit-stop feels too strong / too weak | `fHitstopDurationNPC` / `fHitstopDurationOther` in Precision's MCM set the freeze length; `fHitstopSlowdownTimeMultiplier` sets how slow it gets (0.1 = 10% speed). |
| Sliders show whole numbers instead of decimals | Every float slider needs a `formatString` in `valueOptions` (e.g. `"{2}"` for two decimals, `"{2} s"` for seconds). Without it MCM Helper renders `0.15` as `0`. |

### Reading the first 20 lines of `Papyrus.0.log` is the fastest diagnosis

Both silent-failure modes above are visible there within a second of loading a
save: `Unbound native function` means the natives didn't bind, and an absent
`ERC_PlayerCombat` line entirely means the alias script never ran.
