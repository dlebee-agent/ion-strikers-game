extends SceneTree

# End-to-end check for the spin bot. Connects through the proxy as a client,
# creates a bots-only-opposition lobby, walks from its spawn to a perch above
# the arena centre, and fires straight up every 0.3 s. Every hit it is
# credited with came from the proxy re-aiming a shot that could not have hit
# on its own; every distinct yaw it sees for itself in the snaps came from
# the proxy spinning its state.
#
# It connects the way a client started with --proxy does: the proxy is told
# the real server on the bulk channel, so the proxy needs no --upstream.
#
# Run (with a dedicated server and the proxy already up):
#   godot --headless --path game --script res://tools/spin_bot_check.gd -- --proxy-port 7790 --server-port 7777

const RUN_SECONDS := 25.0
const FIRE_GAP := 0.3
const PERCH := Vector3(0.0, 3.0, 0.0)
const WALK_SPEED := 4.0

var _host: ENetConnection
var _peer: ENetPacketPeer
var _port := 7790
var _server_port := 7777
var _named_target := false
var _my_id := 0
var _pos := Vector3.ZERO
var _alive := false
var _hits := 0
var _kills := 0
var _yaws: Array[float] = []
var _snaps := 0
var _t := 0.0
var _next_shot := 0.0
var _started := false
var _team_sent := false


func _process(dt: float) -> bool:
	_t += dt
	if not _started:
		_started = true
		var args := OS.get_cmdline_user_args()
		for i in args.size():
			if args[i] == "--proxy-port" and i + 1 < args.size():
				_port = int(args[i + 1])
			elif args[i] == "--server-port" and i + 1 < args.size():
				_server_port = int(args[i + 1])
		_host = ENetConnection.new()
		_host.create_host(1, Protocol.MAX_CHANNELS)
		_peer = _host.connect_to_host("127.0.0.1", _port, Protocol.MAX_CHANNELS, Protocol.PROXY_CONNECT_DATA)
		print("[check] connecting to proxy 127.0.0.1:%d" % _port)

	while true:
		var ev: Array = _host.service(0)
		var type: int = ev[0]
		if type == ENetConnection.EVENT_NONE:
			break
		if type == ENetConnection.EVENT_CONNECT and not _named_target:
			_named_target = true
			_peer.send(Protocol.CH_BULK, ("127.0.0.1:%d" % _server_port).to_utf8_buffer(),
				ENetPacketPeer.FLAG_RELIABLE)
		if type == ENetConnection.EVENT_DISCONNECT:
			print("[check] FAIL disconnected")
			quit(1)
			return true
		if type == ENetConnection.EVENT_RECEIVE:
			_on_receive(int(ev[3]), (ev[1] as ENetPacketPeer).get_packet())

	if _alive:
		_pos = _pos.move_toward(PERCH, WALK_SPEED * dt)
		_peer.send(Protocol.CH_UNRELIABLE,
			Protocol.encode_state(_pos.x, _pos.y, _pos.z, 0.0, 0.0, false, true),
			ENetPacketPeer.FLAG_UNSEQUENCED)
		if _t >= _next_shot:
			_next_shot = _t + FIRE_GAP
			var eye := _pos + Vector3(0.0, Hitbox.EYE_STAND, 0.0)
			_peer.send(Protocol.CH_HANDSHAKE,
				Protocol.encode_shot(eye.x, eye.y, eye.z, 0.0, 1.0, 0.0, 80),
				ENetPacketPeer.FLAG_RELIABLE)

	if _t >= RUN_SECONDS:
		_finish()
		return true
	return false


func _on_receive(channel: int, data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	var t := int(msg.get("t", -1))
	if channel == Protocol.CH_HANDSHAKE:
		match t:
			Protocol.Msg.HELLO:
				_peer.send(Protocol.CH_HANDSHAKE, Protocol.encode_create_game(
					"parkour", "dm", 10, 50, 12, 12, true, false, true, 1, "spin check"),
					ENetPacketPeer.FLAG_RELIABLE)
				_peer.send(Protocol.CH_HANDSHAKE, Protocol.encode_join_direct("SpinCheck"),
					ENetPacketPeer.FLAG_RELIABLE)
			Protocol.Msg.INIT:
				_my_id = int(msg["id"])
				print("[check] joined as id %d on map %s" % [_my_id, msg["map"]])
				if not _team_sent:
					_team_sent = true
					_peer.send(Protocol.CH_HANDSHAKE, Protocol.encode_set_team(Protocol.TEAM_BLUE),
						ENetPacketPeer.FLAG_RELIABLE)
			Protocol.Msg.JOIN_ERROR:
				print("[check] FAIL join error: %s" % msg.get("reason", "?"))
				quit(1)
			Protocol.Msg.TEAM:
				if bool(msg["alive"]):
					_spawn(Vector3(float(msg["spawn_x"]), float(msg["spawn_y"]), float(msg["spawn_z"])))
	elif channel == Protocol.CH_EVENTS:
		if t == Protocol.Msg.RESPAWN and int(msg["id"]) == _my_id:
			_spawn(Vector3(float(msg["x"]), float(msg["y"]), float(msg["z"])))
		elif t == Protocol.Msg.HIT and int(msg["by_id"]) == _my_id:
			_hits += 1
			if bool(msg["killed"]):
				_kills += 1
	elif channel == Protocol.CH_UNRELIABLE and t == Protocol.Msg.SNAP:
		_snaps += 1
		for p: Dictionary in msg["players"]:
			if int(p["id"]) == _my_id:
				var yaw := float(p["yaw"])
				if _yaws.is_empty() or absf(yaw - _yaws[-1]) > 0.5:
					_yaws.append(yaw)


func _spawn(at: Vector3) -> void:
	_pos = at
	_alive = true
	print("[check] spawned at %s" % at)


func _finish() -> void:
	var spinning := _yaws.size() >= 10
	print("[check] snaps %d, distinct own yaws %d, hits %d, kills %d" % [_snaps, _yaws.size(), _hits, _kills])
	print("[check] spin  %s" % ("ok " if spinning else "FAIL"))
	print("[check] aim   %s" % ("ok " if _hits > 0 else "FAIL"))
	_peer.send(Protocol.CH_HANDSHAKE, Protocol.encode_leave(), ENetPacketPeer.FLAG_RELIABLE)
	_host.flush()
	_host.destroy()
	quit(0 if spinning and _hits > 0 else 1)
