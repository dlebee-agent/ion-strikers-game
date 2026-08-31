extends SceneTree

# Throwaway harness: drives Movement against the real parkour map and asserts the
# things the AABB collider used to guarantee.
# Run: godot --headless --path game --script res://tools/movement_check.gd

const DT := 1.0 / 60.0

var _fails := 0
var _world: CollisionWorld
# Highest the player got during the last _drive, since a walk across a staircase
# ends on the far side and the peak is what says the climb happened.
var _peak_y := 0.0


func _ok(label: String, got, want) -> void:
	var pass_: bool = got == want
	if not pass_:
		_fails += 1
	print("  %-48s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


# Runs the player for `frames` with a fixed input, returning the movement.
func _run(start: Vector3, fwd: float, side: float, frames: int,
		jump := false, crouch := false) -> Movement:
	var m := Movement.new()
	m.position = start
	m.yaw = 0.0
	for i in frames:
		m.update(DT, fwd, side, jump, crouch, false, _world)
		if _embedded(m):
			_fails += 1
			print("    !! embedded in geometry at frame %d, pos=%s" % [i, m.position])
			break
	return m


# Drops a player onto (x, z) and lets them settle, returning them standing.
func _settled(x: float, z: float) -> Movement:
	var m := Movement.new()
	m.position = Vector3(x, 8.0, z)
	for i in 240:
		m.update(DT, 0.0, 0.0, false, false, false, _world)
	return m


# Continues an already-settled player with a fixed input.
func _drive(m: Movement, fwd: float, side: float, frames: int,
		jump := false, crouch := false) -> Movement:
	_peak_y = m.position.y
	for i in frames:
		_peak_y = maxf(_peak_y, m.position.y)
		m.update(DT, fwd, side, jump, crouch, false, _world)
		if _embedded(m):
			_fails += 1
			print("    !! embedded in geometry at frame %d, pos=%s" % [i, m.position])
			break
	return m


func _embedded(m: Movement) -> bool:
	var h := m.player_height()
	var half := Vector3(Movement.PLAYER_RADIUS, h * 0.5, Movement.PLAYER_RADIUS)
	return _world.box_overlaps(m.position + Vector3(0.0, half.y, 0.0), half)


func _initialize() -> void:
	var compiled := MapEngine.compile(ParkourMap.definition())
	var t0 := Time.get_ticks_msec()
	_world = MapBuilder.build_world(compiled)
	print("world: %d brushes, built in %d ms" % [_world.brush_count(), Time.get_ticks_msec() - t0])
	print("bounds: ", _world.bounds)
	print("")

	print("-- settling --")
	# Dropped from above the spawn, the player must land on the floor and stay
	# there, not sink through it and not hover.
	var drop := _run(Vector3(0, 6, -23), 0.0, 0.0, 180)
	_ok("lands on the floor", absf(drop.position.y) < 0.05, true)
	_ok("is grounded once landed", drop.on_ground, true)
	_ok("vertical velocity settles", absf(drop.velocity.y) < 0.01, true)

	print("-- walls stop the player --")
	# The perimeter wall sits at the arena edge; running at it must not pass it.
	var arena: float = compiled["arena"]
	var into_wall := _run(Vector3(0, 0.1, -arena + 3.0), -1.0, 0.0, 240)
	_ok("does not cross the perimeter", into_wall.position.z > -arena, true)
	_ok("is not stuck inside the wall", _embedded(into_wall), false)

	print("-- open ground is traversable --")
	var open := _settled(-20.0, 0.0)
	var from := Vector2(open.position.x, open.position.z)
	_drive(open, 1.0, 0.0, 120)
	var travelled := from.distance_to(Vector2(open.position.x, open.position.z))
	_ok("actually moves off the spot", travelled > 3.0, true)
	_ok("stays on the ground while running", open.on_ground, true)

	print("-- stairs --")
	# The cover staircase climbs from z=-18 to a 2.4m landing at z=-9.6. Walking
	# it is the step-up path on real content, and the height has to come from
	# stepping rather than from the player being shoved upward.
	var climber := _settled(0.0, -19.0)
	# Forward at yaw 0 is -Z; the staircase climbs toward +Z.
	climber.yaw = 180.0
	var base := climber.position.y
	_drive(climber, 1.0, 0.0, 300)
	_ok("gains the landing height", _peak_y - base > 2.0, true)
	_ok("is standing at the top", climber.on_ground, true)
	_ok("is not embedded in a tread", _embedded(climber), false)

	# And back down without being launched off the noses.
	var airborne := 0
	for i in 300:
		climber.update(DT, -1.0, 0.0, false, false, false, _world)
		if not climber.on_ground:
			airborne += 1
	_ok("stays glued walking back down", airborne < 15, true)

	print("-- jumping --")
	var jumper := _settled(-20.0, 0.0)
	var floor_y := jumper.position.y
	_drive(jumper, 0.0, 0.0, 6, true)
	_ok("leaves the ground on jump", jumper.position.y > floor_y + 0.1, true)
	for i in 240:
		jumper.update(DT, 0.0, 0.0, false, false, false, _world)
	_ok("comes back down and lands", jumper.on_ground, true)
	_ok("lands back where it took off", absf(jumper.position.y - floor_y) < 0.05, true)

	print("-- crouch --")
	var crouched := _settled(-20.0, 0.0)
	_drive(crouched, 0.0, 0.0, 60, false, true)
	_ok("crouches in the open", crouched.is_crouching, true)
	for i in 60:
		crouched.update(DT, 0.0, 0.0, false, false, false, _world)
	_ok("stands back up with headroom", crouched.is_crouching, false)
	_ok("is not embedded after standing", _embedded(crouched), false)

	print("-- sweeping the map for holes --")
	# Drop a player onto a grid of points. Every one must end up resting on
	# something inside the arena, never below the floor slab.
	var fell_through := 0
	var stuck := 0
	var step := arena / 6.0
	var x := -arena + step
	while x < arena:
		var z := -arena + step
		while z < arena:
			var m := _run(Vector3(x, 8.0, z), 0.0, 0.0, 240)
			if m.position.y < -1.0:
				fell_through += 1
			elif _embedded(m):
				stuck += 1
			z += step
		x += step
	_ok("nobody falls through the world", fell_through, 0)
	_ok("nobody lands embedded", stuck, 0)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
