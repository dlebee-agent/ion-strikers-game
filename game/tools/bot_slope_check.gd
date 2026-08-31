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

	_side_walls(level, nav)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


# A ramp's side is a vertical wall. The cell on top of it is sloped, so a rule
# that allows a big rise merely because the destination is sloped lets bots walk
# into that wall and stick there trying to climb it sideways.
func _side_walls(level: TbLevel, nav: BotNav) -> void:
	print("-- ramp sides are not climbable --")
	var res := TraceResult.new()
	var half := Vector3(BotNav.BODY_RADIUS, BotNav.BODY_HEIGHT * 0.5, BotNav.BODY_RADIUS)
	var sideways := 0
	var uphill_ok := 0
	var checked := 0

	var x := level.bounds.position.x + 1.0
	while x < level.bounds.end.x:
		var z := level.bounds.position.z + 1.0
		while z < level.bounds.end.z:
			level.world.trace_box(Vector3(x, level.bounds.end.y, z),
				Vector3(x, level.bounds.position.y, z), half, res)
			var n := res.normal
			if not res.hit() or n.y <= 0.72 or n.y >= 0.99:
				z += 1.0
				continue
			var top := res.end_pos.y - half.y
			var grad := Vector2(n.x, n.z)
			if grad.length() < 0.01:
				z += 1.0
				continue
			grad = grad.normalized()
			# Across the gradient is where a ramp's side wall faces.
			var across := Vector2(-grad.y, grad.x)
			for side: float in [1.0, -1.0]:
				var probe := Vector2(x, z) + across * side * 1.2
				level.world.trace_box(Vector3(probe.x, level.bounds.end.y, probe.y),
					Vector3(probe.x, level.bounds.position.y, probe.y), half, res)
				if not res.hit():
					continue
				var beside := res.end_pos.y - half.y
				# Only interesting where the ground beside is well below the
				# ramp, which is exactly where its side wall is.
				if top - beside <= BotNav.STEP_UP:
					continue
				checked += 1
				if nav.walk_clear(Vector3(probe.x, beside, probe.y), Vector3(x, top, z)):
					sideways += 1
			# Approaching straight up the gradient must still work. The normal
			# leans downhill, so following it is the way down and the point to
			# start from.
			var lower := Vector2(x, z) + grad * 1.2
			level.world.trace_box(Vector3(lower.x, level.bounds.end.y, lower.y),
				Vector3(lower.x, level.bounds.position.y, lower.y), half, res)
			if res.hit():
				var below := res.end_pos.y - half.y
				if top - below > 0.05 and nav.walk_clear(Vector3(lower.x, below, lower.y), Vector3(x, top, z)):
					uphill_ok += 1
			z += 1.0
		x += 1.0

	print("    %d side-wall approaches sampled, %d judged walkable" % [checked, sideways])
	print("    %d uphill approaches still walkable" % uphill_ok)
	_ok("no ramp side wall is walkable", sideways, 0)
	_ok("ramps are still climbable from below", uphill_ok > 0, true)
