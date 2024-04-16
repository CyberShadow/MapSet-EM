module mapset_em.storage.btree;

import std.algorithm.comparison : max;

import ae.sys.data;
import ae.utils.math;

import mapset_em.storage.common;
import mapset_em.storage.value;
import mapset_em.storage.vla;

// debug debug = btree;

// B-tree.
struct BTree(Key, Value, size_t blockIndexBits, size_t blockSize = 4096)
{
	alias BlockIndex = TypeForBits!blockIndexBits;
	static assert(BlockIndex.sizeof * 8 == blockIndexBits, "TODO");

	struct Metadata
	{
		BlockIndex rootBlock;
		BlockIndex depth;
	}
	.Value!Metadata metadata;

	// Non-leaf node items
	align(1)
	struct TrunkItem
	{
	align(1):
		// Keys in the block at `blockIndex` are all >= `keyLowerBound`.
		// Does not necessarily imply that keys in the previous block are < `keyLowerBound`!
		// (Just that they are <= `keyLowerBound`.)
		Key keyLowerBound;
		BlockIndex blockIndex;
	}

	// Leaf node items
	align(1)
	struct LeafItem
	{
	align(1):
		Key key;
		Value value;
	}

	// Upper bounds for numTrunkItems / numLeafItems - to avoid a circular reference
	enum upperTrunkItems = (blockSize - 1) / TrunkItem.sizeof;
	enum upperLeafItems = (blockSize - 1) / LeafItem.sizeof;
	alias BlockItemIndex = TypeForBits!(bitsFor(max(upperTrunkItems, upperLeafItems)));

	union Block
	{
		ubyte[blockSize] bytes;

		align(1)
		struct
		{
			align(1):

			struct Metadata
			{
				BlockItemIndex count;
			}
			Metadata metadata;

			enum itemsSize = blockSize - Metadata.sizeof;

			enum numTrunkItems = itemsSize / TrunkItem.sizeof;
			static assert(numTrunkItems >= 2, "Key too big");

			enum numLeafItems = itemsSize / LeafItem.sizeof;
			static assert(numLeafItems >= 2, "Key and Value too big");

			// Whether a block is leaf or not implicit based on the B-tree depth.
			// A B-tree of depth 0 only has one leaf node.
			union
			{
				TrunkItem[numTrunkItems] trunkItems;
				LeafItem[numLeafItems] leafItems;
			}

			template items(bool isLeaf)
			{
				static if (isLeaf)
					alias items = leafItems;
				else
					alias items = trunkItems;
			}

			/// Return the range of item indices (within `this.*Items`) for which `pred` returns `0`.
			/// `pred` should return -1 if the given item's key is too small, and +1 if too large.
			BlockItemIndex[2] find(bool isLeaf)(scope int delegate(BlockItemIndex) nothrow @nogc pred) const nothrow @nogc
			{
				debug if (metadata.count > 0)
					foreach (BlockItemIndex j; 1 .. metadata.count)
					{
						auto i = j; i--;
						assert(pred(i) <= pred(j));
					}

				// First, find the start of the range.
				// Binary search:
				BlockItemIndex start = 0, end = metadata.count;
				while (start < end)
				{
					auto mid = end; mid -= start; mid /= 2; mid += start;
					assert(start <= mid && mid < end);
					auto midResult = pred(mid);
					if (midResult < 0) // key < items[mid].key
					{
						start = mid; start++;
					}
					else
					{
						end = mid;
					}
				}
				assert(start == end);
				// Now find the end. Assume that the range is small, so use a linear search.
				while (end < metadata.count && pred(end) == 0)
					end++;
				assert(start <= end);
				return [start, end];
			}

			/// Return the range of element indices (within `this.*Items`)
			/// which have the given `key`, or if `key` is not present,
			/// then the 0-length range representing the index of the item
			/// before which it should be inserted.
			BlockItemIndex[2] findExactly(bool isLeaf)(Key key) const nothrow @nogc
			{
				static assert(isLeaf, "This operation only makes sense for leaf nodes");
				return find!isLeaf((BlockItemIndex itemIndex) {
					auto itemKey = items!isLeaf[itemIndex].key;
					//      3  5  7
					// ---------------
					//  4: -1  1  1
					//  5: -1  0  1
					//  6: -1 -1  1
					return key > itemKey ? -1 : key < itemKey ? +1 : 0;
				});
			}

