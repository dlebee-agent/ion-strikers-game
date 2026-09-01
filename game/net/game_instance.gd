class_name GameInstance
extends Node3D

signal event_to_peer(peer_id: int, channel: int, data: PackedByteArray)
signal event_broadcast(channel: int, data: PackedByteArray, exclude_id: int)
signal event_team_broadcast(team: int, channel: int, data: PackedByteArray)
signal peer_init(peer_id: int, data: PackedByteArray)
signal peer_kicked(peer_id: int)

var game_id: String
var display_name: String
var map_id: String
var mode: String
var win_rounds: int = 10
var kill_target: int = 50
var max_players: int = 12
var max_spectators: int = 12
var bots_enabled: bool = true
var bots_shoot: bool = true
var bots_move: bool = true
var bot_skill: String = BotSkill.DEFAULT_LEVEL
var cheats: bool = false

var match_state: MatchState
var participants: Dictionary = {}   # id → Participant
var pawns: Dictionary = {}          # id → ServerPawn
var bot_director: BotDirector
var spawns: Dictionary = {}
var world: CollisionWorld = null
# Reused by every shot this instance traces, so firing allocates nothing.
var _shot_trace := TraceResult.new()
var arena_size: float = 28.0
## Half extents of the map's floor, which is square on every map but grid
## arena. Anything beyond it horizontally is off the map.
var _bounds_half := Vector2(28.0, 28.0)

## Below this a pawn has left the floor behind and is only going to keep
## falling: the floor slab tops out at y=0 and its underside sits at y=-2,
## so nothing that is still on the map is ever down here.
const VOID_Y := -6.0
## How far past the floor edge a pawn may be before it counts as off the
## map. The perimeter walls stand on that edge, so the only way to be out
## here is to have left over the top of one.
const VOID_MARGIN := 1.5
## Enough to kill through any amount of health.
const VOID_DAMAGE := 1000

var _tick: int = 0
var _now: float = 0.0
var _snap_seq: int = 0

const HISTORY_INTERVAL := 1.0 / 60.0
var _history_timer: float = 0.0

const TEAM_SWITCH_COOLDOWN_MS := 5000.0
var _team_switch_cooldowns: Dictionary = {}  # id → timestamp

const CHAT_BURST_MAX := 3
const CHAT_BURST_WINDOW := 4.0
const CHAT_MAX_LEN := 50
var _chat_log: Dictionary = {}  # id → Array of timestamps

const SPECIAL_MIN_WINDUP := 0.3
const SPECIAL_AUTO_FIRE := 5.0
const SPECIAL_RANGE := 45.0
const SPECIAL_BEAM_RADIUS := 8.0
const SPECIAL_BLAST_RADIUS := 8.0
const SPECIAL_BLAST_VERT := 6.0

const DAMAGE_BODY := 34
const DAMAGE_HEAD := 100
const SHOT_RANGE := 200.0
const MELEE_RANGE := 2.6
const MELEE_ARC := deg_to_rad(70.0)
const MELEE_DAMAGE := 50

var _roster_dirty: bool = false

const MAX_REWIND_MS := 300.0
const SPAWN_PROTECTION_MS := 2000.0
const DM_RESPAWN_MS := 5000.0

## Lobby is released after this long with no human participants. Bots do not count.
const EMPTY_HUMAN_TTL := 300.0
# Negative while any human is present; otherwise the instance time they left (0 at create).
var _empty_since: float = 0.0


func _init(cfg: Dictionary = {}) -> void:
	game_id = cfg.get("game_id", _gen_id())
	display_name = cfg.get("display_name", "")
	map_id = cfg.get("map_id", "parkour")
	# Anything that is not deathmatch is arena. The Game API hands the create
	# paths whatever mode string it was given, so a stray value — an older
	# client's "classic", a typo — would otherwise build a match that half
	# behaves like one mode and half like the other.
	mode = "dm" if str(cfg.get("mode", "arena")) == "dm" else "arena"
	win_rounds = cfg.get("rounds", 10)
	kill_target = cfg.get("kills", 50)
	max_players = cfg.get("max_players", 12)
	max_spectators = cfg.get("max_spectators", 12)
	bots_enabled = cfg.get("bots", true)
	bots_shoot = cfg.get("bots_shoot", true)
	bots_move = cfg.get("bots_move", true)
	bot_skill = BotSkill.normalize(str(cfg.get("bot_skill", BotSkill.DEFAULT_LEVEL)))

	match_state = MatchState.new()
	match_state.mode = mode
	match_state.win_rounds = win_rounds
	match_state.kill_target = kill_target

	bot_director = BotDirector.new()


func setup_map() -> void:
	if MapCatalog.is_community(map_id):
		_setup_community_map()
	else:
		_setup_builtin_map()
	bot_director.set_skill(bot_skill)
	bot_director.configure(world, arena_size, spawns)

	match_state.next_meteor_at = _now + match_state.meteor_delay()


func _setup_builtin_map() -> void:
	var map_def: Dictionary = MapCatalog.builtin_definition(map_id)
	var compiled := MapEngine.compile(map_def)
	world = MapBuilder.build_world(compiled)
	spawns = MapCatalog.normalize_spawns(compiled.get("spawns", {}))
	arena_size = compiled.get("arena", 28.0)
	_bounds_half = MapBuilder.floor_half(compiled)


