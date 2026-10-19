// MOCK SKSE SDK — see skse64/PluginAPI.h. Validation only.
// Mirrors the registration surface of the real PapyrusNativeFunctions.h.
#pragma once

#include <string>

#include "PapyrusVM.h"

class BSFixedString
{
public:
	BSFixedString() = default;
	BSFixedString(const char* a_str) : _str(a_str ? a_str : "") {}

	const char* c_str() const { return _str.c_str(); }

private:
	std::string _str;
};

class StaticFunctionTag
{
};

template <typename Parent, typename Ret>
class NativeFunction0
{
public:
	NativeFunction0(const char*, const char*, Ret (*)(Parent*), VMClassRegistry*) {}
};

template <typename Parent, typename Ret, typename A1>
class NativeFunction1
{
public:
	NativeFunction1(const char*, const char*, Ret (*)(Parent*, A1), VMClassRegistry*) {}
};

template <typename Parent, typename Ret, typename A1, typename A2>
class NativeFunction2
{
public:
	NativeFunction2(const char*, const char*, Ret (*)(Parent*, A1, A2), VMClassRegistry*) {}
};