			// BlockItemIndex findInsertionPoint(bool isLeaf)(Key key) const nothrow @nogc
			// {
			// 	auto result = find!isLeaf((BlockItemIndex itemIndex) {
			// 		auto item = &items!isLeaf[itemIndex];
			// 		static if (isLeaf)
			// 			//      3  5  7
			// 			// ---------------
			// 			//  4: -1  1  1
			// 			//  5: -1 -1  1
			// 			//  6: -1 -1  1
			// 			return item.key <= key ? -1 : +1;
			// 		else
			// 			//      3  5  7
			// 			// ---------------
			// 			//  4: 
			// 			//  5: -1 -1  1
			// 			//  6: -1 -1  1
			// 			return item.key <= key ? -1 : +1;
			// 	});
			// 	assert(result[0] == result[1]);
			// 	return result[0];
			// }

			/// Return the range of element indices (for a non-leaf node)
			/// which could potentially contain `key`.
			BlockItemIndex[2] findChildren(bool isLeaf)(Key key) const nothrow @nogc
			{
				static assert(!isLeaf, "This operation only makes sense for non-leaf nodes");
				return find!isLeaf((BlockItemIndex itemIndex) {

					//      3  5  7
					// ---------------
					//  2:  1  1  1
					//  3:  0  1  1
					//  4:  0  1  1
					//  5:  0  0  1
					//  6: -1  0  1
					//  7: -1  0  0
					//  8: -1 -1  0

					auto itemKeyLowerBound = items!isLeaf[itemIndex].keyLowerBound;
					if (key < itemKeyLowerBound) // the bound is inclusive
						return +1;
					if (itemIndex + 1 < metadata.count)
					{
						auto itemKeyUpperBound = items!isLeaf[itemIndex + 1].keyLowerBound;
						if (itemKeyUpperBound < key) // the bound is inclusive on this side too
							return -1;
					}
					return 0;
				});
			}

			auto insert(bool isLeaf)(BlockItemIndex itemIndex)
			{
				assert(itemIndex <= metadata.count);
				if (metadata.count + 1 == items!isLeaf.length)
					return null; // No room
				foreach_reverse (i; itemIndex .. metadata.count)
					items!isLeaf[i + 1] = items!isLeaf[i];
				metadata.count++;
				return &items!isLeaf[itemIndex];
			}
		}
	}
	static assert(Block.sizeof == blockSize);

	VLA!(BlockIndex, Block) blocks;

	this(string name)
	{
		blocks = typeof(blocks)(name ~ ".blocks");
		metadata = typeof(metadata)(name ~ ".metadata");

		// Ensure the initial root block is allocated
		if (blocks.length == 0)
		{
			assert(metadata.rootBlock == 0);
			auto rootBlockAllocation = blocks.allocate();
			assert(rootBlockAllocation.index == 0);
		}
	}

	/// Iterate over all B-tree entries with the given `Key`.
	void findAll(Key key, scope void delegate(ref Value) /*nothrow @nogc*/ callback) //nothrow @nogc
	{
		void search(ref Block node, const BlockIndex remainingDepth /*, Key start, Key end*/) //nothrow @nogc
		{
			void impl(bool isLeaf)()
			{
				if (node.metadata.count > 0)
				{
					// assert(node.items!isLeaf[0].key >= start);
					// assert(node.items!isLeaf[node.metadata.count - 1].key < end);
				}

				static if (isLeaf)
					auto range = node.findExactly !isLeaf(key);
				else
					auto range = node.findChildren!isLeaf(key);

				foreach (itemIndex; range[0] .. range[1])
				{
					auto item = &node.items!isLeaf[itemIndex];
					// auto itemStart = itemIndex ? item.key : start;
					// auto itemEnd = itemIndex < node.metadata.count ? node.items!isLeaf[itemIndex + 1].key : end;

					static if (isLeaf)
					{
						assert(remainingDepth == 0);
						callback(item.value);
					}
					else
					{
						assert(remainingDepth > 0);
						BlockIndex childRemainingDepth = remainingDepth; childRemainingDepth--;
						search(blocks[item.blockIndex], childRemainingDepth/*, itemStart, itemEnd*/);
					}
				}
			}

			bool isLeaf = remainingDepth == 0;
			return isLeaf ? impl!true : impl!false;
		}

		return search(blocks[metadata.rootBlock], metadata.depth/*, Key.min, Key.max*/);
	}

