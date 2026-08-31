class_name MgmtServer
extends Node

## Private JSON-lines TCP surface the Game API uses to create and validate
## lobbies. Godot has no built-in HTTP server, so the wire is one JSON object
## per line.
##
## Every command must carry a signature that verifies against the API public key
## received during registration, so reaching this port is not enough to drive
## the server. Until a handshake completes there is no key and all commands are
## refused.

signal lobby_created(inst: GameInstance)

var port: int = 9090
var allow_dynamic_create: bool = false

## Set from ApiRegistrar once the handshake completes.
var api_public_key_pem: String = ""

## Commands whose timestamp drifts further than this are refused as replays.
const MAX_CLOCK_SKEW_S := 60
const READ_TIMEOUT_MS := 500

var _tcp: TCPServer
var _registry: GameRegistry
var _game_server: Node
var _last_command_at: int = 0


func configure(registry: GameRegistry, game_server: Node) -> void:
	_registry = registry
	_game_server = game_server


func set_api_public_key(pem: String) -> void:
	api_public_key_pem = pem
	print("[mgmt] API public key installed; management commands now accepted")


func _ready() -> void:
	_tcp = TCPServer.new()
	var err := _tcp.listen(port, "127.0.0.1")
	if err != OK:
		push_error("[mgmt] listen failed on port %d: %s" % [port, error_string(err)])
		return
	print("[mgmt] listening on 127.0.0.1:%d" % port)


func _process(_dt: float) -> void:
	if _tcp == null or not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if peer:
			_handle_connection(peer)


func _handle_connection(peer: StreamPeerTCP) -> void:
	var line := _read_line(peer)
	if line.is_empty():
		_respond(peer, {"error": "empty request"})
		return

	var envelope := _parse_json(line)
	if envelope.is_empty():
		_respond(peer, {"error": "invalid envelope JSON"})
		return

	if api_public_key_pem.is_empty():
		_respond(peer, {"error": "server has not completed an API handshake"})
		return

	var body_b64 := str(envelope.get("body", ""))
	var signature := str(envelope.get("sig", ""))
	if body_b64.is_empty() or signature.is_empty():
		_respond(peer, {"error": "envelope missing body or signature"})
		return

	var body_bytes := Marshalls.base64_to_raw(body_b64)
	if body_bytes.is_empty():
		_respond(peer, {"error": "envelope body was not valid base64"})
		return

	if not ServerIdentity.verify_with_pem(api_public_key_pem, body_bytes, signature):
		push_warning("[mgmt] rejected command with bad signature")
		_respond(peer, {"error": "signature verification failed"})
		return

	var msg := _parse_json(body_bytes.get_string_from_utf8())
	if msg.is_empty():
		_respond(peer, {"error": "invalid command JSON"})
		return

	var timestamp := int(msg.get("timestamp", 0))
	if not _timestamp_fresh(timestamp):
		_respond(peer, {"error": "stale or replayed command"})
		return
	_last_command_at = timestamp

	match str(msg.get("op", "")):
		"create_game":
			_handle_create(peer, msg)
		"join_game":
			_handle_join(peer, msg)
		"destroy_game":
			_handle_destroy(peer, msg)
		_:
			_respond(peer, {"error": "unknown op"})


func _handle_create(peer: StreamPeerTCP, msg: Dictionary) -> void:
	if not allow_dynamic_create:
		_respond(peer, {"error": "this server does not accept lobby creation"})
		return

	var cfg := {
		"map_id": str(msg.get("map", "parkour")),
		"mode": str(msg.get("mode", "classic")),
		"rounds": int(msg.get("rounds", 10)),
		"kills": int(msg.get("kills", 50)),
		"max_players": int(msg.get("max_players", 12)),
		"max_spectators": int(msg.get("max_spectators", 12)),
		"bots": bool(msg.get("bots", true)),
		"bots_shoot": bool(msg.get("bots_shoot", true)),
		"bots_move": bool(msg.get("bots_move", true)),
		"display_name": str(msg.get("display_name", "")),
	}

	var inst := _registry.create(cfg)
	if inst == null:
		_respond(peer, {"error": "lobby limit reached"})
		return

	_game_server.add_child(inst)
	inst.setup_map()
	lobby_created.emit(inst)
	print("[mgmt] created lobby '%s' (mode=%s)" % [inst.game_id, cfg["mode"]])
	_respond(peer, {"game_id": inst.game_id})


func _handle_join(peer: StreamPeerTCP, msg: Dictionary) -> void:
	var game_id := str(msg.get("game_id", ""))
	if game_id.is_empty():
		_respond(peer, {"error": "game_id required"})
		return
	if not _registry.instances.has(game_id):
		_respond(peer, {"ok": false, "reason": "Game no longer exists."})
		return

	var inst: GameInstance = _registry.instances[game_id]
	var humans := 0
	for p: Participant in inst.participants.values():
		if not p.is_bot:
			humans += 1

	if humans >= inst.max_players + inst.max_spectators:
		_respond(peer, {"ok": false, "reason": "Lobby is full."})
		return

	_respond(peer, {"ok": true})


func _handle_destroy(peer: StreamPeerTCP, msg: Dictionary) -> void:
	var game_id := str(msg.get("game_id", ""))
	if game_id.is_empty():
		_respond(peer, {"error": "game_id required"})
		return
	if not _registry.instances.has(game_id):
		_respond(peer, {"error": "game not found"})
		return

	var inst: GameInstance = _registry.instances[game_id]
	_registry.remove_instance(game_id)
	inst.queue_free()
	print("[mgmt] destroyed lobby '%s'" % game_id)
	_respond(peer, {"ok": true})


func _timestamp_fresh(timestamp: int) -> bool:
	if timestamp <= 0:
		return false
	var now := int(Time.get_unix_time_from_system())
	if absi(now - timestamp) > MAX_CLOCK_SKEW_S:
		return false
	return timestamp > _last_command_at


func _read_line(peer: StreamPeerTCP) -> String:
	var deadline := Time.get_ticks_msec() + READ_TIMEOUT_MS
	var buffer := PackedByteArray()

	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := peer.get_available_bytes()
		if available > 0:
			buffer.append_array(peer.get_data(available)[1])
			if buffer.has(10):  # newline terminates the command
				break
		else:
			OS.delay_msec(5)

	return buffer.get_string_from_utf8().strip_edges()


func _parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func _respond(peer: StreamPeerTCP, data: Dictionary) -> void:
	peer.put_data((JSON.stringify(data) + "\n").to_utf8_buffer())
	peer.poll()
	peer.disconnect_from_host()