func _setup_community_map() -> void:
	var level := MapCatalog.load_community(map_id)
	if not level.ok():
		push_error("[server] %s did not import (%s); falling back to parkour" % [
			map_id, ", ".join(level.warnings)])
		_setup_builtin_map()
		return
	for w: String in level.warnings:
		print("[server] %s: %s" % [map_id, w])
	world = level.world
	spawns = level.spawns
	arena_size = level.arena
	_bounds_half = Vector2(level.arena, level.arena)
	print("[server] %s: %d brushes, %d spawns" % [
		map_id, world.brush_count(), level.spawn_count()])


func tick(dt: float) -> void:
	_now += dt
	_tick += 1

	_tick_match(dt)
	_tick_specials(dt)
	_tick_bots(dt)
	_tick_meteors(dt)
	_tick_respawns()

	# Coalesced so a join that also spawns bots pushes one roster, not three.
	if _roster_dirty:
		_roster_dirty = false
		_broadcast_roster()

	_history_timer += dt
	if _history_timer >= HISTORY_INTERVAL:
		_history_timer -= HISTORY_INTERVAL
		for pid: int in pawns:
			var pawn: ServerPawn = pawns[pid]
			if pawn.alive:
				pawn.record_history(_now)


# ── Admission ────────────────────────────────────────────────────────────

func admit_spectator(peer_id: int, callsign: String) -> Dictionary:
	if human_count() >= max_players + max_spectators:
		return {"ok": false, "reason": "Lobby is full."}

	var p := Participant.new(peer_id, callsign)
	p.team = Protocol.TEAM_NONE
	participants[peer_id] = p

	_sys_chat("%s joined." % callsign)
	_manage_bots()
	_roster_dirty = true
	_refresh_empty_clock()

	return {
		"ok": true,
		"init": _build_init_data(peer_id),
		"cheats": cheats,
	}


func remove(peer_id: int) -> void:
	if not participants.has(peer_id):
		return
	var p: Participant = participants[peer_id]
	_sys_chat("%s left." % p.display_name)
	_kill_pawn(peer_id, Protocol.CAUSE_VOID, 0, true)
	participants.erase(peer_id)
	pawns.erase(peer_id)
	_manage_bots()
	_roster_dirty = true
	_refresh_empty_clock()


# ── Team management ──────────────────────────────────────────────────────

func handle_team_menu(peer_id: int) -> void:
	if not participants.has(peer_id):
		return
	event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE, _build_team_opts(peer_id))


func handle_set_team(peer_id: int, new_team: int) -> void:
	if not participants.has(peer_id):
		return
	var p: Participant = participants[peer_id]
	var old_team := p.team

	if new_team == old_team:
		return

	if new_team == Protocol.TEAM_BLUE or new_team == Protocol.TEAM_RED:
		var count := _team_count(new_team, false)
		var per_team := max_players / 2
		if count >= per_team:
			event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE,
				Protocol.encode_team_denied("Team is full."))
			return

		var other_team := Protocol.TEAM_RED if new_team == Protocol.TEAM_BLUE else Protocol.TEAM_BLUE
		var other_count := _team_count(other_team, false)
		if count > other_count:
			event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE,
				Protocol.encode_team_denied("Teams would be unbalanced."))
			return

		if _team_switch_cooldowns.has(peer_id):
			var cd: float = _team_switch_cooldowns[peer_id]
			if _now * 1000.0 < cd:
				event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE,
					Protocol.encode_team_denied("Too soon to switch."))
				return

	if old_team == Protocol.TEAM_BLUE or old_team == Protocol.TEAM_RED:
		_kill_pawn(peer_id, Protocol.CAUSE_VOID, 0, true)
		_team_switch_cooldowns[peer_id] = _now * 1000.0 + TEAM_SWITCH_COOLDOWN_MS

	p.team = new_team

	if new_team == Protocol.TEAM_NONE:
		_sys_chat("%s moved to the stands." % p.display_name)
		event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_team(new_team, false, 0.0, 0.0, 0.0, 0.0))
	else:
		var team_name := "BLUE" if new_team == Protocol.TEAM_BLUE else "RED"
		_sys_chat("%s joined %s." % [p.display_name, team_name])
		_spawn_pawn(peer_id)
		var sp: ServerPawn = pawns.get(peer_id)
		if sp:
			event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE,
				Protocol.encode_team(new_team, true, sp.position.x, sp.position.y, sp.position.z, sp.yaw))
		else:
			event_to_peer.emit(peer_id, Protocol.CH_HANDSHAKE,
				Protocol.encode_team(new_team, false, 0.0, 0.0, 0.0, 0.0))

	_manage_bots()
	_roster_dirty = true


# ── State updates from client ────────────────────────────────────────────

func update_state(peer_id: int, pos: Vector3, yaw: float, pitch: float, crouched: bool,
		grounded: bool) -> void:
	if not pawns.has(peer_id):
		return
	var pawn: ServerPawn = pawns[peer_id]
	if not pawn.alive:
		return
	pawn.position = pos
	pawn.yaw = yaw
	pawn.pitch = pitch
	pawn.crouched = crouched
	pawn.grounded = grounded


# ── Combat ───────────────────────────────────────────────────────────────

