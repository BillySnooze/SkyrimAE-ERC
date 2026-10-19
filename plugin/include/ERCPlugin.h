// ============================================================================
//  ERCPlugin.h — ELDEN RING COMBAT SKSE plugin
// ----------------------------------------------------------------------------
//  A small, standard-shaped SKSE plugin. It owns:
//    - The tunable settings store (single source of truth for the MCM + Papyrus)
//    - Per-frame dodge-button tap detection (tap = roll, hold = sprint)
//    - The i-frame invincibility window during rolls (nullifies physical hits)
//    - Hit-stop (global timescale dip on impact)
//    - The MCM menu (IWMCM) exposing every tunable as a slider/toggle
//
//  All combat *logic* that benefits from script-level access to game objects
//  (stagger-reaction selection, equip-load tiers) lives in Papyrus and is called
//  through BSScript; where a native call would be more reliable the plugin does
//  it directly. See docs/BUILD.md for compile instructions.
// ============================================================================

#pragma once

#include <SKSEPlugin.h>
#include <IWMCM.h>
#include <map>
#include <string>
#include <cstdint>

class ERCMCM; // forward decl (defined in ERCMCM.h)

class ERCPlugin : public SKSEPlugin
{
public:
	// --- SKSEPlugin interface -------------------------------------------------
	bool Init(SKSEInterface* a_skse) override;
	void Update(float afGameTime) override;          // called once per frame by the game
	void OnGameLoaded() override;                    // safe point to hook player functions

	// --- Settings store (single source of truth) ------------------------------
	float  GetFloat(const char* akKey);
	int32_t GetInt(const char* akKey);
	bool   GetBool(const char* akKey);
	std::string GetString(const char* akKey);
	void   SetFloat(const char* akKey, float afValue);
	void   SetInt(const char* akKey, int32_t aiValue);
	void   SetBool(const char* akKey, bool abValue);
	void   SetString(const char* akKey, const char* asValue);

	// Load/save the store to <SKSEPlugins>/EldenRingCombat.ini
	bool   LoadSettings();
	bool   SaveSettings() const;

	// --- Roll / i-frame state -------------------------------------------------
	void   OnRollStarted(float afDurationSeconds);
	void   OnRollEnded();
	// Defined in the .cpp (needs GetGameTime(), which is only available there).
	bool   InIframeWindow() const;

	// --- Hit-stop -------------------------------------------------------------
	void   TriggerHitStop(float afSeconds);

	// --- Papyrus bridge (non-fatal; falls back to native behaviour) -----------
	void   CallPapyrusNoArgs(const char* akFunction);
	void   CallPapyrusFloat(const char* akFunction, float afArg0);
	void   CallPapyrusFloatInt(const char* akFunction, float afArg0, int32_t aiArg1);

private:
	SKSEInterface* _skse = nullptr;
	ERCMCM*        _mcm  = nullptr;

	// Settings store: key -> value as a string (parsed per accessor). Strings are
	// used uniformly so the ini file is trivially human-editable.
	std::map<std::string, std::string> _settings;

	// --- Per-frame input state ------------------------------------------------
	bool   _dodgeWasDown = false;
	int32_t _dodgeHeldFrames = 0;

	// --- i-frame window -------------------------------------------------------
	bool   _inIframe = false;
	float  _iframeEndTime = 0.0f;   // game time (seconds) at which the window closes

	// --- Hit-stop -------------------------------------------------------------
	bool   _hitStopActive = false;
	float  _hitStopEnd = 0.0f;
	float  _savedTimeScale = 1.0f;

	// Set in OnGameLoaded after AttachScript; consumed by Update() one frame later
	// to fire ERC_OnPluginAttached once the script is resolvable in the VM.
	bool   _attachPending = false;

	void DetectDodgeTap(float afGameTime);
	void UpdateIframeWindow(float afGameTime);
	void UpdateHitStop(float afGameTime);
};

// The one exported symbol SKSE looks for.
extern "C" __declspec(dllexport) SKSEPlugin* CreateSKSEPlugin();
