extends Node

var _host: ENetConnection
var _registry: GameRegistry
var _port: int = 7777

# peer_id → { enet_peer, game_instance, authed }
var _sessions: Dictionary = {}

const SNAP_INTERVAL := 1.0 / 30.0
var _snap_timer: float = 0.0

const TICK_RATE := 1.0 / 60.0
var _tick_timer: float = 0.0

# A locally spawned server must not outlive the client that launched it,
# otherwise orphans keep the UDP port bound and answer future connections.
var _parent_pid: int = -1
const PARENT_CHECK_INTERVAL := 1.0
var _parent_check_timer: float = 0.0

var _admin_password_hash: PackedByteArray = []
var _ip_fail_counts: Dictionary = {}   # ip_str → int (total failures)
var _ip_lockout_until: Dictionary = {}  # ip_str → float (msec)
var _ip_banned: Dictionary = {}         # ip_str → true
const AUTH_LOCKOUT_THRESHOLD := 5
const AUTH_LOCKOUT_DURATION_MS := 30000.0
const AUTH_BAN_THRESHOLD := 10


var _max_lobbies: int = 1
var _join_secret: String = ""
var _allow_direct_join: bool = true
var _allow_enet_create: bool = true


func configure(port: int, parent_pid: int = -1, admin_password: String = "") -> void:
	_port = port
	_parent_pid = parent_pid
	if not admin_password.is_empty():
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(admin_password.to_utf8_buffer())
		_admin_password_hash = ctx.finish()


## Must be called before _ready; the registry is built there.
func set_max_lobbies(count: int) -> void:
	_max_lobbies = maxi(count, 1)


func set_join_secret(secret: String) -> void:
	_join_secret = secret


## Managed servers only accept JoinAuth; lobby create goes through the Game API.
func set_managed_admission() -> void:
	_allow_direct_join = false
	_allow_enet_create = false


## Built on first use so collaborators wired up before the node enters the
## tree (the management server, the registrar) share the same instance.
func get_registry() -> GameRegistry:
	if _registry == null:
		_registry = GameRegistry.new()
		_registry.max_lobbies = _max_lobbies
	return _registry


## Adopts a lobby created outside the ENet path (i.e. by the Game API).
func attach_instance(inst: GameInstance) -> void:
	_connect_instance(inst)


func _ready() -> void:
	get_registry()

	_host = ENetConnection.new()
	var err := _host.create_host_bound("0.0.0.0", _port, 32, Protocol.MAX_CHANNELS)
	if err != OK:
		push_error("ENet bind failed on port %d: %s" % [_port, error_string(err)])
		get_tree().quit(1)
		return

	print("[server] listening on 0.0.0.0:%d (empty registry)" % _port)


func _process(dt: float) -> void:
	if _host == null:
		return

	if _parent_pid > 0:
		_parent_check_timer += dt
		if _parent_check_timer >= PARENT_CHECK_INTERVAL:
			_parent_check_timer = 0.0
			if not OS.is_process_running(_parent_pid):
				print("[server] parent %d gone, shutting down" % _parent_pid)
				get_tree().quit()
				return

	_poll_enet()

	_tick_timer += dt
	while _tick_timer >= TICK_RATE:
		_tick_timer -= TICK_RATE
		_tick_instances(TICK_RATE)

	_snap_timer += dt
	if _snap_timer >= SNAP_INTERVAL:
		_snap_timer -= SNAP_INTERVAL
		_broadcast_snaps()


func _tick_instances(dt: float) -> void:
	for gid: String in _registry.instances:
		var inst: GameInstance = _registry.instances[gid]
		inst.tick(dt)


func _poll_enet() -> void:
	while true:
		var ev := _host.service(0)
		var event_type: int = ev[0]
		if event_type == ENetConnection.EVENT_NONE:
			break
		var peer: ENetPacketPeer = ev[1]
		var peer_id := _peer_id(peer)

		if event_type == ENetConnection.EVENT_CONNECT:
			var ip := peer.get_remote_address()
			if _ip_banned.has(ip):
				peer.peer_disconnect_now(0)
				print("[server] banned IP %s attempted reconnect" % ip)
				continue
			_sessions[peer_id] = {"peer": peer, "instance": null, "authed": false}
			print("[server] peer %d connected" % peer_id)

		elif event_type == ENetConnection.EVENT_DISCONNECT:
			_on_disconnect(peer_id)

		elif event_type == ENetConnection.EVENT_RECEIVE:
			var data: PackedByteArray = peer.get_packet()
			var channel: int = ev[3]
			_on_receive(peer_id, channel, data)


