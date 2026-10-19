// MOCK SKSE SDK — see SKSEPlugin.h header comment. Validation only.
#pragma once

#include <cstdint>

namespace BSScript
{
	class StackFrame
	{
	public:
		explicit StackFrame(void* /*vm*/) {}
		void Push(float) {}
		void Push(int32_t) {}
	};
}

// The plugin's native functions take a BSStackFrame*; alias it to the mock type.
typedef BSScript::StackFrame BSStackFrame;
