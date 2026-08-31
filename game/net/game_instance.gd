class_name GameInstance
extends RefCounted

# One lobby.  Owns metadata + participants.  No Match object this slice.

var game_id: String
var display_name: String
var map_id: String
var mode: String
var max_players: int
var max_spectators: int
var colliders: Array[AABB] = []
var spawns: Dictionary = {}

# peer_id → participant dict
var participants: Dictionary = {}


func _init(cfg: Dictionary) -> void:
	game_id = cfg.get("game_id", _gen_id())
	display_name = cfg.get("display_name", "")
	map_id = cfg.get("map_id", "parkour")
	mode = cfg.get("mode", "classic")
	max_players = cfg.get("max_players", 12)
	max_spectators = cfg.get("max_spectators", 12)

	var map_def: Dictionary
	if map_id == "parkour":
		map_def = ParkourMap.definition()
	else:
		map_def = ParkourMap.definition()

	var compiled := MapEngine.compile(map_def)
	colliders = MapBuilder.build_colliders(compiled)
	spawns = compiled.get("spawns", {})


func admit(peer_id: int, callsign: String) -> Dictionary:
	if participants.size() >= max_players + max_spectators:
		return {"ok": false, "reason": "Lobby is full."}

	var spawn_list: Array = spawns.get("blue", [[0, 0]])
	var pick: Array = spawn_list[randi() % spawn_list.size()]
	var sx: float = pick[0] + (randf() - 0.5) * 1.4
	var sz: float = pick[1] + (randf() - 0.5) * 1.4
	var spawn_pos := Vector3(sx, 0.0, sz)
	# Blue spawns face center (yaw 180); matches server.js spawn logic.
	var yaw := 180.0

	participants[peer_id] = {
		"id": peer_id,
		"name": callsign,
		"team": "blue",
		"x": spawn_pos.x, "y": spawn_pos.y, "z": spawn_pos.z,
		"yaw": yaw, "pitch": 0.0,
		"alive": true,
	}
	return {"ok": true, "spawn": spawn_pos, "yaw": yaw}


func update_state(peer_id: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if not participants.has(peer_id):
		return
	var p: Dictionary = participants[peer_id]
	p["x"] = pos.x
	p["y"] = pos.y
	p["z"] = pos.z
	p["yaw"] = yaw
	p["pitch"] = pitch


func remove(peer_id: int) -> void:
	participants.erase(peer_id)


func build_snap() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pid: int in participants:
		var p: Dictionary = participants[pid]
		out.append(p.duplicate())
	return out


static func _gen_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var out := ""
	for i in 8:
		out += chars[randi() % chars.length()]
	return out
