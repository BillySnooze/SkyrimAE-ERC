# Vendored MCM Helper public scripts (compile-time only)

These three files are the *public interface* scripts published by MCM Helper
(https://github.com/Exit-9B/MCM-Helper, `scripts/public/`), copied verbatim:

| File | Why it is here |
|---|---|
| `MCM_ConfigBase.psc` | `ERC_MCM.psc` extends it. Also declares the natives (`LoadConfig`, `GetModSetting*`) the framework provides. |
| `SKI_ConfigBase.psc` | `MCM_ConfigBase` extends it; this is the registration entry point. |
| `SKI_QuestBase.psc` | `SKI_ConfigBase` extends it. |

They are needed **only** to compile `ERC_MCM.pex`. The versions that actually run
come from `MCMHelper.bsa` — do not ship these, and never recompile them into the
mod (the real scripts raise `SKI_ConfigBase: Don't recompile this script!` if a
modified copy is loaded, which would silently break every MCM in the modlist).

`tools/build.ps1` adds this folder to the Papyrus import path automatically.
