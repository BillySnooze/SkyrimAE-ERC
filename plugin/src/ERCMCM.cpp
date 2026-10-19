// ============================================================================
//  ERCMCM.cpp — MCM menu implementation for ELDEN RING COMBAT
// ----------------------------------------------------------------------------
//  Two pages of sliders/toggles. Moving a control writes the new value into the
//  plugin's settings store, persists it to EldenRingCombat.ini, and pushes an
//  ERC_SettingsChanged() call so Papyrus re-reads everything immediately.
//
//  Animation event names (the string keys) are NOT MCM-editable — they are set
//  by editing SKSEPlugins/EldenRingCombat.ini directly. See docs/BUILD.md. This
//  keeps the menu to well-supported slider/toggle controls only, so it compiles
//  cleanly across SKSE SDK versions.
//
//  NOTE ON IWMCM API: The control-construction calls below (AddPage /
//  AddSliderControl / AddToggleControl) are part of the standard, stable IWMCM
//  interface shipped with the SKSE SDK. If your SDK version names them slightly
//  differently, adjust only those call sites — the descriptor table and the
//  OnOption/OnInfoRequest logic are version-independent.
// ============================================================================

#include "ERCMCM.h"
#include "ERCPlugin.h"

#include <cstring>

ERCMCM::ERCMCM(ERCPlugin* a_plugin) : _plugin(a_plugin) {}

const CtrlDesc* ERCMCM::FindCtrl(int aiPage, int aiControl) const
{
	for (const auto& d : _ctrls)
		if (d.page == aiPage && d.control == aiControl) return &d;
	return nullptr;
}

// ----------------------------------------------------------------------------
//  Register() — override of IWMCM::Register. Build all pages and controls here,
//  recording a CtrlDesc for each so OnOption can map it to a settings key.
// ----------------------------------------------------------------------------
void ERCMCM::Register()
{
	// --- Page 0: Combat -------------------------------------------------------
	const int pCombat = AddPage("Combat");

	int c;
	c = AddSliderControl(pCombat, "Roll Stamina Cost",       0.0f, 50.0f, 1.0f);   _ctrls.push_back({pCombat, c, "RollStaminaCost",        true});
	c = AddSliderControl(pCombat, "I-Frame Fraction",        0.0f, 1.0f,  0.05f);  _ctrls.push_back({pCombat, c, "IframeFraction",         true});
	c = AddSliderControl(pCombat, "Hit-Stop Duration (s)",   0.0f, 0.3f,  0.01f);  _ctrls.push_back({pCombat, c, "HitStopSeconds",         true});
	c = AddSliderControl(pCombat, "Hit-Stop Timescale",      0.05f,1.0f,   0.05f);  _ctrls.push_back({pCombat, c, "HitStopScale",           true});
	c = AddSliderControl(pCombat, "Flinch Threshold",        0.0f, 100.0f, 1.0f);   _ctrls.push_back({pCombat, c, "StaggerFlinchThreshold", true});
	c = AddSliderControl(pCombat, "Stagger Threshold",       0.0f, 200.0f, 1.0f);   _ctrls.push_back({pCombat, c, "StaggerStaggerThreshold",true});
	c = AddSliderControl(pCombat, "Large Stagger Threshold", 0.0f, 400.0f, 1.0f);   _ctrls.push_back({pCombat, c, "StaggerLargeThreshold",  true});

	c = AddToggleControl(pCombat, "Enable Dodge Rolls");     _ctrls.push_back({pCombat, c, "EnableRolls",      false});
	c = AddToggleControl(pCombat, "Enable Hit-Stop");        _ctrls.push_back({pCombat, c, "EnableHitStop",    false});
	c = AddToggleControl(pCombat, "Enable Guard Break");     _ctrls.push_back({pCombat, c, "EnableGuardBreak", false});

	// --- Page 1: Movement -----------------------------------------------------
	const int pMove = AddPage("Movement");

	c = AddSliderControl(pMove, "Equip Load Light Cut",    0.0f, 50.0f,   1.0f);   _ctrls.push_back({pMove, c, "EquipLoadLightCut",   true});
	c = AddSliderControl(pMove, "Equip Load Medium Cut",   0.0f, 100.0f,  1.0f);   _ctrls.push_back({pMove, c, "EquipLoadMediumCut",  true});
	c = AddSliderControl(pMove, "Roll Duration Light (s)", 0.2f, 2.0f,    0.05f);  _ctrls.push_back({pMove, c, "RollDurationLight",   true});
	c = AddSliderControl(pMove, "Roll Duration Medium(s)", 0.2f, 2.0f,    0.05f);  _ctrls.push_back({pMove, c, "RollDurationMedium",  true});
	c = AddSliderControl(pMove, "Roll Duration Heavy (s)", 0.2f, 3.0f,    0.05f);  _ctrls.push_back({pMove, c, "RollDurationHeavy",   true});
	c = AddSliderControl(pMove, "Sprint Hold Threshold",   1.0f, 30.0f,   1.0f);   _ctrls.push_back({pMove, c, "SprintHoldFrames",      true});

	c = AddToggleControl(pMove, "Enable Lock-On Rolls");    _ctrls.push_back({pMove, c, "EnableLockOnRolls",   false});
}

