class_name ApiRegistrar
extends Node

## Registers this server with a Game API and heartbeats its lobby list.
##
## Registration is a key exchange: we send our public key, the API replies with
## a public key minted for this registration. From then on our heartbeats are
## signed, and management commands are only honoured if they verify against the
## API key we were given here (see MgmtServer).

signal api_key_received(api_public_key_pem: String)

var api_url: String = ""
var identity: ServerIdentity = null
var endpoint: String = ""
var mgmt_endpoint: String = ""
var allow_dynamic_create: bool = false
var build_version: String = "1.0.0"
var protocol_version: int = 1
var dev_mode: bool = false
var max_peers: int = 2048
var max_lobbies: int = 1

const HEARTBEAT_INTERVAL := 10.0
const REGISTER_RETRY_DELAY := 5.0

var _register_http: HTTPRequest
var _heartbeat_http: HTTPRequest
var _registered: bool = false
var _heartbeat_timer: float = 0.0
var _registry: GameRegistry


func configure(registry: GameRegistry) -> void:
	_registry = registry


func _ready() -> void:
	if api_url.is_empty():
		push_warning("[registrar] no --api-url, registration disabled")
		set_process(false)
		return
	if identity == null or identity.key == null:
		push_error("[registrar] no server identity, registration disabled")
		set_process(false)
		return

	_register_http = HTTPRequest.new()
	_register_http.name = "RegisterHTTP"
	add_child(_register_http)
	_register_http.request_completed.connect(_on_register_done)

	_heartbeat_http = HTTPRequest.new()
	_heartbeat_http.name = "HeartbeatHTTP"
	add_child(_heartbeat_http)
	_heartbeat_http.request_completed.connect(_on_heartbeat_done)

	_do_register()


func _process(dt: float) -> void:
	if not _registered:
		return
	_heartbeat_timer += dt
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_do_heartbeat()


func push_now() -> void:
	if _registered:
		_do_heartbeat()


func _do_register() -> void:
	var body := JSON.stringify({
		"server_id": identity.server_id,
		"endpoint": endpoint,
		"mgmt_endpoint": mgmt_endpoint,
		"build_version": build_version,
		"protocol_version": protocol_version,
		"max_peers": max_peers,
		"max_lobbies": max_lobbies,
		"active_peers": 0,
		"active_lobbies": 0,
		"allow_dynamic_create": allow_dynamic_create,
		"dev_mode": dev_mode,
		"server_public_key_pem": identity.public_key_pem(),
	})

	var err := _register_http.request(api_url + "/v1/internal/register",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("[registrar] register request failed: %s" % error_string(err))
		_retry_register()


func _on_register_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("[registrar] could not reach %s (result %d)" % [api_url, result])
		_retry_register()
		return
	if code != 200:
		push_error("[registrar] registration rejected (HTTP %d): %s" % [code, body.get_string_from_utf8()])
		_retry_register()
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[registrar] registration response was not JSON")
		_retry_register()
		return

	var data: Dictionary = json.data
	var api_pem: String = str(data.get("api_public_key_pem", ""))
	if api_pem.is_empty():
		push_error("[registrar] registration response carried no API public key")
		_retry_register()
		return

	_registered = true
	api_key_received.emit(api_pem)
	print("[registrar] registered with %s as '%s' (create=%s)" % [
		api_url, identity.server_id, allow_dynamic_create])

	# Publish the current lobby list immediately rather than after a full interval.
	_do_heartbeat()


func _retry_register() -> void:
	await get_tree().create_timer(REGISTER_RETRY_DELAY).timeout
	if is_inside_tree():
		_do_register()


func _do_heartbeat() -> void:
	if _registry == null:
		return

	var games: Array = []
	var active_peers := 0

	for gid: String in _registry.instances:
		var inst: GameInstance = _registry.instances[gid]
		if inst.map_id.is_empty():
			continue
		var humans := 0
		var spectators := 0
		for p: Participant in inst.participants.values():
			if p.is_bot:
				continue
			humans += 1
			if p.team == Protocol.TEAM_NONE:
				spectators += 1
		active_peers += humans

		games.append({
			"game_id": inst.game_id,
			"server_id": identity.server_id,
			"display_name": inst.display_name,
			"mode": inst.mode,
			"map_id": inst.map_id,
			"players": inst.participants.size(),
			"humans": humans,
			"max": inst.max_players,
			"spectators": spectators,
			"spec_max": inst.max_spectators,
			"capacity": inst.max_players + inst.max_spectators,
			"blue": inst.match_state.score_blue if inst.match_state else 0,
			"red": inst.match_state.score_red if inst.match_state else 0,
			"round": inst.match_state.round_num if inst.match_state else 0,
			"bots_shoot": inst.bots_shoot,
			"lifecycle_state": _lifecycle_str(inst),
		})

	# The signature covers these exact bytes, so send the same string we signed.
	var body := JSON.stringify({
		"server_id": identity.server_id,
		"timestamp": int(Time.get_unix_time_from_system()),
		"active_peers": active_peers,
		"active_lobbies": _registry.instances.size(),
		"games": games,
	})

	var signature := identity.sign(body.to_utf8_buffer())
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Signature: " + signature,
	])
	_heartbeat_http.request(api_url + "/v1/internal/heartbeat",
		headers, HTTPClient.METHOD_POST, body)


func _on_heartbeat_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 401:
		# The API no longer recognises us — most likely it restarted with an
		# empty registry. Re-run the handshake to get a fresh key pair.
		push_warning("[registrar] heartbeat unauthorized, re-registering")
		_registered = false
		_do_register()
	elif code != 200:
		push_warning("[registrar] heartbeat failed (HTTP %d): %s" % [code, body.get_string_from_utf8()])


static func _lifecycle_str(inst: GameInstance) -> String:
	if inst.match_state == null:
		return "waiting"
	match inst.match_state.round_state:
		Protocol.RS_ACTIVE:
			return "active"
		Protocol.RS_ENDED:
			return "ended"
		Protocol.RS_OVER:
			return "over"
	return "waiting"
