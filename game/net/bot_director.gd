class_name BotDirector
extends RefCounted

## Server-side bot brains. One BotNav is shared by every bot on the map; the
## per-bot state lives in Participant.connection_session["ai"].

const BOT_TARGET_PER_TEAM := 3
const BOT_SPEED := 6.6
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
const FALL_ACCEL := 20.32

## Target picking and routing run on their own clock — a bot re-deciding who to
## shoot sixty times a second only burns raycasts, and the jitter it produced in
## aim and pathing read as twitchiness rather than skill.
const THINK_INTERVAL := 0.09
## How long a bot keeps chasing someone who broke line of sight before it gives
## up and goes back to roaming.
const MEMORY_TIME := 5.0
const REPATH_INTERVAL := 1.1
const WAYPOINT_R := 0.9
const ROAM_TIMEOUT := 9.0
const SEPARATION_R := 1.8
const AIM_DRIFT_INTERVAL := 0.25

## Wanting to move but not moving for this many thinks means something is in the
## way that the steering cannot see. Pathing takes over until it is clear.
const STUCK_THINKS := 4
const STUCK_DIST := 0.22

var nav: BotNav = null

var _name_idx: int = 0
var _next_bot_id: int = -1
var _arena_size: float = 28.0
var _homes: Dictionary = {}  # team → Vector3


## Called once the map is compiled. Everything the bots reason about — what is
## solid, what is walkable, where each side lives — is derived here.
func configure(colliders: Array[AABB], arena: float, spawns: Dictionary) -> void:
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
	nav.build(colliders, arena, seeds)


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
	var skill := 0.35 + randf() * 0.5
	var bot_name := "BOT " + BOT_NAMES[_name_idx % BOT_NAMES.size()]
	_name_idx += 1

	var id := _next_bot_id
	_next_bot_id -= 1

	return {
		"action": "add",
		"id": id,
		"name": bot_name,
		"team": team_val,
		"skill": skill,
		"reaction": 0.35 - skill * 0.22,
		"aim_err": 0.09 * (1.0 - skill) + 0.01,
	}


func init_ai(p: Participant) -> void:
	p.connection_session["ai"] = {
		"skill": p.connection_session.get("skill", 0.5),
		"reaction": p.connection_session.get("reaction", 0.25),
		"aim_err": p.connection_session.get("aim_err", 0.05),
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
		"vy": 0.0,
		"wish": Vector3.ZERO,
		"separation": Vector3.ZERO,
		"stuck": 0,
		"unstick_until": 0.0,
		"force_path_until": 0.0,
		"think_pos": Vector3.ZERO,
		"think_at": 0.0,
		"pawn_iid": 0,
	}


# ── per-tick brain ───────────────────────────────────────────────────────

## `bots_shoot` and `bots_move` are the dev-mode switches. Either one off leaves
## the rest of the brain running: a bot that cannot move still tracks and fires,
## and one that cannot shoot still roams, so each is useful on its own.
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

	# Winding a special up plants the bot: no steering, no trigger, no way out
	# of it until the hold elapses. Gravity still applies so a bot charging on a
	# ledge it just walked off still lands.
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

	# Pinned bots still get a motion pass so gravity settles them onto the floor
	# rather than leaving one hanging where it happened to be standing.
	var wish := Vector3.ZERO
	if bots_move:
		if engaged and now >= float(ai["force_path_until"]):
			wish = _combat_wish(pawn, ai, target_pawn, now)
		else:
			wish = _path_wish(pawn, ai)

		wish += (ai["separation"] as Vector3) * 0.9
		if now < float(ai["unstick_until"]):
			# Slide along whatever is in the way instead of grinding into it.
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
	ai["vy"] = 0.0
	ai["stuck"] = 0
	ai["unstick_until"] = 0.0
	ai["force_path_until"] = 0.0
	ai["think_pos"] = pawn.position
	ai["think_at"] = 0.0


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

	# Swapping targets every time someone edges closer means never finishing a
	# duel, so whoever is already being fought keeps priority until someone else
	# is clearly the better shot.
	var chosen := nearest
	if current_seen and current_dist <= nearest_dist * 1.5:
		chosen = current

	if chosen != 0:
		if chosen != current or not bool(ai["visible"]):
			ai["seen_at"] = now
		ai["target"] = chosen
		ai["visible"] = true
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
	if ai["state"] != "roam":
		ai["state"] = "roam"
		ai["has_goal"] = false


