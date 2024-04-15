module mapset_em.db;

import ae.utils.math : TypeForBits;

import mapset_em.storage.vlavla;

struct MapSetDB(
	DimName,
	DimValue,
	// How many mapsets we want to have, at most
	size_t mapSetIndexBits,
	// How big the file storing the mapsets should be, at most
	size_t mapSetOffsetBits,
)
{
	alias MapSetIndex = TypeForBits!mapSetIndexBits;

	VLAVLA!(MapSetIndex, mapSetOffsetBits) mapsets;

	this(string name)
	{
		mapsets = typeof(mapsets)(name ~ "/mapsets");
	}
}