func handle_shot(peer_id: int, origin: Vector3, dir: Vector3, lag_ms: int) -> void:
	if not participants.has(peer_id) or not pawns.has(peer_id):
		return
	var shooter: Participant = participants[peer_id]
	var shooter_pawn: ServerPawn = pawns[peer_id]
	if not shooter_pawn.alive:
		return
	if shooter.special_at > 0.0:
		return

	var rewind := clampf(float(lag_ms), 0.0, MAX_REWIND_MS) / 1000.0
	var rewind_time := _now - rewind
	var aim := dir.normalized()

	var team_u8 := Protocol.TEAM_BLUE if shooter.team == Protocol.TEAM_BLUE else Protocol.TEAM_RED
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_tracer(peer_id, origin.x, origin.y, origin.z,
			aim.x, aim.y, aim.z, team_u8), peer_id)

	# Nearest wall or cover occludes anything past it, so a player behind
	# geometry cannot take a laser hit through the map.
	var best_id := 0
	var best_dist := _raycast_world(origin, aim, SHOT_RANGE)
	var best_head := false

	for pid: int in participants:
		if pid == peer_id:
			continue
		var target: Participant = participants[pid]
		if target.team == shooter.team or target.team == Protocol.TEAM_NONE:
			continue
		if not pawns.has(pid):
			continue
		var target_pawn: ServerPawn = pawns[pid]
		if not target_pawn.alive:
			continue
		if _is_protected(target_pawn):
			continue

		var pose: Dictionary
		if target.is_bot:
			pose = {"x": target_pawn.position.x, "y": target_pawn.position.y,
					"z": target_pawn.position.z, "cr": target_pawn.crouched}
		else:
			pose = target_pawn.rewind_to(rewind_time)

		var target_pos := Vector3(pose["x"], pose["y"], pose["z"])
		var cr: bool = pose["cr"]
		var result := Hitbox.ray_vs_player(origin, aim, target_pos, cr, best_dist)
		if result["hit"]:
			best_id = pid
			best_dist = result["dist"]
			best_head = result["head"]

	if best_id != 0:
		var damage := DAMAGE_HEAD if best_head else DAMAGE_BODY
		_apply_damage(best_id, peer_id, damage, best_head, Protocol.CAUSE_LASER)


func handle_melee(peer_id: int, lag_ms: int) -> void:
	if not participants.has(peer_id) or not pawns.has(peer_id):
		return
	var shooter: Participant = participants[peer_id]
	var pawn: ServerPawn = pawns[peer_id]
	if not pawn.alive:
		return

	var eye := Vector3(pawn.position.x, pawn.position.y + Hitbox.eye_height(pawn.crouched), pawn.position.z)
	var fwd := _yaw_dir(pawn.yaw)

	for pid: int in participants:
		if pid == peer_id:
			continue
		var target: Participant = participants[pid]
		if target.team == shooter.team or target.team == Protocol.TEAM_NONE:
			continue
		if not pawns.has(pid):
			continue
		var tp: ServerPawn = pawns[pid]
		if not tp.alive or _is_protected(tp):
			continue

		var to_target := tp.position - pawn.position
		to_target.y = 0.0
		if to_target.length() > MELEE_RANGE:
			continue
		if to_target.length() > 0.001:
			var angle := fwd.angle_to(to_target.normalized())
			if angle > MELEE_ARC:
				continue

		_apply_damage(pid, peer_id, MELEE_DAMAGE, false, Protocol.CAUSE_MELEE)
		break


func handle_special_start(peer_id: int) -> void:
	if not participants.has(peer_id) or not pawns.has(peer_id):
		return
	var p: Participant = participants[peer_id]
	if not p.special_armed or p.special_at > 0.0:
		return
	var pawn: ServerPawn = pawns[peer_id]
	if not pawn.alive:
		return

	p.special_at = _now
	p.special_release = false
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_special(peer_id, p.team, Protocol.SP_CHARGE,
			Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0), 0)


func handle_special_fire(peer_id: int) -> void:
	if not participants.has(peer_id):
		return
	var p: Participant = participants[peer_id]
	if p.special_at <= 0.0:
		return
	p.special_release = true
	if _now - p.special_at >= SPECIAL_MIN_WINDUP:
		_fire_special(peer_id)


# ── Chat ─────────────────────────────────────────────────────────────────

func handle_chat(peer_id: int, text: String, team_only: bool) -> void:
	if not participants.has(peer_id):
		return
	var p: Participant = participants[peer_id]
	text = text.strip_edges().left(CHAT_MAX_LEN)
	if text.is_empty():
		return
	if not _chat_allowed(peer_id):
		return

	var msg := Protocol.encode_chat(peer_id, p.display_name, p.team, text, team_only, false)

	if team_only:
		if p.team == Protocol.TEAM_NONE:
			for pid: int in participants:
				var other: Participant = participants[pid]
				if other.team == Protocol.TEAM_NONE and not other.is_bot:
					event_to_peer.emit(pid, Protocol.CH_EVENTS, msg)
		else:
			event_team_broadcast.emit(p.team, Protocol.CH_EVENTS, msg)
	else:
		event_broadcast.emit(Protocol.CH_EVENTS, msg, -1)


func handle_set_cheats(enabled: bool) -> void:
	cheats = enabled
	var text := "Cheats enabled." if cheats else "Cheats disabled."
	_sys_chat(text)
	event_broadcast.emit(Protocol.CH_EVENTS, Protocol.encode_cheats(cheats), -1)


# ── SNAP ─────────────────────────────────────────────────────────────────

