extends SceneTree

# Throwaway harness: drives a headless match and reports what the bots do.
# Run: godot --headless --path game --script res://tools/bot_sim_check.gd

# The two audits below test trigger discipline, not target acquisition, so they
# run with the cone and the burst pause opened right up. Left on a difficulty
# preset they would spend the whole run failing to notice the enemy instead.
const AUDIT_SESSION := {
	"reaction": 0.0, "aim_err": 0.0, "aim_gate": 0.11, "turn": 0.30,
	"fov": 360.0, "sight": 200.0, "fire_gap": 0.15,
	"burst": 100000, "burst_pause": 0.0,
	"duck_chance": 0.0, "cover_chance": 0.0, "idle_chance": 0.0,
}

func _initialize() -> void:
	var compiled := MapEngine.compile(ParkourMap.definition())
	var cols := MapBuilder.build_world(compiled)
	var arena: float = compiled["arena"]

	var nav := BotNav.new()
	var t0 := Time.get_ticks_msec()
	nav.build(cols, arena, [Vector3(0, 0, -23), Vector3(0, 0, 23), Vector3.ZERO])
	print("nav build ms: ", Time.get_ticks_msec() - t0, "  open cells: ", nav.open_points.size())

	print("-- line of sight --")
	print("  spawn->spawn over the hills (want true):  ", nav.blocked(Vector3(0, 1.6, -23), Vector3(0, 1.15, 23)))
	print("  through the perimeter wall (want true):   ", nav.blocked(Vector3(0, 1.6, -20), Vector3(0, 1.15, -40)))
	print("  clear side lane (want false):             ", nav.blocked(Vector3(20, 1.6, -8), Vector3(20, 1.15, 8)))
	print("  point blank (want false):                 ", nav.blocked(Vector3(0, 1.6, -23), Vector3(2, 1.15, -21)))
	print("  over a 0.9m crate (want false):           ", nav.blocked(Vector3(-14, 1.6, -16), Vector3(-14, 1.15, -12.5)))
	print("  into a 2.4m pillar (want true):           ", nav.blocked(Vector3(-14, 1.6, -10), Vector3(-14, 1.15, -5)))

	var t1 := Time.get_ticks_msec()
	var path := nav.find_path(Vector3(0, 0, -23), Vector3(0, 0, 23))
	print("-- routing --")
	print("  blue spawn -> red spawn: ", path.size(), " waypoints in ", Time.get_ticks_msec() - t1, "ms")
	var peaks := ""
	for wp in path:
		peaks += "(%.0f,%.1f,%.0f) " % [wp.x, wp.y, wp.z]
	print("  ", peaks)

	_wall_audit(cols, arena)
	_pinned_audit(cols, arena)

	print("\n== difficulty sweep (60s deathmatch each) ==")
	for level: String in BotSkill.LEVELS:
		_run_match(arena, level)

	quit()


func _pinned_audit(cols: CollisionWorld, arena: float) -> void:
	var director := BotDirector.new()
	director.configure(cols, arena, MapCatalog.normalize_spawns(ParkourMap.definition()["spawns"]))

	var bot := Participant.new(-1, "BOT Pinned", true)
	bot.team = Protocol.TEAM_BLUE
	bot.connection_session = AUDIT_SESSION.duplicate()
	director.init_ai(bot)

	var victim := Participant.new(2, "Victim", false)
	victim.team = Protocol.TEAM_RED

	var bot_pawn := ServerPawn.new()
	bot_pawn.position = Vector3(18.0, 0.0, -6.0)
	var victim_pawn := ServerPawn.new()
	victim_pawn.position = Vector3(18.0, 0.0, 6.0)

	var people := {-1: bot, 2: victim}
	var bodies := {-1: bot_pawn, 2: victim_pawn}

	var start := bot_pawn.position
	var shots := 0
	var now := 0.0
	var dt := 1.0 / 60.0
	for i in 600:
		now += dt
		var out := director.update_bot(bot, bot_pawn, people, bodies, true, false, true, now, dt)
		if out["shoot"] or out["special_start"]:
			shots += 1

	print("-- pinned audit (10s, bots_move off) --")
	print("  drifted: %.3fm   shots wanted: %d   final y: %.2f" % [
		(bot_pawn.position - start).length(), shots, bot_pawn.position.y,
	])


