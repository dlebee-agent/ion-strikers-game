extends SceneTree

# Audits the bot navigation grid on every map.
# Run: godot --headless --path game --script res://tools/nav_check.gd
#
# A map where bots stand still or circle is usually a map whose grid never
# opened: nothing to route on, so nowhere to go. This builds the grid exactly
# as the server does and checks that the two sides can reach each other.

var failed := 0


func _initialize() -> void:
	var compiled: Dictionary = MapEngine.compile(ParkourMap.definition())
	_audit("parkour", MapBuilder.build_world(compiled),
		compiled.get("arena", 28.0), MapCatalog.normalize_spawns(compiled.get("spawns", {})))
	for map_id in MapCatalog.list_community():
		var level = MapCatalog.load_community(map_id)
		_audit(map_id, level.world, level.arena, level.spawns)
	print("\nFAILURES: ", failed)
	quit(1 if failed > 0 else 0)


func _fail(msg: String) -> void:
	print("  FAIL: ", msg)
	failed += 1


func _audit(map_id: String, world, arena: float, spawns: Dictionary) -> void:
	print("== %s   arena %.1f   bounds (%.1f %.1f %.1f) .. (%.1f %.1f %.1f)" % [
		map_id, arena, world.bounds.position.x, world.bounds.position.y, world.bounds.position.z,
		world.bounds.end.x, world.bounds.end.y, world.bounds.end.z])

	var director = BotDirector.new()
	var t0 := Time.get_ticks_msec()
	director.configure(world, arena, spawns)
	print("  build        %d ms" % (Time.get_ticks_msec() - t0))
	var nav = director.nav

	var open := 0
	for v in nav._open:
		if v == 1:
			open += 1
	print("  open cells   %d of %d" % [open, nav._open.size()])
	if open == 0:
		_fail("grid has no open cell")
		return

	var blue: Array = spawns.get("blue", [])
	var red: Array = spawns.get("red", [])
	if blue.is_empty() or red.is_empty():
		_fail("a side has no spawn")
		return
	var a: Vector3 = blue[0]["position"]
	var b: Vector3 = red[0]["position"]
	var path: PackedVector3Array = nav.find_path(a, b)
	print("  blue -> red  %d waypoints" % path.size())
	if path.size() < 2:
		_fail("no route from blue spawn %s to red spawn %s" % [a, b])
	for s: Dictionary in blue + red:
		if nav.nearest_id(s["position"]) < 0:
			_fail("spawn %s is off the grid" % s["position"])
