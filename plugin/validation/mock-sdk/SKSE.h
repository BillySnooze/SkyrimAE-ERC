// MOCK SKSE SDK — see SKSEPlugin.h header comment. Validation only.
#pragma once

#include <cstdint>
#include <string>

#include "SKSEPlugin.h"
#include "BSScript_StackFrame.h"

typedef int32_t BSScriptObjectHandle;
static const BSScriptObjectHandle kBSInvalidHandle = -1;

enum BSScriptType
{
	kBSSType_Void = 0,
	kBSSType_Bool,
	kBSSType_Int32,
	kBSSType_Float,
	kBSSType_String
};

class PapyrusVM
{
public:
	template <typename Fn>
	void AddFunction(const char* /*name*/, int /*argc*/, Fn /*fn*/, BSScriptType /*ret*/) {}

	BSScriptObjectHandle GetPlayerScript() { return kBSInvalidHandle; }
	void AttachScript(BSScriptObjectHandle /*handle*/, const char* /*script*/) {}
	BSScriptObjectHandle GetFunctionByName(BSScriptObjectHandle /*handle*/, const char* /*fn*/) { return kBSInvalidHandle; }
	void CallFunction(BSScriptObjectHandle /*fn*/, BSScriptObjectHandle /*self*/, BSScript::StackFrame* /*frame*/, int /*argc*/) {}
};

struct SKSEInterface
{
	PapyrusVM* papyrusVM = nullptr;
};

inline SKSEInterface* GetSKSE() { static SKSEInterface s; return &s; }
inline float GetGameTime() { return 0.0f; }
inline float GetGameSettingFloat(const char* /*name*/) { return 1.0f; }
inline void  SetGameSettingFloat(const char* /*name*/, float /*v*/) {}
