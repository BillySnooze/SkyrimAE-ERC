// ============================================================================
//  ERCPlugin.h — Elden Ring Combat SKSE plugin core
// ----------------------------------------------------------------------------
//  Written against the OFFICIAL SKSE 2.x plugin API (PluginAPI.h):
//    * entry points live in ERCMain.cpp (SKSEPlugin_Version / SKSEPlugin_Load)
//    * Papyrus natives are registered in ERCNatives.cpp
//    * this class owns settings, the i-frame window, hit-stop and the dodge-tap
//      queue drained by Papyrus polling
//
//  Transport to Papyrus is POLLING, not event push: the official plugin API has
//  no simple "raise a Papyrus event" call, so Papyrus calls ERC_ConsumeDodgeTap()
//  on a short update loop instead. This keeps the plugin free of BSScript/VM
//  internals. See docs/SKSE-API-NOTES.md.
// ============================================================================
#pragma once

#include <map>
#include <string>

struct SKSEInterface;

class ERCPlugin
{
public:
	static ERCPlugin& Get();

	// Called from SKSEPlugin_Load. Registers Papyrus natives + messaging.
	bool Init(const SKSEInterface* skse);

	// --- settings (Data/SKSE/Plugins/EldenRingCombat.ini and MCM Helper ini) --
	void LoadSettings();
	float       GetFloat(const std::string& key) const;
	int         GetInt(const std::string& key) const;
	bool        GetBool(const std::string& key) const;
	std::string GetString(const std::string& key) const;
	void        SetFloat(const std::string& key, float value);

	// --- dodge provider detection --------------------------------------------
	// JOJ's roll is TK Dodge RE: a script-free SKSE plugin that owns the roll
	// clip, the stamina cost and (with I-Frame Generator) the invincibility
	// window. Its hotkey defaults to the same scan code ERC used to poll, so
	// when it is installed ERC stands down from its own roll instead of billing
	// stamina twice and playing an animation event no behaviour graph defines.
	bool  HasTKdodge() const { return _tkdodgePresent; }
	float TKdodgeFloat(const std::string& key) const;

	// --- dodge taps -----------------------------------------------------------
	// Filled by the input hook ([HOOK-1]); drained by Papyrus polling.
	void QueueDodgeTap(int direction);   // 0 front, 1 back, 2 left, 3 right
	int  ConsumeDodgeTap();              // -1 when nothing pending

	// --- i-frames -------------------------------------------------------------
	void OnRollStarted(float durationSeconds);
	void OnRollEnded();
	bool InIframeWindow() const;

	// Hit-stop is NOT here: Skyrim's timescale is the `TimeScale` global
	// (Skyrim.esm 0x0000003A), which Papyrus can write through
	// GlobalVariable.SetValue without any address lookup. Applying it from C++
	// would have needed the [HOOK-2] address, so it lives in the script.

	// Called once per frame from the game update hook ([HOOK-1]), if installed.
	void Update();

	static double Now();

private:
	ERCPlugin() = default;

	std::map<std::string, std::string> _settings;

	// TK Dodge RE's own ini, read only so the script can decide whether to
	// defer. ERC never writes to it.
	bool _tkdodgePresent = false;
	std::map<std::string, std::string> _tkdodge;

	bool  _inIframe      = false;
	double _iframeEndTime = 0.0;

	int   _pendingDodgeTap = -1;
};