func build_snap() -> PackedByteArray:
	_snap_seq += 1
	var players: Array[Dictionary] = []

	for pid: int in participants:
		var p: Participant = participants[pid]
		var pawn_ref: ServerPawn = pawns.get(pid)
		var flags := 0
		if pawn_ref != null and pawn_ref.alive:
			flags |= Protocol.PFLG_ALIVE
		if pawn_ref and pawn_ref.grounded:
			flags |= Protocol.PFLG_GROUNDED
		if pawn_ref and pawn_ref.crouched:
			flags |= Protocol.PFLG_CROUCHED
		if pawn_ref and _is_protected(pawn_ref):
			flags |= Protocol.PFLG_PROTECTED
		if p.is_bot:
			flags |= Protocol.PFLG_BOT
		if p.special_armed:
			flags |= Protocol.PFLG_SPECIAL_ARMED
		if p.special_at > 0.0:
			flags |= Protocol.PFLG_SPECIAL_CHARGING

		var entry: Dictionary = {
			"id": pid,
			"flags": flags,
			"x": pawn_ref.position.x if pawn_ref else 0.0,
			"y": pawn_ref.position.y if pawn_ref else 0.0,
			"z": pawn_ref.position.z if pawn_ref else 0.0,
			"yaw": pawn_ref.yaw if pawn_ref else 0.0,
			"pitch": pawn_ref.pitch if pawn_ref else 0.0,
			"hp": pawn_ref.hp if pawn_ref else 0,
			"kills": p.kills,
			"deaths": p.deaths,
			"team": p.team,
			"ping": p.ping_ms,
			"special_progress": p.special_progress,
		}
		players.append(entry)

	var mode_int := Protocol.MODE_DM if mode == "dm" else Protocol.MODE_ARENA
	var clock := _clock_reading()
	return Protocol.encode_snap(
		match_state.score_blue, match_state.score_red, match_state.round_num,
		match_state.round_state, mode_int, match_state.kill_target,
		match_state.win_rounds, players, clock[0], clock[1])


# What the score bar should read, as [seconds, mode]. Decided here so every
# client agrees on it and someone joining late picks up the real time left,
# rather than each running its own timer from whenever it happened to load.
func _clock_reading() -> Array:
	if mode == "dm":
		if MatchState.DM_TIME_S <= 0.0:
			return [int(maxf(0.0, _now)), Protocol.CLOCK_UP]
		if match_state.match_ends_at <= 0.0:
			return [int(MatchState.DM_TIME_S), Protocol.CLOCK_DOWN]
		return [int(ceilf(maxf(0.0, match_state.match_ends_at - _now))), Protocol.CLOCK_DOWN]
	if match_state.round_ends_at <= 0.0:
		return [int(MatchState.ROUND_TIME_S), Protocol.CLOCK_DOWN]
	return [int(ceilf(maxf(0.0, match_state.round_ends_at - _now))), Protocol.CLOCK_DOWN]


# ── Internals ────────────────────────────────────────────────────────────

func _tick_match(_dt: float) -> void:
	if match_state.round_state == Protocol.RS_OVER:
		return

	if match_state.round_state == Protocol.RS_ENDED:
		if _now >= match_state.round_end_at:
			_start_round()
		return

	_check_out_of_bounds()

	if mode == "dm":
		_check_dm_time()
	else:
		_check_arena_round()


# Falling off the map kills rather than dropping forever. Grid arena's
# catwalks run above the tops of its perimeter walls, so a player can step
# over one into open space with nothing below to ever stop them.
#
# The height test is the one that catches everything: whatever route took
# them off the map, they end up under it. The horizontal test is for a pawn
# flung past the wall by a blast while still level with the floor.
func _check_out_of_bounds() -> void:
	for pid: int in pawns:
		var pawn: ServerPawn = pawns[pid]
		if not pawn.alive:
			continue
		if pawn.position.y > VOID_Y \
				and absf(pawn.position.x) <= _bounds_half.x + VOID_MARGIN \
				and absf(pawn.position.z) <= _bounds_half.y + VOID_MARGIN:
			continue
		# Routed through the damage path so the death counts, the kill feed
		# names the void, and a deathmatch respawn is scheduled, exactly as
		# a lethal hit would. by_id 0 leaves it uncredited.
		_apply_damage(pid, 0, VOID_DAMAGE, false, Protocol.CAUSE_VOID)


# Deathmatch is played to the kill target; the clock is only here so a
# lobby that never gets there still finishes. It starts when the first
# player arrives rather than when the lobby is created, or an idle lobby
# would burn the whole match down waiting for someone to join.
func _check_dm_time() -> void:
	if match_state.match_ends_at <= 0.0:
		if MatchState.DM_TIME_S > 0.0 and not participants.is_empty():
			match_state.match_ends_at = _now + MatchState.DM_TIME_S
		return
	if _now < match_state.match_ends_at:
		return

	var winner := Protocol.TEAM_NONE
	if match_state.score_blue > match_state.score_red:
		winner = Protocol.TEAM_BLUE
	elif match_state.score_red > match_state.score_blue:
		winner = Protocol.TEAM_RED

	match_state.round_state = Protocol.RS_OVER
	match_state.winner = winner
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_round_end(winner, match_state.score_blue, match_state.score_red,
			true, false, match_state.round_num, Protocol.END_TIME), -1)
	_broadcast_match_over(winner)


