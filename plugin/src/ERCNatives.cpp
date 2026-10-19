// ============================================================================
//  ERCNatives.cpp — Papyrus native function implementations + VM registration
// ----------------------------------------------------------------------------
//  The bodies are simple forwards to ERCPlugin and are version-independent.
//  RegisterNatives() is the one SDK-sensitive part: the exact AddFunction call
//  form depends on your SKSE/BSScript version. A typical modern-SDK pattern is
//  shown; adjust the argument-type tokens if yours differ. See docs/BUILD.md.
// ============================================================================

#include "ERCNatives.h"
#include "ERCPlugin.h"

#include <SKSE.h>
#include <BSScript_VMState.h>

namespace erc_natives
{
	// We need a pointer to the live plugin instance inside each native body.
	// The cleanest way is a file-scope pointer set in RegisterNatives().
	static ERCPlugin* g_plugin = nullptr;

	float GetFloat(BSStackFrame*, const char* akKey)
	{
		return g_plugin ? g_plugin->GetFloat(akKey) : 0.0f;
	}

	int32_t GetInt(BSStackFrame*, const char* akKey)
	{
		return g_plugin ? g_plugin->GetInt(akKey) : 0;
	}

	bool GetBool(BSStackFrame*, const char* akKey)
	{
		return g_plugin ? g_plugin->GetBool(akKey) : false;
	}

	const char* GetString(BSStackFrame*, const char* akKey)
	{
		static thread_local std::string buf;   // stable storage for the returned C-string
		if (!g_plugin) return "";
		buf = g_plugin->GetString(akKey);
		return buf.c_str();
	}

	void SetFloat(BSStackFrame*, const char* akKey, float afValue)
	{
		if (g_plugin) { g_plugin->SetFloat(akKey, afValue); g_plugin->SaveSettings(); }
	}

	void OnPluginAttached(BSStackFrame*)
	{
		if (g_plugin) g_plugin->CallPapyrusNoArgs("ERC_OnPluginAttached");
	}

	void RollStarted(BSStackFrame*, float afDurationSeconds)
	{
		if (g_plugin) g_plugin->OnRollStarted(afDurationSeconds);
	}

	void RollEnded(BSStackFrame*)
	{
		if (g_plugin) g_plugin->OnRollEnded();
	}

	void TriggerHitStop(BSStackFrame*, float afSeconds)
	{
		if (g_plugin) g_plugin->TriggerHitStop(afSeconds);
	}

	float GetTimeScale(BSStackFrame*)
	{
		return GetGameSettingFloat("fTimeScale");   // SKSE free function
	}

	void SetTimeScale(BSStackFrame*, float afValue)
	{
		SetGameSettingFloat("fTimeScale", afValue);  // SKSE free function
	}

	// ------------------------------------------------------------------------
	//  RegisterNatives — wire every native into the Papyrus VM.
	// ------------------------------------------------------------------------
	void RegisterNatives(ERCPlugin* a_plugin)
	{
		g_plugin = a_plugin;
		if (!a_plugin || !GetSKSE()->papyrusVM) return;

		auto* vm = GetSKSE()->papyrusVM;

		// [VERSION-SPECIFIC] The AddFunction signature below follows the common
		// modern SKSE SDK form:  AddFunction(name, argCount, funcPtr, retType).
		// Argument/return type tokens (kBSSType_*) come from <BSScript_Type.h>.
		// If your SDK uses a different overload, adjust ONLY these calls.

		vm->AddFunction("ERC_GetFloat",        1, &GetFloat,       kBSSType_Float);
		vm->AddFunction("ERC_GetInt",          1, &GetInt,         kBSSType_Int32);
		vm->AddFunction("ERC_GetBool",         1, &GetBool,        kBSSType_Bool);
		vm->AddFunction("ERC_GetString",       1, &GetString,      kBSSType_String);
		vm->AddFunction("ERC_SetFloat",        2, &SetFloat,       kBSSType_Void);
		vm->AddFunction("ERC_OnPluginAttached",0, &OnPluginAttached,kBSSType_Void);
		vm->AddFunction("ERC_RollStarted",     1, &RollStarted,    kBSSType_Void);
		vm->AddFunction("ERC_RollEnded",       0, &RollEnded,      kBSSType_Void);
		vm->AddFunction("ERC_TriggerHitStop",  1, &TriggerHitStop, kBSSType_Void);
		vm->AddFunction("ERC_GetTimeScale",    0, &GetTimeScale,   kBSSType_Float);
		vm->AddFunction("ERC_SetTimeScale",    1, &SetTimeScale,   kBSSType_Void);
	}
}
