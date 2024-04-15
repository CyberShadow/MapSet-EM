module mapset_em.storage.value;

import ae.sys.data;

import mapset_em.storage.common;

/// Fixed-size structure (like a struct).
struct Value(S)
{
	private TData!S data;

	this(string name)
	{
		data = mapData(name, S.sizeof).asDataOf!S;
	}

	@property ref S _get()
	{
		return data.unsafeContents[0];
	}

	alias _get this;
}

unittest
{
	import ae.sys.cmd : getTempFileName;
	import std.file : mkdir, rmdirRecurse;
	auto dir = getTempFileName("test");
	mkdir(dir);
	scope(exit) rmdirRecurse(dir);

	struct S { int i; }

	{
		auto a = Value!S(dir ~ "/test");
		a.i = 42;
	}

	{
		auto a = Value!S(dir ~ "/test");
		assert(a.i == 42);
	}
}
