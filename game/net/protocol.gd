class_name Protocol
extends RefCounted

const CH_UNRELIABLE := 0
const CH_HANDSHAKE := 1
const CH_EVENTS := 2
const CH_BULK := 3
const MAX_CHANNELS := 4
const PROTOCOL_VERSION := 7

# Why a round ended, so the overlay can say so rather than always claiming
# the losing side was wiped out.
const END_ELIMINATION := 0
const END_TIME := 1
const END_FORFEIT := 2

# How to read the clock a snap carries. It always runs, so there is no
# third state for a stopped one.
const CLOCK_UP := 0
const CLOCK_DOWN := 1

const MODE_ARENA := 0
const MODE_DM := 1

const PFLG_ALIVE := 1
const PFLG_CROUCHED := 2
const PFLG_PROTECTED := 4
const PFLG_BOT := 8
const PFLG_SPECIAL_ARMED := 16
const PFLG_SPECIAL_CHARGING := 32
const PFLG_GROUNDED := 64

# Flags on a client's own state message. Whether the player is standing on
# something is theirs to report: only they run the movement code that decides
# it, and it cannot be recovered from position alone. Vertical speed does not
# separate the two, because at a full run a jump leaves the ground at about the
# same rate as climbing a steep ramp.
const SFLG_CROUCHED := 1
const SFLG_GROUNDED := 2

enum Msg {
	CREATE_GAME,
	JOIN_DIRECT,
	JOIN_ERROR,
	INIT,
	STATE,
	SNAP,
	SET_TEAM,
	TEAM_OPTS,
	TEAM,
	TEAM_DENIED,
	SHOT,
	LEAVE,
	SPECIAL_START,
	SPECIAL_FIRE,
	MELEE,
	TEAM_MENU,
	HIT,
	TRACER,
	ROUND_START,
	ROUND_END,
	MATCH_OVER,
	RESPAWN,
	CHAT,
	SPECIAL,
	ANNOUNCE,
	METEOR,
	ROSTER,
	SET_CHEATS,
	CHEATS,
	SET_CHEATS_DENIED,
	JOIN_AUTH,
	HELLO,
}

enum Team { TEAM_NONE = 0, TEAM_BLUE = 1, TEAM_RED = 2 }
enum Cause { CAUSE_LASER = 0, CAUSE_MELEE = 1, CAUSE_SPECIAL = 2, CAUSE_METEOR = 3, CAUSE_VOID = 4 }
enum RoundState { RS_ACTIVE = 0, RS_ENDED = 1, RS_OVER = 2 }
enum SpecialPhase { SP_READY = 0, SP_CHARGE = 1, SP_FIRE = 2, SP_END = 3 }

const TEAM_NONE := 0
const TEAM_BLUE := 1
const TEAM_RED := 2
const CAUSE_LASER := 0
const CAUSE_MELEE := 1
const CAUSE_SPECIAL := 2
const CAUSE_METEOR := 3
const CAUSE_VOID := 4
const RS_ACTIVE := 0
const RS_ENDED := 1
const RS_OVER := 2
const SP_READY := 0
const SP_CHARGE := 1
const SP_FIRE := 2
const SP_END := 3


# ============================================================
#  Helpers
# ============================================================

static func _buf() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	return b


