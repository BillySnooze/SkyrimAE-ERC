// ============================================================================
//  MOCK IWMCM — FOR OFFLINE SYNTAX/TYPE VALIDATION ONLY (see SKSEPlugin.h)
// ----------------------------------------------------------------------------
//  Declares the IWMCM surface ERCMCM.cpp uses. The real interface also carries
//  page/control construction; the names below must match it. Validation only.
// ============================================================================
#pragma once

class IWMCM
{
public:
	virtual ~IWMCM() = default;

	// Pure virtuals the menu class overrides.
	virtual const char* GetName() const = 0;
	virtual void OnOption(int aiPage, int aiControl) = 0;
	virtual void OnInfoRequest(int aiPage, int aiControl) = 0;
	virtual void Register() = 0;

	// Helpers the real interface provides for building the menu.
	int   AddPage(const char* /*name*/) { return 0; }
	int   AddSliderControl(int /*page*/, const char* /*name*/, float /*min*/, float /*max*/, float /*step*/) { return 0; }
	int   AddToggleControl(int /*page*/, const char* /*name*/) { return 0; }
	float GetSliderValue(int /*page*/, int /*control*/) { return 0.0f; }
	bool  GetToggleValue(int /*page*/, int /*control*/) { return false; }
	void  SetInfoText(int /*page*/, int /*control*/, const char* /*text*/) {}
};