# An arena round ends three ways: one side is wiped out, one side empties
# because everyone on it left or went to spectate, or the clock runs out.
# The middle one matters as much as the first: a round waiting on a team
# with nobody left to kill would sit there forever.
func _check_arena_round() -> void:
	# The clock runs from the moment the round does, whoever is here. A
	# number that only starts once the lobby fills reads as a broken one.
	if match_state.round_ends_at <= 0.0:
		match_state.round_ends_at = _now + MatchState.ROUND_TIME_S

	var blue := _team_standing(Protocol.TEAM_BLUE)
	var red := _team_standing(Protocol.TEAM_RED)
	match_state.round_had_blue = match_state.round_had_blue or blue["total"] > 0
	match_state.round_had_red = match_state.round_had_red or red["total"] > 0

	# A side that emptied out hands the round over. A side nobody has
	# joined yet does not: a lobby with one player would otherwise award
	# them the whole match a round at a time while they waited for someone.
	var blue_left: bool = blue["total"] == 0 and match_state.round_had_blue
	var red_left: bool = red["total"] == 0 and match_state.round_had_red
	if blue_left != red_left:
		_award_round(
			Protocol.TEAM_RED if blue_left else Protocol.TEAM_BLUE,
			Protocol.END_FORFEIT)
		return

	var contested: bool = blue["total"] > 0 and red["total"] > 0
	if contested and (blue["alive"] == 0 or red["alive"] == 0):
		var standing := Protocol.TEAM_NONE
		if blue["alive"] > 0:
			standing = Protocol.TEAM_BLUE
		elif red["alive"] > 0:
			standing = Protocol.TEAM_RED
		# Both sides going down together is a draw, not a win for whoever
		# the comparison happens to fall through to.
		_award_round(standing, Protocol.END_ELIMINATION)
		return

	if _now >= match_state.round_ends_at:
		# Uncontested, the clock simply resets the round: there was nobody
		# to beat, so nobody won it.
		_award_round(_time_winner(blue, red) if contested else Protocol.TEAM_NONE,
			Protocol.END_TIME)


# Who is on a team and how they are doing, as one pass over the roster.
func _team_standing(team: int) -> Dictionary:
	var total := 0
	var alive := 0
	var hp := 0
	for pid: int in participants:
		if participants[pid].team != team:
			continue
		total += 1
		if pawns.has(pid) and (pawns[pid] as ServerPawn).alive:
			alive += 1
			hp += maxi((pawns[pid] as ServerPawn).hp, 0)
	return {"total": total, "alive": alive, "hp": hp}


# Time ran out with both sides still standing, so it goes to whoever is in
# better shape: more players up, and failing that more health between them.
# Dead level is a draw.
func _time_winner(blue: Dictionary, red: Dictionary) -> int:
	if blue["alive"] != red["alive"]:
		return Protocol.TEAM_BLUE if blue["alive"] > red["alive"] else Protocol.TEAM_RED
	if blue["hp"] != red["hp"]:
		return Protocol.TEAM_BLUE if blue["hp"] > red["hp"] else Protocol.TEAM_RED
	return Protocol.TEAM_NONE


func _award_round(winner: int, reason: int) -> void:
	# A draw closes the round out without scoring for either side.
	if winner == Protocol.TEAM_BLUE:
		match_state.score_blue += 1
	elif winner == Protocol.TEAM_RED:
		match_state.score_red += 1

	match_state.round_ends_at = 0.0

	var match_over := false
	var match_point := false
	if match_state.score_blue >= match_state.win_rounds or match_state.score_red >= match_state.win_rounds:
		match_over = true
		match_state.round_state = Protocol.RS_OVER
		match_state.winner = winner
	else:
		match_state.round_state = Protocol.RS_ENDED
		match_state.round_end_at = _now + MatchState.ROUND_END_DELAY

		var needed := match_state.win_rounds
		if match_state.score_blue == needed - 1 or match_state.score_red == needed - 1:
			match_point = true

	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_round_end(winner, match_state.score_blue, match_state.score_red,
			match_over, match_point, match_state.round_num, reason), -1)

	if match_over:
		_broadcast_match_over(winner)


func _start_round() -> void:
	match_state.round_num += 1
	match_state.round_state = Protocol.RS_ACTIVE
	# Left unarmed; the round's first tick starts the clock.
	match_state.round_ends_at = 0.0
	match_state.round_had_blue = false
	match_state.round_had_red = false
	match_state.first_blood_done = false
	match_state.match_point_announced = false
	match_state.pending_meteor = {}
	match_state.next_meteor_at = _now + match_state.meteor_delay()

	# Rebalance before redeploying so bots added for this round spawn with everyone else.
	_manage_bots()

	# Arena redeploys the whole side at base each round, survivors included.
	for pid: int in participants:
		var p: Participant = participants[pid]
		if p.team != Protocol.TEAM_BLUE and p.team != Protocol.TEAM_RED:
			continue
		# Streaks and an armed special carry over, but a wind-up caught by the
		# round boundary must not auto-fire into the new round.
		p.special_at = 0.0
		p.special_release = false
		_spawn_pawn(pid, MatchState.PREP_TIME_MS)
		if p.is_bot:
			continue
		var rp: ServerPawn = pawns[pid]
		event_to_peer.emit(pid, Protocol.CH_EVENTS,
			Protocol.encode_respawn(pid, rp.position.x, rp.position.y, rp.position.z, rp.yaw, true))

	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_round_start(match_state.score_blue, match_state.score_red, match_state.round_num), -1)


func _broadcast_match_over(winner: int) -> void:
	var stats: Array[Dictionary] = []
	for pid: int in participants:
		var p: Participant = participants[pid]
		stats.append({
			"id": pid, "name": p.display_name, "team": p.team,
			"kills": p.kills, "deaths": p.deaths, "is_bot": p.is_bot,
		})
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_match_over(
			winner, match_state.score_blue, match_state.score_red, stats), -1)


