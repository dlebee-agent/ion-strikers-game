extends SceneTree

# Drives a live GameInstance through the anti-cheat hooks on a small world
# with one wall, and checks each decision the module makes: which position
# reports are dropped, which shots are changed, who is left out of whose
# snapshot, and when strikes turn into a kick.
# Run: godot --headless --path game --script res://tools/anticheat_check.gd

const DT := 1.0 / 60.0
const A := 1
const B := 2

var failed := 0
var _strikes: Array = []          # [peer, kind]
var _kicks: Array = []            # [peer, reason]
var _tracers: Array[Dictionary] = []


func _initialize() -> void:
	_movement()
	_flight()
	_shots()
	_culling()
	_bench()
	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


# ── world: a floor and one wall along z at x=0 ─────────────────────────

func _instance(anticheat := true, floor_half := 30.0, wall_height := 4.0) -> GameInstance:
	var inst := GameInstance.new({
		"map_id": "parkour", "mode": "dm", "bots": false, "kills": 999, "anticheat": anticheat,
	})
	root.add_child(inst)
	inst.setup_map()
	var w := CollisionWorld.new()
	w.add_box(AABB(Vector3(-floor_half, -1.0, -floor_half), Vector3(floor_half * 2.0, 1.0, floor_half * 2.0)))
	w.add_box(AABB(Vector3(-0.5, 0.0, -5.0), Vector3(1.0, wall_height, 10.0)))
	w.build()
	inst.world = w
	inst.anti_cheat.configure(w)
	inst.match_state.round_state = Protocol.RS_ACTIVE
	inst.match_state.freeze_until = 0.0
	_strikes = []
	_kicks = []
	_tracers = []
	inst.anti_cheat.strike.connect(func(peer: int, kind: String, _n: int) -> void: _strikes.append([peer, kind]))
	inst.anti_cheat.kick_requested.connect(func(peer: int, reason: String) -> void: _kicks.append([peer, reason]))
	inst.event_broadcast.connect(func(_ch: int, data: PackedByteArray, _ex: int) -> void:
		var msg := Protocol.decode(data)
		if int(msg.get("t", -1)) == Protocol.Msg.TRACER:
			_tracers.append(msg))
	return inst


## Swaps the instance's world for a floor plus the given boxes.
func _world(inst: GameInstance, boxes: Array) -> void:
	var w := CollisionWorld.new()
	w.add_box(AABB(Vector3(-30.0, -1.0, -30.0), Vector3(60.0, 1.0, 60.0)))
	for box: AABB in boxes:
		w.add_box(box)
	w.build()
	inst.world = w
	inst.anti_cheat.configure(w)


func _player(inst: GameInstance, id: int, team: int, at: Vector3) -> ServerPawn:
	var p := Participant.new(id, "P%d" % id, false)
	p.team = team
	inst.participants[id] = p
	inst._spawn_pawn(id, 0.0)
	var pawn: ServerPawn = inst.pawns[id]
	pawn.position = at
	inst.anti_cheat.on_spawn(id, at, inst._now)
	return pawn


func _ticks(inst: GameInstance, n: int) -> void:
	for _i in n:
		inst.tick(DT)


func _report(inst: GameInstance, id: int, pos: Vector3, yaw := 0.0, grounded := true) -> void:
	inst.update_state(id, pos, yaw, 0.0, false, grounded)


func _count(kind: String, peer := A) -> int:
	var n := 0
	for s: Array in _strikes:
		if s[0] == peer and s[1] == kind:
			n += 1
	return n


func _expect(label: String, ok: bool) -> void:
	print("  %-58s %s" % [label, "ok " if ok else "FAIL"])
	if not ok:
		failed += 1


# ── movement ────────────────────────────────────────────────────────────

