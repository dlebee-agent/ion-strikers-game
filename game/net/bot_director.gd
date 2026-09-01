class_name BotDirector
extends RefCounted

## Server-side bot brains. One BotNav is shared by every bot on the map; the
## per-bot state lives in Participant.connection_session["ai"].

const BOT_TARGET_PER_TEAM := 3
const BOT_NAMES: Array[String] = [
	"Vortex", "Ghost", "Razor", "Nova", "Echo", "Blitz", "Cobra", "Ace",
	"Fury", "Jinx", "Rook", "Zero", "Havoc", "Sly", "Onyx", "Viper",
]

const SPECIAL_RANGE := 45.0
const PREFERRED_RANGE := 12.0
const MELEE_RANGE := 2.2
const PLAYER_R := BotNav.BODY_RADIUS
const BODY_HEIGHT := BotNav.BODY_HEIGHT
const STEP_UP := BotNav.STEP_UP

const THINK_INTERVAL := 0.09
const MEMORY_TIME := 5.0
const REPATH_INTERVAL := 1.1
const WAYPOINT_R := 0.9
const ROAM_TIMEOUT := 9.0
const SEPARATION_R := 1.8
const AIM_DRIFT_INTERVAL := 0.25

const STUCK_THINKS := 4
const STUCK_DIST := 0.22

## How long a bot hides behind cover before peeking back out.
const COVER_PEEK_LO := 1.2
const COVER_PEEK_HI := 2.8
## How far to search for a cover spot.
const COVER_SEARCH_R := 10.0

## Alert window after taking damage — lifts the FOV cone so a bot shot from
## behind can spin around and fight.
const ALERT_DURATION := 3.0

var nav: BotNav = null
var _skill_level: String = BotSkill.DEFAULT_LEVEL
var _preset: Dictionary = BotSkill.preset(BotSkill.DEFAULT_LEVEL)

var _name_idx: int = 0
var _next_bot_id: int = -1
var _arena_size: float = 28.0
var _homes: Dictionary = {}


func set_skill(level: String) -> void:
	_skill_level = BotSkill.normalize(level)
	_preset = BotSkill.preset(_skill_level)


func configure(world: CollisionWorld, arena: float, spawns: Dictionary) -> void:
	_arena_size = arena
	_homes.clear()

	var seeds: Array[Vector3] = [Vector3.ZERO]
	for key: String in spawns:
		var points: Array = spawns[key]
		if points.is_empty():
			continue
		var sum := Vector3.ZERO
		for entry: Dictionary in points:
			var pos: Vector3 = entry["position"]
			seeds.append(pos)
			sum += pos
		var team_val := Protocol.TEAM_BLUE if key == "blue" else Protocol.TEAM_RED
		_homes[team_val] = sum / float(points.size())

	nav = BotNav.new()
	nav.build(world, arena, seeds)


# ── roster ───────────────────────────────────────────────────────────────

