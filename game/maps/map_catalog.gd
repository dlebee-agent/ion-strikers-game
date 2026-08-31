class_name MapCatalog
extends RefCounted

# Which maps exist and how to get one.
#
# Built-in maps are compiled from a shapes definition. Community maps are .map
# files under maps/community, addressed as "community/<name>", which is the
# prefix the lobby and the protocol pass around.

const COMMUNITY_DIR := "res://maps/community"
const COMMUNITY_PREFIX := "community/"

# Importing a level parses text and solves every brush, so it is done once per
# process rather than once per match.
static var _cache: Dictionary = {}


static func is_community(map_id: String) -> bool:
	return map_id.begins_with(COMMUNITY_PREFIX)


static func map_path(map_id: String) -> String:
	return "%s/%s.map" % [COMMUNITY_DIR, map_id.substr(COMMUNITY_PREFIX.length())]


# Imports a community map, or returns the cached level if it has already been
# imported in this process. Always returns a TbLevel; ask it whether it is ok().
static func load_community(map_id: String) -> TbLevel:
	if _cache.has(map_id):
		return _cache[map_id]
	var level := TbImporter.import_file(map_path(map_id))
	_cache[map_id] = level
	return level


# Every .map sitting in the community directory, as ids ready to hand back.
static func list_community() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(COMMUNITY_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		# Exported builds hand back the import stub rather than the file itself.
		var name := String(file).trim_suffix(".remap")
		if name.get_extension() == "map":
			out.append(COMMUNITY_PREFIX + name.get_basename())
	out.sort()
	return out


static func display_name(map_id: String) -> String:
	if not is_community(map_id):
		return map_id.capitalize()
	var level: TbLevel = _cache.get(map_id, null)
	if level != null and level.name != "":
		return level.name
	return map_id.substr(COMMUNITY_PREFIX.length()).capitalize()


# Built-in maps give flat [x, z] pairs, on a floor at y=0, facing whichever way
# their team always faces. Imported maps carry a height and a per-point angle.
# Everything downstream takes the richer shape, so the flat one is widened here
# and there is only one spawn path to reason about.
static func normalize_spawns(flat: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for team: String in flat:
		var points: Array = []
		var yaw := 180.0 if team == "blue" else 0.0
		for entry: Array in flat[team]:
			points.append({
				"position": Vector3(float(entry[0]), 0.0, float(entry[1])),
				"yaw": yaw,
			})
		out[team] = points
	return out


# A stand-in for the compiled dictionary the built-in maps produce, so imported
# levels get the same lighting and sky treatment without inventing a second one.
static func ambience_for(level: TbLevel) -> Dictionary:
	return {
		"arena": level.arena,
		"theme": {
			"floor": 0x2a3240,
			"grid": 0x38424c,
			"wall": 0x6f7d8a,
			"cover": 0x8aa0b4,
			"fog": 0x1e262e,
		},
		"sky": {
			"cubemap": {
				"seed": 17,
				"stars": 3200,
				"galaxies": 6,
				"density": 0.48,
				"nebula": [0x2b3fa8, 0x1a70a8, 0x6a2ab0, 0xd0763a],
			},
		},
	}
