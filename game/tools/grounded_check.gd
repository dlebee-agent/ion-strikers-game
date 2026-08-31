extends SceneTree

# Throwaway harness: the grounded flag survives both wire hops, and the
# animation state machine reads it.
# Run: godot --headless --path game --script res://tools/grounded_check.gd

var _fails := 0


func _ok(label: String, got, want) -> void:
	var pass_: bool = got == want
	if not pass_:
		_fails += 1
	print("  %-52s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


func _initialize() -> void:
	print("-- client to server --")
	for grounded: bool in [true, false]:
		for crouched: bool in [true, false]:
			var buf := Protocol.encode_state(1.0, 2.0, 3.0, 45.0, -10.0, crouched, grounded)
			var msg: Dictionary = Protocol.decode(buf)
			_ok("grounded=%s crouched=%s survives" % [grounded, crouched],
				[msg.get("grounded"), msg.get("crouched")], [grounded, crouched])
			_ok("  and the position with it", msg.get("y"), 2.0)

	print("-- server to client --")
	# The snapshot carries it as its own bit, so it cannot collide with another.
	var bits := [Protocol.PFLG_ALIVE, Protocol.PFLG_CROUCHED, Protocol.PFLG_PROTECTED,
		Protocol.PFLG_BOT, Protocol.PFLG_SPECIAL_ARMED, Protocol.PFLG_SPECIAL_CHARGING,
		Protocol.PFLG_GROUNDED]
	var seen := {}
	var clashes := 0
	for b: int in bits:
		if seen.has(b):
			clashes += 1
		seen[b] = true
	_ok("every snapshot flag has its own bit", clashes, 0)
	_ok("grounded fits in a byte", Protocol.PFLG_GROUNDED < 256, true)

	var players := [{
		"id": 7, "flags": Protocol.PFLG_ALIVE | Protocol.PFLG_GROUNDED,
		"x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.0, "pitch": 0.0,
		"hp": 100, "kills": 0, "deaths": 0, "team": 1, "ping": 20,
		"special_progress": 0,
	}]
	var snap: Dictionary = Protocol.decode(Protocol.encode_snap(0, 0, 1, 0, 0, 10, 3, players))
	var back: Dictionary = (snap["players"] as Array)[0]
	_ok("grounded set on the wire", (int(back["flags"]) & Protocol.PFLG_GROUNDED) != 0, true)
	_ok("crouched still clear", (int(back["flags"]) & Protocol.PFLG_CROUCHED) != 0, false)

	print("-- the animation reads it --")
	# Walking up a ramp: real upward speed, but standing on something. The old
	# rule read vy > 1.2 as airborne and held the jump pose all the way up.
	var m := Movement.new()
	m.velocity = Vector3(4.0, 2.0, 0.0)
	m.on_ground = true
	var driver := AnimDriver.new()
	_ok("climbing a slope is not a jump", driver._resolve_state(m) != AnimDriver.State.JUMP, true)
	m.on_ground = false
	_ok("actually airborne still is", driver._resolve_state(m), AnimDriver.State.JUMP)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
