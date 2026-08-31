extends SceneTree

# Throwaway harness: can bots see and route over the community arena's ramps?
# Run: godot --headless --path game --script res://tools/bot_slope_check.gd

var _fails := 0


func _ok(label: String, got, want) -> void:
	var pass_: bool = got == want
	if not pass_:
		_fails += 1
	print("  %-52s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


func _initialize() -> void:
	var level := MapCatalog.load_community("community/arena1")
	_ok("arena imported", level.ok(), true)

	var seeds: Array[Vector3] = []
	for team: String in level.spawns:
		for entry: Dictionary in level.spawns[team]:
			seeds.append(entry["position"])

	var nav := BotNav.new()
	var t0 := Time.get_ticks_msec()
	nav.build(level.world, level.arena, seeds)
	print("nav build %d ms, %d open cells" % [Time.get_ticks_msec() - t0, nav.open_points.size()])
	_ok("the grid has walkable ground", nav.open_points.size() > 100, true)

	# The arena's central platform is the thing ramps exist to reach. Bots could
	# not get onto it while every cell of a ramp reported the top of the ramp's
	# bounding box, because the floor-to-ramp join then looked like a cliff.
	print("-- reachable heights --")
	var highest := -INF
	var lowest := INF
	for p: Vector3 in nav.open_points:
		highest = maxf(highest, p.y)
		lowest = minf(lowest, p.y)
	print("    reachable ground spans y %.2f to %.2f" % [lowest, highest])
	_ok("bots can reach above floor level", highest > 1.0, true)

	# Cells partway up a ramp, which only exist if heights are read per cell.
	var on_slope := 0
	for p: Vector3 in nav.open_points:
		if p.y > 0.3 and p.y < 2.7:
			on_slope += 1
	print("    %d cells at intermediate heights" % on_slope)
	_ok("the ramps themselves are walkable", on_slope > 20, true)

	print("-- routing onto high ground --")
	# Route from a spawn to the highest reachable cell and check the path
	# actually climbs rather than giving up at the bottom.
	var start: Vector3 = seeds[0]
	var goal := Vector3.ZERO
	for p: Vector3 in nav.open_points:
		if p.y >= highest - 0.01:
			goal = p
			break
	var path := nav.find_path(start, goal)
	print("    %s -> %s : %d waypoints" % [start, goal, path.size()])
	_ok("a route exists", path.size() > 0, true)
	if path.size() > 0:
		var top := -INF
		for p: Vector3 in path:
			top = maxf(top, p.y)
		_ok("the route climbs to the goal", top >= highest - 0.6, true)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