static func _write_string(b: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_utf8_buffer()
	b.put_u16(bytes.size())
	if bytes.size() > 0:
		b.put_data(bytes)


static func _read_string(b: StreamPeerBuffer) -> String:
	var len := b.get_u16()
	if len == 0:
		return ""
	return b.get_data(len)[1].get_string_from_utf8()


static func channel_for(t: int) -> int:
	match t:
		Msg.STATE, Msg.SNAP:
			return CH_UNRELIABLE
		Msg.HIT, Msg.TRACER, Msg.ROUND_START, Msg.ROUND_END, Msg.MATCH_OVER, Msg.RESPAWN, Msg.CHAT, Msg.SPECIAL, Msg.ANNOUNCE, Msg.METEOR, Msg.ROSTER, Msg.CHEATS:
			return CH_EVENTS
		_:
			return CH_HANDSHAKE


# ============================================================
#  Framing
# ============================================================

# Reliable: u16 size | body   (enables message batching per ENet packet)
static func frame_reliable(body: PackedByteArray) -> PackedByteArray:
	var b := _buf()
	b.put_u16(body.size())
	b.put_data(body)
	return b.data_array


# Unreliable: rearranges body[type,flags,payload…] into wire order
#   type(u8) flags(u8) seq(u16) tick(u32) payload…
static func frame_unreliable(body: PackedByteArray, seq: int, tick: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(body[0])
	b.put_u8(body[1])
	b.put_u16(seq)
	b.put_u32(tick)
	if body.size() > 2:
		b.put_data(body.slice(2))
	return b.data_array


static func decode_reliable_batch(data: PackedByteArray) -> Array[Dictionary]:
	var b := _buf()
	b.data_array = data
	var out: Array[Dictionary] = []
	while b.get_position() < b.get_size():
		var size := b.get_u16()
		var end_pos := b.get_position() + size
		var t := b.get_u8()
		var flags := b.get_u8()
		out.append(_decode_body(b, t, flags))
		b.seek(end_pos)
	return out


# ============================================================
#  Decode
# ============================================================

static func decode(data: PackedByteArray, unreliable: bool = false) -> Dictionary:
	var b := _buf()
	b.data_array = data
	var t := b.get_u8()
	var flags := b.get_u8()
	if unreliable:
		var seq := b.get_u16()
		var tick := b.get_u32()
		var d := _decode_body(b, t, flags)
		d["seq"] = seq
		d["tick"] = tick
		return d
	return _decode_body(b, t, flags)


static func _decode_body(b: StreamPeerBuffer, t: int, flags: int) -> Dictionary:
	var d := {"t": t, "flags": flags}
	match t:
		Msg.CREATE_GAME:
			d["map"] = _read_string(b)
			d["mode"] = _read_string(b)
			d["rounds"] = b.get_u16()
			d["kills"] = b.get_u16()
			d["max_players"] = b.get_u8()
			d["max_spectators"] = b.get_u8()
			d["bots"] = b.get_u8() != 0
			d["bots_shoot"] = b.get_u8() != 0
			d["bots_move"] = b.get_u8() != 0
			d["bot_skill"] = b.get_u8()
			d["display_name"] = _read_string(b)
		Msg.HELLO:
			d["v"] = b.get_u8()
			var map_count := b.get_u16()
			var maps: Array[String] = []
			for i in map_count:
				maps.append(_read_string(b))
			d["maps"] = maps
		Msg.JOIN_DIRECT:
			d["v"] = b.get_u8()
			d["name"] = _read_string(b)
		Msg.JOIN_AUTH:
			d["v"] = b.get_u8()
			d["name"] = _read_string(b)
			d["token_id"] = _read_string(b)
			d["game_id"] = _read_string(b)
			d["expires_at"] = b.get_64()
			d["signature"] = _read_string(b)
		Msg.JOIN_ERROR:
			d["reason"] = _read_string(b)
		Msg.INIT:
			d["id"] = b.get_32()
			d["team"] = _read_string(b)
			d["map"] = _read_string(b)
			d["mode"] = _read_string(b)
			d["score_blue"] = b.get_u16()
			d["score_red"] = b.get_u16()
			d["round_num"] = b.get_u16()
			d["win_rounds"] = b.get_u16()
			d["kill_target"] = b.get_u16()
			d["bots_shoot"] = b.get_u8() != 0
			d["round_state"] = _read_string(b)
			d["max_spectators"] = b.get_u8()
		Msg.STATE:
			d["crouched"] = (flags & SFLG_CROUCHED) != 0
			d["grounded"] = (flags & SFLG_GROUNDED) != 0
			d["x"] = b.get_float()
			d["y"] = b.get_float()
			d["z"] = b.get_float()
			d["yaw"] = b.get_float()
			d["pitch"] = b.get_float()
		Msg.SNAP:
			d["score_blue"] = b.get_u16()
			d["score_red"] = b.get_u16()
			d["round_num"] = b.get_u16()
			d["round_state"] = b.get_u8()
			d["mode"] = b.get_u8()
			d["kill_target"] = b.get_u16()
			d["win_rounds"] = b.get_u16()
			d["clock_s"] = b.get_u16()
			d["clock_mode"] = b.get_u8()
			var count := b.get_u8()
			var players: Array[Dictionary] = []
			for _i in count:
				var p := {}
				p["id"] = b.get_32()
				p["flags"] = b.get_u8()
				p["x"] = b.get_float()
				p["y"] = b.get_float()
				p["z"] = b.get_float()
				p["yaw"] = b.get_float()
				p["pitch"] = b.get_float()
				p["hp"] = b.get_u8()
				p["kills"] = b.get_u16()
				p["deaths"] = b.get_u16()
				p["team"] = b.get_u8()
				p["ping"] = b.get_u16()
				p["special_progress"] = b.get_u8()
				players.append(p)
			d["players"] = players
		Msg.SET_TEAM:
			d["team"] = b.get_u8()
		Msg.TEAM_MENU:
			pass
		Msg.TEAM_OPTS:
			d["current_team"] = b.get_u8()
			d["blue_used"] = b.get_u8()
			d["blue_max"] = b.get_u8()
			d["red_used"] = b.get_u8()
			d["red_max"] = b.get_u8()
			d["spec_used"] = b.get_u8()
			d["spec_max"] = b.get_u8()
		Msg.TEAM:
			d["alive"] = (flags & 1) != 0
			d["team"] = b.get_u8()
			d["spawn_x"] = b.get_float()
			d["spawn_y"] = b.get_float()
			d["spawn_z"] = b.get_float()
			d["yaw"] = b.get_float()
		Msg.TEAM_DENIED:
			d["reason"] = _read_string(b)
		Msg.SHOT:
			d["origin_x"] = b.get_float()
			d["origin_y"] = b.get_float()
			d["origin_z"] = b.get_float()
			d["dir_x"] = b.get_float()
			d["dir_y"] = b.get_float()
			d["dir_z"] = b.get_float()
			d["lag_ms"] = b.get_u16()
		Msg.MELEE:
			d["lag_ms"] = b.get_u16()
		Msg.HIT:
			d["killed"] = (flags & 1) != 0
			d["head"] = (flags & 2) != 0
			d["target_id"] = b.get_32()
			d["by_id"] = b.get_32()
			d["hp"] = b.get_u8()
			d["cause"] = b.get_u8()
			d["by_name"] = _read_string(b)
			d["target_name"] = _read_string(b)
			d["by_team"] = b.get_u8()
			d["target_team"] = b.get_u8()
		Msg.TRACER:
			d["by_id"] = b.get_32()
			d["origin_x"] = b.get_float()
			d["origin_y"] = b.get_float()
			d["origin_z"] = b.get_float()
			d["dir_x"] = b.get_float()
			d["dir_y"] = b.get_float()
			d["dir_z"] = b.get_float()
			d["team"] = b.get_u8()
		Msg.ROUND_START:
			d["score_blue"] = b.get_u16()
			d["score_red"] = b.get_u16()
			d["round_num"] = b.get_u16()
		Msg.ROUND_END:
			d["match_over"] = (flags & 1) != 0
			d["match_point"] = (flags & 2) != 0
			d["winner"] = b.get_u8()
			d["score_blue"] = b.get_u16()
			d["score_red"] = b.get_u16()
			d["round_num"] = b.get_u16()
			d["reason"] = b.get_u8()
		Msg.MATCH_OVER:
			d["winner"] = b.get_u8()
			d["score_blue"] = b.get_u16()
			d["score_red"] = b.get_u16()
			var count := b.get_u8()
			var stats: Array[Dictionary] = []
			for _i in count:
				var s := {}
				s["id"] = b.get_32()
				s["name"] = _read_string(b)
				s["team"] = b.get_u8()
				s["kills"] = b.get_u16()
				s["deaths"] = b.get_u16()
				s["is_bot"] = b.get_u8() != 0
				stats.append(s)
			d["stats"] = stats
		Msg.ROSTER:
			var rcount := b.get_u8()
			var roster: Array[Dictionary] = []
			for _i in rcount:
				var e := {}
				e["id"] = b.get_32()
				e["name"] = _read_string(b)
				e["team"] = b.get_u8()
				e["is_bot"] = b.get_u8() != 0
				roster.append(e)
			d["entries"] = roster
		Msg.RESPAWN:
			d["round_start"] = (flags & RESPAWN_FLAG_ROUND_START) != 0
			d["id"] = b.get_32()
			d["x"] = b.get_float()
			d["y"] = b.get_float()
			d["z"] = b.get_float()
			d["yaw"] = b.get_float()
		Msg.CHAT:
			d["team_only"] = (flags & 1) != 0
			d["sys"] = (flags & 2) != 0
			d["id"] = b.get_32()
			d["name"] = _read_string(b)
			d["team"] = b.get_u8()
			d["text"] = _read_string(b)
		Msg.SPECIAL:
			d["by_id"] = b.get_32()
			d["team"] = b.get_u8()
			d["phase"] = b.get_u8()
			if d["phase"] == SpecialPhase.SP_FIRE:
				d["from_x"] = b.get_float()
				d["from_y"] = b.get_float()
				d["from_z"] = b.get_float()
				d["dir_x"] = b.get_float()
				d["dir_y"] = b.get_float()
				d["dir_z"] = b.get_float()
				d["hit_x"] = b.get_float()
				d["hit_y"] = b.get_float()
				d["hit_z"] = b.get_float()
				d["beam_len"] = b.get_float()
				d["blast_radius"] = b.get_float()
		Msg.SPECIAL_START:
			pass
		Msg.SPECIAL_FIRE:
			pass
		Msg.ANNOUNCE:
			d["first_blood"] = (flags & 1) != 0
			d["head"] = (flags & 2) != 0
			d["match_point"] = (flags & 4) != 0
			d["by_id"] = b.get_32()
			d["by_name"] = _read_string(b)
			d["by_team"] = b.get_u8()
			d["multi"] = b.get_u8()
			d["spree"] = b.get_u8()
			d["special_progress"] = b.get_u8()
		Msg.METEOR:
			d["x"] = b.get_float()
			d["y"] = b.get_float()
			d["z"] = b.get_float()
			d["lead_ms"] = b.get_u16()
			d["radius"] = b.get_float()
		Msg.LEAVE:
			pass
		Msg.SET_CHEATS:
			d["enabled"] = b.get_u8() != 0
			d["password"] = _read_string(b)
		Msg.CHEATS:
			d["enabled"] = b.get_u8() != 0
		Msg.SET_CHEATS_DENIED:
			pass
	return d


# ============================================================
#  Encode — each returns type(u8) + flags(u8) + payload bytes.
#  Wrap with frame_reliable / frame_unreliable before sending.
# ============================================================

static func encode_create_game(
		map_name: String, mode: String, rounds: int, kills: int,
		max_players: int, max_spectators: int, bots: bool,
		bots_shoot: bool, bots_move: bool, bot_skill: int,
		display_name: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.CREATE_GAME)
	b.put_u8(0)
	_write_string(b, map_name)
	_write_string(b, mode)
	b.put_u16(rounds)
	b.put_u16(kills)
	b.put_u8(max_players)
	b.put_u8(max_spectators)
	b.put_u8(1 if bots else 0)
	b.put_u8(1 if bots_shoot else 0)
	b.put_u8(1 if bots_move else 0)
	b.put_u8(bot_skill)
	_write_string(b, display_name)
	return b.data_array


# Sent by the server to every peer the moment it connects, before the peer
# has said anything. Carries the server's protocol version and the maps it
# can actually simulate, so a client can refuse a create or join it knows
# will desync instead of discovering it mid-match. Clients older than the
# HELLO message fall through their decode switch and ignore it.
static func encode_hello(maps: Array) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.HELLO)
	b.put_u8(0)
	b.put_u8(PROTOCOL_VERSION)
	b.put_u16(maps.size())
	for m in maps:
		_write_string(b, str(m))
	return b.data_array


static func encode_join_direct(callsign: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.JOIN_DIRECT)
	b.put_u8(0)
	b.put_u8(PROTOCOL_VERSION)
	_write_string(b, callsign)
	return b.data_array


static func encode_join_auth(callsign: String, token: Dictionary) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.JOIN_AUTH)
	b.put_u8(0)
	b.put_u8(PROTOCOL_VERSION)
	_write_string(b, callsign)
	_write_string(b, str(token.get("token_id", "")))
	_write_string(b, str(token.get("game_id", "")))
	b.put_64(int(token.get("expires_at", 0)))
	_write_string(b, str(token.get("signature", "")))
	return b.data_array


