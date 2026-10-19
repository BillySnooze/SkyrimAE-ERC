// ============================================================================
//  ERCPlugin.cpp — ELDEN RING COMBAT SKSE plugin implementation
// ----------------------------------------------------------------------------
//  See ERCPlugin.h for the overview. Two parts of this file are deliberately
//  isolated and clearly marked because they depend on exact symbols in YOUR
//  copy of the SKSE SDK (which varies by Skyrim AE / SKSE version):
//
//    [HOOK-1] ReadDodgeButton()   — per-frame dodge-button state
//    [HOOK-2] CancelIframeHit()   — nullify physical damage during i-frames
//
//  Everything else (settings store, MCM wiring, i-frame window math, hit-stop)
//  is fully self-contained and version-independent. If a hook symbol does not
//  match your SDK, adjust ONLY that marked block; the mod still runs — rolls,
//  hit-stop and stagger reactions all work without [HOOK-2], and tap detection
//  works as long as [HOOK-1] is wired to your input manager. See docs/BUILD.md.
// ============================================================================

#include "ERCPlugin.h"
#include "ERCMCM.h"
#include "ERCNatives.h"

#include <SKSE.h>
#include <BSScript_StackFrame.h>
#include <BSUtility_Heap.h>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// ----------------------------------------------------------------------------
//  Exported plugin factory — the one symbol SKSE looks for.
// ----------------------------------------------------------------------------
extern "C" __declspec(dllexport) SKSEPlugin* CreateSKSEPlugin()
{
	static ERCPlugin plugin;
	return &plugin;
}

// ----------------------------------------------------------------------------
//  Default settings (ER-derived values from the source repo's data.rs, used as
//  sensible starting points). Every one of these is overridable in the MCM and
//  persisted to EldenRingCombat.ini.
// ----------------------------------------------------------------------------
static void RegisterDefaults(std::map<std::string, std::string>& s)
{
	// Stamina cost (ER: a roll costs 12). Backstep/jump costs are intentionally not
	// exposed: Skyrim has no backstep or jump-attack system for them to apply to.
	s["RollStaminaCost"]     = "12";

	// I-frames
	s["IframeFraction"]      = "0.55";   // fraction of roll that is invincible

	// Hit-stop (ER freezes ~ a few frames; scaled down for Skyrim feel)
	s["HitStopSeconds"]      = "0.06";
	s["HitStopScale"]        = "0.15";   // timescale dip during hit-stop

	// Stagger tiers (damage thresholds -> flinch / stagger / large / knockdown)
	s["StaggerFlinchThreshold"]  = "8";
	s["StaggerStaggerThreshold"] = "20";
	s["StaggerLargeThreshold"]   = "40";

	// Feature toggles
	s["EnableRolls"]       = "1";
	s["EnableHitStop"]     = "1";
	s["EnableGuardBreak"]  = "1";
	s["EnableLockOnRolls"] = "1";

	// Equip-load thresholds (weapon+armour weight -> tier)
	s["EquipLoadLightCut"]   = "12";
	s["EquipLoadMediumCut"]  = "30";

	// Roll durations per tier (seconds), used to size the i-frame window AND
	// express equip-load speed (heavier = longer/slower roll).
	s["RollDurationLight"]   = "0.62";
	s["RollDurationMedium"]  = "0.78";
	s["RollDurationHeavy"]   = "1.05";

	// Tap-vs-hold threshold in frames (ER: ~10 frames at 30fps ~= 0.33s)
	s["SprintHoldFrames"]    = "6";      // frames; held longer than this = sprint

	// Animation event names (defaults target BFCO/For-Honor movesets in JOJ).
	// Override in the MCM to match whatever moveset you run.
	s["AnimFlinch"]        = "HitReaction_Flinch";
	s["AnimStagger"]       = "HitReaction_Stagger";
	s["AnimLargeStagger"]  = "HitReaction_LargeStagger";
	s["AnimKnockdown"]     = "HitReaction_Knockdown";

	s["RollLightFront"]    = "ERC_Roll_Light_Front";
	s["RollMediumFront"]   = "ERC_Roll_Medium_Front";
	s["RollHeavyFront"]    = "ERC_Roll_Heavy_Front";
}

// ----------------------------------------------------------------------------
//  ERCPlugin::Init
// ----------------------------------------------------------------------------
bool ERCPlugin::Init(SKSEInterface* a_skse)
{
	_skse = a_skse;

	Info("Elden Ring Combat (ERC) plugin loading...");

	// Register the Papyrus native functions so scripts can call ERC_Get*, etc.
	erc_natives::RegisterNatives(this);

	// Populate the settings store: defaults first, then overlay any saved ini.
	RegisterDefaults(_settings);
	if (!LoadSettings())
	{
		Info("No saved settings found — using built-in defaults.");
	}

	// Build the MCM menu (it edits _settings through this plugin).
	_mcm = new ERCMCM(this);
	_mcm->Register();

	return true;
}