func _choose_goal(p: Participant, pawn: ServerPawn, ai: Dictionary,
		all_pawns: Dictionary, now: float) -> void:
	var state: String = ai["state"]

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

	var reached: bool = bool(ai["has_goal"]) and _flat_dist(pawn.position, ai["goal"]) < 2.0
	if not bool(ai["has_goal"]) or reached or now - float(ai["goal_at"]) > ROAM_TIMEOUT:
		ai["goal"] = _roam_goal(p, pawn)
		ai["has_goal"] = true
		ai["goal_at"] = now
		ai["repath_at"] = 0.0


## Roaming used to be a random point anywhere, which left bots milling around
## their own half. Sampling a handful of reachable cells and favouring the ones
## near the other side's spawn pushes them out to contest the map instead, while
## the random term keeps six bots from filing down the same lane.
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

	# Nowhere to go: the goal is walled off or on a ledge no bot can climb.
	# Pick somewhere else rather than stand there pushing at the geometry.
	if (ai["path"] as PackedVector3Array).is_empty() and ai["state"] == "roam":
		ai["has_goal"] = false


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
		return flat.normalized()

	ai["path_i"] = i
	if not bool(ai["has_goal"]):
		return Vector3.ZERO

	var goal: Vector3 = ai["goal"]
	var direct := Vector3(goal.x - pawn.position.x, 0.0, goal.z - pawn.position.z)
	return direct.normalized() if direct.length() > WAYPOINT_R else Vector3.ZERO


func _combat_wish(pawn: ServerPawn, ai: Dictionary, target_pawn: ServerPawn, now: float) -> Vector3:
	if now > float(ai["strafe_flip_at"]):
		ai["strafe_dir"] = -float(ai["strafe_dir"])
		ai["strafe_flip_at"] = now + 0.6 + randf() * 1.2

	var facing: float = ai["yaw"]
	var face := Vector3(-sin(facing), 0.0, -cos(facing))
	var side := Vector3(face.z, 0.0, -face.x)

	var wish := side * float(ai["strafe_dir"])
	var dist := _flat_dist(pawn.position, target_pawn.position)

	if dist > PREFERRED_RANGE + 3.0:
		wish += face
	elif dist < PREFERRED_RANGE - 5.0:
		wish -= face

	# Hurt bots give ground instead of trading to the death.
	if pawn.hp < 35:
		wish -= face * 0.8

	return wish


## Walks the bot one tick: horizontal push-out against anything too tall to step
## onto, then the vertical settle that lets it take stairs and drop off ledges.
## Without the settle a bot is pinned at spawn height and the first 0.3m tread on
## the map is a wall to it.
func _apply_motion(pawn: ServerPawn, ai: Dictionary, wish: Vector3, dt: float) -> void:
	var dir := Vector3(wish.x, 0.0, wish.z)
	var speed := dir.length()
	dir = dir / speed if speed > 0.001 else Vector3.ZERO
	ai["wish"] = dir

	var feet := pawn.position.y
	var nx := pawn.position.x + dir.x * BOT_SPEED * dt
	var nz := pawn.position.z + dir.z * BOT_SPEED * dt

	for box in nav.colliders:
		if box.end.y <= feet + STEP_UP:
			continue  # low enough to walk up onto
		if box.position.y >= feet + BODY_HEIGHT:
			continue  # hangs overhead
		if nx <= box.position.x - PLAYER_R or nx >= box.end.x + PLAYER_R:
			continue
		if nz <= box.position.z - PLAYER_R or nz >= box.end.z + PLAYER_R:
			continue

		var push_left := (nx + PLAYER_R) - box.position.x
		var push_right := box.end.x - (nx - PLAYER_R)
		var push_front := (nz + PLAYER_R) - box.position.z
		var push_back := box.end.z - (nz - PLAYER_R)
		var least := minf(push_left, minf(push_right, minf(push_front, push_back)))
		if least == push_left:
			nx = box.position.x - PLAYER_R
		elif least == push_right:
			nx = box.end.x + PLAYER_R
		elif least == push_front:
			nz = box.position.z - PLAYER_R
		else:
			nz = box.end.z + PLAYER_R

	var lim := _arena_size - 0.8
	nx = clampf(nx, -lim, lim)
	nz = clampf(nz, -lim, lim)

	var support := nav.surface_at(nx, nz, feet + STEP_UP)
	if support == -INF:
		support = 0.0

	if support >= feet:
		feet = support
		ai["vy"] = 0.0
	else:
		var vy := float(ai["vy"]) - FALL_ACCEL * dt
		feet += vy * dt
		if feet <= support:
			feet = support
			vy = 0.0
		ai["vy"] = vy

	pawn.position = Vector3(nx, feet, nz)


