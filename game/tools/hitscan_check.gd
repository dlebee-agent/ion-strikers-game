extends SceneTree

# Throwaway harness for world hitscan.
# Run: godot --headless --path game --script res://tools/hitscan_check.gd

var _fails := 0


func _ok(label: String, got, want, tol := 0.01) -> void:
	var pass_: bool
	if got is float and want is float:
		pass_ = absf(got - want) <= tol
	else:
		pass_ = got == want
	if not pass_:
		_fails += 1
	print("  %-52s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


# What hitscan used to do: nearest hit against each brush's bounding box.
func _aabb_distance(boxes: Array[AABB], origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var best := max_dist
	for box: AABB in boxes:
		var t := _ray_aabb(origin, dir, box)
		if t > 0.0 and t < best:
			best = t
	return best


func _ray_aabb(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var tmin := -1e20
	var tmax := 1e20
	for i in 3:
		if absf(dir[i]) < 1e-8:
			if origin[i] < box.position[i] or origin[i] > box.end[i]:
				return -1.0
			continue
		var inv := 1.0 / dir[i]
		var t1 := (box.position[i] - origin[i]) * inv
		var t2 := (box.end[i] - origin[i]) * inv
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < tmin or tmax < 0.0:
		return -1.0
	return tmin if tmin > 0.0 else tmax


# A wedge rising along +Z: solid below the slope, nothing above it.
func _ramp_planes() -> Array[Plane]:
	var slope := Vector3(0, 1, -1).normalized()
	return [
		Plane(slope, slope.dot(Vector3(0, 0, -4))),
		Plane(Vector3(0, -1, 0), 0.0),
		Plane(Vector3(0, 0, 1), 4.0),
		Plane(Vector3(0, 0, -1), 4.0),
		Plane(Vector3(1, 0, 0), 4.0),
		Plane(Vector3(-1, 0, 0), 4.0),
	]


func _initialize() -> void:
	var res := TraceResult.new()

	print("-- a shot over a ramp is not stopped by the ramp's bounding box --")
	var ramp_bounds := AABB(Vector3(-4, 0, -4), Vector3(8, 8, 8))
	var w := CollisionWorld.new()
	w.add_brush(_ramp_planes(), ramp_bounds)
	w.build()
	# At z=-3 the slope surface is y=1, so y=6 is well clear of the solid while
	# still inside the bounding box, which spans y 0 to 8.
	var origin := Vector3(-10, 6, -3)
	var dir := Vector3(1, 0, 0)
	_ok("the bounding box blocks the shot", _aabb_distance([ramp_bounds], origin, dir, 30.0) < 30.0, true)
	_ok("the brush lets it through", w.ray_distance(origin, dir, 30.0, res), 30.0)

	print("-- but the ramp itself still stops a shot into it --")
	# At z=-3 the surface is at y=1, so half a metre up is inside the wedge.
	_ok("a shot into the slope is stopped", w.ray_distance(Vector3(-10, 0.5, -3), dir, 30.0, res) < 30.0, true)

	print("-- the special beam punches low cover, not walls --")
	var c := CollisionWorld.new()
	# Chest-high cover, which the beam goes through.
	var cover := AABB(Vector3(2, 0, -2), Vector3(1, 1.2, 4))
	var cover_i := c.add_box(cover)
	if Hitbox.special_blocks(cover):
		c.tag_brush(cover_i, CollisionWorld.CONTENT_SPECIAL)
	# A full wall, which it does not.
	var wall := AABB(Vector3(8, 0, -2), Vector3(1, 4.0, 4))
	var wall_i := c.add_box(wall)
	if Hitbox.special_blocks(wall):
		c.tag_brush(wall_i, CollisionWorld.CONTENT_SPECIAL)
	c.build()

	_ok("cover does not stop the beam", Hitbox.special_blocks(cover), false)
	_ok("a wall does", Hitbox.special_blocks(wall), true)

	var from := Vector3(0, 0.6, 0)
	var solid := c.ray_distance(from, dir, 30.0, res, CollisionWorld.MASK_SOLID)
	var special := c.ray_distance(from, dir, 30.0, res, CollisionWorld.MASK_SPECIAL)
	_ok("an ordinary shot stops at the cover", solid, 2.0)
	_ok("the beam carries on to the wall", special, 8.0)

	print("-- on the real arena --")
	var level := MapCatalog.load_community("community/arena1")
	_ok("arena imported", level.ok(), true)
	var centre := level.bounds.position + level.bounds.size * 0.5
	var far := level.world.ray_distance(Vector3(centre.x, 1.0, centre.z), dir, 500.0, res)
	_ok("a shot at the perimeter is stopped inside the level", far < level.bounds.size.x, true)
	var over := level.world.ray_distance(
		Vector3(centre.x, level.bounds.end.y + 5.0, centre.z), dir, 50.0, res)
	_ok("a shot above everything reaches full range", over, 50.0)

	# How often the old bounding-box hitscan would have stopped a shot the
	# brushes let through, sampled over the whole level.
	var freed := 0
	var shots := 0
	# Start inside the play area: the perimeter wall is 1.6 m thick and the floor
	# slab sits below y=0, so a sample that begins in either just measures two
	# ways of saying zero.
	var y := 0.3
	while y < level.bounds.end.y:
		var z := level.bounds.position.z + 3.0
		while z < level.bounds.end.z - 3.0:
			var o := Vector3(level.bounds.position.x + 2.5, y, z)
			var brushed := level.world.ray_distance(o, dir, 60.0, res)
			if brushed < 0.01:
				z += 1.0
				continue
			shots += 1
			if brushed > _aabb_distance(level.colliders, o, dir, 60.0) + 0.05:
				freed += 1
			z += 1.0
		y += 0.5
	print("    %d sample shots, %d reached further against brushes" % [shots, freed])
	_ok("bounding boxes were shortening real shots", freed > 0, true)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
