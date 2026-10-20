// ============================================================================
//  ERCNatives.cpp — Papyrus natives registered on class "ERC_PlayerCombat"
// ----------------------------------------------------------------------------
//  Standard SKSE registration pattern (PapyrusNativeFunctions.h):
//    registry->RegisterFunction(new NativeFunctionN<Parent, Ret, Args...>(
//        "PapyrusName", "ClassName", CppFunction, registry));
//  The registry takes ownership of the function object.
// ============================================================================
#include "ERCPlugin.h"
#include "erc_compat.h"

#include "skse64/PapyrusNativeFunctions.h"
#include "skse64/PapyrusVM.h"

namespace
{
	// --- settings ---------------------------------------------------------
	float GetFloatNative(StaticFunctionTag*, BSFixedString akKey)
	{
		return ERCPlugin::Get().GetFloat(akKey.c_str());
	}

	SInt32 GetIntNative(StaticFunctionTag*, BSFixedString akKey)
	{
		return ERCPlugin::Get().GetInt(akKey.c_str());
	}

	bool GetBoolNative(StaticFunctionTag*, BSFixedString akKey)
	{
		return ERCPlugin::Get().GetBool(akKey.c_str());
	}

	BSFixedString GetStringNative(StaticFunctionTag*, BSFixedString akKey)
	{
		const std::string value = ERCPlugin::Get().GetString(akKey.c_str());
		return BSFixedString(value.c_str());
	}

	void SetFloatNative(StaticFunctionTag*, BSFixedString akKey, float afValue)
	{
		ERCPlugin::Get().SetFloat(akKey.c_str(), afValue);
	}

	// --- dodge taps (Papyrus polls this) ----------------------------------
	SInt32 ConsumeDodgeTapNative(StaticFunctionTag*)
	{
		return ERCPlugin::Get().ConsumeDodgeTap();
	}

	// --- dodge provider ----------------------------------------------------
	// True when TK Dodge RE is installed. Papyrus uses this to decide whether
	// ERC should drive its own roll or leave the roll to TK Dodge.
	bool HasTKdodgeNative(StaticFunctionTag*)
	{
		return ERCPlugin::Get().HasTKdodge();
	}

	// Re-reads Data/SKSE/Plugins/EldenRingCombat.ini and MCM Helper's
	// Data/MCM/Settings/EldenRingCombat.ini. Without this the DLL's in-memory
	// copy is whatever it read at plugin load, so every MCM slider would appear
	// to do nothing until the game was restarted.
	void ReloadSettingsNative(StaticFunctionTag*)
	{
		ERCPlugin::Get().LoadSettings();
	}

	// --- i-frames / hit-stop ----------------------------------------------
	void RollStartedNative(StaticFunctionTag*, float afDurationSeconds)
	{
		ERCPlugin::Get().OnRollStarted(afDurationSeconds);
	}
}

bool ERCRegisterNatives(VMClassRegistry* registry)
{
	if (!registry)
	{
		return false;
	}

	const char* cls = "ERC_PlayerCombat";

	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, float, BSFixedString>(
		"ERC_GetFloat", cls, GetFloatNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, SInt32, BSFixedString>(
		"ERC_GetInt", cls, GetIntNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, bool, BSFixedString>(
		"ERC_GetBool", cls, GetBoolNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, BSFixedString, BSFixedString>(
		"ERC_GetString", cls, GetStringNative, registry));
	registry->RegisterFunction(new NativeFunction2<StaticFunctionTag, void, BSFixedString, float>(
		"ERC_SetFloat", cls, SetFloatNative, registry));

	registry->RegisterFunction(new NativeFunction0<StaticFunctionTag, SInt32>(
		"ERC_ConsumeDodgeTap", cls, ConsumeDodgeTapNative, registry));
	registry->RegisterFunction(new NativeFunction0<StaticFunctionTag, bool>(
		"ERC_HasTKDodge", cls, HasTKdodgeNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, void, float>(
		"ERC_RollStarted", cls, RollStartedNative, registry));

	registry->RegisterFunction(new NativeFunction0<StaticFunctionTag, void>(
		"ERC_ReloadSettings", cls, ReloadSettingsNative, registry));
	return true;
}
