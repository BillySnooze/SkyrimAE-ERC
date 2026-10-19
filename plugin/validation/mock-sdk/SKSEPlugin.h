// ============================================================================
//  MOCK SKSE SDK — FOR OFFLINE SYNTAX/TYPE VALIDATION ONLY
// ----------------------------------------------------------------------------
//  These headers are NOT the real SKSE SDK and produce nothing runnable. They
//  declare just enough of the API surface ERC uses so the plugin sources can be
//  compiled with MSVC (cl /c) to catch typos, type errors and missing symbols
//  before you build against the real SDK. See ../build-check.bat.
// ============================================================================
#pragma once

#include <cstdarg>
#include <cstdio>

struct SKSEInterface;

class SKSEPlugin
{
public:
	virtual ~SKSEPlugin() = default;
	virtual bool Init(SKSEInterface* a_skse) { (void)a_skse; return true; }
	virtual void Update(float afGameTime) { (void)afGameTime; }
	virtual void OnGameLoaded() {}
};

// Variadic logger (the real SDK provides this).
inline void Info(const char* /*fmt*/, ...) {}