static func encode_join_error(reason: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.JOIN_ERROR)
	b.put_u8(0)
	_write_string(b, reason)
	return b.data_array


static func encode_init(
		id: int, team: String, map_name: String, mode: String,
		score_blue: int, score_red: int, round_num: int,
		win_rounds: int, kill_target: int, bots_shoot: bool,
		round_state: String, max_spectators: int = 0) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.INIT)
	b.put_u8(0)
	b.put_32(id)
	_write_string(b, team)
	_write_string(b, map_name)
	_write_string(b, mode)
	b.put_u16(score_blue)
	b.put_u16(score_red)
	b.put_u16(round_num)
	b.put_u16(win_rounds)
	b.put_u16(kill_target)
	b.put_u8(1 if bots_shoot else 0)
	_write_string(b, round_state)
	b.put_u8(max_spectators)
	return b.data_array


static func encode_state(
		x: float, y: float, z: float,
		yaw: float, pitch: float, crouched: bool, grounded: bool) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.STATE)
	var flags := 0
	if crouched:
		flags |= SFLG_CROUCHED
	if grounded:
		flags |= SFLG_GROUNDED
	b.put_u8(flags)
	b.put_float(x)
	b.put_float(y)
	b.put_float(z)
	b.put_float(yaw)
	b.put_float(pitch)
	return b.data_array


