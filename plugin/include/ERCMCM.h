// ============================================================================
//  ERCMCM.h — MCM (IWMCM) menu for ELDEN RING COMBAT
// ----------------------------------------------------------------------------
//  Exposes every tunable as a slider or toggle. The menu is the *editor* for
//  the plugin's settings store: moving a slider calls back into ERCPlugin to
//  update the value, which Papyrus then re-reads on the next event (and the
//  plugin pushes an ERC_SettingsChanged() call so it refreshes immediately).
//
//  Layout:
//    Page 0 "Combat"   : rolls, i-frames, hit-stop, stagger tiers
//    Page 1 "Movement" : equip-load thresholds, roll rates/durations, lock-on
//    Page 2 "Animations": animation event names (text fields)
// ============================================================================

#pragma once

#include <IWMCM.h>
#include <string>
#include <vector>

class ERCPlugin; // forward decl

// Describes one MCM control and the settings key it edits. This table is the
// version-independent "spec" of the menu: OnOption maps (page, control) -> key
// through it. The actual IWMCM construction of pages/controls is SDK-specific
// and lives in Register() (see ERCMCM.cpp).
struct CtrlDesc
{
	int         page;
	int         control;
	const char* key;
	bool        isSlider;   // true = slider, false = toggle
};

class ERCMCM : public IWMCM
{
public:
	ERCMCM(ERCPlugin* a_plugin);

	// --- IWMCM interface ------------------------------------------------------
	const char* GetName() const override { return "Elden Ring Combat"; }
	void        OnOption(int aiPage, int aiControl) override;   // slider/toggle changed
	void        OnInfoRequest(int aiPage, int aiControl) override; // tooltip text

	// Override of IWMCM::Register — build all pages/controls here (see .cpp).
	void Register() override;

private:
	ERCPlugin* _plugin = nullptr;

	// The control descriptor table (page, control index, settings key).
	std::vector<CtrlDesc> _ctrls;

	const CtrlDesc* FindCtrl(int aiPage, int aiControl) const;
};