func _movement() -> void:
	print("movement")
	var inst := _instance()
	var pawn := _player(inst, A, Protocol.TEAM_BLUE, Vector3(-10.0, 0.0, -20.0))

	var pos := pawn.position
	for _i in 120:
		_ticks(inst, 1)
		pos.z += Movement.RUN_SPEED * DT
		_report(inst, A, pos)
	_expect("running at full speed is accepted", pawn.position.is_equal_approx(pos))

	# Lag: nothing for 2.5 s, then 18 m away. Within the budget, no strike.
	_ticks(inst, 150)
	pos.z -= 18.0
	_report(inst, A, pos)
	_expect("18 m after 2.5 s of silence is accepted (lag)", pawn.position.is_equal_approx(pos) and _strikes.is_empty())

	var before := pawn.position
	var far := before + Vector3(40.0, 0.0, 0.0)
	_ticks(inst, 1)
	_report(inst, A, far)
	_expect("a 40 m jump in one report is dropped", pawn.position.is_equal_approx(before))
	_expect("a dropped report is not yet a strike", _count("teleport") == 0)

	for _i in int(AcMovementCheck.RESYNC_S / DT) + 2:
		_ticks(inst, 1)
		_report(inst, A, far)
	_expect("after %.0f s the client is resynced" % AcMovementCheck.RESYNC_S, pawn.position.is_equal_approx(far))
	_expect("the resync counts one teleport", _count("teleport") == 1)

	var jumps := int(AcViolations.KICK_AFTER["teleport"])
	for _n in jumps - 1:
		far += Vector3(-40.0, 0.0, 0.0) if _n % 2 == 0 else Vector3(40.0, 0.0, 0.0)
		for _i in int(AcMovementCheck.RESYNC_S / DT) + 2:
			_ticks(inst, 1)
			_report(inst, A, far)
	_expect("%d teleports in a minute is a kick" % jumps, _kicks.size() == 1 and _kicks[0][1] == "teleport")
	inst.queue_free()

	# A bunny hop through the real solver: 60 deg/s of air strafe at 60 Hz
	# passes 25 m/s within 45 s. Every report must land and none may strike.
	var big := _instance(true, 2000.0)
	var hopper := _player(big, A, Protocol.TEAM_BLUE, Vector3(100.0, 0.0, 100.0))
	var m := Movement.new()
	m.position = hopper.position
	m.on_ground = true
	var side := 1.0
	var top := 0.0
	var landed := true
	for _i in 60 * 45:
		_ticks(big, 1)
		var jump := m.on_ground
		if jump:
			side = -side
		if not m.on_ground:
			m.yaw += side * 60.0 * DT
		m.update(DT, 0.0, side, jump, false, false, big.world)
		top = maxf(top, Vector2(m.velocity.x, m.velocity.z).length())
		_report(big, A, m.position, m.yaw, m.on_ground)
		landed = landed and hopper.position.is_equal_approx(m.position)
	_expect("a 45 s bunny hop peaking at %.0f m/s is accepted throughout" % top, landed and top > 25.0)
	_expect("and earns no strike", _strikes.is_empty())
	big.queue_free()

	# A dead player riding a bot reports from wherever the bot walked to.
	var ride := _instance()
	_player(ride, A, Protocol.TEAM_BLUE, Vector3(-10.0, 0.0, -20.0))
	var bot_p := Participant.new(B, "BOT", true)
	bot_p.team = Protocol.TEAM_BLUE
	ride.participants[B] = bot_p
	ride._spawn_pawn(B, 0.0)
	var bot_pawn: ServerPawn = ride.pawns[B]
	bot_pawn.position = Vector3(20.0, 0.0, 20.0)
	ride._bind_possession(A, B)
	_ticks(ride, 1)
	_report(ride, A, Vector3(20.1, 0.0, 20.0))
	_expect("the first report after a takeover is accepted", bot_pawn.position.is_equal_approx(Vector3(20.1, 0.0, 20.0)))
	ride.queue_free()


# ── flight and clipping ─────────────────────────────────────────────────