# clock_s is whatever the score bar should read, in seconds, already decided
# by the server: time left where there is a limit, time elapsed where there
# is not. clock_mode says which, so the client renders rather than rules on
# it. Both ride the snap because the clock has to survive a dropped packet.
static func encode_snap(
		score_blue: int, score_red: int, round_num: int,
		round_state: int, mode: int, kill_target: int, win_rounds: int,
		players: Array, clock_s: int = 0, clock_mode: int = CLOCK_UP) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SNAP)
	b.put_u8(0)
	b.put_u16(score_blue)
	b.put_u16(score_red)
	b.put_u16(round_num)
	b.put_u8(round_state)
	b.put_u8(mode)
	b.put_u16(kill_target)
	b.put_u16(win_rounds)
	b.put_u16(clampi(clock_s, 0, 65535))
	b.put_u8(clock_mode)
	b.put_u8(players.size())
	for p: Dictionary in players:
		b.put_32(p["id"])
		b.put_u8(p["flags"])
		b.put_float(p["x"])
		b.put_float(p["y"])
		b.put_float(p["z"])
		b.put_float(p["yaw"])
		b.put_float(p["pitch"])
		b.put_u8(p["hp"])
		b.put_u16(p["kills"])
		b.put_u16(p["deaths"])
		b.put_u8(p["team"])
		b.put_u16(p["ping"])
		b.put_u8(p.get("special_progress", 0))
	return b.data_array