func _tick_specials(_dt: float) -> void:
	for pid: int in participants:
		var p: Participant = participants[pid]
		if p.special_at <= 0.0:
			continue
		var elapsed := _now - p.special_at
		if p.special_release and elapsed >= SPECIAL_MIN_WINDUP:
			_fire_special(pid)
		elif elapsed >= SPECIAL_AUTO_FIRE:
			_fire_special(pid)


func _fire_special(pid: int) -> void:
	if not participants.has(pid) or not pawns.has(pid):
		return
	var p: Participant = participants[pid]
	var pawn: ServerPawn = pawns[pid]
	if not pawn.alive:
		_clear_special(p)
		return

	p.special_at = 0.0
	p.special_release = false
	p.special_armed = false

	var eye := Vector3(pawn.position.x,
		pawn.position.y + Hitbox.eye_height(pawn.crouched), pawn.position.z)
	var dir := _aim_dir(pawn.yaw, pawn.pitch)

	# Cover and stairs do not stop a special — only the floor and the arena
	# walls do. Otherwise the blast goes off on the pad in front of you.
	var beam_len := _raycast_world(eye, dir, SPECIAL_RANGE, true)
	var impact := eye + dir * beam_len

	var victims: Array[int] = []
	for target_id: int in participants:
		if target_id == pid:
			continue
		var target: Participant = participants[target_id]
		if target.team == p.team or target.team == Protocol.TEAM_NONE:
			continue
		if not pawns.has(target_id):
			continue
		var tp: ServerPawn = pawns[target_id]
		if not tp.alive:
			continue

		# Landing blast: meteor slab, through cover, no line of sight.
		if _in_blast(tp.position, impact, SPECIAL_BLAST_RADIUS, SPECIAL_BLAST_VERT):
			victims.append(target_id)
			continue

		# Anyone standing near the beam line, measured to the chest so a
		# beam at eye height still catches people on the floor.
		var chest := Vector3(tp.position.x,
			tp.position.y + Hitbox.aim_height(tp.crouched), tp.position.z)
		if _point_to_segment_dist(chest, eye, dir, beam_len) <= SPECIAL_BEAM_RADIUS:
			victims.append(target_id)

	for target_id in victims:
		if match_state.round_state != Protocol.RS_ACTIVE:
			break
		_apply_damage(target_id, pid, 999, false, Protocol.CAUSE_SPECIAL)

	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_special(pid, p.team, Protocol.SP_FIRE,
			eye, dir, impact, beam_len, SPECIAL_BLAST_RADIUS), 0)


func _tick_bots(dt: float) -> void:
	if not bots_enabled:
		return
	if match_state.round_state != Protocol.RS_ACTIVE:
		return

	for pid: int in participants:
		var p: Participant = participants[pid]
		if not p.is_bot:
			continue
		if not pawns.has(pid):
			continue
		var pawn: ServerPawn = pawns[pid]
		if not pawn.alive:
			continue

		var actions := bot_director.update_bot(p, pawn, participants, pawns,
			bots_shoot, bots_move, true, _now, dt)

		if actions.get("special_start", false):
			handle_special_start(pid)
		if actions.get("special_release", false):
			handle_special_fire(pid)
		if actions.get("shoot", false):
			var eye := Vector3(pawn.position.x,
				pawn.position.y + Hitbox.eye_height(pawn.crouched), pawn.position.z)
			var dir := _aim_dir(pawn.yaw, pawn.pitch)
			handle_shot(pid, eye, dir, 0)
		if actions.get("melee", false):
			handle_melee(pid, 0)


func _tick_meteors(_dt: float) -> void:
	if not match_state.pending_meteor.is_empty():
		var impact_at: float = match_state.pending_meteor.get("impact_at", 0.0)
		if _now >= impact_at:
			_meteor_impact()
		return

	if match_state.round_state != Protocol.RS_ACTIVE:
		return

	if _now >= match_state.next_meteor_at:
		_arm_meteor()


func _arm_meteor() -> void:
	var a := arena_size - 2.5
	var x := (randf() * 2.0 - 1.0) * a
	var z := (randf() * 2.0 - 1.0) * a

	var ground_y := 0.0
	var ray_origin := Vector3(x, 50.0, z)
	var world_dist := _raycast_world(ray_origin, Vector3.DOWN, 100.0)
	if world_dist < 100.0:
		ground_y = 50.0 - world_dist

	match_state.pending_meteor = {
		"x": x, "y": ground_y, "z": z,
		"impact_at": _now + MatchState.METEOR_LEAD_S,
		"radius": MatchState.METEOR_RADIUS,
	}

	var lead_ms := int(MatchState.METEOR_LEAD_S * 1000.0)
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_meteor(x, ground_y, z, lead_ms, MatchState.METEOR_RADIUS), -1)


func _meteor_impact() -> void:
	var mx: float = match_state.pending_meteor["x"]
	var my: float = match_state.pending_meteor["y"]
	var mz: float = match_state.pending_meteor["z"]
	var radius: float = match_state.pending_meteor["radius"]
	match_state.pending_meteor = {}
	match_state.next_meteor_at = _now + match_state.meteor_delay()

	if match_state.round_state != Protocol.RS_ACTIVE:
		return

	for pid: int in participants:
		if not pawns.has(pid):
			continue
		var pawn: ServerPawn = pawns[pid]
		if not pawn.alive:
			continue
		if _is_protected(pawn):
			continue
		if _in_blast(pawn.position, Vector3(mx, my, mz), radius, MatchState.METEOR_VERT):
			_apply_damage(pid, 0, 999, false, Protocol.CAUSE_METEOR)