// ----------------------------------------------------------------------------
//  ERCPlugin::OnGameLoaded — safe point to attach scripts and install hooks.
// ----------------------------------------------------------------------------
void ERCPlugin::OnGameLoaded()
{
	if (!_skse) return;

	// [ATTACH] Attach the ERC_PlayerCombat script to the Player. We set a pending
	// flag rather than calling ERC_OnPluginAttached immediately — the freshly
	// attached script may not be resolvable in the VM on this same frame, so we
	// fire it from Update() one frame later (see _attachPending). This is a
	// version-specific call (AttachScript / GetPlayer); adjust to your SDK. If you
	// instead attach the script in CK, skip this — but then the OnDamage fallback
	// may double-react on early hits until the first DLL event arrives.
	if (_skse->papyrusVM)
	{
		auto* vm = _skse->papyrusVM;
		const auto playerHandle = vm->GetPlayerScript();   // stable SKSE helper
		if (playerHandle != kBSInvalidHandle)
		{
			vm->AttachScript(playerHandle, "ERC_PlayerCombat");  // [VERSION-SPECIFIC]
			_attachPending = true;
		}
	}

	// [HOOK-1] Wire the dodge-button reader to your SKSE version's input manager.
	// See docs/BUILD.md, section "Wiring HOOK-1". Until it is wired, tap detection
	// reports "not down" and rolls are not auto-triggered (see fallback note there).

	// [HOOK-2] Install the damage-nullification hook for i-frames. Optional: if not
	// installed, i-frames degrade to whatever invincibility your dodge animation
	// already provides. See docs/BUILD.md, section "Wiring HOOK-2".

	Info("Elden Ring Combat (ERC) ready.");
}

// ----------------------------------------------------------------------------
//  ERCPlugin::Update — called once per frame by the game.
// ----------------------------------------------------------------------------
void ERCPlugin::Update(float afGameTime)
{
	if (!_skse) return;

	// Fire the deferred attach notification now that the script is resolvable.
	if (_attachPending)
	{
		_attachPending = false;
		CallPapyrusNoArgs("ERC_OnPluginAttached");
	}

	DetectDodgeTap(afGameTime);
	UpdateIframeWindow(afGameTime);
	UpdateHitStop(afGameTime);
}

// ============================================================================
//  [HOOK-1] Per-frame dodge-button state
// ----------------------------------------------------------------------------
//  Returns true if the dodge/roll button is currently pressed. The exact way to
//  read this depends on your SKSE SDK version. Two common approaches:
//
//   (a) Read from BGSInputManager via a hooked method pointer, e.g.:
//         auto* im = <your input manager>;
//         return im->GetButtonState(kGamepad_B /* or kKeyboard_Space */);
//
//   (b) Hook the function the game calls when the dodge action fires and set a
//       flag — this is more robust across versions because it keys off the
//       *action* rather than raw button state.
//
//  Adjust this single function to your SDK. The tap/hold logic below only needs
//  a reliable per-frame bool, so either approach works.
// ============================================================================
static bool ReadDodgeButton()
{
	// TODO(BUILD): wire to your SKSE version's input manager. Default: false,
	// which disables automatic roll triggering (see docs/BUILD.md fallback).
	return false;
}

void ERCPlugin::DetectDodgeTap(float afGameTime)
{
	const bool down = ReadDodgeButton();

	if (down && !_dodgeWasDown)
	{
		_dodgeHeldFrames = 0;          // button just went down
	}
	else if (down)
	{
		_dodgeHeldFrames++;            // still held
	}
	else if (_dodgeWasDown)
	{
		// Button released. If it was a quick tap, fire a roll; otherwise it was
		// a sprint (held past the threshold) and we do nothing.
		const int32_t threshold = GetInt("SprintHoldFrames");
		if (_dodgeHeldFrames < threshold)
		{
			int dir = 0; // front by default; directional rolls resolved in Papyrus
			CallPapyrusFloatInt("ERC_DodgeTap", 0.0f, dir);
		}
		_dodgeHeldFrames = 0;
	}

	_dodgeWasDown = down;
}

