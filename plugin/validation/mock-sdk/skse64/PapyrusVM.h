// MOCK SKSE SDK — see skse64/PluginAPI.h. Validation only.
#pragma once

class IFunction
{
public:
	virtual ~IFunction() = default;
};

class VMClassRegistry
{
public:
	// The real registry takes ownership of the function object.
	template <typename Fn>
	bool RegisterFunction(Fn* fn)
	{
		delete fn;
		return true;
	}
};
