class_name TbImporter
extends RefCounted

# Turns a .map file, and the WAD beside it, into a playable TbLevel.
#
# Nothing here can fail hard. A community map is untrusted input, so a missing
# texture, a malformed brush or a spawn with no origin is recorded and skipped
# rather than taken as a reason to refuse the level.

# Quake spawn classnames, and which side of this game they belong to.
const TEAM_CLASSES := {
	"info_player_team1": "blue",
	"info_player_team2": "red",
}
# Spawns that belong to nobody in particular, used by both sides when a map
# ships no team spawns of its own.
const NEUTRAL_CLASSES := ["info_player_start", "info_player_deathmatch"]
const PAD_CLASSES := ["ion_jump_pad", "trigger_push", "target_push"]

const TEAMS := ["blue", "red"]


# Imports `map_path`. The WAD is taken from worldspawn's `wad` key, resolved
# next to the map, unless `wad_path` overrides it.
static func import_file(map_path: String, wad_path := "") -> TbLevel:
	var level := TbLevel.new()
	level.id = map_path.get_file().get_basename()

	var parsed := TbParser.new().parse_file(map_path)
	level.warnings.append_array(parsed.warnings)
	if parsed.entities.is_empty():
		level.warnings.append("%s contains no entities" % map_path)
		return level

	var world_entity := parsed.worldspawn()
	if world_entity == null:
		level.warnings.append("%s has no worldspawn" % map_path)
		return level

	level.name = world_entity.get_string("message", level.id)

	# Geometry. Brushes on any entity count as solid: a func_detail or a
	# func_group is a mapper's organisational device, not a different kind of
	# wall, and treating them as decoration would leave holes.
	var brushes: Array = []
	for e: TbMap.Entity in parsed.entities:
		for b: TbMap.Brush in e.brushes:
			brushes.append(b)
	var solids := TbGeometry.solve_all(brushes, level.warnings)
	if solids.is_empty():
		level.warnings.append("no brush in %s enclosed a volume" % map_path)
		return level

	level.world = CollisionWorld.new()
	TbMesh.add_to_world(solids, level.world)
	level.world.build()
	level.bounds = level.world.bounds
	for s: TbGeometry.Solid in solids:
		level.colliders.append(s.bounds)

	# Half the larger horizontal extent, since the systems built around a square
	# arena want a radius rather than a box.
	level.arena = maxf(level.bounds.size.x, level.bounds.size.z) * 0.5

	var wad := _load_wad(map_path, wad_path, world_entity, level.warnings)
	var materials := TbMaterials.new(wad)
	level.mesh = TbMesh.build(solids, materials)
	level.warnings.append_array(materials.warnings)

	_read_spawns(parsed, level)
	_read_pads(parsed, level)
	return level


static func _load_wad(map_path: String, override: String, world_entity: TbMap.Entity,
		warnings: Array[String]) -> WadPack:
	var candidates: Array[String] = []
	if override != "":
		candidates.append(override)
	else:
		# TrenchBroom writes absolute paths from the machine it was authored on,
		# separated by semicolons. Only the filename can be trusted, and the map
		# it shipped beside is the only place worth looking.
		var declared := world_entity.get_string("wad", "")
		for entry in declared.split(";", false):
			var file := String(entry).replace("\\", "/").get_file()
			if file != "":
				candidates.append(map_path.get_base_dir().path_join(file))
		candidates.append(map_path.get_basename() + ".wad")

	for path: String in candidates:
		if not FileAccess.file_exists(path):
			continue
		var pack := WadPack.load_file(path)
		warnings.append_array(pack.warnings)
		if pack.size() > 0:
			return pack

	if not candidates.is_empty():
		warnings.append("no texture pack found; tried %s" % ", ".join(candidates))
	return null


static func _read_spawns(parsed: TbMap, level: TbLevel) -> void:
	for team: String in TEAMS:
		level.spawns[team] = []

	var neutral: Array = []
	for e: TbMap.Entity in parsed.entities:
		var cls := e.classname()
		var is_neutral := NEUTRAL_CLASSES.has(cls)
		if not TEAM_CLASSES.has(cls) and not is_neutral:
			continue
		if not e.properties.has("origin"):
			level.warnings.append("%s has no origin, skipped" % cls)
			continue
		var entry := {
			"position": e.get_position("origin"),
			# Quake measures its angle counter-clockwise from +X; this game's
			# yaw zero faces -Z, which is Quake's +Y, so the two are a quarter
			# turn apart.
			"yaw": e.get_float("angle", 90.0) - 90.0,
		}
		if is_neutral:
			neutral.append(entry)
		else:
			(level.spawns[TEAM_CLASSES[cls]] as Array).append(entry)

	# A map that ships no team spawns still has to be playable, so both sides
	# fall back to whatever neutral points it does have.
	for team: String in TEAMS:
		if (level.spawns[team] as Array).is_empty():
			level.spawns[team] = neutral.duplicate()

	if level.spawn_count() == 0:
		level.warnings.append("no spawn points of any kind")


static func _read_pads(parsed: TbMap, level: TbLevel) -> void:
	for e: TbMap.Entity in parsed.entities:
		if not PAD_CLASSES.has(e.classname()):
			continue
		if not e.properties.has("origin"):
			continue
		var pos := e.get_position("origin")
		level.pads.append({
			"x": pos.x,
			"z": pos.z,
			"team": e.get_string("team", ""),
		})