	/// Add the given key/value pair to the B-tree.
	void add(Key key, Value value) nothrow @nogc
	{
		debug(btree) dumpToStderr(&dump, ">>> putValue before: ");

		void splitNode(ref Block parent, bool childIsLeaf, BlockItemIndex childItemIndex) @nogc
		{
			assert(parent.metadata.count + 1 < Block.trunkItems.length);
			auto leftIndex = parent.trunkItems[childItemIndex].blockIndex;
			auto leftNode = &blocks[leftIndex];
			auto rightAllocation = blocks.allocate();
			auto rightIndex = rightAllocation.index;
			auto rightNode = rightAllocation.ptr;
			assert(rightNode.metadata.count == 0);
			auto pivotItemIndex = leftNode.metadata.count; pivotItemIndex /= 2;
			assert(pivotItemIndex > 0);
			Key pivot;
			// Save pivot and move nodes from left to right
			if (childIsLeaf)
			{
				enum isLeaf = true;
				pivot = leftNode.items!isLeaf[pivotItemIndex].key;
				rightNode.items!isLeaf[0 .. leftNode.metadata.count - pivotItemIndex] =
					leftNode.items!isLeaf[pivotItemIndex .. leftNode.metadata.count];
			}
			else
			{
				enum isLeaf = false;
				pivot = leftNode.items!isLeaf[pivotItemIndex].keyLowerBound;
				rightNode.items!isLeaf[0 .. leftNode.metadata.count - pivotItemIndex] =
					leftNode.items!isLeaf[pivotItemIndex .. leftNode.metadata.count];
			}
			// Fix right node's metadata
			rightNode.metadata.count = leftNode.metadata.count;
			rightNode.metadata.count -= pivotItemIndex;
			// Update left node's metadata
			leftNode.metadata.count = pivotItemIndex;
			// Insert new node in parent
			auto newChildItemIndex = childItemIndex; newChildItemIndex++;
			auto newItem = parent.insert!false(newChildItemIndex);
			newItem.keyLowerBound = pivot;
			newItem.blockIndex = rightIndex;
			debug(btree) dumpToStderr(&dump, ">>> putValue psplit: ");
		}

		/// Returns false if there was not enough room, and the parent needs splitting.
		bool descend(ref Block node, const BlockIndex remainingDepth/*, Key start, Key end*/) @nogc nothrow
		{
			bool impl(bool isLeaf)() @nogc
			{
				if (node.metadata.count > 0)
				{
					// assert(node.items!isLeaf[0].key >= start);
					// assert(node.items!isLeaf[node.metadata.count - 1].key < end);
				}

			retry:
				// auto item = &node.items!isLeaf[itemIndex];
				// auto itemStart = itemIndex ? item.key : start;
				// auto itemEnd = itemIndex < node.metadata.count ? node.items!isLeaf[itemIndex + 1].key : end;
				// assert(key >= itemStart && key < itemEnd);
				static if (isLeaf)
				{
					auto range = node.findExactly!isLeaf(key);
					auto itemIndex = range[1];
					auto newItem = node.insert!isLeaf(itemIndex);
					if (!newItem)
						return false; // No room
					newItem.key = key;
					newItem.value = value;
					return true;
				}
				else
				{
					auto range = node.findChildren!isLeaf(key);
					assert(range[0] < range[1]);
					auto itemIndex = range[1]; itemIndex--;
					auto item = &node.items!isLeaf[itemIndex];

					assert(remainingDepth > 0);
					BlockIndex childRemainingDepth = remainingDepth; childRemainingDepth--;

					if (!descend(blocks[item.blockIndex], childRemainingDepth/*, itemStart, itemEnd*/))
					{
						// No room below, split the child
						if (node.metadata.count + 1 == node.items!isLeaf.length)
							return false; // We ourselves don't have room. Split us up first
						auto childIsLeaf = childRemainingDepth == 0;
						splitNode(node, childIsLeaf, itemIndex);
						// Adjust key after splitting
						if (key >= node.items!isLeaf[itemIndex + 1].keyLowerBound)
							itemIndex++;
						goto retry;
					}
					return true;
				}
			}

			bool isLeaf = remainingDepth == 0;
			return isLeaf ? impl!true : impl!false;
		}

		while (!descend(blocks[metadata.rootBlock], metadata.depth/*, Key.min, Key.max*/))
		{
			// First, allocate new root
			auto newRootAllocation = blocks.allocate();
			auto newRootIndex = newRootAllocation.index;
			auto newRoot = newRootAllocation.ptr;
			assert(newRoot.metadata.count == 0);

			enum newRootIsLeaf = false;
			enum BlockItemIndex newItemIndex = 0;
			auto newItem = newRoot.insert!newRootIsLeaf(newItemIndex);
			newItem.keyLowerBound = Key.min; // !
			newItem.blockIndex = metadata.rootBlock;

			metadata.rootBlock = newRootIndex;
			auto oldDepth = metadata.depth;
			metadata.depth++;

			// Now split
			auto rootChildIsLeaf = oldDepth == 0;
			splitNode(*newRoot, rootChildIsLeaf, newItemIndex);
		}

		debug(btree) dumpToStderr(&dump, ">>> putValue after : ");
	}

