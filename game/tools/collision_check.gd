extends SceneTree

# Throwaway harness for the brush collider.
# Run: godot --headless --path game --script res://tools/collision_check.gd

var _fails := 0


func _ok(label: String, got, want, tol := 0.002) -> void:
	var pass_ := false
	if got is float and want is float:
		pass_ = absf(got - want) <= tol
	elif got is Vector3 and want is Vector3:
		pass_ = (got - want).length() <= tol
	else:
		pass_ = got == want
	if not pass_:
		_fails += 1
	print("  %-46s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


# A 45 degree ramp rising along +Z, as a five-plane wedge.
func _ramp() -> Array[Plane]:
	var slope := Vector3(0, 1, -1).normalized()
	return [
		# Surface passes through the base edge at z=-4, y=0 and climbs to y=8 at
		# z=4. Anchoring it at the origin instead would put the slope plane below
		# the floor plane over the whole -Z half and enclose no volume there.
		Plane(slope, slope.dot(Vector3(0, 0, -4))),
		Plane(Vector3(0, -1, 0), 0.0),
		Plane(Vector3(0, 0, 1), 4.0),
		Plane(Vector3(1, 0, 0), 4.0),
		Plane(Vector3(-1, 0, 0), 4.0),
	]


func _initialize() -> void:
	var half := Vector3(0.4, 0.895, 0.4)
	var res := TraceResult.new()

	print("-- box vs wall --")
	var w := CollisionWorld.new()
	# Wall slab occupying x in [2,3], the player box is 0.4 wide.
	w.add_box(AABB(Vector3(2, 0, -5), Vector3(1, 4, 10)))
	w.build()
	w.trace_box(Vector3(0, 1, 0), Vector3(4, 1, 0), half, res)
	# Centre stops 0.4 short of x=2, less the surface offset.
	_ok("stops short of the wall", res.end_pos.x, 1.6, 0.01)
	_ok("wall normal faces back at the mover", res.normal, Vector3(-1, 0, 0))
	_ok("reports a hit", res.hit(), true)

	print("-- ray misses and hits --")
	w.raycast(Vector3(0, 1, 0), Vector3(1.5, 1, 0), res)
	_ok("ray short of the wall does not hit", res.hit(), false)
	w.raycast(Vector3(0, 1, 0), Vector3(4, 1, 0), res)
	_ok("ray through the wall hits at x=2", res.end_pos.x, 2.0, 0.01)

	print("-- box vs 45 degree ramp --")
	var r := CollisionWorld.new()
	r.add_brush(_ramp(), AABB(Vector3(-4, 0, -4), Vector3(8, 8, 8)))
	r.build()
	# Drop onto the ramp face above z=-2, where the surface sits at y=2.
	r.trace_box(Vector3(0, 6, -2), Vector3(0, 0, -2), half, res)
	var slope := Vector3(0, 1, -1).normalized()
	_ok("ramp normal is the slope, not axis aligned", res.normal, slope)
	_ok("normal has real Y so it is walkable", res.normal.y > 0.7, true)
	# The box rests where its corner touches the plane, which is higher than the
	# surface directly beneath the centre. That offset is the whole point of the
	# expansion: an AABB collider would sink the box into the slope.
	var rest := res.end_pos.y - half.y
	_ok("box rests on the slope, not inside it", rest > 2.0, true)

	print("-- start solid is reported, not silently ignored --")
	r.trace_box(Vector3(0, 0.5, 0), Vector3(0, 0.5, 1), half, res)
	_ok("embedded start flagged", res.start_solid, true)
	_ok("embedded start travels nothing", res.fraction, 0.0)

	print("-- overlap probe --")
	_ok("box inside the ramp overlaps", r.box_overlaps(Vector3(0, 0.5, 0), half), true)
	_ok("box well clear does not overlap", r.box_overlaps(Vector3(0, 20, 0), half), false)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
