// ============================================================================
//  MOCK SKSE SDK — OFFLINE COMPILE VALIDATION ONLY
// ----------------------------------------------------------------------------
//  Self-authored stand-in that mirrors the parts of the real SKSE 2.x
//  PluginAPI.h this plugin uses. It is NOT the SKSE SDK and produces nothing
//  runnable. It exists so `build-check.bat` can type-check the plugin without
//  the SDK's `common` submodule.
//
//  The entry points in ERCMain.cpp were additionally verified to compile
//  against the GENUINE SKSE 2.2.6 PluginAPI.h.
// ============================================================================
#pragma once

#include <cstdint>

typedef std::uint8_t  UInt8;
typedef std::uint32_t UInt32;
typedef std::uint64_t UInt64;

typedef UInt32 PluginHandle;

class VMClassRegistry;

struct PluginInfo
{
	enum { kInfoVersion = 1 };
	UInt32      infoVersion;
	const char* name;
	UInt32      version;
};

enum
{
	kPluginHandle_Invalid = 0xFFFFFFFF
};

enum
{
	kInterface_Invalid = 0,
	kInterface_Scaleform,
	kInterface_Papyrus,
	kInterface_Serialization,
	kInterface_Task,
	kInterface_Messaging,
	kInterface_Object,
	kInterface_Trampoline,
	kInterface_Max,
};

struct SKSEInterface
{
	UInt32 skseVersion;
	UInt32 runtimeVersion;
	UInt32 editorVersion;
	UInt32 isEditor;
	void* (*QueryInterface)(UInt32 id);
	PluginHandle (*GetPluginHandle)(void);
	UInt32 (*GetReleaseIndex)(void);
	const PluginInfo* (*GetPluginInfo)(const char* name);
};

struct SKSEPapyrusInterface
{
	enum { kInterfaceVersion = 1 };
	UInt32 interfaceVersion;
	typedef bool (*RegisterFunctions)(VMClassRegistry* registry);
	bool (*Register)(RegisterFunctions callback);
};

struct SKSEMessagingInterface
{
	struct Message
	{
		const char* sender;
		UInt32      type;
		UInt32      dataLen;
		void*       data;
	};

	typedef void (*EventCallback)(Message* msg);

	enum { kInterfaceVersion = 2 };

	enum
	{
		kMessage_PostLoad,
		kMessage_PostPostLoad,
		kMessage_PreLoadGame,
		kMessage_PostLoadGame,
		kMessage_SaveGame,
		kMessage_DeleteGame,
		kMessage_InputLoaded,
		kMessage_NewGame,
		kMessage_DataLoaded
	};

	UInt32 interfaceVersion;
	bool (*RegisterListener)(PluginHandle listener, const char* sender, EventCallback handler);
	bool (*Dispatch)(PluginHandle sender, UInt32 messageType, void* data, UInt32 dataLen, const char* receiver);
};

struct SKSEPluginVersionData
{
	enum { kVersion = 1 };

	UInt32 dataVersion;
	UInt32 pluginVersion;
	char   name[256];
	char   author[256];
	char   supportEmail[252];
	UInt32 versionIndependenceEx;
	UInt32 versionIndependence;
	UInt32 compatibleVersions[16];
	UInt32 seVersionRequired;
};
