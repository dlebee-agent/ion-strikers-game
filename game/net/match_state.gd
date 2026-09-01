class_name MatchState
extends RefCounted

const ROUND_END_DELAY := 3.5
const DM_RESPAWN_MS := 5000.0

## How long an arena round runs before it is decided on who is left
## standing. Deathmatch has no round clock: everyone respawns there, so a
## round that could only ever end on a timer is just the match itself.
const ROUND_TIME_S := 120.0
## Ceiling on a whole deathmatch, so a lobby that never reaches the kill
## target still finishes. Zero runs it uncapped.
const DM_TIME_S := 600.0
const PREP_TIME_MS := 2200.0
const SPECIAL_STREAK := 5
const MULTI_WINDOW := 4.0

const METEOR_MIN_S := 30.0
const METEOR_MAX_S := 120.0
const METEOR_END_MIN_S := 6.0
const METEOR_END_MAX_S := 18.0
const METEOR_LEAD_S := 2.6
const METEOR_RADIUS := 5.0
const METEOR_VERT := 3.5

var match_id: String
var mode: String = "arena"
var win_rounds: int = 10
var kill_target: int = 50
var score_blue: int = 0
var score_red: int = 0
var round_num: int = 1
var round_state: int = 0
var winner: int = 0
var first_blood_done: bool = false
var match_point_announced: bool = false

var round_end_at: float = 0.0

## Instance clock the running round expires on, and the same for a whole
## deathmatch. Zero arms on the next tick.
var round_ends_at: float = 0.0
var match_ends_at: float = 0.0
## Whether each side has had anyone on it at any point this round. A side
## that emptied out forfeits; a side nobody ever joined is just a lobby
## short of players, and handing its rounds to whoever did join would have
## a solo host winning the match by themselves.
var round_had_blue: bool = false
var round_had_red: bool = false

var pending_meteor: Dictionary = {}
var next_meteor_at: float = 0.0


func _init() -> void:
	match_id = _gen_id()


static func _gen_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := ""
	for i in 8:
		out += chars[randi() % chars.length()]
	return out


func meteor_progress() -> float:
	if mode != "dm":
		return 0.0
	var lead := maxi(score_red, score_blue)
	return clampf(float(lead) / float(kill_target), 0.0, 1.0)


func meteor_delay() -> float:
	var t := meteor_progress() ** 2
	var lo := METEOR_MIN_S + (METEOR_END_MIN_S - METEOR_MIN_S) * t
	var hi := METEOR_MAX_S + (METEOR_END_MAX_S - METEOR_MAX_S) * t
	return lo + randf() * (hi - lo)
