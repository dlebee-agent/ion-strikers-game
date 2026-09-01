class_name MapCatalog
extends RefCounted

# Which maps exist and how to get one.
#
# Built-in maps are compiled from a shapes definition and live in a folder per
# map (res://maps/<id>/) next to their baked sky faces. Community maps live under
# maps/community, addressed as "community/<name>", which is the prefix the lobby
# and the protocol pass around.
#
# Two source formats are accepted. A .map is TrenchBroom's text brush list, read
# with the WAD beside it. A .bsp is a compiled GoldSrc level, which is what a
# released Quake-lineage map almost always ships as. The id carries no extension
# either way, so nothing downstream has to care which one a level came from.

# Preloaded by path rather than referenced by class name: headless tool runs
# (sky bake, build checks) can start with a stale global class cache, where an
# unresolved class name fails this whole script's compile.
const _ParkourMap := preload("res://maps/parkour/parkour.gd")
const _SkydeckMap := preload("res://maps/skydeck/skydeck.gd")

const BUILTIN_IDS: Array[String] = ["parkour", "skydeck"]

const COMMUNITY_DIR := "res://maps/community"
const COMMUNITY_PREFIX := "community/"
const SOURCE_EXTENSIONS := ["map", "bsp"]

# Importing a level parses text and solves every brush, so it is done once per
# process rather than once per match.
static var _cache: Dictionary = {}


# The shapes definition for a built-in map. Unknown ids fall back to parkour,
# which is also what the community-map paths fall back to when an import fails.
static func builtin_definition(map_id: String) -> Dictionary:
	match map_id:
		"skydeck":
			return _SkydeckMap.definition()
		_:
			return _ParkourMap.definition()


# Every map this build can compile or import, as ids. What the server puts in
# its HELLO, and what both sides check an id against before trusting it.
static func available_maps() -> Array[String]:
	var out: Array[String] = BUILTIN_IDS.duplicate()
	out.append_array(list_community())
	return out


static func has_map(map_id: String) -> bool:
	if not is_community(map_id):
		return BUILTIN_IDS.has(map_id)
	return list_community().has(map_id)


static func is_community(map_id: String) -> bool:
	return map_id.begins_with(COMMUNITY_PREFIX)


# The file behind an id. A .map wins over a .bsp of the same name: if someone
# has the brush source, that is the better level.
static func map_path(map_id: String) -> String:
	var name := map_id.substr(COMMUNITY_PREFIX.length())
	for ext: String in SOURCE_EXTENSIONS:
		var path := "%s/%s.%s" % [COMMUNITY_DIR, name, ext]
		if FileAccess.file_exists(path):
			return path
	return "%s/%s.map" % [COMMUNITY_DIR, name]


# Imports a community map, or returns the cached level if it has already been
# imported in this process. Always returns a TbLevel; ask it whether it is ok().
static func load_community(map_id: String) -> TbLevel:
	if _cache.has(map_id):
		return _cache[map_id]
	var path := map_path(map_id)
	var level: TbLevel
	if path.get_extension().to_lower() == "bsp":
		level = BspImporter.import_file(path)
	else:
		level = TbImporter.import_file(path)
	_cache[map_id] = level
	return level


# Every level sitting in the community directory, as ids ready to hand back.
static func list_community() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	var dir := DirAccess.open(COMMUNITY_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		# Exported builds hand back the import stub rather than the file itself.
		var name := String(file).trim_suffix(".remap")
		if not SOURCE_EXTENSIONS.has(name.get_extension().to_lower()):
			continue
		# A level shipping both a .map and a .bsp is one entry, not two.
		var id := COMMUNITY_PREFIX + name.get_basename()
		if seen.has(id):
			continue
		seen[id] = true
		out.append(id)
	out.sort()
	return out


static func display_name(map_id: String) -> String:
	if not is_community(map_id):
		return map_id.capitalize()
	var level: TbLevel = _cache.get(map_id, null)
	if level != null and level.name != "":
		return level.name
	return map_id.substr(COMMUNITY_PREFIX.length()).capitalize()


# Built-in maps give flat [x, z] pairs (optionally [x, z, y] on a raised
# floor), on the ground at y=0 otherwise, facing whichever way
# their team always faces. Imported maps carry a height and a per-point angle.
# Everything downstream takes the richer shape, so the flat one is widened here
# and there is only one spawn path to reason about.
static func normalize_spawns(flat: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for team: String in flat:
		var points: Array = []
		var yaw := 180.0 if team == "blue" else 0.0
		for entry: Array in flat[team]:
			# An optional third number is a floor height, for spawn points
			# that sit on a raised deck rather than the ground.
			var y := float(entry[2]) if entry.size() > 2 else 0.0
			points.append({
				"position": Vector3(float(entry[0]), y, float(entry[1])),
				"yaw": yaw,
			})
		out[team] = points
	return out


# A stand-in for the compiled dictionary the built-in maps produce, so imported
# levels get the same lighting and sky treatment without inventing a second one.
static func ambience_for(level: TbLevel) -> Dictionary:
	var out: Dictionary = {
		"arena": level.arena,
		"theme": {
			"floor": 0x2a3240,
			"grid": 0x38424c,
			"wall": 0x6f7d8a,
			"cover": 0x8aa0b4,
			"fog": 0x1e262e,
		},
	}
	# A sky is only offered when its faces are already baked on disk. The
	# procedural generator is an offline tool: asked for a cubemap it has not
	# got, it spends about twenty seconds building one, and doing that while a
	# match is connecting stalls the client long enough for the server to drop
	# it. Without a sky the environment falls back to a flat background, which
	# is plain but instant.
	if has_baked_sky(level.sky_id):
		out["id"] = level.sky_id
		out["sky"] = {"cubemap": {}}
	return out


static func has_baked_sky(sky_id: String) -> bool:
	for i in 6:
		if not ResourceLoader.exists("res://maps/%s/sky_%d.png" % [sky_id, i]):
			return false
	return true
