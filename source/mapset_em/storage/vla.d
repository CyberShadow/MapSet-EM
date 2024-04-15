module mapset_em.storage.vla;

import mapset_em.storage.array;
import mapset_em.storage.common;
import mapset_em.storage.value;

import ae.sys.data;
import ae.utils.math : TypeForBits;

/// Array (with length).
struct VLA(Index, Item)
{
	struct Metadata
	{
		Index length;
	}
	Value!Metadata metadata;

	Array!(Index, Item) data;

	this(string name)
	{
		metadata = typeof(metadata)(name ~ ".metadata");
		data = typeof(data)(name ~ ".data");
	}

	@property Index length() { return metadata.length; }

	Item[] opSlice()
	{
		return data[0 .. length];
	}

	ref Item opIndex(Index index)
	{
		return data[index];
	}

	Item[] opSlice(Index start, Index end)
	{
		return data[start .. end];
	}

	struct AllocateOneResult { Item* ptr; Index index; }

	AllocateOneResult allocate() @nogc
	{
		auto index = metadata.length++;
		if (metadata.length == 0)
			assert(false, "VLA maximum length exceeded");
		auto item = &data[index];
		return AllocateOneResult(item, index);
	}

	struct AllocateNResult { Item[] items; Index start, end; }

	AllocateNResult allocate(Index count) @nogc
	{
		auto oldLength = metadata.length;
		auto newLength = oldLength; newLength += count;
		auto storage = data[];
		auto maxLength = storage.length;
		if (newLength < oldLength || newLength > maxLength)
			assert(false, "VLA maximum length exceeded");
		metadata.length = newLength;
		auto items = storage[oldLength .. newLength];
		return AllocateNResult(items, oldLength, newLength);
	}
}

unittest
{
	VLA!(uint, uint) _;
}