func _wall_audit(cols: CollisionWorld, arena: float) -> void:
	var director := BotDirector.new()
	director.configure(cols, arena, MapCatalog.normalize_spawns(ParkourMap.definition()["spawns"]))

	var shooter := Participant.new(-1, "BOT Audit", true)
	shooter.team = Protocol.TEAM_BLUE
	shooter.connection_session = AUDIT_SESSION.duplicate()
	director.init_ai(shooter)

	var victim := Participant.new(2, "Victim", false)
	victim.team = Protocol.TEAM_RED

	var shooter_pawn := ServerPawn.new()
	shooter_pawn.participant_id = -1
	shooter_pawn.position = Vector3(0.0, 0.0, -13.0)
	var victim_pawn := ServerPawn.new()
	victim_pawn.participant_id = 2
	victim_pawn.position = Vector3(0.0, 0.0, -6.0)

	var people := {-1: shooter, 2: victim}
	var bodies := {-1: shooter_pawn, 2: victim_pawn}

	var shots := 0
	var through_wall := 0
	var now := 0.0
	var dt := 1.0 / 60.0
	for i in 900:
		now += dt
		shooter_pawn.position = Vector3(0.0, 0.0, -13.0)
		var out := director.update_bot(shooter, shooter_pawn, people, bodies, true, true, true, now, dt)
		if out["shoot"] or out["special_start"]:
			shots += 1
			var eye := Vector3(0.0, Hitbox.eye_height(false), -13.0)
			var aim := Vector3(0.0, Hitbox.aim_height(false), -6.0)
			if director.nav.blocked(eye, aim):
				through_wall += 1

	print("-- wall audit (15s, enemy behind the 2.4m crest) --")
	print("  shots wanted: ", shots, "   fired with geometry in the way: ", through_wall)


func _run_match(arena: float, level: String) -> void:
	var inst := GameInstance.new({
		"map_id": "parkour", "mode": "dm", "bots": true,
		"kills": 999, "bot_skill": level,
	})
	root.add_child(inst)
	inst.setup_map()

	var human := Participant.new(1, "Tester", false)
	human.team = Protocol.TEAM_BLUE
	inst.participants[1] = human
	inst._spawn_pawn(1)
	(inst.pawns[1] as ServerPawn).position = Vector3(-20.0, 0.0, -20.0)

	inst._manage_bots()
	inst.match_state.round_state = Protocol.RS_ACTIVE
	for pid: int in inst.participants:
		if pid != 1:
			inst._spawn_pawn(pid)

	var dt := 1.0 / 60.0
	var start: Dictionary = {}
	var travelled: Dictionary = {}
	var peak_y: Dictionary = {}
	var stopped_ticks: Dictionary = {}
	var crouched_ticks: Dictionary = {}
	for pid: int in inst.pawns:
		start[pid] = (inst.pawns[pid] as ServerPawn).position
		travelled[pid] = 0.0
		peak_y[pid] = 0.0
		stopped_ticks[pid] = 0
		crouched_ticks[pid] = 0

	var prev: Dictionary = start.duplicate()
	var sim_t0 := Time.get_ticks_msec()
	var span_z := {}
	for i in 3600:  # 60 seconds
		inst.tick(dt)
		(inst.pawns[1] as ServerPawn).position = Vector3(-20.0, 0.0, -20.0)
		(inst.pawns[1] as ServerPawn).protected_until = 1e9
		for pid: int in inst.pawns:
			var pawn: ServerPawn = inst.pawns[pid]
			if not pawn.alive:
				continue
			if prev.has(pid):
				var hop := (pawn.position - (prev[pid] as Vector3)).length()
				if hop < 1.0:
					travelled[pid] = float(travelled[pid]) + hop
				if hop < 0.01:
					stopped_ticks[pid] = int(stopped_ticks[pid]) + 1
			if pawn.crouched:
				crouched_ticks[pid] = int(crouched_ticks[pid]) + 1
			prev[pid] = pawn.position
			peak_y[pid] = maxf(float(peak_y.get(pid, 0.0)), pawn.position.y)
			var seen: Array = span_z.get(pid, [999.0, -999.0])
			span_z[pid] = [minf(seen[0], pawn.position.z), maxf(seen[1], pawn.position.z)]

	print("-- %s (60s, %dms cpu) --" % [level.to_upper(), Time.get_ticks_msec() - sim_t0])
	for pid: int in inst.participants:
		var p: Participant = inst.participants[pid]
		if not inst.pawns.has(pid):
			continue
		var seen: Array = span_z.get(pid, [0.0, 0.0])
		var stop_s := float(stopped_ticks.get(pid, 0)) * dt
		var crouch_s := float(crouched_ticks.get(pid, 0)) * dt
		print("  %-12s team=%d  moved=%6.1fm  stopped=%.1fs  crouched=%.1fs  kills=%d deaths=%d" % [
			p.display_name, p.team, float(travelled.get(pid, 0.0)),
			stop_s, crouch_s, p.kills, p.deaths,
		])

	var total_kills := 0
	for pid: int in inst.participants:
		total_kills += (inst.participants[pid] as Participant).kills
	print("  total kills: ", total_kills, "   arena: ", arena)

	inst.queue_free()