	void dump()
	{
		import std.stdio : stderr;
		stderr.writeln("B-Tree depth: ", metadata.depth);
		stderr.writeln("B-Tree root block: #", metadata.rootBlock);

		void dump(BlockIndex blockIndex, BlockIndex depth)
		{
			void impl(bool isLeaf)()
			{
				auto block = &blocks[blockIndex];
				stderr.writefln("%*sBlock #%d:", 2 * depth, "", blockIndex);
				stderr.writefln("%*s%d items:", 2 * depth, "", block.metadata.count);
				foreach (item; block.items!isLeaf[0 .. block.metadata.count])
				{
					static if (isLeaf)
						stderr.writefln("%*s- %s: %s", 2 * depth, "", item.key, item.value);
					else
					{
						stderr.writefln("%*s- >= %s: #%d", 2 * depth, "", item.keyLowerBound, item.blockIndex);
						auto nextDepth = depth; nextDepth++;
						dump(item.blockIndex, nextDepth);
					}
				}
			}

			auto remainingDepth = metadata.depth - depth;
			auto isLeaf = remainingDepth == 0;
			return isLeaf ? impl!true : impl!false;
		}

		dump(metadata.rootBlock, 0);
	}
}

void dumpToStderr(void delegate() fun, string prefix) nothrow
{
	import std.stdio : stderr;
	import std.exception : assertNotThrown;
	(){
		stderr.write(prefix);
		// auto writer = stderr.lockingTextWriter();
		fun();
	}().assertNotThrown();
}

unittest
{
	import ae.sys.cmd : getTempFileName;
	import std.file : mkdir, rmdirRecurse;
	auto dir = getTempFileName("test");
	mkdir(dir);
	scope(exit) rmdirRecurse(dir);

	{
		auto a = BTree!(uint, uint, 16, 32)(dir ~ "/test");
		a.add(1, 1);
		a.add(2, 2);
		a.add(2, 3);
		a.add(3, 4);
	}

	{
		auto a = BTree!(uint, uint, 16, 32)(dir ~ "/test");

		int[] getAll(int key)
		{
			int[] result;
			a.findAll(key, (value) { result ~= value; });
			return result;
		}
		assert(getAll(1) == [1]);
		assert(getAll(2) == [2, 3]);
		assert(getAll(3) == [4]);
	}
}
