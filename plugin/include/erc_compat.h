// ============================================================================
//  erc_compat.h — base types for the offline mock build
// ----------------------------------------------------------------------------
//  The real SKSE SDK supplies UInt32/UInt64/... (and <string>) through
//  common/IPrefix.h, which is a FORCED include in SKSE's own projects. When
//  building against the real SDK we therefore define nothing here.
//
//  Only the offline mock build (plugin/validation/build-check.bat) defines
//  ERC_MOCK_SDK and needs these stand-ins.
// ============================================================================
#pragma once

#include <cstdint>
#include <string>

#ifdef ERC_MOCK_SDK

using UInt8  = std::uint8_t;
using UInt16 = std::uint16_t;
using UInt32 = std::uint32_t;
using UInt64 = std::uint64_t;

using SInt8  = std::int8_t;
using SInt16 = std::int16_t;
using SInt32 = std::int32_t;
using SInt64 = std::int64_t;

#endif  // ERC_MOCK_SDK
