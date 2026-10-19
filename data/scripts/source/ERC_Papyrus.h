// ============================================================================
//  ERC_Papyrus.h — Native function declarations for CK script compilation
// ----------------------------------------------------------------------------
//  Place this file in your CK project's Script/ folder (or add its directory
//  to the include path). It declares the native functions implemented by
//  ERC.dll so that CK can type-check calls to them across multiple scripts.
//
//  NOTE: For a single-script mod like this one, CK will compile fine without
//  this header (the `native` keyword in the .psc is sufficient). This file is
//  provided for documentation clarity and for future multi-script expansion.
// ============================================================================

#pragma once

// --- Settings getters (read from the plugin's value store / MCM) -----------
float      ERC_GetFloat(const char* akKey);
int32_t    ERC_GetInt(const char* akKey);
bool       ERC_GetBool(const char* akKey);
const char* ERC_GetString(const char* akKey);

// --- Settings setter (pushed from MCM or external tools) --------------------
void       ERC_SetFloat(const char* akKey, float afValue);

// --- Roll / i-frame lifecycle -----------------------------------------------
void       ERC_RollStarted(float afDurationSeconds);
void       ERC_RollEnded();

// --- Hit-stop ----------------------------------------------------------------
void       ERC_TriggerHitStop(float afSeconds);
float      ERC_GetTimeScale();
void       ERC_SetTimeScale(float afValue);
