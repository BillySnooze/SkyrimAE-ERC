// ============================================================================
//  erc_compat.h — base types the SKSE headers assume
// ----------------------------------------------------------------------------
//  The official SKSE plugin SDK expects UInt32/UInt64/... and <string> to already
//  be visible (normally via SKSE's prelude). Including this first makes the
//  plugin build both against the real SDK and the offline mock in
//  plugin/validation/mock-sdk/.
// ============================================================================
#pragma once

#include <cstdint>
#include <string>

using UInt8  = std::uint8_t;
using UInt16 = std::uint16_t;
using UInt32 = std::uint32_t;
using UInt64 = std::uint64_t;

using SInt8  = std::int8_t;
using SInt16 = std::int16_t;
using SInt32 = std::int32_t;
using SInt64 = std::int64_t;