# ── aiming ───────────────────────────────────────────────────────────────

## Turns the head toward whatever the bot cares about and returns how far off
## target it still is, in radians, so the trigger can wait for the barrel.
func _update_aim(pawn: ServerPawn, ai: Dictionary, target_pawn: ServerPawn,
		now: float, dt: float) -> float:
	var eye := _eye(pawn)
	var look: Vector3

	if target_pawn != null:
		look = _aim_point(target_pawn)
	else:
		var heading: Vector3 = ai["wish"]
		if heading.length_squared() < 0.01:
			return PI
		look = eye + heading * 8.0

	var flat_x := look.x - eye.x
	var flat_z := look.z - eye.z
	var horiz := sqrt(flat_x * flat_x + flat_z * flat_z)
	if horiz < 0.05:
		return PI

	var want_yaw := atan2(-flat_x, -flat_z)
	var turn := 0.10 + float(ai["skill"]) * 0.22
	# Expressed as a rate so the turn is the same whatever the tick length.
	var blend := 1.0 - pow(1.0 - turn, dt * 60.0)

	var delta := wrapf(want_yaw - float(ai["yaw"]), -PI, PI)
	ai["yaw"] = float(ai["yaw"]) + delta * blend

	var want_pitch := atan2(-(look.y - eye.y), horiz) if target_pawn != null else 0.0
	ai["pitch"] = lerpf(float(ai["pitch"]), want_pitch, minf(1.0, blend * 1.6))

	_drift_aim_error(ai, now, dt)

	pawn.yaw = rad_to_deg(float(ai["yaw"]) + float(ai["err_yaw"]))
	pawn.pitch = clampf(rad_to_deg(float(ai["pitch"]) + float(ai["err_pitch"])), -89.0, 89.0)

	return absf(delta)


## Aim error wanders instead of being re-rolled every frame. Fresh noise per tick
## averaged out to a dead-centre bot that occasionally flicked; a slow drift is
## what a hand that is not quite steady actually looks like.
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
	var skill: float = ai["skill"]
	if aim_off > 0.10 + (1.0 - skill) * 0.14:
		return
	if now - float(ai["seen_at"]) < float(ai["reaction"]):
		return
	# Spawn protection makes them untouchable, so shooting is a giveaway of
	# position for nothing.
	if now < target_pawn.protected_until:
		return

	var eye := _eye(pawn)
	var dist := eye.distance_to(target_pawn.position)

	# A punch hits harder than a bolt, so take it whenever it is off cooldown —
	# but keep shooting in between rather than standing there winding up.
	if dist < MELEE_RANGE and now > float(ai["next_melee"]):
		ai["next_melee"] = now + 0.9
		result["melee"] = true
		return

	# The gate that stops a bot firing into a wall: the shot is confirmed against
	# the same geometry the server will trace it through, at the moment of firing
	# rather than whenever the last think happened.
	if nav.blocked(eye, _aim_point(target_pawn)):
		return

	if p.special_armed and dist < SPECIAL_RANGE * 0.8:
		result["special_start"] = true
		ai["special_until"] = now + 0.5 + randf() * 0.7
		return

	if now <= float(ai["next_shot"]):
		return
	if _friendly_in_line(p, pawn, all_participants, all_pawns, dist):
		return

	ai["next_shot"] = now + 0.14 + (1.0 - skill) * 0.12
	result["shoot"] = true


## Bots hold fire rather than put a laser through a team-mate's back.
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
