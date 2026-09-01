extends SceneTree

# Audits every spawn point on every map against the collision world.
# Run: godot --headless --path game --script res://tools/spawn_check.gd
#
# A spawn is only good if a standing body placed there is out of the walls,
# lands on a floor within a short drop, and still has a floor under it at the
# far corners of _spawn_pawn's horizontal jitter. Anything else either floats,
# is born inside a brush, or walks off into the void.

## Longest acceptable fall from the spawn point to the floor under it.
const MAX_DROP := 0.5
## Half the jitter square _spawn_pawn scatters across.
const JITTER := 0.7
## How far down to look for a floor before calling the spawn bottomless.
const PROBE := 64.0

var failed := 0


func _initialize() -> void:
	_audit("parkour", _builtin_world(), _builtin_spawns())
	for map_id in MapCatalog.list_community():
		var level = MapCatalog.load_community(map_id)
		_audit(map_id, level.world, level.spawns)
	print("\nFAILURES: ", failed)
	quit(1 if failed > 0 else 0)


func _builtin_world():
	return MapBuilder.build_world(MapEngine.compile(ParkourMap.definition()))


func _builtin_spawns() -> Dictionary:
	return MapCatalog.normalize_spawns(MapEngine.compile(ParkourMap.definition()).get("spawns", {}))


func _audit(map_id: String, world, spawns: Dictionary) -> void:
	print("== ", map_id, "   bounds y %.2f .. %.2f" % [
		world.bounds.position.y, world.bounds.end.y])
	for team: String in spawns:
		var i := 0
		for s: Dictionary in spawns[team]:
			_check(world, "%s[%d]" % [team, i], s["position"])
			i += 1


func _check(world, label: String, at: Vector3) -> void:
	var half := Vector3(Movement.PLAYER_RADIUS, Movement.STAND_HEIGHT * 0.5, Movement.PLAYER_RADIUS)
	var lift := Vector3(0.0, half.y, 0.0)
	var problems: PackedStringArray = []

	if world.box_overlaps(at + lift, half):
		problems.append("inside solid")

	var drop := _drop(world, at, half)
	if drop < 0.0:
		problems.append("no floor within %.0fm" % PROBE)
	elif drop > MAX_DROP:
		problems.append("floats %.2fm" % drop)

	for dx in [-JITTER, JITTER]:
		for dz in [-JITTER, JITTER]:
			var d := _drop(world, at + Vector3(dx, 0.0, dz), half)
			if d < 0.0 or d > MAX_DROP + Movement.STEP_HEIGHT:
				problems.append("jitter (%+.1f,%+.1f) drop %s" % [dx, dz, "none" if d < 0.0 else "%.2f" % d])

	var line := "  %-10s (%7.2f %6.2f %7.2f) drop %5.2f" % [label, at.x, at.y, at.z, drop]
	if problems.is_empty():
		print(line)
	else:
		print(line, "  FAIL: ", ", ".join(problems))
		failed += 1


# Distance from `at` down to the floor a standing body would rest on, or -1
# when nothing is under it within PROBE.
func _drop(world, at: Vector3, half: Vector3) -> float:
	var lift := Vector3(0.0, half.y, 0.0)
	var res = TraceResult.new()
	world.trace_box(at + lift, at + lift - Vector3(0.0, PROBE, 0.0), half, res)
	if res.start_solid:
		return 0.0
	if res.fraction >= 1.0:
		return -1.0
	return PROBE * res.fraction