func manage_bots(participants: Dictionary, bots_enabled: bool, max_players: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	if not bots_enabled:
		for pid: int in participants:
			var p: Participant = participants[pid]
			if p.is_bot:
				actions.append({"action": "remove", "id": pid})
		return actions

	var human_count := 0
	var humans_blue := 0
	var humans_red := 0
	var bots_blue := 0
	var bots_red := 0

	for pid: int in participants:
		var p: Participant = participants[pid]
		if p.is_bot:
			if p.team == Protocol.TEAM_BLUE:
				bots_blue += 1
			elif p.team == Protocol.TEAM_RED:
				bots_red += 1
		else:
			human_count += 1
			if p.team == Protocol.TEAM_BLUE:
				humans_blue += 1
			elif p.team == Protocol.TEAM_RED:
				humans_red += 1

	if human_count == 0:
		for pid: int in participants:
			var p: Participant = participants[pid]
			if p.is_bot:
				actions.append({"action": "remove", "id": pid})
		return actions

	var total_count := participants.size()

	for team_data: Array in [[Protocol.TEAM_BLUE, humans_blue, bots_blue], [Protocol.TEAM_RED, humans_red, bots_red]]:
		var team_val: int = team_data[0]
		var humans_on: int = team_data[1]
		var bots_on: int = team_data[2]

		var want := maxi(0, BOT_TARGET_PER_TEAM - humans_on)
		var need := mini(want, max_players - total_count) - bots_on

		for _i in range(need):
			var bot := _make_bot_info(team_val)
			actions.append(bot)
			total_count += 1

		if bots_on > want:
			var extra := bots_on - want
			for pid: int in participants:
				if extra <= 0:
					break
				var p: Participant = participants[pid]
				if p.is_bot and p.team == team_val:
					actions.append({"action": "remove", "id": pid})
					extra -= 1

	return actions


func _make_bot_info(team_val: int) -> Dictionary:
	var bot_name := "BOT " + BOT_NAMES[_name_idx % BOT_NAMES.size()]
	_name_idx += 1

	var id := _next_bot_id
	_next_bot_id -= 1

	var info := {
		"action": "add",
		"id": id,
		"name": bot_name,
		"team": team_val,
	}
	# Write every preset field into the connection_session so init_ai picks
	# them up without knowing which level is active.
	for key: String in _preset:
		info[key] = _preset[key]
	return info


func init_ai(p: Participant) -> void:
	var s := p.connection_session
	var pr := _preset
	p.connection_session["ai"] = {
		"aim_err": s.get("aim_err", pr.get("aim_err", 0.12)),
		"aim_gate": s.get("aim_gate", pr.get("aim_gate", 0.20)),
		"reaction": s.get("reaction", pr.get("reaction", 0.55)),
		"fire_gap": s.get("fire_gap", pr.get("fire_gap", 0.34)),
		"burst": s.get("burst", pr.get("burst", 3)),
		"burst_pause": s.get("burst_pause", pr.get("burst_pause", 0.9)),
		"turn": s.get("turn", pr.get("turn", 0.11)),
		"fov": s.get("fov", pr.get("fov", 130.0)),
		"sight": s.get("sight", pr.get("sight", 30.0)),
		"speed": s.get("speed", pr.get("speed", 0.85)),
		# The same solver a player is moved by. There is no second movement
		# model for bots any more: everything about how a body slides, steps,
		# lands and crouches lives in Movement and is tested there.
		"mover": Movement.new(),
		"idle_chance": s.get("idle_chance", pr.get("idle_chance", 0.30)),
		"idle_time_lo": s.get("idle_time_lo", pr.get("idle_time_lo", 0.8)),
		"idle_time_hi": s.get("idle_time_hi", pr.get("idle_time_hi", 2.0)),
		"duck_chance": s.get("duck_chance", pr.get("duck_chance", 0.25)),
		"cover_chance": s.get("cover_chance", pr.get("cover_chance", 0.40)),
		"special_delay": s.get("special_delay", pr.get("special_delay", 1.2)),
		"state": "roam",
		"target": 0,
		"visible": false,
		"seen_at": 0.0,
		"last_seen_pos": Vector3.ZERO,
		"last_seen_at": -100.0,
		"yaw": 0.0,
		"pitch": 0.0,
		"err_yaw": 0.0,
		"err_pitch": 0.0,
		"err_yaw_to": 0.0,
		"err_pitch_to": 0.0,
		"drift_at": 0.0,
		"strafe_dir": 1.0 if randf() < 0.5 else -1.0,
		"strafe_flip_at": 0.0,
		"path": PackedVector3Array(),
		"path_i": 0,
		"path_goal": Vector3.ZERO,
		"goal": Vector3.ZERO,
		"has_goal": false,
		"goal_at": 0.0,
		"repath_at": 0.0,
		"next_shot": 0.0,
		"next_melee": 0.0,
		"special_until": 0.0,
		"special_dither_until": 0.0,
		"wish": Vector3.ZERO,
		"separation": Vector3.ZERO,
		"stuck": 0,
		"unstick_until": 0.0,
		"force_path_until": 0.0,
		"think_pos": Vector3.ZERO,
		"think_at": 0.0,
		"pawn_iid": 0,
		# Burst fire
		"burst_left": int(s.get("burst", pr.get("burst", 3))),
		# Idle / stop
		"idle_until": 0.0,
		"scan_yaw": 0.0,
		"scan_yaw_at": 0.0,
		# Duck
		"want_crouch": false,
		# Cover
		"cover_until": 0.0,
		"cover_goal": Vector3.ZERO,
		"last_hp": 100,
		# Alert (lifts FOV cone after being hit)
		"alert_until": 0.0,
	}


# ── per-tick brain ───────────────────────────────────────────────────────

func update_bot(p: Participant, pawn: ServerPawn, all_participants: Dictionary,
		all_pawns: Dictionary, bots_shoot: bool, bots_move: bool,
		round_active: bool, now: float, dt: float) -> Dictionary:
	var result := {"shoot": false, "melee": false, "special_start": false, "special_release": false}

	if nav == null or not round_active or not pawn.alive:
		return result

	if not p.connection_session.has("ai"):
		init_ai(p)
	var ai: Dictionary = p.connection_session["ai"]

	if int(ai["pawn_iid"]) != int(pawn.get_instance_id()):
		_on_respawn(ai, pawn)

	# Detect hp drops to trigger cover-seeking and alert.
	if pawn.hp < int(ai["last_hp"]):
		ai["alert_until"] = now + ALERT_DURATION
		_maybe_seek_cover(pawn, ai, all_pawns, now)
	ai["last_hp"] = pawn.hp

	# Winding a special up plants the bot: no steering, no trigger, no way out
	# of it until the hold elapses. Gravity still applies.
	if p.special_at > 0.0:
		if now > float(ai["special_until"]):
			result["special_release"] = true
		_apply_motion(pawn, ai, Vector3.ZERO, dt)
		return result

	if now >= float(ai["think_at"]):
		ai["think_at"] = now + THINK_INTERVAL * (0.85 + randf() * 0.3)
		_think(p, pawn, all_participants, all_pawns, now, bots_move)

	var target_id := int(ai["target"])
	var target_pawn: ServerPawn = all_pawns.get(target_id) if target_id != 0 else null
	var engaged: bool = bool(ai["visible"]) and target_pawn != null and target_pawn.alive

	# Spotting a target breaks idle and cover.
	if engaged:
		ai["idle_until"] = 0.0

	var wish := Vector3.ZERO
	if bots_move:
		var state: String = ai["state"]

		# While idling the bot stands still and scans its head.
		if state == "roam" and now < float(ai["idle_until"]) and not engaged:
			wish = Vector3.ZERO
		elif state == "cover" and now < float(ai["cover_until"]):
			wish = _path_wish(pawn, ai)
		elif engaged and now >= float(ai["force_path_until"]):
			wish = _combat_wish(pawn, ai, target_pawn, now)
		else:
			wish = _path_wish(pawn, ai)

		wish += (ai["separation"] as Vector3) * 0.9
		if now < float(ai["unstick_until"]):
			wish = Vector3(-wish.z, 0.0, wish.x) * float(ai["strafe_dir"]) + wish * 0.35

	_apply_motion(pawn, ai, wish, dt)

	var aim_off := _update_aim(pawn, ai, target_pawn if engaged else null, now, dt)

	if not engaged or not bots_shoot:
		return result

	_fire_decision(p, pawn, ai, target_pawn, all_participants, all_pawns, aim_off, now, result)
	return result


func _on_respawn(ai: Dictionary, pawn: ServerPawn) -> void:
	ai["pawn_iid"] = int(pawn.get_instance_id())
	ai["yaw"] = deg_to_rad(pawn.yaw)
	ai["pitch"] = 0.0
	ai["state"] = "roam"
	ai["target"] = 0
	ai["visible"] = false
	ai["last_seen_at"] = -100.0
	ai["path"] = PackedVector3Array()
	ai["path_i"] = 0
	ai["has_goal"] = false
	ai["repath_at"] = 0.0
	# A respawn is a fresh pawn at a fresh place; the solver must not carry the
	# old body's velocity or crouch into it.
	var mover: Movement = ai["mover"]
	mover.position = pawn.position
	mover.velocity = Vector3.ZERO
	mover.on_ground = true
	mover.is_crouching = false
	mover.crouch_fraction = 0.0
	ai["stuck"] = 0
	ai["unstick_until"] = 0.0
	ai["force_path_until"] = 0.0
	ai["think_pos"] = pawn.position
	ai["think_at"] = 0.0
	ai["burst_left"] = int(ai["burst"])
	ai["idle_until"] = 0.0
	ai["want_crouch"] = false
	ai["cover_until"] = 0.0
	ai["last_hp"] = 100
	ai["alert_until"] = 0.0
	ai["special_dither_until"] = 0.0


# ── deciding ─────────────────────────────────────────────────────────────

func _think(p: Participant, pawn: ServerPawn, all_participants: Dictionary,
		all_pawns: Dictionary, now: float, can_move: bool) -> void:
	var ai: Dictionary = p.connection_session["ai"]

	_pick_target(p, pawn, ai, all_participants, all_pawns, now)
	if not can_move:
		return

	_choose_goal(p, pawn, ai, all_pawns, now)
	ai["separation"] = _separation(p, pawn, all_participants, all_pawns)
	_check_stuck(pawn, ai, now)
	_maybe_repath(pawn, ai, now)


func _pick_target(p: Participant, pawn: ServerPawn, ai: Dictionary,
		all_participants: Dictionary, all_pawns: Dictionary, now: float) -> void:
	var eye := _eye(pawn)
	var current := int(ai["target"])

	var my_yaw: float = ai["yaw"]
	var half_fov := deg_to_rad(float(ai["fov"]) * 0.5)
	var sight_range: float = ai["sight"]
	var alerted := now < float(ai["alert_until"])

	var nearest := 0
	var nearest_dist := INF
	var current_dist := INF
	var current_seen := false

	for pid: int in all_participants:
		if pid == p.id:
			continue
		var enemy: Participant = all_participants[pid]
		if enemy.team == p.team or enemy.team == Protocol.TEAM_NONE:
			continue
		var enemy_pawn: ServerPawn = all_pawns.get(pid)
		if enemy_pawn == null or not enemy_pawn.alive:
			continue

		var dist := eye.distance_to(enemy_pawn.position)

		# Range gate (alert lifts it).
		if not alerted and dist > sight_range:
			continue

		# FOV gate: angle between our facing and the enemy, on the horizontal
		# plane. Alert or 360-degree FOV skips the test.
		if not alerted and half_fov < PI:
			var dx := enemy_pawn.position.x - pawn.position.x
			var dz := enemy_pawn.position.z - pawn.position.z
			var angle_to := atan2(-dx, -dz)
			var diff := absf(wrapf(angle_to - my_yaw, -PI, PI))
			if diff > half_fov:
				continue

		if dist >= nearest_dist and pid != current:
			continue
		if nav.blocked(eye, _aim_point(enemy_pawn)):
			continue

		if pid == current:
			current_seen = true
			current_dist = dist
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = pid

	var chosen := nearest
	if current_seen and current_dist <= nearest_dist * 1.5:
		chosen = current

	if chosen != 0:
		if chosen != current or not bool(ai["visible"]):
			ai["seen_at"] = now
		ai["target"] = chosen
		ai["visible"] = true
		if ai["state"] != "cover" or now >= float(ai["cover_until"]):
			ai["state"] = "fight"
		ai["last_seen_pos"] = (all_pawns[chosen] as ServerPawn).position
		ai["last_seen_at"] = now
		return

	ai["visible"] = false

	var lost: ServerPawn = all_pawns.get(current) if current != 0 else null
	if lost != null and lost.alive and now - float(ai["last_seen_at"]) < MEMORY_TIME:
		ai["state"] = "hunt"
		return

	ai["target"] = 0
	if ai["state"] != "roam" and ai["state"] != "cover":
		ai["state"] = "roam"
		ai["has_goal"] = false


func _choose_goal(p: Participant, pawn: ServerPawn, ai: Dictionary,
		all_pawns: Dictionary, now: float) -> void:
	var state: String = ai["state"]

	if state == "cover":
		ai["goal"] = ai["cover_goal"]
		ai["has_goal"] = true
		return

	if state == "fight":
		var target_pawn: ServerPawn = all_pawns.get(int(ai["target"]))
		if target_pawn != null:
			ai["goal"] = target_pawn.position
			ai["has_goal"] = true
		return

	if state == "hunt":
		ai["goal"] = ai["last_seen_pos"]
		ai["has_goal"] = true
		return

	# Roam
	var reached: bool = bool(ai["has_goal"]) and _flat_dist(pawn.position, ai["goal"]) < 2.0
	if not bool(ai["has_goal"]) or reached or now - float(ai["goal_at"]) > ROAM_TIMEOUT:
		# Roll for an idle stop when arriving at a destination.
		if reached and randf() < float(ai["idle_chance"]):
			var lo: float = ai["idle_time_lo"]
			var hi: float = ai["idle_time_hi"]
			ai["idle_until"] = now + lo + randf() * (hi - lo)
			ai["scan_yaw"] = float(ai["yaw"]) + (randf() - 0.5) * 2.0
			ai["scan_yaw_at"] = now + 0.6 + randf() * 1.0
		ai["goal"] = _roam_goal(p, pawn)
		ai["has_goal"] = true
		ai["goal_at"] = now
		ai["repath_at"] = 0.0


func _roam_goal(p: Participant, pawn: ServerPawn) -> Vector3:
	var points := nav.open_points
	if points.is_empty():
		return pawn.position

	var enemy_team := Protocol.TEAM_RED if p.team == Protocol.TEAM_BLUE else Protocol.TEAM_BLUE
	var enemy_home: Vector3 = _homes.get(enemy_team, Vector3.ZERO)

	var best := pawn.position
	var best_score := -INF
	for _i in 14:
		var candidate := points[randi() % points.size()]
		if _flat_dist(candidate, pawn.position) < 6.0:
			continue
		var score := -candidate.distance_to(enemy_home) + randf() * 16.0
		if score > best_score:
			best_score = score
			best = candidate

	return best


func _separation(p: Participant, pawn: ServerPawn, all_participants: Dictionary,
		all_pawns: Dictionary) -> Vector3:
	var push := Vector3.ZERO

	for pid: int in all_pawns:
		if pid == p.id:
			continue
		var mate: Participant = all_participants.get(pid)
		if mate == null or mate.team != p.team:
			continue
		var mate_pawn: ServerPawn = all_pawns[pid]
		if not mate_pawn.alive:
			continue

		var away := Vector3(pawn.position.x - mate_pawn.position.x, 0.0,
			pawn.position.z - mate_pawn.position.z)
		var dist := away.length()
		if dist > SEPARATION_R or dist < 0.001:
			continue
		push += (away / dist) * (1.0 - dist / SEPARATION_R)

	return push


func _check_stuck(pawn: ServerPawn, ai: Dictionary, now: float) -> void:
	var wanted: Vector3 = ai["wish"]
	var moved := _flat_dist(pawn.position, ai["think_pos"])
	ai["think_pos"] = pawn.position

	if wanted.length_squared() > 0.01 and moved < STUCK_DIST:
		ai["stuck"] = int(ai["stuck"]) + 1
	else:
		ai["stuck"] = 0

	if int(ai["stuck"]) < STUCK_THINKS:
		return

	ai["stuck"] = 0
	ai["repath_at"] = 0.0
	ai["force_path_until"] = now + 1.5
	ai["unstick_until"] = now + 0.35
	ai["strafe_dir"] = -float(ai["strafe_dir"])
	if ai["state"] == "roam":
		ai["has_goal"] = false


func _maybe_repath(pawn: ServerPawn, ai: Dictionary, now: float) -> void:
	if not bool(ai["has_goal"]):
		return

	var path: PackedVector3Array = ai["path"]
	var stale := now >= float(ai["repath_at"])
	var spent := int(ai["path_i"]) >= path.size()
	var drifted := _flat_dist(ai["goal"], ai["path_goal"]) > 2.5
	if not (stale or spent or drifted):
		return

	ai["path"] = nav.find_path(pawn.position, ai["goal"])
	ai["path_i"] = 0
	ai["path_goal"] = ai["goal"]
	ai["repath_at"] = now + REPATH_INTERVAL * (0.8 + randf() * 0.4)

	if (ai["path"] as PackedVector3Array).is_empty() and ai["state"] == "roam":
		ai["has_goal"] = false


# ── cover ────────────────────────────────────────────────────────────────

## Called when the bot takes damage. Rolls cover_chance and, if it hits,
## searches nearby open points for a spot that breaks line of sight to the
## current target, then paths there crouched.
func _maybe_seek_cover(pawn: ServerPawn, ai: Dictionary,
		all_pawns: Dictionary, now: float) -> void:
	if ai["state"] == "cover":
		return
	if randf() >= float(ai["cover_chance"]):
		return

	var target_id := int(ai["target"])
	var target_pawn: ServerPawn = all_pawns.get(target_id) if target_id != 0 else null
	if target_pawn == null or not target_pawn.alive:
		return

	var target_aim := _aim_point(target_pawn)
	var points := nav.open_points
	if points.is_empty():
		return

	var best := Vector3.ZERO
	var best_score := INF
	var found := false
	for _i in 20:
		var candidate := points[randi() % points.size()]
		var d := _flat_dist(candidate, pawn.position)
		if d < 1.5 or d > COVER_SEARCH_R:
			continue
		var cover_eye := Vector3(candidate.x, candidate.y + Hitbox.eye_height(true), candidate.z)
		if not nav.blocked(cover_eye, target_aim):
			continue
		if d < best_score:
			best_score = d
			best = candidate
			found = true

	if not found:
		return

	ai["state"] = "cover"
	ai["cover_goal"] = best
	ai["goal"] = best
	ai["has_goal"] = true
	ai["repath_at"] = 0.0
	ai["cover_until"] = now + COVER_PEEK_LO + randf() * (COVER_PEEK_HI - COVER_PEEK_LO)
	ai["want_crouch"] = true


# ── steering ─────────────────────────────────────────────────────────────

func _path_wish(pawn: ServerPawn, ai: Dictionary) -> Vector3:
	var path: PackedVector3Array = ai["path"]
	var i := int(ai["path_i"])

	while i < path.size():
		var wp := path[i]
		var flat := Vector3(wp.x - pawn.position.x, 0.0, wp.z - pawn.position.z)
		if flat.length() < WAYPOINT_R and absf(wp.y - pawn.position.y) < 1.6:
			i += 1
			continue
		ai["path_i"] = i
		# Drop crouch while travelling long distances so the bot is not
		# permanently duck-walking across the map.
		if flat.length() > 3.0 and ai["state"] != "cover":
			ai["want_crouch"] = false
		return flat.normalized()

	ai["path_i"] = i
	if not bool(ai["has_goal"]):
		return Vector3.ZERO

	# Arrived at cover spot — stay crouched and stop.
	if ai["state"] == "cover":
		return Vector3.ZERO

	var goal: Vector3 = ai["goal"]
	var direct := Vector3(goal.x - pawn.position.x, 0.0, goal.z - pawn.position.z)
	return direct.normalized() if direct.length() > WAYPOINT_R else Vector3.ZERO


func _combat_wish(pawn: ServerPawn, ai: Dictionary, target_pawn: ServerPawn, now: float) -> Vector3:
	if now > float(ai["strafe_flip_at"]):
		ai["strafe_dir"] = -float(ai["strafe_dir"])
		ai["strafe_flip_at"] = now + 0.6 + randf() * 1.2
		# Roll for a duck on each strafe flip when beyond melee range.
		var dist_to_target := _flat_dist(pawn.position, target_pawn.position)
		if dist_to_target > MELEE_RANGE:
			ai["want_crouch"] = randf() < float(ai["duck_chance"])
		else:
			ai["want_crouch"] = false

	var facing: float = ai["yaw"]
	var face := Vector3(-sin(facing), 0.0, -cos(facing))
	var side := Vector3(face.z, 0.0, -face.x)

	var wish := side * float(ai["strafe_dir"])
	var dist := _flat_dist(pawn.position, target_pawn.position)

	if dist > PREFERRED_RANGE + 3.0:
		wish += face
	elif dist < PREFERRED_RANGE - 5.0:
		wish -= face

	# Hurt bots give ground.
	if pawn.hp < 35:
		wish -= face * 0.8

	return wish


func _apply_motion(pawn: ServerPawn, ai: Dictionary, wish: Vector3, dt: float) -> void:
	var dir := Vector3(wish.x, 0.0, wish.z)
	dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.ZERO
	ai["wish"] = dir

	# The pawn is the record and the mover is the solver: sync in, solve, sync
	# out. Reading position back every tick is also what makes a respawn — which
	# swaps in a fresh pawn at the spawn point — land on the solver for free.
	var mover: Movement = ai["mover"]
	mover.position = pawn.position
	mover.yaw = rad_to_deg(float(ai["yaw"]))
	mover.speed_scale = float(ai.get("speed", 1.0))

	if nav.world == null:
		pawn.position += dir * Movement.RUN_SPEED * mover.speed_scale * dt
		return

	# Movement steers relative to its own facing; the bot thinks in world space.
	# The basis is orthonormal and the wish is flat, so this loses nothing.
	mover.update(dt, dir.dot(mover.get_forward()), dir.dot(mover.get_right()),
		false, bool(ai["want_crouch"]), false, nav.world)

	pawn.position = mover.position
	pawn.grounded = mover.on_ground
	pawn.crouched = mover.is_crouching


# ── aiming ───────────────────────────────────────────────────────────────

func _update_aim(pawn: ServerPawn, ai: Dictionary, target_pawn: ServerPawn,
		now: float, dt: float) -> float:
	var eye := _eye(pawn)
	var look: Vector3

	if target_pawn != null:
		look = _aim_point(target_pawn)
	else:
		# A bot with nowhere to look sweeps its head instead of freezing. Without
		# this a stationary bot stays permanently blind to anything outside the
		# cone it happens to be facing, since the cone is measured off this yaw.
		var heading: Vector3 = ai["wish"]
		var idling := now < float(ai["idle_until"])
		if not idling and heading.length_squared() >= 0.01:
			look = eye + heading * 8.0
		else:
			if now >= float(ai["scan_yaw_at"]):
				ai["scan_yaw"] = float(ai["yaw"]) + (randf() - 0.5) * 2.0
				ai["scan_yaw_at"] = now + 1.0 + randf() * 1.0
			var scan_yaw: float = ai["scan_yaw"]
			look = eye + Vector3(-sin(scan_yaw), 0.0, -cos(scan_yaw)) * 8.0

	var flat_x := look.x - eye.x
	var flat_z := look.z - eye.z
	var horiz := sqrt(flat_x * flat_x + flat_z * flat_z)
	if horiz < 0.05:
		return PI

	var want_yaw := atan2(-flat_x, -flat_z)
	var turn: float = ai["turn"]
	var blend := 1.0 - pow(1.0 - turn, dt * 60.0)

	var delta := wrapf(want_yaw - float(ai["yaw"]), -PI, PI)
	ai["yaw"] = float(ai["yaw"]) + delta * blend

	var want_pitch := atan2(-(look.y - eye.y), horiz) if target_pawn != null else 0.0
	ai["pitch"] = lerpf(float(ai["pitch"]), want_pitch, minf(1.0, blend * 1.6))

	_drift_aim_error(ai, now, dt)

	pawn.yaw = rad_to_deg(float(ai["yaw"]) + float(ai["err_yaw"]))
	pawn.pitch = clampf(rad_to_deg(float(ai["pitch"]) + float(ai["err_pitch"])), -89.0, 89.0)

	return absf(delta)


func _drift_aim_error(ai: Dictionary, now: float, dt: float) -> void:
	var err: float = ai["aim_err"]
	if now > float(ai["drift_at"]):
		ai["drift_at"] = now + AIM_DRIFT_INTERVAL * (0.7 + randf() * 0.6)
		ai["err_yaw_to"] = (randf() - 0.5) * 2.0 * err
		ai["err_pitch_to"] = (randf() - 0.5) * err

	var blend := minf(1.0, dt * 6.0)
	ai["err_yaw"] = lerpf(float(ai["err_yaw"]), float(ai["err_yaw_to"]), blend)
	ai["err_pitch"] = lerpf(float(ai["err_pitch"]), float(ai["err_pitch_to"]), blend)


# ── shooting ─────────────────────────────────────────────────────────────

func _fire_decision(p: Participant, pawn: ServerPawn, ai: Dictionary,
		target_pawn: ServerPawn, all_participants: Dictionary, all_pawns: Dictionary,
		aim_off: float, now: float, result: Dictionary) -> void:
	var gate: float = ai["aim_gate"]
	if aim_off > gate:
		return
	if now - float(ai["seen_at"]) < float(ai["reaction"]):
		return
	if now < target_pawn.protected_until:
		return

	var eye := _eye(pawn)
	var dist := eye.distance_to(target_pawn.position)

	if dist < MELEE_RANGE and now > float(ai["next_melee"]):
		ai["next_melee"] = now + 0.9
		result["melee"] = true
		return

	if nav.blocked(eye, _aim_point(target_pawn)):
		return

	# Special: dither for special_delay seconds before spending it.
	if p.special_armed and dist < SPECIAL_RANGE * 0.8:
		if float(ai["special_dither_until"]) <= 0.0:
			ai["special_dither_until"] = now + float(ai["special_delay"])
		if now >= float(ai["special_dither_until"]):
			result["special_start"] = true
			ai["special_until"] = now + 0.5 + randf() * 0.7
			ai["special_dither_until"] = 0.0
			return

	if now <= float(ai["next_shot"]):
		return
	if _friendly_in_line(p, pawn, all_participants, all_pawns, dist):
		return

	# Burst fire: shoot burst shots, then pause.
	var left := int(ai["burst_left"])
	if left <= 0:
		ai["burst_left"] = int(ai["burst"])
		ai["next_shot"] = now + float(ai["burst_pause"])
		return

	ai["burst_left"] = left - 1
	ai["next_shot"] = now + float(ai["fire_gap"])
	result["shoot"] = true


func _friendly_in_line(p: Participant, pawn: ServerPawn, all_participants: Dictionary,
		all_pawns: Dictionary, dist: float) -> bool:
	var eye := _eye(pawn)
	var dir := _aim_dir(pawn.yaw, pawn.pitch)

	for pid: int in all_pawns:
		if pid == p.id:
			continue
		var mate: Participant = all_participants.get(pid)
		if mate == null or mate.team != p.team:
			continue
		var mate_pawn: ServerPawn = all_pawns[pid]
		if not mate_pawn.alive:
			continue
		if eye.distance_to(mate_pawn.position) > dist:
			continue
		if Hitbox.ray_vs_player(eye, dir, mate_pawn.position, mate_pawn.crouched, dist)["hit"]:
			return true

	return false


# ── small helpers ────────────────────────────────────────────────────────

func _eye(pawn: ServerPawn) -> Vector3:
	return Vector3(pawn.position.x, pawn.position.y + Hitbox.eye_height(pawn.crouched),
		pawn.position.z)


func _aim_point(pawn: ServerPawn) -> Vector3:
	return Vector3(pawn.position.x, pawn.position.y + Hitbox.aim_height(pawn.crouched),
		pawn.position.z)


static func _aim_dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	var ry := deg_to_rad(yaw_deg)
	var rp := deg_to_rad(pitch_deg)
	return Vector3(-sin(ry) * cos(rp), -sin(rp), -cos(ry) * cos(rp))


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)
