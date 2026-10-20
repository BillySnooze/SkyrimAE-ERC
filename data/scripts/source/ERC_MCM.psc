; ============================================================================
;  ERC_MCM.psc — the quest script that makes the MCM appear
; ----------------------------------------------------------------------------
;  This script exists for one reason: MCM Helper does not scan Data/MCM/Config.
;  It iterates SkyUI's registered config list and, for each entry, derives the
;  JSON path from the *plugin that owns the quest the script is attached to*:
;
;      ConfigStore::ReadConfig() -> "Data/MCM/Config" / GetModName(quest) / "config.json"
;
;  So a config.json that nobody claims is never read, silently — no log line, no
;  error, just a missing menu. Registration itself is inherited from MCM Helper:
;
;      SKI_ConfigBase.OnInit  -> OnGameReload   (registers SKICP_configManagerReady)
;      SKICP_configManagerReady -> RegisterMod  (SkyUI now lists the menu)
;      MCM Helper            -> ReadConfig(pluginName) -> our config.json
;
;  Because the plugin is EldenRingCombat.esp, GetModName() is "EldenRingCombat",
;  which is why the config folder must be named exactly that.
;
;  Deliberately empty of events. Overriding OnInit/OnConfigClose here would
;  suppress SKI_ConfigBase's own implementations (Papyrus does not auto-call
;  parents), which would break registration and the menu's state handling. All
;  controls are declarative in config.json, so there is nothing to initialise.
; ============================================================================

Scriptname ERC_MCM extends MCM_ConfigBase
