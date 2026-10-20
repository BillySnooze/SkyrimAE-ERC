#include "ERCPlugin.h"
#include "erc_compat.h"

#include <Windows.h>

#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>

#include "skse64/PluginAPI.h"

// ----------------------------------------------------------------------------
//  Logging — OutputDebugString keeps this dependency-free (view with DbgView).
// ----------------------------------------------------------------------------
static void ERC_Log(const std::string& msg)
{
	OutputDebugStringA(("[ERC] " + msg + "\n").c_str());
}

// ----------------------------------------------------------------------------
//  Paths (relative to the game root, which is the working directory).
// ----------------------------------------------------------------------------
static const char* kPluginIni = "Data\\SKSE\\Plugins\\EldenRingCombat.ini";
static const char* kMcmIni    = "Data\\MCM\\Settings\\EldenRingCombat.ini";
static const char* kTKdodgeIni = "Data\\SKSE\\Plugins\\TK Dodge RE.ini";

ERCPlugin& ERCPlugin::Get()
{
	static ERCPlugin instance;
	return instance;
}

double ERCPlugin::Now()
{
	// Wall clock is enough for i-frame / hit-stop windows and is independent of
	// game timescale (which hit-stop itself changes).
	return static_cast<double>(GetTickCount64()) / 1000.0;
}

// ----------------------------------------------------------------------------
//  Settings
// ----------------------------------------------------------------------------
static void Defaults(std::map<std::string, std::string>& s)
{
	s["RollStaminaCost"]        = "12";
	s["IframeFraction"]         = "0.55";
	s["HitStopSeconds"]         = "0.06";
	s["HitStopScale"]           = "0.15";
	s["SprintHoldSeconds"]      = "0.25";
	s["DodgeKeyCode"]           = "56";   // DirectInput scan code: 56 = Left Alt

	s["StaggerFlinchThreshold"] = "8";
	s["StaggerStaggerThreshold"] = "20";
	s["StaggerLargeThreshold"]  = "40";
	s["KnockdownHealthFraction"] = "0.35";

	s["EnableRolls"]            = "true";
	s["EnableHitStop"]          = "true";
	s["EnableGuardBreak"]       = "true";
	s["EnableLockOnRolls"]      = "true";
	s["DeferDodgeToTKDodge"]    = "true";

	s["AnimFlinch"]             = "HitReaction_Flinch";
	s["AnimStagger"]            = "HitReaction_Stagger";
	s["AnimLargeStagger"]       = "HitReaction_LargeStagger";
	s["AnimKnockdown"]          = "HitReaction_Knockdown";

	s["RollLightFront"]         = "ERC_Roll_Light_Front";
	s["RollMediumFront"]        = "ERC_Roll_Medium_Front";
	s["RollHeavyFront"]         = "ERC_Roll_Heavy_Front";

	s["RollDurationLight"]      = "0.62";
	s["RollDurationMedium"]     = "0.78";
	s["RollDurationHeavy"]      = "1.05";

	s["EquipLoadLightCut"]      = "0.30";
	s["EquipLoadMediumCut"]     = "0.70";
}

static std::string Trim(const std::string& in)
{
	const char* ws = " \t\r\n";
	const auto  b  = in.find_first_not_of(ws);
	if (b == std::string::npos)
	{
		return std::string();
	}
	const auto e = in.find_last_not_of(ws);
	return in.substr(b, e - b + 1);
}

// Presence check that works through MO2's virtual file system, exactly like the
// ini reads above: the plugin runs with the game root as its working directory.
static bool FileExists(const char* path)
{
	std::ifstream file(path);
	return file.is_open();
}

// Reads a simple "key = value" ini. MCM Helper writes ids with a type prefix
// (f/i/b/s); we strip a leading prefix char so "fRollStaminaCost" maps to the
// same setting as "RollStaminaCost".
static void LoadIniFile(const char* path, std::map<std::string, std::string>& out, bool stripPrefix)
{
	std::ifstream file(path);
	if (!file.is_open())
	{
		return;
	}

	std::string line;
	while (std::getline(file, line))
	{
		const std::string t = Trim(line);
		if (t.empty() || t[0] == ';' || t[0] == '#' || t[0] == '[')
		{
			continue;
		}

		const auto eq = t.find('=');
		if (eq == std::string::npos)
		{
			continue;
		}

		std::string key = Trim(t.substr(0, eq));
		std::string val = Trim(t.substr(eq + 1));

		if (stripPrefix && key.size() > 1)
		{
			const char p = key[0];
			if (p == 'f' || p == 'i' || p == 'b' || p == 's')
			{
				key = key.substr(1);
			}
		}

		out[key] = val;
	}
}

void ERCPlugin::LoadSettings()
{
	_settings.clear();
	Defaults(_settings);

	// Plugin ini first, then MCM Helper's settings (user choices win).
	LoadIniFile(kPluginIni, _settings, false);
	LoadIniFile(kMcmIni, _settings, true);

	// Is TK Dodge RE installed? It owns the roll in JOJ (animation, stamina and
	// i-frames), so ERC only runs its own roll when it is absent. Read-only:
	// ERC never writes TK Dodge's ini.
	_tkdodge.clear();
	_tkdodgePresent = FileExists(kTKdodgeIni);
	if (_tkdodgePresent)
	{
		LoadIniFile(kTKdodgeIni, _tkdodge, false);
		std::ostringstream msg;
		msg << "TK Dodge RE detected (hotkey " << static_cast<int>(TKdodgeFloat("DodgeHotkey"))
			<< ", stamina " << TKdodgeFloat("DodgeStamina")
			<< ", i-frames " << TKdodgeFloat("iFrameDuration")
			<< "s) - ERC defers the roll to it";
		ERC_Log(msg.str());
	}
	else
	{
		ERC_Log("TK Dodge RE not found - ERC runs its own roll; its animation "
		        "events must exist in the behaviour graph or nothing will play");
	}

	ERC_Log("settings loaded");
}