static func encode_set_team(team: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SET_TEAM)
	b.put_u8(0)
	b.put_u8(team)
	return b.data_array


static func encode_team_menu() -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.TEAM_MENU)
	b.put_u8(0)
	return b.data_array


static func encode_team_opts(
		current_team: int, blue_used: int, blue_max: int,
		red_used: int, red_max: int, spec_used: int, spec_max: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.TEAM_OPTS)
	b.put_u8(0)
	b.put_u8(current_team)
	b.put_u8(blue_used)
	b.put_u8(blue_max)
	b.put_u8(red_used)
	b.put_u8(red_max)
	b.put_u8(spec_used)
	b.put_u8(spec_max)
	return b.data_array


static func encode_team(
		team: int, alive: bool,
		spawn_x: float, spawn_y: float, spawn_z: float,
		yaw: float) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.TEAM)
	b.put_u8(1 if alive else 0)
	b.put_u8(team)
	b.put_float(spawn_x)
	b.put_float(spawn_y)
	b.put_float(spawn_z)
	b.put_float(yaw)
	return b.data_array


static func encode_team_denied(reason: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.TEAM_DENIED)
	b.put_u8(0)
	_write_string(b, reason)
	return b.data_array


static func encode_shot(
		origin_x: float, origin_y: float, origin_z: float,
		dir_x: float, dir_y: float, dir_z: float,
		lag_ms: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SHOT)
	b.put_u8(0)
	b.put_float(origin_x)
	b.put_float(origin_y)
	b.put_float(origin_z)
	b.put_float(dir_x)
	b.put_float(dir_y)
	b.put_float(dir_z)
	b.put_u16(lag_ms)
	return b.data_array