func _tick_respawns() -> void:
	if mode != "dm":
		return
	if match_state.round_state != Protocol.RS_ACTIVE:
		return

	for pid: int in pawns:
		var pawn: ServerPawn = pawns[pid]
		if pawn.alive:
			continue
		if pawn.respawn_at > 0.0 and _now * 1000.0 >= pawn.respawn_at:
			_spawn_pawn(pid)
			if not participants[pid].is_bot:
				var rp: ServerPawn = pawns[pid]
				event_to_peer.emit(pid, Protocol.CH_EVENTS,
					Protocol.encode_respawn(pid, rp.position.x, rp.position.y, rp.position.z, rp.yaw))


func _apply_damage(target_id: int, by_id: int, damage: int, head: bool, cause: int) -> void:
	if not pawns.has(target_id) or not participants.has(target_id):
		return
	var target_pawn: ServerPawn = pawns[target_id]
	if not target_pawn.alive:
		return

	target_pawn.hp -= damage
	var killed := target_pawn.hp <= 0

	var by_name := ""
	var by_team := Protocol.TEAM_NONE
	if participants.has(by_id):
		by_name = participants[by_id].display_name
		by_team = participants[by_id].team
	var target: Participant = participants[target_id]

	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_hit(target_id, by_id, maxi(target_pawn.hp, 0), killed, head,
			cause, by_name, target.display_name, by_team, target.team), -1)

	if not killed:
		return

	target_pawn.alive = false
	target_pawn.hp = 0
	target.deaths += 1
	target.streak = 0
	target.special_progress = 0
	target.multi = 0
	_clear_special(target)

	if mode == "dm":
		target_pawn.respawn_at = _now * 1000.0 + DM_RESPAWN_MS

	if by_id != 0 and by_id != target_id and participants.has(by_id):
		_on_kill(by_id, target_id, head, cause)


func _on_kill(killer_id: int, _victim_id: int, head: bool, cause: int) -> void:
	var killer: Participant = participants[killer_id]
	killer.kills += 1
	killer.streak += 1

	if _now - killer.last_kill_at <= MatchState.MULTI_WINDOW:
		killer.multi += 1
	else:
		killer.multi = 1
	killer.last_kill_at = _now

	# A banked special freezes charge progress. Extra frags while you sit on it
	# do not count toward the next one — spend it, then start a fresh five.
	# Special-weapon kills themselves also do not charge the next one.
	if not killer.special_armed and cause != Protocol.CAUSE_SPECIAL:
		killer.special_progress += 1
		if killer.special_progress >= MatchState.SPECIAL_STREAK:
			killer.special_progress = 0
			_grant_special(killer_id)

	if mode == "dm":
		if killer.team == Protocol.TEAM_BLUE:
			match_state.score_blue += 1
		elif killer.team == Protocol.TEAM_RED:
			match_state.score_red += 1

		if match_state.score_blue >= match_state.kill_target or match_state.score_red >= match_state.kill_target:
			var winner := Protocol.TEAM_BLUE if match_state.score_blue >= match_state.kill_target else Protocol.TEAM_RED
			match_state.round_state = Protocol.RS_OVER
			match_state.winner = winner
			_broadcast_match_over(winner)
			return

	var is_first_blood := not match_state.first_blood_done
	if is_first_blood:
		match_state.first_blood_done = true

	var mp := false
	if mode == "arena":
		var needed := match_state.win_rounds
		if (match_state.score_blue == needed - 1 or match_state.score_red == needed - 1) and not match_state.match_point_announced:
			mp = true
			match_state.match_point_announced = true

	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_announce(killer_id, killer.display_name, killer.team,
			killer.multi, killer.streak, is_first_blood, head, mp, killer.special_progress), -1)


func _grant_special(pid: int) -> void:
	if not participants.has(pid):
		return
	var p: Participant = participants[pid]
	if p.special_armed:
		return
	p.special_armed = true
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_special(pid, p.team, Protocol.SP_READY,
			Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0), -1)


func _clear_special(p: Participant) -> void:
	p.special_armed = false
	p.special_at = 0.0
	p.special_release = false


func _spawn_pawn(pid: int, protection_ms: float = SPAWN_PROTECTION_MS) -> void:
	var p: Participant = participants[pid]
	if p.team == Protocol.TEAM_NONE:
		return

	var team_key := "blue" if p.team == Protocol.TEAM_BLUE else "red"
	var fallback := [{"position": Vector3.ZERO, "yaw": 180.0 if p.team == Protocol.TEAM_BLUE else 0.0}]
	var spawn_list: Array = spawns.get(team_key, fallback)
	if spawn_list.is_empty():
		spawn_list = fallback
	var pick: Dictionary = spawn_list[randi() % spawn_list.size()]
	var at: Vector3 = pick["position"]
	# Scatter across the point so two players spawning together do not arrive
	# inside one another, but only horizontally: nudging the height would drop
	# someone through a platform or float them above it.
	var jitter := Vector3((randf() - 0.5) * 1.4, 0.0, (randf() - 0.5) * 1.4)

	var pawn := ServerPawn.new()
	pawn.participant_id = pid
	pawn.position = at + jitter
	pawn.yaw = float(pick["yaw"])
	pawn.hp = 100
	pawn.alive = true
	pawn.protected_until = _now + protection_ms / 1000.0
	pawns[pid] = pawn


