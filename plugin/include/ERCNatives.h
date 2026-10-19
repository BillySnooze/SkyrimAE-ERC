// ============================================================================
//  ERCNatives.h — Papyrus native function implementations for ERC.dll
// ----------------------------------------------------------------------------
//  Each free function below has the exact calling signature BSScript expects for
//  a native of that arity/return type. RegisterNatives() wires them into the VM.
//  The *bodies* are version-independent (they just forward to ERCPlugin). Only
//  the AddFunction registration calls in RegisterNatives() are SDK-version-
//  sensitive — see docs/BUILD.md, "Registering natives".
// ============================================================================

#pragma once

#include <BSScript_StackFrame.h>
#include <cstdint>

class ERCPlugin; // forward decl

namespace erc_natives
{
	// float  ERC_GetFloat(string)
	float      GetFloat(BSStackFrame* a_frame, const char* akKey);
	// int    ERC_GetInt(string)
	int32_t    GetInt(BSStackFrame* a_frame, const char* akKey);
	// bool   ERC_GetBool(string)
	bool       GetBool(BSStackFrame* a_frame, const char* akKey);
	// string ERC_GetString(string)
	const char* GetString(BSStackFrame* a_frame, const char* akKey);

	// void   ERC_SetFloat(string, float)
	void       SetFloat(BSStackFrame* a_frame, const char* akKey, float afValue);

	// void   ERC_OnPluginAttached()  — called once when the script is attached
	void       OnPluginAttached(BSStackFrame* a_frame);

	// void   ERC_RollStarted(float)
	void       RollStarted(BSStackFrame* a_frame, float afDurationSeconds);
	// void   ERC_RollEnded()
	void       RollEnded(BSStackFrame* a_frame);

	// void   ERC_TriggerHitStop(float)
	void       TriggerHitStop(BSStackFrame* a_frame, float afSeconds);
	// float  ERC_GetTimeScale()
	float      GetTimeScale(BSStackFrame* a_frame);
	// void   ERC_SetTimeScale(float)
	void       SetTimeScale(BSStackFrame* a_frame, float afValue);

	// Register all of the above with the Papyrus VM. Call once from Init().
	void       RegisterNatives(ERCPlugin* a_plugin);
}