func _on_receive(peer_id: int, channel: int, data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	if msg.is_empty():
		return

	var t: int = int(msg.get("t", -1))

	if channel == Protocol.CH_UNRELIABLE:
		if t == Protocol.Msg.STATE:
			_handle_state(peer_id, msg)

	elif channel == Protocol.CH_HANDSHAKE:
		match t:
			Protocol.Msg.CREATE_GAME:
				_handle_create_game(peer_id, msg)
			Protocol.Msg.JOIN_DIRECT:
				_handle_join_direct(peer_id, msg)
			Protocol.Msg.JOIN_AUTH:
				_handle_join_auth(peer_id, msg)
			Protocol.Msg.SET_TEAM:
				_handle_set_team(peer_id, msg)
			Protocol.Msg.TEAM_MENU:
				_handle_team_menu(peer_id)
			Protocol.Msg.SHOT:
				_handle_shot(peer_id, msg)
			Protocol.Msg.MELEE:
				_handle_melee(peer_id, msg)
			Protocol.Msg.SPECIAL_START:
				_handle_special_start(peer_id)
			Protocol.Msg.SPECIAL_FIRE:
				_handle_special_fire(peer_id)
			Protocol.Msg.LEAVE:
				_on_disconnect(peer_id)
			Protocol.Msg.SET_CHEATS:
				_handle_set_cheats(peer_id, msg)

	elif channel == Protocol.CH_EVENTS:
		if t == Protocol.Msg.CHAT:
			_handle_chat(peer_id, msg)


func _handle_create_game(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
		return
	if not _allow_enet_create:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("Create via the Game API."))
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
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("Cannot create lobby (limit reached)."))
		return

	add_child(inst)
	inst.setup_map()
	_connect_instance(inst)
	print("[server] lobby '%s' created by peer %d (mode=%s)" % [inst.game_id, peer_id, cfg["mode"]])


func _handle_join_direct(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	if session["authed"]:
		return
	if not _allow_direct_join:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("This server requires a join token."))
		return

	var version: int = int(msg.get("v", 0))
	if version != Protocol.PROTOCOL_VERSION:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("Protocol version mismatch."))
		return

	var inst := _registry.resolve_join_direct()
	if inst == null:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("No lobby available."))
		return

	_admit(peer_id, inst, str(msg.get("name", "Player")))


func _handle_join_auth(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	if session["authed"]:
		return

	var version: int = int(msg.get("v", 0))
	if version != Protocol.PROTOCOL_VERSION:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("Protocol version mismatch."))
		return

	if not _verify_join_token(
			str(msg.get("token_id", "")),
			str(msg.get("game_id", "")),
			int(msg.get("expires_at", 0)),
			str(msg.get("signature", ""))):
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("Invalid or expired join token."))
		return

	var game_id := str(msg.get("game_id", ""))
	if not _registry.instances.has(game_id):
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error("Game no longer exists."))
		return

	_admit(peer_id, _registry.instances[game_id], str(msg.get("name", "Player")))


func _admit(peer_id: int, inst: GameInstance, callsign: String) -> void:
	var session: Dictionary = _sessions[peer_id]
	var result := inst.admit_spectator(peer_id, callsign)
	if not result["ok"]:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error(str(result["reason"])))
		return

	session["instance"] = inst
	session["authed"] = true

	_send(peer_id, Protocol.CH_HANDSHAKE, result["init"])
	if result.get("cheats", false):
		_send(peer_id, Protocol.CH_EVENTS, Protocol.encode_cheats(true))
	print("[server] peer %d joined as '%s' (stands)" % [peer_id, callsign])


func _verify_join_token(token_id: String, game_id: String, expires_at: int, signature: String) -> bool:
	if _join_secret.is_empty() or token_id.is_empty() or game_id.is_empty() or signature.is_empty():
		return false
	if int(Time.get_unix_time_from_system()) > expires_at:
		return false
	var payload := "%s:%s:%d" % [token_id, game_id, expires_at]
	var ctx := HMACContext.new()
	if ctx.start(HashingContext.HASH_SHA256, _join_secret.to_utf8_buffer()) != OK:
		return false
	if ctx.update(payload.to_utf8_buffer()) != OK:
		return false
	return ctx.finish().hex_encode() == signature.to_lower()


