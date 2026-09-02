class_name Participant
extends RefCounted

## Match-lifetime identity. Survives death and round boundaries.
## Streak does NOT reset on spawn (laser-arena bug was fixed).

var id: int
var display_name: String
var team: int = 0
var kills: int = 0
var deaths: int = 0
var streak: int = 0
var special_progress: int = 0
var multi: int = 0
var last_kill_at: float = 0.0
var is_bot: bool = false
## Daemon possession: a dead human rides this bot (`possessed_by`), and that
## human's `possessing` points back at the bot. Kills stay on the bot's row.
var possessing: int = 0
var possessed_by: int = 0
var special_armed: bool = false
var special_at: float = 0.0
var special_release: bool = false
var ping_ms: int = 0
var connection_session: Dictionary = {}

## Bots never leave the server, so they report a token loopback latency rather
## than 0 — a flat zero column reads as "missing data" on the scoreboard.
const BOT_PING_MS := 12


func _init(p_id: int, p_name: String, p_is_bot: bool = false) -> void:
	id = p_id
	display_name = p_name
	is_bot = p_is_bot
	if p_is_bot:
		ping_ms = BOT_PING_MS
