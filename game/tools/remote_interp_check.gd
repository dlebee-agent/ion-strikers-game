extends SceneTree

# Audits what the CLIENT draws, not what the server computes.
# Run: godot --headless --path game --script res://tools/remote_interp_check.gd
#
# The server collides bots properly and tools/bot_collision_check.gd proves it.
# None of that reaches the screen directly: a remote body is drawn by lerping
# between two received snapshots, and a straight line between two points on a
# collision-resolved path can cut through the level. Snapshots arrive at half
# the server's tick rate, unsequenced, so this measures the rendered position
# against the same world the server used — with packets reordered and dropped,
# because that is when the chord gets long.

const TICK := 1.0 / 60.0
const SNAP_EVERY := 2      # 60 Hz server tick, 30 Hz snapshots
const SECONDS := 40
const MAP := "community/arena1"

# The rendered body may graze a corner; a slide legitimately does. Anything
# approaching the body's own radius is it being drawn inside the level.
const BREACH := 0.20

var failed := 0


var _path: Array = []
var _frame := 0


func _initialize() -> void:
	_path = _record()
	print("recorded %d server frames for %d bots" % [_path.size(), _path[0].size()])


# RemotePawn reads its mannequin's global transform, which only exists once the
# node is in a running tree — so the replays wait a frame.
func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_replay(_path, "in order, no loss", 0.0, false)
	_replay(_path, "10% loss", 0.10, false)
	_replay(_path, "10% loss + reordering", 0.10, true)
	print("\nFAILURES: ", failed)
	quit(1 if failed > 0 else 0)
	return true


# One authoritative run, kept as the ground truth every replay is measured on.
func _record() -> Array:
	var inst := GameInstance.new({
		"map_id": MAP, "mode": "arena", "bots": true, "rounds": 99,
		"max_players": 12, "bots_shoot": true,
	})
	root.add_child(inst)
	inst.setup_map()
	inst.admit_spectator(1, "Auditor")
	inst.handle_set_team(1, Protocol.TEAM_BLUE)
	inst._kill_pawn(1, Protocol.CAUSE_VOID, 0, true)

	var frames: Array = []
	for i in 60 * SECONDS:
		inst.tick(TICK)
		var row: Array = []
		for pid: int in inst.pawns:
			if inst.participants[pid].is_bot and inst.pawns[pid].alive:
				row.append(inst.pawns[pid].position)
		frames.append(row)
	_world = inst.world
	return frames


var _world: CollisionWorld


func _replay(frames: Array, label: String, loss: float, reorder: bool) -> void:
	var body := Vector3(BotNav.BODY_RADIUS, BotNav.BODY_HEIGHT * 0.5, BotNav.BODY_RADIUS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# Real RemotePawns, fed exactly the way match.gd feeds them and read back
	# through their own interpolate(). No reimplementation of the bracket
	# search: if the shipped code cuts a corner, this sees it.
	var count: int = frames[0].size()
	var pawns: Array = []
	for k in count:
		var rp = load("res://core/remote_pawn.gd").new()
		root.add_child(rp)
		rp.setup(-1 - k, "BOT %d" % k, 2)
		rp.adopt_initial_alive(true)
		pawns.append(rp)

	var clock := 0.0
	var sample_clock := 0.0
	var held: Array = []
	var samples := 0
	var breaches := 0
	var worst := 0.0

	for i in frames.size():
		clock += TICK
		if i % SNAP_EVERY == 0:
			var pkt := {"row": frames[i]}
			var queue: Array = []
			if reorder and held.size() > 0 and rng.randf() < 0.5:
				queue.append(held.pop_front())
			if rng.randf() >= loss:
				if reorder and rng.randf() < 0.25:
					held.append(pkt)
				else:
					queue.append(pkt)
			for q: Dictionary in queue:
				# The same monotonic stamp match.gd uses.
				sample_clock = maxf(clock, sample_clock + 0.002)
				var row: Array = q["row"]
				for k in mini(count, row.size()):
					var v: Vector3 = row[k]
					pawns[k].push_snapshot({
						"x": v.x, "y": v.y, "z": v.z, "yaw": 0.0, "pitch": 0.0,
						"alive": true, "grounded": true, "crouched": false,
					}, sample_clock)

		# Draw, through the real interpolator, and read the mannequin back.
		for k in count:
			var rp = pawns[k]
			rp.interpolate(clock)
			if rp._samples.size() < 1:
				continue
			var drawn: Vector3 = rp._mannequin.global_position
			samples += 1
			var centre := drawn + Vector3(0.0, body.y, 0.0)
			if _world.box_overlaps(centre, body):
				var depth := _world.depenetrate(centre, body).length()
				if depth > BREACH:
					breaches += 1
					worst = maxf(worst, depth)

	for rp in pawns:
		rp.queue_free()

	var pct := 100.0 * breaches / maxi(1, samples)
	print("  %-24s drawn %6d   INSIDE LEVEL %5d (%.2f%%)  worst %.2f m"
		% [label, samples, breaches, pct, worst])
	if breaches > 0:
		failed += 1