static func encode_melee(lag_ms: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.MELEE)
	b.put_u8(0)
	b.put_u16(lag_ms)
	return b.data_array


static func encode_hit(
		target_id: int, by_id: int, hp: int,
		killed: bool, head: bool, cause: int,
		by_name: String, target_name: String,
		by_team: int, target_team: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.HIT)
	var flags := 0
	if killed:
		flags |= 1
	if head:
		flags |= 2
	b.put_u8(flags)
	b.put_32(target_id)
	b.put_32(by_id)
	b.put_u8(hp)
	b.put_u8(cause)
	_write_string(b, by_name)
	_write_string(b, target_name)
	b.put_u8(by_team)
	b.put_u8(target_team)
	return b.data_array


static func encode_tracer(
		by_id: int,
		origin_x: float, origin_y: float, origin_z: float,
		dir_x: float, dir_y: float, dir_z: float,
		team: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.TRACER)
	b.put_u8(0)
	b.put_32(by_id)
	b.put_float(origin_x)
	b.put_float(origin_y)
	b.put_float(origin_z)
	b.put_float(dir_x)
	b.put_float(dir_y)
	b.put_float(dir_z)
	b.put_u8(team)
	return b.data_array


static func encode_round_start(
		score_blue: int, score_red: int, round_num: int) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.ROUND_START)
	b.put_u8(0)
	b.put_u16(score_blue)
	b.put_u16(score_red)
	b.put_u16(round_num)
	return b.data_array


# winner may be TEAM_NONE, which is a draw: nobody scores and the round
# still advances. A clock can run out with both sides even, or with both
# wiped out in the same instant.
static func encode_round_end(
		winner: int, score_blue: int, score_red: int,
		match_over: bool, match_point: bool, round_num: int,
		reason: int = END_ELIMINATION) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.ROUND_END)
	var flags := 0
	if match_over:
		flags |= 1
	if match_point:
		flags |= 2
	b.put_u8(flags)
	b.put_u8(winner)
	b.put_u16(score_blue)
	b.put_u16(score_red)
	b.put_u16(round_num)
	b.put_u8(reason)
	return b.data_array


static func encode_match_over(
		winner: int, score_blue: int, score_red: int, stats: Array) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.MATCH_OVER)
	b.put_u8(0)
	b.put_u8(winner)
	b.put_u16(score_blue)
	b.put_u16(score_red)
	b.put_u8(stats.size())
	for s: Dictionary in stats:
		b.put_32(s["id"])
		_write_string(b, s["name"])
		b.put_u8(s["team"])
		b.put_u16(s["kills"])
		b.put_u16(s["deaths"])
		b.put_u8(1 if s["is_bot"] else 0)
	return b.data_array


