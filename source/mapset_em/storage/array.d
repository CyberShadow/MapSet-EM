module mapset_em.storage.array;

import mapset_em.storage.common;
import mapset_em.storage.value;

import ae.sys.data;
import ae.utils.math : TypeForBits;

/// Length-less array.
struct Array(Index, Item)
{
	private TData!Item data;

	this(string name)
	{
		ulong maxSize = Item.sizeof * (ulong(Index.max) + 1);
		if (maxSize / Item.sizeof == 0 || maxSize / Item.sizeof - 1 != Index.max)
		{
			// Overflow
			maxSize = maxMapSize / Item.sizeof * Item.sizeof;
		}
		data = mapData(name, maxSize).asDataOf!Item;
	}

	@property Item[] _get()
	{
		return data.unsafeContents;
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

	{
		auto a = Array!(uint, uint)(dir ~ "/test");
		a[17] = 42;
	}

	{
		auto a = Array!(uint, uint)(dir ~ "/test");
		assert(a[17] == 42);
	}
}