func _flight() -> void:
	print("flight")
	var inst := _instance()
	var pawn := _player(inst, A, Protocol.TEAM_BLUE, Vector3(-10.0, 0.0, 0.0))

	# A jump: up at JUMP_VEL, down under gravity, on the floor by 0.76 s.
	var t := 0.0
	var ok := true
	while t < 0.75:
		_ticks(inst, 1)
		t += DT
		var y := maxf(0.0, Movement.JUMP_VEL * t - 0.5 * Movement.GRAVITY * t * t)
		_report(inst, A, Vector3(-10.0, y, 0.0), 0.0, y <= 0.0)
		ok = ok and is_equal_approx(pawn.position.y, y)
	_expect("a jump is accepted throughout", ok and _strikes.is_empty())

	# Hover: parked 3 m up with nothing under it.
	var hover := Vector3(-10.0, 3.0, 0.0)
	pawn.position = hover
	inst.anti_cheat.on_spawn(A, hover, inst._now)
	for _i in int(AcFlightCheck.HOVER_S / DT) - 3:
		_ticks(inst, 1)
		_report(inst, A, hover)
	_expect("hanging in the air for under %.0f s is fine" % AcFlightCheck.HOVER_S, _count("flight") == 0)
	for _i in 6:
		_ticks(inst, 1)
		_report(inst, A, hover)
	_expect("hanging longer is a flight strike", _count("flight") == 1)
	var strikes_needed := int(AcViolations.KICK_AFTER["flight"])
	for _i in int((strikes_needed) * AcFlightCheck.STRIKE_GAP_S / DT) + 5:
		_ticks(inst, 1)
		_report(inst, A, hover)
	_expect("a hover that goes on is a kick", _kicks.size() == 1 and _kicks[0][1] == "flight")

	# Standing with the feet over a ledge: the solver allows the body's centre
	# up to its radius past the edge, and that is still standing.
	var ledge := Vector3(-30.0 - Movement.PLAYER_RADIUS + 0.02, 0.0, -10.0)
	var inst3 := _instance()
	_player(inst3, A, Protocol.TEAM_BLUE, ledge)
	for _i in int(AcFlightCheck.HOVER_S / DT) + 30:
		_ticks(inst3, 1)
		_report(inst3, A, ledge)
	_expect("standing on the very edge of a ledge is not flight", _strikes.is_empty())
	inst3.queue_free()

	# A long fall is not a hover: it keeps dropping.
	var inst2 := _instance()
	var pawn2 := _player(inst2, A, Protocol.TEAM_BLUE, Vector3(-10.0, 40.0, 0.0))
	t = 0.0
	while t < 1.5:
		_ticks(inst2, 1)
		t += DT
		_report(inst2, A, Vector3(-10.0, 40.0 - 0.5 * Movement.GRAVITY * t * t, 0.0), 0.0, false)
	_expect("a 1.5 s fall earns no strike", _strikes.is_empty() and pawn2.position.y < 30.0)

	# Inside the wall.
	var on_floor := Vector3(-0.9, 0.0, 0.0)
	pawn2.position = on_floor
	inst2.anti_cheat.on_spawn(A, on_floor, inst2._now)
	_ticks(inst2, 1)
	_report(inst2, A, Vector3(-0.4, 0.0, 0.0))
	_expect("a report from inside the wall is dropped", pawn2.position.is_equal_approx(on_floor))
	_expect("and is a noclip strike", _count("noclip") == 1)

	inst.queue_free()
	inst2.queue_free()


# ── shots ───────────────────────────────────────────────────────────────

