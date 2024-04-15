module mapset_em.storage.btree;

import std.algorithm.comparison : max;

import ae.sys.data;
import ae.utils.math;

import mapset_em.storage.common;
import mapset_em.storage.value;
import mapset_em.storage.vla;

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

	align(1)
	struct TrunkItem
	{
	align(1):
		Key key;
		BlockIndex blockIndex;
	}

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

			/// Return the element index (within `this.*Items`)
			/// with the given `key`, or if `key` is not present,
			/// then the index of the item before which it should be inserted.
			BlockItemIndex find(bool isLeaf)(Key key) const nothrow @nogc
			{
				// Binary search:
				BlockItemIndex start = 0, end = metadata.count;
				while (start + 1 < end)
				{
					assert(start < end);
					auto mid = end; mid -= start; mid /= 2; mid += start;
					assert(start <= mid && mid < end);
					if (key >= items!isLeaf[mid].key)
						start = mid;
					else
						end = mid;
				}
				return start;
			}

			auto insert(bool isLeaf)(BlockItemIndex itemIndex)
			{
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
	}

	/// Read the B-tree and return the `Value` corresponding to the given `Key`.
	Value* getValue(Key key) nothrow @nogc
	{
		Value* search(ref Block node, BlockIndex remainingDepth, Key start, Key end) nothrow @nogc
		{
			Value* impl(bool isLeaf)()
			{
				if (node.metadata.count > 0)
				{
					assert(node.items!isLeaf[0].key >= start);
					assert(node.items!isLeaf[node.metadata.count - 1].key < end);
				}

				auto itemIndex = node.find!isLeaf(key);
				auto item = &node.items!isLeaf[itemIndex];
				auto itemStart = itemIndex ? item.key : start;
				auto itemEnd = itemIndex < node.metadata.count ? node.items!isLeaf[itemIndex + 1].key : end;
				static if (isLeaf)
				{
					assert(remainingDepth == 0);
					return item.key == key ? &item.value : null;
				}
				else
				{
					assert(remainingDepth > 0);
					return search(blocks[item.blockIndex], remainingDepth - 1, itemStart, itemEnd);
				}
			}

			bool isLeaf = remainingDepth == 0;
			return isLeaf ? impl!true : impl!false;
		}

		return search(blocks[metadata.rootBlock], key, Key.min, Key.max);
	}

	alias opIn_r = getValue;

	/// Write to the B-tree and set the given `Key` to the given `Value`.
	void putValue(Key key, Value value) nothrow @nogc
	{
		debug(btree) dumpToStderr!dumpBtree(">>> putValue before: ");

		void splitNode(ref Block parent, bool childIsLeaf, BlockItemIndex childItemIndex) @nogc
		{
			void impl(bool childIsLeaf)() @nogc
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
				auto pivot = leftNode.items!childIsLeaf[pivotItemIndex].key;
				// Move nodes from left to right
				foreach (i; pivotItemIndex .. leftNode.metadata.count)
					rightNode.items!childIsLeaf[i - pivotItemIndex] = leftNode.items!childIsLeaf[i];
				// Fix right node's metadata
				rightNode.metadata.count = leftNode.metadata.count;
				rightNode.metadata.count -= pivotItemIndex;
				// Update left node's metadata
				leftNode.metadata.count = pivotItemIndex;
				// Insert new node in parent
				auto newChildItemIndex = childItemIndex; newChildItemIndex++;
				auto newItem = parent.insert!false(newChildItemIndex);
				newItem.key = pivot;
				newItem.blockIndex = rightIndex;
				debug(btree) dumpToStderr!dumpBtree(">>> putValue psplit: ");
			}

			return childIsLeaf ? impl!true : impl!false;
		}

		/// Returns false if there was not enough room, and the parent needs splitting.
		bool descend(ref Block node, BlockIndex remainingDepth, Key start, Key end) @nogc nothrow
		{
			bool impl(bool isLeaf)() @nogc
			{
				if (node.metadata.count > 0)
				{
					assert(node.items!isLeaf[0].key >= start);
					assert(node.items!isLeaf[node.metadata.count - 1].key < end);
				}

				auto itemIndex = node.find!isLeaf(key);
			retry:
				auto item = &node.items!isLeaf[itemIndex];
				auto itemStart = itemIndex ? item.key : start;
				auto itemEnd = itemIndex < node.metadata.count ? node.items!isLeaf[itemIndex + 1].key : end;
				assert(key >= itemStart && key < itemEnd);
				static if (isLeaf)
				{
					if (item.key == key)
					{
						item.value = value;
						return true;
					}
					else
					{
						auto newItem = node.insert!isLeaf(itemIndex);
						if (!newItem)
							return false; // No room
						newItem.key = key;
						newItem.value = value;
						return true;
					}
				}
				else
				{
					assert(remainingDepth > 0);
					auto childRemainingDepth = remainingDepth - 1;
					if (!descend(blocks[item.blockIndex], childRemainingDepth, itemStart, itemEnd))
					{
						// No room below, split the child
						if (node.metadata.count + 1 == node.items!isLeaf.length)
							return false; // We ourselves don't have room. Split us up first
						auto childIsLeaf = childRemainingDepth == 0;
						splitNode(node, childIsLeaf, itemIndex);
						// Adjust key after splitting
						if (key >= node.items!isLeaf[itemIndex + 1].key)
							itemIndex++;
						goto retry;
					}
					return true;
				}
			}

			bool isLeaf = remainingDepth == 0;
			return isLeaf ? impl!true : impl!false;
		}

		while (!descend(blocks[metadata.rootBlock], metadata.depth, Key.min, Key.max))
		{
			// First, allocate new root
			auto newRootAllocation = blocks.allocate();
			auto newRootIndex = newRootAllocation.index;
			auto newRoot = newRootAllocation.ptr;
			assert(newRoot.metadata.count == 0);
			enum newRootIsLeaf = false;
			newRoot.items!newRootIsLeaf[0].blockIndex = metadata.rootBlock;
			metadata.rootBlock = newRootIndex;
			auto oldDepth = metadata.depth;
			metadata.depth++;
			// Now split
			auto rootChildIsLeaf = oldDepth == 0;
			splitNode(*newRoot, rootChildIsLeaf, 0);
		}

		debug(btree) dumpToStderr!dumpBtree(">>> putValue after : ");
	}
}

unittest
{
	BTree!(uint, uint, 32) _;
}