// ============================================================================
//  I-frame window management
// ----------------------------------------------------------------------------
//  The Papyrus script calls ERC_RollStarted(duration) when a roll begins. We
//  open an invincibility window covering IframeFraction of that duration, and
//  close it when the game time passes the end. While open, [HOOK-2] nullifies
//  incoming physical damage (see CancelIframeHit).
// ============================================================================
void ERCPlugin::OnRollStarted(float afDurationSeconds)
{
	const float fraction = GetFloat("IframeFraction");
	_inIframe     = true;
	_iframeEndTime = GetGameTime();   // SKSE free function (declared in <SKSE.h>)
	// Window covers the first `fraction` of the roll:
	_iframeEndTime += afDurationSeconds * fraction;

	CallPapyrusFloat("ERC_RollStarted", afDurationSeconds);
}

bool ERCPlugin::InIframeWindow() const
{
	return _inIframe && (GetGameTime() < _iframeEndTime);
}

void ERCPlugin::OnRollEnded()
{
	_inIframe = false;
	_iframeEndTime = 0.0f;
	CallPapyrusNoArgs("ERC_RollEnded");
}

void ERCPlugin::UpdateIframeWindow(float afGameTime)
{
	if (_inIframe && afGameTime >= _iframeEndTime)
	{
		OnRollEnded();
	}
}

// ============================================================================
//  [HOOK-2] I-frame damage nullification
// ----------------------------------------------------------------------------
//  Called from a hook on the player's damage function (e.g. BGSLivingProcess::
//  ApplyDamage or BGSActor::TakeHit). If we are inside an i-frame window and the
//  incoming hit is PHYSICAL (not magic/spell), cancel it so the roll's
//  invincibility frames actually protect you — exactly like ELDEN RING.
//
//  Wire this to your SDK in OnGameLoaded(). The decision logic here is
//  version-independent; only the hook installation is version-specific.
// ============================================================================
void CancelIframeHit(ERCPlugin* a_self, bool abIsPhysical)
{
	if (!a_self || !abIsPhysical) return;      // magic always gets through
	if (!a_self->InIframeWindow())  return;    // not invincible right now

	// Nullify: the hook should return "no damage applied" here. The exact
	// mechanism (zeroing a damage struct, returning early, etc.) is set up at
	// hook-install time in OnGameLoaded(). See docs/BUILD.md, "Wiring HOOK-2".
}

// ============================================================================
//  Hit-stop — dip the global timescale on impact, then restore.
// ----------------------------------------------------------------------------
//  ELDEN RING freezes both attacker and target for a few frames when a blow
//  lands. We approximate this by dropping fTimeScale to HitStopScale for
//  HitStopSeconds, then restoring it. This is fully version-independent (it only
//  uses the standard game-setting API).
// ============================================================================
void ERCPlugin::TriggerHitStop(float afSeconds)
{
	if (!_skse || afSeconds <= 0.0f) return;

	const float scale = GetFloat("HitStopScale");

	// SKSE free functions (declared in <SKSE.h>), not interface members:
	_savedTimeScale = GetGameSettingFloat("fTimeScale");
	SetGameSettingFloat("fTimeScale", scale);

	_hitStopActive = true;
	_hitStopEnd    = GetGameTime() + afSeconds;
}

void ERCPlugin::UpdateHitStop(float afGameTime)
{
	if (_hitStopActive && afGameTime >= _hitStopEnd)
	{
		SetGameSettingFloat("fTimeScale", _savedTimeScale);
		_hitStopActive = false;
	}
}

// ============================================================================
//  Settings store accessors (string-backed, parsed per call).
// ============================================================================
float ERCPlugin::GetFloat(const char* akKey)
{
	auto it = _settings.find(akKey);
	return it == _settings.end() ? 0.0f : static_cast<float>(atof(it->second.c_str()));
}

int32_t ERCPlugin::GetInt(const char* akKey)
{
	auto it = _settings.find(akKey);
	return it == _settings.end() ? 0 : atoi(it->second.c_str());
}

bool ERCPlugin::GetBool(const char* akKey)
{
	auto it = _settings.find(akKey);
	if (it == _settings.end()) return false;
	const std::string& v = it->second;
	return !(v == "0" || v == "false" || v == "no");
}

std::string ERCPlugin::GetString(const char* akKey)
{
	auto it = _settings.find(akKey);
	return it == _settings.end() ? std::string() : it->second;
}

void ERCPlugin::SetFloat(const char* akKey, float afValue) { _settings[akKey] = std::to_string(afValue); }
void ERCPlugin::SetInt  (const char* akKey, int32_t aiValue){ _settings[akKey] = std::to_string(aiValue); }
void ERCPlugin::SetBool (const char* akKey, bool abValue)   { _settings[akKey] = abValue ? "1" : "0"; }
void ERCPlugin::SetString(const char* akKey, const char* asValue){ _settings[akKey] = asValue; }

// ----------------------------------------------------------------------------
//  Path of the persisted settings file (defined below; declared here because
//  LoadSettings/SaveSettings use it before the definition appears).
// ----------------------------------------------------------------------------
static std::string GetIniPath();