func _shots() -> void:
	print("shots")
	var inst := _instance()
	var pawn := _player(inst, A, Protocol.TEAM_BLUE, Vector3(-10.0, 0.0, 0.0))
	_player(inst, B, Protocol.TEAM_RED, Vector3(10.0, 0.0, 20.0))
	_ticks(inst, 2)
	var eye := pawn.position + Vector3(0.0, Hitbox.EYE_STAND, 0.0)
	var ahead := AcShotCheck.aim_dir(pawn.yaw, pawn.pitch)

	for _i in 5:
		inst.handle_shot(A, eye, ahead, 80)
	_expect("five shots at once: two go through", _tracers.size() == 2)
	_expect("the other three are fire-rate strikes", _count("fire_rate") == 3)
	_ticks(inst, int(AcShotCheck.FIRE_GAP_S * 2.0 / DT) + 2)
	_tracers.clear()
	for _i in 3:
		inst.handle_shot(A, eye, ahead, 80)
	_expect("two more after two fire delays", _tracers.size() == 2)

	_ticks(inst, int(AcShotCheck.FIRE_GAP_S / DT) + 2)
	_tracers.clear()
	inst.handle_shot(A, eye + Vector3(5.0, 0.0, 0.0), ahead, 80)
	var tr := _tracers[0] if not _tracers.is_empty() else {}
	var moved := Vector3(float(tr.get("origin_x", 99.0)), float(tr.get("origin_y", 99.0)), float(tr.get("origin_z", 99.0)))
	_expect("an origin 5 m from the eye is moved to the eye", moved.is_equal_approx(eye))
	_expect("and is a shot_origin strike", _count("shot_origin") == 1)

	var v := inst.anti_cheat.shots.check_shot(A, pawn, eye, ahead, 300, 20, inst._now + 10.0, 300.0)
	_expect("rewind is capped by the shooter's own ping", int(v["lag_ms"]) == int(20 * 0.5 + AcShotCheck.LAG_SLACK_MS))

	_ticks(inst, int(AcShotCheck.FIRE_GAP_S / DT) + 2)
	inst.handle_shot(A, eye, -ahead, 80)
	_expect("a shot behind the reported view is an aim_view strike", _count("aim_view") == 1)

	var off := _instance(false)
	var pawn_off := _player(off, A, Protocol.TEAM_BLUE, Vector3(-10.0, 0.0, 0.0))
	_ticks(off, 2)
	for _i in 5:
		off.handle_shot(A, pawn_off.position + Vector3(0.0, Hitbox.EYE_STAND, 0.0), ahead, 80)
	_expect("with anticheat off all five shots go through", _tracers.size() == 5)

	inst.queue_free()
	off.queue_free()


# ── corner culling ──────────────────────────────────────────────────────

func _snap_pos(inst: GameInstance, receiver: int, of: int) -> Vector3:
	var snap := Protocol.decode(inst.build_snap(receiver))
	for p: Dictionary in snap.get("players", []):
		if int(p["id"]) == of:
			return Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
	return Vector3(NAN, NAN, NAN)


func _hidden(inst: GameInstance, receiver: int, of: int) -> bool:
	return _snap_pos(inst, receiver, of).y == GameInstance.HIDDEN_Y