func _handle_state(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	if not session["authed"]:
		return
	var inst: GameInstance = session["instance"]
	if inst == null:
		return
	inst.update_state(peer_id,
		Vector3(float(msg.get("x", 0.0)), float(msg.get("y", 0.0)), float(msg.get("z", 0.0))),
		float(msg.get("yaw", 0.0)), float(msg.get("pitch", 0.0)),
		bool(msg.get("crouched", false)))


func _handle_set_team(peer_id: int, msg: Dictionary) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	inst.handle_set_team(peer_id, int(msg.get("team", 0)))


func _handle_team_menu(peer_id: int) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	inst.handle_team_menu(peer_id)


func _handle_shot(peer_id: int, msg: Dictionary) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	var origin := Vector3(float(msg.get("origin_x", 0.0)), float(msg.get("origin_y", 0.0)), float(msg.get("origin_z", 0.0)))
	var dir := Vector3(float(msg.get("dir_x", 0.0)), float(msg.get("dir_y", 0.0)), float(msg.get("dir_z", 0.0)))
	inst.handle_shot(peer_id, origin, dir, int(msg.get("lag_ms", 0)))


func _handle_melee(peer_id: int, msg: Dictionary) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	inst.handle_melee(peer_id, int(msg.get("lag_ms", 0)))


func _handle_special_start(peer_id: int) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	inst.handle_special_start(peer_id)


func _handle_special_fire(peer_id: int) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	inst.handle_special_fire(peer_id)


func _handle_chat(peer_id: int, msg: Dictionary) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	inst.handle_chat(peer_id, str(msg.get("text", "")), bool(msg.get("team_only", false)))


func _handle_set_cheats(peer_id: int, msg: Dictionary) -> void:
	var inst := _get_instance(peer_id)
	if inst == null:
		return
	if _admin_password_hash.is_empty():
		_send(peer_id, Protocol.CH_HANDSHAKE, Protocol.encode_set_cheats_denied())
		return

	var peer: ENetPacketPeer = _sessions[peer_id]["peer"]
	var ip := peer.get_remote_address()

	if _ip_banned.has(ip):
		peer.peer_disconnect_now(0)
		return

	var now_ms := Time.get_ticks_msec() as float
	if _ip_lockout_until.has(ip) and now_ms < _ip_lockout_until[ip]:
		_send(peer_id, Protocol.CH_HANDSHAKE, Protocol.encode_set_cheats_denied())
		return

	var submitted: String = str(msg.get("password", ""))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(submitted.to_utf8_buffer())
	var submitted_hash := ctx.finish()

	if submitted_hash != _admin_password_hash:
		if not _ip_fail_counts.has(ip):
			_ip_fail_counts[ip] = 0
		_ip_fail_counts[ip] += 1
		var fails: int = _ip_fail_counts[ip]
		print("[server] bad admin password from %s (attempt %d)" % [ip, fails])

		if fails >= AUTH_BAN_THRESHOLD:
			_ip_banned[ip] = true
			print("[server] IP %s banned after %d failed admin attempts" % [ip, fails])
			peer.peer_disconnect_now(0)
			return
		elif fails >= AUTH_LOCKOUT_THRESHOLD:
			_ip_lockout_until[ip] = now_ms + AUTH_LOCKOUT_DURATION_MS

		_send(peer_id, Protocol.CH_HANDSHAKE, Protocol.encode_set_cheats_denied())
		return

	var enabled: bool = bool(msg.get("enabled", false))
	inst.handle_set_cheats(enabled)


func _on_disconnect(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	var inst: GameInstance = session.get("instance")
	if inst:
		inst.remove(peer_id)
	_sessions.erase(peer_id)
	print("[server] peer %d disconnected" % peer_id)


func _broadcast_snaps() -> void:
	for gid: String in _registry.instances:
		var inst: GameInstance = _registry.instances[gid]
		_refresh_pings(inst)
		var snap := inst.build_snap()
		for pid: int in inst.participants:
			var p: Participant = inst.participants[pid]
			if p.is_bot:
				continue
			_send_raw(pid, Protocol.CH_UNRELIABLE, snap)


func _refresh_pings(inst: GameInstance) -> void:
	for pid: int in inst.participants:
		var p: Participant = inst.participants[pid]
		if p.is_bot or not _sessions.has(pid):
			continue
		var peer: ENetPacketPeer = _sessions[pid]["peer"]
		p.ping_ms = mini(int(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)), 999)


func _connect_instance(inst: GameInstance) -> void:
	inst.event_to_peer.connect(_on_instance_event_to_peer)
	inst.event_broadcast.connect(_on_instance_broadcast.bind(inst))
	inst.event_team_broadcast.connect(_on_instance_team_broadcast.bind(inst))


func _on_instance_event_to_peer(peer_id: int, channel: int, data: PackedByteArray) -> void:
	_send_raw(peer_id, channel, data)


func _on_instance_broadcast(channel: int, data: PackedByteArray, exclude_id: int, inst: GameInstance) -> void:
	for pid: int in inst.participants:
		if pid == exclude_id:
			continue
		var p: Participant = inst.participants[pid]
		if p.is_bot:
			continue
		_send_raw(pid, channel, data)


func _on_instance_team_broadcast(team: int, channel: int, data: PackedByteArray, inst: GameInstance) -> void:
	for pid: int in inst.participants:
		var p: Participant = inst.participants[pid]
		if p.is_bot:
			continue
		if p.team == team:
			_send_raw(pid, channel, data)


func _get_instance(peer_id: int) -> GameInstance:
	if not _sessions.has(peer_id):
		return null
	var session: Dictionary = _sessions[peer_id]
	if not session["authed"]:
		return null
	return session.get("instance")


func _send(peer_id: int, channel: int, data: PackedByteArray) -> void:
	_send_raw(peer_id, channel, data)


func _send_raw(peer_id: int, channel: int, data: PackedByteArray) -> void:
	if not _sessions.has(peer_id):
		return
	var peer: ENetPacketPeer = _sessions[peer_id]["peer"]
	var flags := ENetPacketPeer.FLAG_RELIABLE if channel != Protocol.CH_UNRELIABLE else ENetPacketPeer.FLAG_UNSEQUENCED
	peer.send(channel, data, flags)


func _peer_id(peer: ENetPacketPeer) -> int:
	return peer.get_instance_id()
