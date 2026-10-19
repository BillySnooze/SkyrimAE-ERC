// ============================================================================
//  ERCMain.cpp — SKSE plugin entry points (official API)
// ----------------------------------------------------------------------------
//  SKSE reads SKSEPlugin_Version at load time to decide compatibility, then
//  calls SKSEPlugin_Load. There is no CreateSKSEPlugin factory in the real API.
//  Target runtime: Skyrim SE 1.6.1170 (the JOJ stock game).
// ============================================================================
#include "erc_compat.h"

#include "skse64/PluginAPI.h"
#include "skse64_common/skse_version.h"

#include "ERCPlugin.h"

extern "C" {

__declspec(dllexport) SKSEPluginVersionData SKSEPlugin_Version =
{
	SKSEPluginVersionData::kVersion,

	1,                          // plugin version
	"Elden Ring Combat",        // name
	"ERC",                      // author
	"",                         // support email

	0,                          // versionIndependenceEx
	0,                          // versionIndependence
	{ RUNTIME_VERSION_1_6_1170, 0 },   // compatible runtimes (zero-terminated)

	0,                          // minimum SKSE version
};

__declspec(dllexport) bool SKSEPlugin_Load(const SKSEInterface* skse)
{
	return ERCPlugin::Get().Init(skse);
}

}  // extern "C"