func _culling() -> void:
	print("culling")
	var inst := _instance()
	var a := _player(inst, A, Protocol.TEAM_BLUE, Vector3(-5.0, 0.0, 0.0))
	var b := _player(inst, B, Protocol.TEAM_RED, Vector3(5.0, 0.0, 0.0))
	_ticks(inst, 1)

	_expect("across the wall, A's snapshot hides B", _hidden(inst, A, B))
	_expect("and B's hides A", _hidden(inst, B, A))
	_expect("A still sees itself", _snap_pos(inst, A, A).is_equal_approx(a.position))
	_expect("a receiver of 0 gets everything", _snap_pos(inst, 0, B).is_equal_approx(b.position))

	# Well past the wall's end (z=5): plain line of sight. Every move below
	# is followed by a few ticks so the pair is due for another look.
	b.position = Vector3(5.0, 0.0, 12.0)
	_ticks(inst, 5)
	_expect("in the open B is sent", _snap_pos(inst, A, B).is_equal_approx(b.position))

	# Back behind the wall: held for HOLD_S, then hidden.
	b.position = Vector3(5.0, 0.0, 0.0)
	_ticks(inst, 5)
	_expect("just after ducking back B is still sent (hold)", not _hidden(inst, A, B))
	_ticks(inst, int(AcVisibilityCull.HOLD_S / DT) + 2)
	_expect("after the hold B is hidden", _hidden(inst, A, B))

	# Peeking: the centre line to (5,0,9.4) crosses x=0 at z=4.7, inside the
	# wall, but B can be a lead further along by the time A's snapshot shows.
	b.position = Vector3(5.0, 0.0, 9.4)
	_ticks(inst, 5)
	_expect("a peeker still behind the edge is sent early (lookahead)", not _hidden(inst, A, B))
	b.position = Vector3(5.0, 0.0, 6.0)
	_ticks(inst, int(AcVisibilityCull.HOLD_S / DT) + 2)
	_expect("but not from deep behind it", _hidden(inst, A, B))

	# Through a wall but close: always sent.
	a.position = Vector3(-1.0, 0.0, 0.0)
	b.position = Vector3(1.0, 0.0, 0.0)
	_ticks(inst, 5)
	_expect("within %.0f m B is sent through the wall" % AcVisibilityCull.NEAR_ALWAYS, not _hidden(inst, A, B))

	# A dead receiver gets everything.
	a.position = Vector3(-5.0, 0.0, 0.0)
	b.position = Vector3(5.0, 0.0, 0.0)
	_ticks(inst, int(AcVisibilityCull.HOLD_S / DT) + 2)
	_expect("hidden again once apart", _hidden(inst, A, B))
	a.alive = false
	_ticks(inst, 5)
	_expect("a dead receiver is told where B is", _snap_pos(inst, A, B).is_equal_approx(b.position))
	inst.queue_free()

	# The viewer is the one peeking: a step past the wall's end opens the
	# line, while pushing the far target sideways would not.
	var peek := _instance()
	var pa := _player(peek, A, Protocol.TEAM_BLUE, Vector3(-1.0, 0.0, 4.5))
	var pb := _player(peek, B, Protocol.TEAM_RED, Vector3(8.0, 0.0, 0.0))
	_ticks(peek, 1)
	_expect("a viewer about to step past the edge is sent the enemy", _snap_pos(peek, A, B).is_equal_approx(pb.position))
	pa.position = Vector3(-1.0, 0.0, -2.0)
	_ticks(peek, int(AcVisibilityCull.HOLD_S / DT) + 2)
	_expect("but not from well inside the wall's shadow", _hidden(peek, A, B))
	peek.queue_free()

	# A fast body gets a longer lead: hidden at rest where it is sent at
	# 20 m/s, since the server's own history says where it will be.
	var fast := _instance()
	_player(fast, A, Protocol.TEAM_BLUE, Vector3(-5.0, 0.0, 0.0))
	var fb := _player(fast, B, Protocol.TEAM_RED, Vector3(5.0, 0.0, 6.5))
	_ticks(fast, 5)
	_expect("at rest, deep enough behind the edge to be hidden", _hidden(fast, A, B))
	# Two history samples 0.2 s apart and 4 m along z say 20 m/s; the pair
	# cache is cleared so the next snapshot looks again at once.
	fb.record_history(fast._now - 0.2)
	fb.position = Vector3(5.0, 0.0, 6.5 + 20.0 * 0.2)
	fb.record_history(fast._now)
	fb.position = Vector3(5.0, 0.0, 6.5)
	fast.anti_cheat.culling._pairs.clear()
	_expect("moving at 20 m/s the same spot is sent (speed lead)", not _hidden(fast, A, B))
	fast.queue_free()

	# A viewer in front of a 0.6 m slit with the enemy dead ahead behind the
	# wall: a full-lead sidestep lands past the slit, a half one in it.
	var slit := _instance()
	_world(slit, [AABB(Vector3(-0.5, 0.0, -5.0), Vector3(1.0, 4.0, 4.1)),
		AABB(Vector3(-0.5, 0.0, -0.3), Vector3(1.0, 4.0, 5.3))])
	_player(slit, A, Protocol.TEAM_BLUE, Vector3(-1.0, 0.0, -1.4))
	var sb := _player(slit, B, Protocol.TEAM_RED, Vector3(8.0, 0.0, -1.4))
	_ticks(slit, 1)
	_expect("half a sidestep from a slit is enough to be sent the enemy", _snap_pos(slit, A, B).is_equal_approx(sb.position))
	slit.queue_free()

	# Next to the blocking wall a hidden pair is looked at again every tick;
	# far from it, every 50 ms.
	var near := _instance()
	_player(near, A, Protocol.TEAM_BLUE, Vector3(-1.5, 0.0, 0.0))
	var nb := _player(near, B, Protocol.TEAM_RED, Vector3(5.0, 0.0, 0.0))
	_ticks(near, 1)
	_expect("hidden with the viewer 1 m from the wall", _hidden(near, A, B))
	nb.position = Vector3(5.0, 0.0, 12.0)
	_ticks(near, 1)
	_expect("one tick later the move into the open is already sent", _snap_pos(near, A, B).is_equal_approx(nb.position))
	near.queue_free()
	var farv := _instance()
	_player(farv, A, Protocol.TEAM_BLUE, Vector3(-6.0, 0.0, 0.0))
	var fbb := _player(farv, B, Protocol.TEAM_RED, Vector3(5.0, 0.0, 0.0))
	_ticks(farv, 1)
	_expect("hidden with the viewer 5.5 m from the wall", _hidden(farv, A, B))
	fbb.position = Vector3(5.0, 0.0, 12.0)
	_ticks(farv, 1)
	_expect("one tick later it is still the cached verdict", _hidden(farv, A, B))
	_ticks(farv, 3)
	_expect("and sent once the 50 ms recheck comes round", _snap_pos(farv, A, B).is_equal_approx(fbb.position))
	farv.queue_free()

	# A wall too tall to see over standing, but not after a jump: the eye
	# rises about 1.45 m at the apex. Vertical lookahead sends B before the hop.
	var low := _instance(true, 30.0, 2.2)
	_player(low, A, Protocol.TEAM_BLUE, Vector3(-1.5, 0.0, 0.0))
	var lb := _player(low, B, Protocol.TEAM_RED, Vector3(3.0, 0.0, 0.0))
	_ticks(low, 1)
	_expect("over a %.1f m wall B is sent for the jump to come" % 2.2, _snap_pos(low, A, B).is_equal_approx(lb.position))
	low.queue_free()


