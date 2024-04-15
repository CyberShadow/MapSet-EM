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
	Array!(uint, uint) _;
}
