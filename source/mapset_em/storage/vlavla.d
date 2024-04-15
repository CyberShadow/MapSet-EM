module mapset_em.storage.vlavla;

import ae.sys.data;
import ae.utils.math;

import mapset_em.storage.common;
import mapset_em.storage.vla;

// Array of variable-length arrays.
struct VLAVLA(Index, size_t offsetBits, Element = ubyte)
{
	alias Offset = TypeForBits!offsetBits;
	static assert(Offset.sizeof * 8 == offsetBits, "TODO");

	VLA!(Index, Offset) index;
	VLA!(Offset, Element) data;

	this(string name)
	{
		index = typeof(index)(name ~ ".index");
		data = typeof(data)(name ~ ".data");
	}

	Element[] opIndex(Index i)
	{
		Offset start = index[i];
		Offset end = i + 1 == index.length ? data.length : index[i + 1];
		return data[start .. end];
	}

	struct AllocateResult { Element[] item; Index index; }

	AllocateResult allocate(Offset size)
	{
		auto dataAllocation = data.allocate(size);
		auto indexAllocation = index.allocate();
		*indexAllocation.ptr = dataAllocation.start;
		return AllocateResult(dataAllocation.items, indexAllocation.index);
	}
}

unittest
{
	VLAVLA!(uint, 32) _;
}