float ERCPlugin::TKdodgeFloat(const std::string& key) const
{
	const auto it = _tkdodge.find(key);
	return (it == _tkdodge.end()) ? 0.0f : static_cast<float>(std::atof(it->second.c_str()));
}

float ERCPlugin::GetFloat(const std::string& key) const
{
	const auto it = _settings.find(key);
	return (it == _settings.end()) ? 0.0f : static_cast<float>(std::atof(it->second.c_str()));
}

int ERCPlugin::GetInt(const std::string& key) const
{
	const auto it = _settings.find(key);
	return (it == _settings.end()) ? 0 : std::atoi(it->second.c_str());
}

bool ERCPlugin::GetBool(const std::string& key) const
{
	const auto it = _settings.find(key);
	if (it == _settings.end())
	{
		return false;
	}
	const std::string v = it->second;
	return v == "1" || v == "true" || v == "True" || v == "yes";
}

std::string ERCPlugin::GetString(const std::string& key) const
{
	const auto it = _settings.find(key);
	return (it == _settings.end()) ? std::string() : it->second;
}

void ERCPlugin::SetFloat(const std::string& key, float value)
{
	std::ostringstream ss;
	ss << value;
	_settings[key] = ss.str();
}

// ----------------------------------------------------------------------------
//  Dodge taps
// ----------------------------------------------------------------------------
void ERCPlugin::QueueDodgeTap(int direction)
{
	_pendingDodgeTap = direction;
}

int ERCPlugin::ConsumeDodgeTap()
{
	const int d = _pendingDodgeTap;
	_pendingDodgeTap = -1;
	return d;
}

// ----------------------------------------------------------------------------
//  I-frames
// ----------------------------------------------------------------------------
void ERCPlugin::OnRollStarted(float durationSeconds)
{
	if (durationSeconds <= 0.0f)
	{
		return;
	}
	_inIframe       = true;
	_iframeEndTime  = Now() + (durationSeconds * GetFloat("IframeFraction"));
}

void ERCPlugin::OnRollEnded()
{
	_inIframe      = false;
	_iframeEndTime = 0.0;
}

bool ERCPlugin::InIframeWindow() const
{
	return _inIframe && (Now() < _iframeEndTime);
}

// ----------------------------------------------------------------------------
//  Hit-stop
// ----------------------------------------------------------------------------
// [HOOK-2] Applying the timescale dip needs the game's own timescale setting.
// The official plugin API exposes no call for that, so this is the version-
// specific part (CommonLibSSE-NG's Calendar, or a signature-scanned global).
// It is deliberately isolated here and logs nothing per frame.
static void ApplyTimeScale(float scale)
{
	(void)scale;
	// TODO(HOOK-2): set the game's fTimeScale equivalent. See docs/BUILD.md.
}

void ERCPlugin::TriggerHitStop(float seconds)
{
	if (seconds <= 0.0f)
	{
		return;
	}
	if (!_hitStopActive)
	{
		_savedTimeScale = 1.0f;
	}
	_hitStopActive = true;
	_hitStopEndTime = Now() + seconds;
	ApplyTimeScale(GetFloat("HitStopScale"));
}

// ----------------------------------------------------------------------------
//  Tick
// ----------------------------------------------------------------------------
void ERCPlugin::Update()
{
	if (_inIframe && Now() >= _iframeEndTime)
	{
		OnRollEnded();
	}

	if (_hitStopActive && Now() >= _hitStopEndTime)
	{
		_hitStopActive = false;
		ApplyTimeScale(_savedTimeScale);
	}
}

// ----------------------------------------------------------------------------
//  SKSE entry
// ----------------------------------------------------------------------------
static void OnSKSEMessage(SKSEMessagingInterface::Message* msg)
{
	if (msg && msg->type == SKSEMessagingInterface::kMessage_PostLoadGame)
	{
		ERCPlugin::Get().LoadSettings();
	}
}

bool ERCPlugin::Init(const SKSEInterface* skse)
{
	if (!skse)
	{
		return false;
	}

	LoadSettings();

	auto* papyrus = static_cast<SKSEPapyrusInterface*>(skse->QueryInterface(kInterface_Papyrus));
	if (!papyrus)
	{
		ERC_Log("Papyrus interface unavailable");
		return false;
	}

	extern bool ERCRegisterNatives(VMClassRegistry*);
	if (!papyrus->Register(ERCRegisterNatives))
	{
		ERC_Log("native registration failed");
		return false;
	}

	auto* messaging = static_cast<SKSEMessagingInterface*>(skse->QueryInterface(kInterface_Messaging));
	if (messaging)
	{
		messaging->RegisterListener(skse->GetPluginHandle(), "SKSE", OnSKSEMessage);
	}

	ERC_Log("loaded");
	return true;
}