## Names change rarely, so the roster is pushed on membership changes rather
## than riding along in every snapshot.
static func encode_roster(entries: Array) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.ROSTER)
	b.put_u8(0)
	b.put_u8(entries.size())
	for e: Dictionary in entries:
		b.put_32(e["id"])
		_write_string(b, e["name"])
		b.put_u8(e["team"])
		b.put_u8(1 if e["is_bot"] else 0)
	return b.data_array


const RESPAWN_FLAG_ROUND_START := 1

static func encode_respawn(
		id: int, x: float, y: float, z: float, yaw: float,
		round_start: bool = false) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.RESPAWN)
	b.put_u8(RESPAWN_FLAG_ROUND_START if round_start else 0)
	b.put_32(id)
	b.put_float(x)
	b.put_float(y)
	b.put_float(z)
	b.put_float(yaw)
	return b.data_array


static func encode_chat(
		id: int, p_name: String, team: int, text: String,
		team_only: bool, sys: bool) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.CHAT)
	var flags := 0
	if team_only:
		flags |= 1
	if sys:
		flags |= 2
	b.put_u8(flags)
	b.put_32(id)
	_write_string(b, p_name)
	b.put_u8(team)
	_write_string(b, text)
	return b.data_array


static func encode_special(
		by_id: int, team: int, phase: int,
		from: Vector3 = Vector3.ZERO, dir: Vector3 = Vector3.ZERO,
		hit: Vector3 = Vector3.ZERO, beam_len: float = 0.0,
		blast_radius: float = 0.0) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SPECIAL)
	b.put_u8(0)
	b.put_32(by_id)
	b.put_u8(team)
	b.put_u8(phase)
	if phase == SpecialPhase.SP_FIRE:
		b.put_float(from.x)
		b.put_float(from.y)
		b.put_float(from.z)
		b.put_float(dir.x)
		b.put_float(dir.y)
		b.put_float(dir.z)
		b.put_float(hit.x)
		b.put_float(hit.y)
		b.put_float(hit.z)
		b.put_float(beam_len)
		b.put_float(blast_radius)
	return b.data_array


static func encode_special_start() -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SPECIAL_START)
	b.put_u8(0)
	return b.data_array


static func encode_special_fire() -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SPECIAL_FIRE)
	b.put_u8(0)
	return b.data_array


static func encode_announce(
		by_id: int, by_name: String, by_team: int,
		multi: int, spree: int, first_blood: bool,
		head: bool, match_point: bool, special_progress: int = 0) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.ANNOUNCE)
	var flags := 0
	if first_blood:
		flags |= 1
	if head:
		flags |= 2
	if match_point:
		flags |= 4
	b.put_u8(flags)
	b.put_32(by_id)
	_write_string(b, by_name)
	b.put_u8(by_team)
	b.put_u8(multi)
	b.put_u8(spree)
	b.put_u8(special_progress)
	return b.data_array


static func encode_meteor(
		x: float, y: float, z: float,
		lead_ms: int, radius: float) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.METEOR)
	b.put_u8(0)
	b.put_float(x)
	b.put_float(y)
	b.put_float(z)
	b.put_u16(lead_ms)
	b.put_float(radius)
	return b.data_array


static func encode_leave() -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.LEAVE)
	b.put_u8(0)
	return b.data_array


static func encode_set_cheats(enabled: bool, password: String) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SET_CHEATS)
	b.put_u8(0)
	b.put_u8(1 if enabled else 0)
	_write_string(b, password)
	return b.data_array


static func encode_cheats(enabled: bool) -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.CHEATS)
	b.put_u8(0)
	b.put_u8(1 if enabled else 0)
	return b.data_array


static func encode_set_cheats_denied() -> PackedByteArray:
	var b := _buf()
	b.put_u8(Msg.SET_CHEATS_DENIED)
	b.put_u8(0)
	return b.data_array