func _kill_pawn(pid: int, cause: int, by_id: int, silent: bool) -> void:
	if not pawns.has(pid):
		return
	var pawn: ServerPawn = pawns[pid]
	if not pawn.alive:
		return
	pawn.alive = false
	pawn.hp = 0

	if not silent:
		var p: Participant = participants[pid]
		p.deaths += 1
		p.streak = 0
		p.special_progress = 0
		_clear_special(p)


func _manage_bots() -> void:
	if not bots_enabled:
		return

	var actions := bot_director.manage_bots(participants, true, max_players)
	if not actions.is_empty():
		_roster_dirty = true
	for action: Dictionary in actions:
		if action["action"] == "add":
			var bot_p := Participant.new(action["id"], action["name"], true)
			bot_p.team = action["team"]
			var session := {}
			for key: String in action:
				if key != "action" and key != "id" and key != "name" and key != "team":
					session[key] = action[key]
			bot_p.connection_session = session
			participants[action["id"]] = bot_p
			bot_director.init_ai(bot_p)
			_spawn_pawn(action["id"])
		elif action["action"] == "remove":
			var bid: int = action["id"]
			_kill_pawn(bid, Protocol.CAUSE_VOID, 0, true)
			participants.erase(bid)
			pawns.erase(bid)


func _is_protected(pawn: ServerPawn) -> bool:
	if pawn == null:
		return false
	return _now < pawn.protected_until


func human_count() -> int:
	var n := 0
	for p: Participant in participants.values():
		if not p.is_bot:
			n += 1
	return n


func empty_of_humans_for() -> float:
	if _empty_since < 0.0:
		return 0.0
	return _now - _empty_since


func _refresh_empty_clock() -> void:
	if human_count() > 0:
		_empty_since = -1.0
	elif _empty_since < 0.0:
		_empty_since = _now


func _team_count(team: int, include_bots: bool) -> int:
	var count := 0
	for p: Participant in participants.values():
		if p.team == team:
			if include_bots or not p.is_bot:
				count += 1
	return count


func _broadcast_roster() -> void:
	var entries: Array[Dictionary] = []
	for pid: int in participants:
		var p: Participant = participants[pid]
		entries.append({
			"id": pid, "name": p.display_name,
			"team": p.team, "is_bot": p.is_bot,
		})
	event_broadcast.emit(Protocol.CH_EVENTS, Protocol.encode_roster(entries), -1)


func _build_init_data(peer_id: int) -> PackedByteArray:
	var p: Participant = participants[peer_id]
	var team_str := ""
	if p.team == Protocol.TEAM_BLUE:
		team_str = "blue"
	elif p.team == Protocol.TEAM_RED:
		team_str = "red"
	var rs_str := "active"
	if match_state.round_state == Protocol.RS_ENDED:
		rs_str = "ended"
	elif match_state.round_state == Protocol.RS_OVER:
		rs_str = "over"
	return Protocol.encode_init(peer_id, team_str, map_id, mode,
		match_state.score_blue, match_state.score_red, match_state.round_num,
		win_rounds, kill_target, bots_shoot, rs_str, max_spectators)


func _build_team_opts(peer_id: int) -> PackedByteArray:
	var p: Participant = participants[peer_id]
	var per_team := max_players / 2
	return Protocol.encode_team_opts(
		p.team,
		_team_count(Protocol.TEAM_BLUE, true), per_team,
		_team_count(Protocol.TEAM_RED, true), per_team,
		_team_count(Protocol.TEAM_NONE, false), max_spectators)


func _sys_chat(text: String) -> void:
	event_broadcast.emit(Protocol.CH_EVENTS,
		Protocol.encode_chat(0, "", Protocol.TEAM_NONE, text, false, true), -1)


func _chat_allowed(peer_id: int) -> bool:
	if not _chat_log.has(peer_id):
		_chat_log[peer_id] = []
	var log: Array = _chat_log[peer_id]
	var cutoff := _now - CHAT_BURST_WINDOW
	while not log.is_empty() and log[0] < cutoff:
		log.pop_front()
	if log.size() >= CHAT_BURST_MAX:
		return false
	log.append(_now)
	return true


func _raycast_world(origin: Vector3, dir: Vector3, max_dist: float,
		punch_cover: bool = false) -> float:
	if world == null:
		return max_dist
	# Against brushes rather than their bounding boxes, so a shot over a ramp
	# reaches what is behind it instead of stopping on the empty air above the
	# slope. The special beam only sees brushes tall enough to stop it.
	var mask := CollisionWorld.MASK_SPECIAL if punch_cover else CollisionWorld.MASK_SOLID
	return world.ray_distance(origin, dir.normalized(), max_dist, _shot_trace, mask)




func _yaw_dir(yaw_deg: float) -> Vector3:
	var rad := deg_to_rad(yaw_deg)
	return Vector3(-sin(rad), 0.0, -cos(rad))


func _aim_dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	var ry := deg_to_rad(yaw_deg)
	var rp := deg_to_rad(pitch_deg)
	return Vector3(-sin(ry) * cos(rp), -sin(rp), -cos(ry) * cos(rp))


func _point_to_segment_dist(point: Vector3, origin: Vector3, dir: Vector3,
		length: float) -> float:
	var t := clampf((point - origin).dot(dir), 0.0, length)
	return point.distance_to(origin + dir * t)


func _in_blast(pos: Vector3, center: Vector3, radius: float, vert: float) -> bool:
	if absf(pos.y - center.y) > vert:
		return false
	var dx := pos.x - center.x
	var dz := pos.z - center.z
	return dx * dx + dz * dz <= radius * radius


static func _gen_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := ""
	for i in 8:
		out += chars[randi() % chars.length()]
	return out