// ----------------------------------------------------------------------------
//  ini persistence: <SKSEPlugins>/EldenRingCombat.ini
// ----------------------------------------------------------------------------
bool ERCPlugin::LoadSettings()
{
	const std::string path = GetIniPath();
	FILE* f = fopen(path.c_str(), "r");
	if (!f) return false;

	char line[512];
	while (fgets(line, sizeof(line), f))
	{
		// Trim whitespace / newlines.
		size_t len = strlen(line);
		while (len > 0 && isspace((unsigned char)line[len - 1])) line[--len] = '\0';
		if (len == 0 || line[0] == ';' || line[0] == '#') continue;

		char* eq = strchr(line, '=');
		if (!eq) continue;
		*eq = '\0';

		std::string key(line);
		std::string val(eq + 1);
		// Trim leading spaces on the value.
		size_t vs = val.find_first_not_of(" \t");
		if (vs != std::string::npos) val = val.substr(vs);

		_settings[key] = val;
	}
	fclose(f);
	return true;
}

bool ERCPlugin::SaveSettings() const
{
	const std::string path = GetIniPath();
	FILE* f = fopen(path.c_str(), "w");
	if (!f) return false;

	fprintf(f, "; ELDEN RING COMBAT — settings (edited via the MCM)\n");
	for (const auto& kv : _settings)
	{
		fprintf(f, "%s = %s\n", kv.first.c_str(), kv.second.c_str());
	}
	fclose(f);
	return true;
}

static std::string GetIniPath()
{
	// SKSEPlugins/ is the standard writable plugin-data directory.
	return "SKSEPlugins/EldenRingCombat.ini";
}

// ============================================================================
//  Papyrus bridge — call a function on the player's ERC_PlayerCombat script.
// ----------------------------------------------------------------------------
//  Uses the BSScript VM to invoke named functions on the Player object. This is
//  how the plugin tells Papyrus "a dodge tap happened" / "the player landed a
//  hit". Three arity-specific helpers match each event's signature exactly.
//
//  The GetFunctionByName + CallFunction calls below use stable SKSE/BSScript
//  APIs; if your SDK version names them slightly differently, adjust only those
//  lines. A failed call is logged and ignored — native behaviour (i-frames,
//  hit-stop) is independent of Papyrus, so a bridge mismatch never crashes.
// ============================================================================

static BSScriptObjectHandle GetPlayerScriptHandle()
{
	auto* vm = GetSKSE()->papyrusVM;
	if (!vm) return kBSInvalidHandle;

	// The player's script object (the ERC_PlayerCombat instance attached to the
	// Player actor). Adjust if your SDK exposes this differently.
	return vm->GetPlayerScript();   // stable SKSE helper in modern SDKs
}

void ERCPlugin::CallPapyrusNoArgs(const char* akFunction)
{
	auto* vm = GetSKSE()->papyrusVM;
	if (!vm) return;

	const auto handle = GetPlayerScriptHandle();
	if (handle == kBSInvalidHandle) { Info("ERC: no player script for %s", akFunction); return; }

	const auto fn = vm->GetFunctionByName(handle, akFunction);
	if (fn == kBSInvalidHandle) { Info("ERC: function %s not found on player script", akFunction); return; }

	vm->CallFunction(fn, handle, nullptr, 0);
}

void ERCPlugin::CallPapyrusFloat(const char* akFunction, float afArg0)
{
	auto* vm = GetSKSE()->papyrusVM;
	if (!vm) return;

	const auto handle = GetPlayerScriptHandle();
	if (handle == kBSInvalidHandle) { Info("ERC: no player script for %s", akFunction); return; }

	const auto fn = vm->GetFunctionByName(handle, akFunction);
	if (fn == kBSInvalidHandle) { Info("ERC: function %s not found on player script", akFunction); return; }

	BSScript::StackFrame frame(vm);
	frame.Push(afArg0);
	vm->CallFunction(fn, handle, &frame, 1);
}

void ERCPlugin::CallPapyrusFloatInt(const char* akFunction, float afArg0, int32_t aiArg1)
{
	auto* vm = GetSKSE()->papyrusVM;
	if (!vm) return;

	const auto handle = GetPlayerScriptHandle();
	if (handle == kBSInvalidHandle) { Info("ERC: no player script for %s", akFunction); return; }

	const auto fn = vm->GetFunctionByName(handle, akFunction);
	if (fn == kBSInvalidHandle) { Info("ERC: function %s not found on player script", akFunction); return; }

	BSScript::StackFrame frame(vm);
	frame.Push(afArg0);
	frame.Push(aiArg1);
	vm->CallFunction(fn, handle, &frame, 2);
}
