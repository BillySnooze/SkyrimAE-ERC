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

	int GetIntNative(StaticFunctionTag*, BSFixedString akKey)
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
	int ConsumeDodgeTapNative(StaticFunctionTag*)
	{
		return ERCPlugin::Get().ConsumeDodgeTap();
	}

	// --- i-frames / hit-stop ----------------------------------------------
	void RollStartedNative(StaticFunctionTag*, float afDurationSeconds)
	{
		ERCPlugin::Get().OnRollStarted(afDurationSeconds);
	}

	void TriggerHitStopNative(StaticFunctionTag*, float afSeconds)
	{
		ERCPlugin::Get().TriggerHitStop(afSeconds);
	}

	float GetTimeScaleNative(StaticFunctionTag*)
	{
		// [HOOK-2] read the game's live timescale where available.
		return 1.0f;
	}

	void SetTimeScaleNative(StaticFunctionTag*, float afValue)
	{
		// [HOOK-2] write the game's timescale where available.
		(void)afValue;
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
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, int, BSFixedString>(
		"ERC_GetInt", cls, GetIntNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, bool, BSFixedString>(
		"ERC_GetBool", cls, GetBoolNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, BSFixedString, BSFixedString>(
		"ERC_GetString", cls, GetStringNative, registry));
	registry->RegisterFunction(new NativeFunction2<StaticFunctionTag, void, BSFixedString, float>(
		"ERC_SetFloat", cls, SetFloatNative, registry));

	registry->RegisterFunction(new NativeFunction0<StaticFunctionTag, int>(
		"ERC_ConsumeDodgeTap", cls, ConsumeDodgeTapNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, void, float>(
		"ERC_RollStarted", cls, RollStartedNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, void, float>(
		"ERC_TriggerHitStop", cls, TriggerHitStopNative, registry));
	registry->RegisterFunction(new NativeFunction0<StaticFunctionTag, float>(
		"ERC_GetTimeScale", cls, GetTimeScaleNative, registry));
	registry->RegisterFunction(new NativeFunction1<StaticFunctionTag, void, float>(
		"ERC_SetTimeScale", cls, SetTimeScaleNative, registry));

	return true;
}
