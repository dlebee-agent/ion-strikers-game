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


func configure(port: int, parent_pid: int = -1) -> void:
	_port = port
	_parent_pid = parent_pid


func _ready() -> void:
	_registry = GameRegistry.new()
	_registry.max_lobbies = 1

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

	elif channel == Protocol.CH_EVENTS:
		if t == Protocol.Msg.CHAT:
			_handle_chat(peer_id, msg)


func _handle_create_game(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
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

	var callsign: String = str(msg.get("name", "Player"))
	var result := inst.admit_spectator(peer_id, callsign)
	if not result["ok"]:
		_send(peer_id, Protocol.CH_HANDSHAKE,
			Protocol.encode_join_error(str(result["reason"])))
		return

	session["instance"] = inst
	session["authed"] = true

	_send(peer_id, Protocol.CH_HANDSHAKE, result["init"])
	print("[server] peer %d joined as '%s' (stands)" % [peer_id, callsign])


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
