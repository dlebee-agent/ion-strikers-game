extends Node

# Headless game server.  Owns an ENetConnection host, a GameRegistry, and
# pumps events in _process.  Started by boot.gd when --dedicated is passed.

var _host: ENetConnection
var _registry: GameRegistry
var _port: int = 7777
var _map_id: String = "parkour"
var _server_name: String = ""

# peer_id → { enet_peer, game_instance, authed }
var _sessions: Dictionary = {}

const SNAP_INTERVAL := 1.0 / 30.0
var _snap_timer: float = 0.0


func configure(port: int, map_id: String, server_name: String) -> void:
	_port = port
	_map_id = map_id
	_server_name = server_name


func _ready() -> void:
	_registry = GameRegistry.new()
	_registry.max_lobbies = 1

	var inst := _registry.preload_instance({
		"map_id": _map_id,
		"display_name": _server_name,
	})
	if inst == null:
		push_error("Failed to preload GameInstance")
		get_tree().quit(1)
		return

	_host = ENetConnection.new()
	var err := _host.create_host_bound("0.0.0.0", _port, 32, 2)
	if err != OK:
		push_error("ENet bind failed on port %d: %s" % [_port, error_string(err)])
		get_tree().quit(1)
		return

	print("[server] listening on 0.0.0.0:%d  map=%s" % [_port, _map_id])


func _process(dt: float) -> void:
	if _host == null:
		return
	_poll_enet()
	_snap_timer += dt
	if _snap_timer >= SNAP_INTERVAL:
		_snap_timer -= SNAP_INTERVAL
		_broadcast_snap()


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


func _on_receive(peer_id: int, _channel: int, data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	if msg.is_empty():
		return

	var t: int = int(msg.get("t", -1))

	if t == Protocol.Msg.JOIN_DIRECT:
		_handle_join_direct(peer_id, msg)
	elif t == Protocol.Msg.STATE:
		_handle_state(peer_id, msg)
	elif t == Protocol.Msg.LEAVE:
		_on_disconnect(peer_id)


func _handle_join_direct(peer_id: int, msg: Dictionary) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	if session["authed"]:
		return

	var version: int = int(msg.get("v", 0))
	if version != Protocol.PROTOCOL_VERSION:
		_send(peer_id, Protocol.CHANNEL_RELIABLE,
			Protocol.join_error("Protocol version mismatch."))
		return

	var inst := _registry.resolve_join_direct()
	if inst == null:
		_send(peer_id, Protocol.CHANNEL_RELIABLE,
			Protocol.join_error("No lobby available."))
		return

	var callsign: String = str(msg.get("name", "Player"))
	var result := inst.admit(peer_id, callsign)
	if not result["ok"]:
		_send(peer_id, Protocol.CHANNEL_RELIABLE,
			Protocol.join_error(str(result["reason"])))
		return

	session["instance"] = inst
	session["authed"] = true

	var spawn: Vector3 = result["spawn"]
	var yaw: float = result["yaw"]
	_send(peer_id, Protocol.CHANNEL_RELIABLE,
		Protocol.init_msg(peer_id, _map_id, spawn, yaw))
	print("[server] peer %d joined as '%s'" % [peer_id, callsign])


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
		Vector3(msg.get("x", 0.0), msg.get("y", 0.0), msg.get("z", 0.0)),
		msg.get("yaw", 0.0), msg.get("pitch", 0.0))


func _on_disconnect(peer_id: int) -> void:
	if not _sessions.has(peer_id):
		return
	var session: Dictionary = _sessions[peer_id]
	var inst: GameInstance = session.get("instance")
	if inst:
		inst.remove(peer_id)
	_sessions.erase(peer_id)
	print("[server] peer %d disconnected" % peer_id)


func _broadcast_snap() -> void:
	for gid: String in _registry.instances:
		var inst: GameInstance = _registry.instances[gid]
		var snap := inst.build_snap()
		var pkt := Protocol.encode(Protocol.snap_msg(snap))
		for pid: int in inst.participants:
			_send(pid, Protocol.CHANNEL_UNRELIABLE, pkt, true)


func _send(peer_id: int, channel: int, msg_or_buf, pre_encoded := false) -> void:
	if not _sessions.has(peer_id):
		return
	var peer: ENetPacketPeer = _sessions[peer_id]["peer"]
	var buf: PackedByteArray
	if pre_encoded:
		buf = msg_or_buf
	else:
		buf = Protocol.encode(msg_or_buf)
	var flags := ENetPacketPeer.FLAG_RELIABLE if channel == Protocol.CHANNEL_RELIABLE else ENetPacketPeer.FLAG_UNSEQUENCED
	peer.send(channel, buf, flags)


func _peer_id(peer: ENetPacketPeer) -> int:
	return peer.get_instance_id()