// ----------------------------------------------------------------------------
//  OnOption — a slider/toggle changed. Write the value into the store, persist,
//  and tell Papyrus to refresh.
// ----------------------------------------------------------------------------
void ERCMCM::OnOption(int aiPage, int aiControl)
{
	const CtrlDesc* d = FindCtrl(aiPage, aiControl);
	if (!d || !_plugin) return;

	if (d->isSlider)
	{
		const float v = GetSliderValue(aiPage, aiControl);
		_plugin->SetFloat(d->key, v);
	}
	else
	{
		const bool b = GetToggleValue(aiPage, aiControl);
		_plugin->SetBool(d->key, b);
	}

	_plugin->SaveSettings();
	_plugin->CallPapyrusNoArgs("ERC_SettingsChanged");
}

// ----------------------------------------------------------------------------
//  OnInfoRequest — provide tooltip text for a control.
// ----------------------------------------------------------------------------
void ERCMCM::OnInfoRequest(int aiPage, int aiControl)
{
	const CtrlDesc* d = FindCtrl(aiPage, aiControl);
	if (!d) return;

	static const struct { const char* key; const char* info; } kInfo[] = {
		{"RollStaminaCost",        "Stamina spent when a dodge roll starts."},
		{"IframeFraction",         "Fraction of the roll that is invincible (i-frames). 0.55 = first 55%."},
		{"HitStopSeconds",         "How long the world freezes when a hit lands."},
		{"HitStopScale",           "Timescale dip applied during hit-stop (lower = stronger freeze)."},
		{"StaggerFlinchThreshold", "Damage below this causes a flinch reaction."},
		{"StaggerStaggerThreshold","Damage below this (and above flinch) causes a stagger."},
		{"StaggerLargeThreshold",  "Damage below this (and above stagger) causes a large stagger; at/above = knockdown."},
		{"EnableRolls",            "Master switch for tap-to-dodge rolls."},
		{"EnableHitStop",          "Master switch for the impact freeze."},
		{"EnableGuardBreak",       "Master switch for guard-break / stagger reactions."},
		{"EquipLoadLightCut",      "Weapon+armour weight below this = light equip load."},
		{"EquipLoadMediumCut",     "Weight below this (and above light cut) = medium; at/above = heavy."},
		{"RollDurationLight",      "Base duration of a light-load roll, in seconds. Heavier tiers roll longer/slower."},
		{"RollDurationMedium",     "Base duration of a medium-load roll, in seconds."},
		{"RollDurationHeavy",      "Base duration of a heavy-load roll, in seconds."},
		{"SprintHoldFrames",       "Dodge button held fewer frames than this = roll; at/above = sprint."},
		{"EnableLockOnRolls",      "Use facing-preserving directional rolls while locked on."},
	};

	for (const auto& e : kInfo)
		if (strcmp(e.key, d->key) == 0) { SetInfoText(aiPage, aiControl, e.info); return; }

	SetInfoText(aiPage, aiControl, "Elden Ring Combat setting.");
}
