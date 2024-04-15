module mapset_em.storage.common;

import std.exception : enforce;
import std.format : format;
import std.stdio : File;

import ae.sys.data;
import ae.sys.datamm;
import ae.sys.file : truncate, ensurePathExists;

enum maxMapSize = 64UL << 40; // 64 TiB

Data mapData(string name, size_t size)
{
	auto fileName = name;

	ensurePathExists(fileName);

	{
		auto f = File(fileName, "ab");
		if (f.size == 0)
			f.truncate(size);
		else
			enforce(f.size == size, "Size mismatch: was %d, want %d".format(f.size, size));
		f.close();
	}

	return mapFile(fileName, MmMode.readWrite);
}