# ── cost ────────────────────────────────────────────────────────────────

func _bench() -> void:
	print("cost on parkour")
	var inst := GameInstance.new({"map_id": "parkour", "mode": "dm", "bots": false})
	root.add_child(inst)
	inst.setup_map()
	var a := ServerPawn.new()
	a.participant_id = A
	var b := ServerPawn.new()
	b.participant_id = B
	var cull := AcVisibilityCull.new()
	var points := inst.bot_director.nav.open_points
	var n := 0
	var hidden := 0
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		inst.world.raycast(points[i % points.size()] + Vector3(0.0, 1.6, 0.0),
			points[(i * 31 + 7) % points.size()] + Vector3(0.0, 1.0, 0.0), cull._trace)
	print("  one ray: %.0f us" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in 400:
		a.position = points[(i * 7919) % points.size()]
		b.position = points[(i * 104729 + 13) % points.size()]
		a.participant_id = i * 2 + 10
		b.participant_id = i * 2 + 11
		if not cull.sees(inst.world, a, b, 1.0, -100.0 - i):
			hidden += 1
		n += 1
	var us := float(Time.get_ticks_usec() - t0) / float(n)
	print("  %d pairs, %d hidden, %.0f us per pair" % [n, hidden, us])
	_expect("an open pair on parkour costs under 1 ms", us < 1000.0)
	inst.queue_free()

	# Worst case: every ray blocked, on the one-wall world.
	var w := _instance()
	var va := ServerPawn.new()
	va.participant_id = A
	var vb := ServerPawn.new()
	vb.participant_id = B
	var wcull := AcVisibilityCull.new()
	t0 = Time.get_ticks_usec()
	for i in 400:
		va.position = Vector3(-5.0, 0.0, -3.0 + (i % 7) * 0.5)
		vb.position = Vector3(5.0, 0.0, -3.0 + (i % 5) * 0.5)
		va.participant_id = i * 2 + 10
		vb.participant_id = i * 2 + 11
		if not wcull.sees(w.world, va, vb, 1.0, -100.0 - i):
			hidden += 1
	us = float(Time.get_ticks_usec() - t0) / 400.0
	print("  400 hidden pairs behind a wall, %.0f us per pair" % us)
	_expect("a hidden pair costs under 2 ms", us < 2000.0)
	w.queue_free()
