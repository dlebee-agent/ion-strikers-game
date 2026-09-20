extends SceneTree

## Spin bot: an external proxy that sits between the installed Ion Strikers
## client and the game server. The client plays normally and renders its own
## honest view; on the wire its yaw spins and every shot is re-aimed at the
## nearest visible enemy's head.
##
## Two listeners on 127.0.0.1:
##   Game API proxy (HTTP)  forwards to the real API and rewrites the host/port
##                          in create/join answers so the client connects here.
##   ENet proxy             one upstream connection per client, packets relayed
##                          both ways, STATE and SHOT rewritten on the way up.
##
## The relay target comes from one of three places, in this order: a client
## started with `-- --proxy` names it on the bulk channel (works for every
## server, the local New Game one included), else the last API create/join
## answer, else --upstream.
##
## Run: godot --headless --path game --script res://tools/spin_bot.gd -- [options]
##   --api URL         real Game API (default https://api.ionstrikers.com)
##   --api-port N      local API proxy port (default 8790)
##   --enet-port N     local ENet proxy port (default 7790)
##   --upstream H:P    game server to relay to when no API join happened yet
##   --spin DEG_PER_S  spin rate as others see it (default 720); 0 keeps real yaw
##   --no-aim          forward shots untouched
##
## Point the game at the proxy, either way:
##   godot --path game -- --proxy 127.0.0.1:7790                      (every server)
##   "/Applications/Ion Strikers.app/Contents/MacOS/Ion Strikers" -- --api-url http://127.0.0.1:8790

const DEFAULT_API := "https://api.ionstrikers.com"
const REWIND_CAP_MS := 300.0
const SHOT_RANGE := 200.0
const TELEPORT_SPEED := 20.0

var _api_url := DEFAULT_API
var _api_port := 8790
var _enet_port := 7790
var _spin_rate := 720.0
var _aim := true
var _upstream_host := ""
var _upstream_port := 0

var _tcp: TCPServer
var _http_conns: Array[Dictionary] = []
var _listen: ENetConnection
var _sessions: Dictionary = {}
var _trace := TraceResult.new()
var _started := false
var _t := 0.0


class Session:
	var client: ENetPacketPeer
	var up_host: ENetConnection = null
	var up_peer: ENetPacketPeer = null
	var up_connected := false
	var awaiting_target := false
	var pending: Array = []
	var my_id := 0
	var my_team := Protocol.TEAM_NONE
	var world: CollisionWorld = null
	var pos := Vector3.ZERO
	var crouched := false
	var grounded := true
	var players: Array = []
	var snap_at := -1.0
	var prev_pos: Dictionary = {}
	var vel: Dictionary = {}
	var hits := 0
	var kills := 0


func _process(dt: float) -> bool:
	_t += dt
	if not _started:
		_started = true
		_parse_args()
		if not _start():
			quit(1)
			return true
	_poll_http()
	_poll_listen()
	_poll_upstreams()
	return false


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a := args[i]
		var next := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--api":
				_api_url = next.rstrip("/")
			"--api-port":
				_api_port = int(next)
			"--enet-port":
				_enet_port = int(next)
			"--spin":
				_spin_rate = float(next)
			"--no-aim":
				_aim = false
			"--upstream":
				var parts := next.rsplit(":", true, 1)
				if parts.size() == 2:
					_upstream_host = parts[0]
					_upstream_port = int(parts[1])


func _start() -> bool:
	_tcp = TCPServer.new()
	var err := _tcp.listen(_api_port, "127.0.0.1")
	if err != OK:
		push_error("[spinbot] cannot listen on 127.0.0.1:%d for the API proxy (%s)" % [_api_port, error_string(err)])
		return false

	_listen = ENetConnection.new()
	err = _listen.create_host_bound("127.0.0.1", _enet_port, 8, Protocol.MAX_CHANNELS)
	if err != OK:
		push_error("[spinbot] cannot bind ENet proxy on 127.0.0.1:%d (%s)" % [_enet_port, error_string(err)])
		return false

	print("[spinbot] API proxy   http://127.0.0.1:%d -> %s" % [_api_port, _api_url])
	print("[spinbot] ENet proxy  127.0.0.1:%d -> %s" % [_enet_port,
		"%s:%d" % [_upstream_host, _upstream_port] if _upstream_port > 0 else "(server from the next API join)"])
	print("[spinbot] spin %.0f deg/s, aim %s" % [_spin_rate, "on" if _aim else "off"])
	print("[spinbot] launch the game with:  -- --api-url http://127.0.0.1:%d" % _api_port)
	return true


# ── Game API proxy ──────────────────────────────────────────────────────

func _poll_http() -> void:
	while _tcp.is_connection_available():
		_http_conns.append({"peer": _tcp.take_connection(), "buf": PackedByteArray(), "busy": false})

	for i in range(_http_conns.size() - 1, -1, -1):
		var c: Dictionary = _http_conns[i]
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_http_conns.remove_at(i)
			continue
		if c["busy"]:
			continue
		var avail := peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_data(avail)
			c["buf"] = (c["buf"] as PackedByteArray) + (chunk[1] as PackedByteArray)
		var req := _parse_http(c["buf"])
		if req.is_empty():
			continue
		c["busy"] = true
		_serve_http(c, req)


func _parse_http(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_ascii()
	var head_end := text.find("\r\n\r\n")
	if head_end < 0:
		return {}
	var lines := text.substr(0, head_end).split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		return {}
	var length := 0
	for j in range(1, lines.size()):
		var kv := lines[j].split(":", true, 1)
		if kv.size() == 2 and kv[0].strip_edges().to_lower() == "content-length":
			length = int(kv[1].strip_edges())
	var body_start := head_end + 4
	if buf.size() < body_start + length:
		return {}
	return {
		"method": request_line[0],
		"path": request_line[1],
		"body": buf.slice(body_start, body_start + length).get_string_from_utf8(),
	}


func _serve_http(c: Dictionary, req: Dictionary) -> void:
	var method := HTTPClient.METHOD_GET
	match req["method"]:
		"POST": method = HTTPClient.METHOD_POST
		"PUT": method = HTTPClient.METHOD_PUT
		"DELETE": method = HTTPClient.METHOD_DELETE

	var http := HTTPRequest.new()
	http.timeout = 10.0
	root.add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var status := 502
	var body := '{"error":"spin bot could not reach the Game API"}'
	var err := http.request(_api_url + str(req["path"]), headers, method, str(req["body"]))
	if err == OK:
		var done: Array = await http.request_completed
		if int(done[0]) == HTTPRequest.RESULT_SUCCESS:
			status = int(done[1])
			body = _rewrite_connect(req, (done[3] as PackedByteArray).get_string_from_utf8())
	http.queue_free()

	var peer: StreamPeerTCP = c["peer"]
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var payload := body.to_utf8_buffer()
		var reply := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
			status, "OK" if status < 400 else "Error", payload.size()]
		peer.put_data(reply.to_ascii_buffer() + payload)
		peer.disconnect_from_host()
	_http_conns.erase(c)


## A create or join answer names the real server. Remember it and hand the
## client this proxy instead.
func _rewrite_connect(req: Dictionary, body: String) -> String:
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return body
	var d: Dictionary = parsed
	if not (d.has("host") and d.has("port")):
		return body
	_upstream_host = str(d["host"])
	_upstream_port = int(d["port"])
	d["host"] = "127.0.0.1"
	d["port"] = _enet_port
	print("[api] %s %s -> server %s:%d, client sent to 127.0.0.1:%d" % [
		req["method"], req["path"], _upstream_host, _upstream_port, _enet_port])
	return JSON.stringify(d)


# ── ENet proxy ──────────────────────────────────────────────────────────

func _flags(channel: int) -> int:
	return ENetPacketPeer.FLAG_UNSEQUENCED if channel == Protocol.CH_UNRELIABLE else ENetPacketPeer.FLAG_RELIABLE


func _poll_listen() -> void:
	while true:
		var ev: Array = _listen.service(0)
		var type: int = ev[0]
		if type == ENetConnection.EVENT_NONE:
			break
		var peer: ENetPacketPeer = ev[1]
		var key := peer.get_instance_id()
		if type == ENetConnection.EVENT_CONNECT:
			_open_session(peer, int(ev[2]))
		elif type == ENetConnection.EVENT_DISCONNECT:
			_close_session(key, "client left")
		elif type == ENetConnection.EVENT_RECEIVE:
			var s: Session = _sessions.get(key)
			if s != null:
				_client_to_server(s, int(ev[3]), peer.get_packet())


func _open_session(peer: ENetPacketPeer, connect_data: int) -> void:
	var s := Session.new()
	s.client = peer
	_sessions[peer.get_instance_id()] = s
	if connect_data == Protocol.PROXY_CONNECT_DATA:
		s.awaiting_target = true
		print("[enet] client connected, waiting for it to name its server")
		return
	if _upstream_port <= 0:
		push_error("[spinbot] client connected but no server is known yet; start the game with --proxy, join through the API proxy, or pass --upstream")
		_close_session(peer.get_instance_id(), "no server known")
		return
	_connect_upstream(s, _upstream_host, _upstream_port)


func _connect_upstream(s: Session, host: String, port: int) -> void:
	s.up_host = ENetConnection.new()
	var err := s.up_host.create_host(1, Protocol.MAX_CHANNELS)
	if err != OK:
		push_error("[spinbot] cannot create upstream host (%s)" % error_string(err))
		_close_session(s.client.get_instance_id(), "upstream host failed")
		return
	s.up_peer = s.up_host.connect_to_host(host, port, Protocol.MAX_CHANNELS)
	if s.up_peer == null:
		push_error("[spinbot] cannot connect upstream to %s:%d" % [host, port])
		_close_session(s.client.get_instance_id(), "upstream connect failed")
		return
	print("[enet] relaying to %s:%d" % [host, port])


func _close_session(key: int, why: String) -> void:
	var s: Session = _sessions.get(key)
	if s == null:
		return
	_sessions.erase(key)
	if s.client.get_state() == ENetPacketPeer.STATE_CONNECTED:
		s.client.peer_disconnect_later(0)
	if s.up_connected:
		s.up_peer.peer_disconnect_now(0)
	if s.up_host != null:
		s.up_host.flush()
		s.up_host.destroy()
	print("[enet] session closed (%s): %d hits, %d kills re-aimed" % [why, s.hits, s.kills])


func _poll_upstreams() -> void:
	for key: int in _sessions.keys():
		var s: Session = _sessions[key]
		while _sessions.has(key) and s.up_host != null:
			var ev: Array = s.up_host.service(0)
			var type: int = ev[0]
			if type == ENetConnection.EVENT_NONE:
				break
			if type == ENetConnection.EVENT_CONNECT:
				s.up_connected = true
				for item: Array in s.pending:
					s.up_peer.send(item[0], item[1], _flags(item[0]))
				s.pending.clear()
			elif type == ENetConnection.EVENT_DISCONNECT:
				_close_session(key, "server closed")
			elif type == ENetConnection.EVENT_RECEIVE:
				_server_to_client(s, int(ev[3]), (ev[1] as ENetPacketPeer).get_packet())


func _send_up(s: Session, channel: int, data: PackedByteArray) -> void:
	if not s.up_connected:
		s.pending.append([channel, data])
		return
	s.up_peer.send(channel, data, _flags(channel))


func _client_to_server(s: Session, channel: int, data: PackedByteArray) -> void:
	if channel == Protocol.CH_BULK and s.awaiting_target:
		s.awaiting_target = false
		var parts := data.get_string_from_utf8().rsplit(":", true, 1)
		if parts.size() != 2 or int(parts[1]) <= 0:
			_close_session(s.client.get_instance_id(), "bad target from client")
			return
		_connect_upstream(s, parts[0], int(parts[1]))
		return

	var msg := Protocol.decode(data)
	var t := int(msg.get("t", -1))
	var out := data

	if channel == Protocol.CH_UNRELIABLE and t == Protocol.Msg.STATE:
		s.pos = Vector3(float(msg["x"]), float(msg["y"]), float(msg["z"]))
		s.crouched = bool(msg["crouched"])
		s.grounded = bool(msg["grounded"])
		if _spin_rate != 0.0:
			out = Protocol.encode_state(s.pos.x, s.pos.y, s.pos.z,
				fposmod(_t * _spin_rate, 360.0), float(msg["pitch"]), s.crouched, s.grounded)
	elif channel == Protocol.CH_HANDSHAKE and _aim:
		match t:
			Protocol.Msg.SHOT:
				out = _aimed_shot(s, msg, data)
			Protocol.Msg.MELEE, Protocol.Msg.SPECIAL_START, Protocol.Msg.SPECIAL_FIRE:
				_face_target(s)

	_send_up(s, channel, out)


func _server_to_client(s: Session, channel: int, data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	var t := int(msg.get("t", -1))

	if channel == Protocol.CH_UNRELIABLE and t == Protocol.Msg.SNAP:
		_on_snap(s, msg)
	elif channel == Protocol.CH_HANDSHAKE and t == Protocol.Msg.INIT:
		s.my_id = int(msg.get("id", 0))
		_load_world(s, str(msg.get("map", "")))
	elif channel == Protocol.CH_EVENTS and t == Protocol.Msg.HIT and int(msg.get("by_id", 0)) == s.my_id:
		s.hits += 1
		if bool(msg.get("killed", false)):
			s.kills += 1
		print("[hit] %s %s%s" % [msg.get("target_name", "?"),
			"head" if bool(msg.get("head", false)) else "body",
			", killed" if bool(msg.get("killed", false)) else " (%d hp left)" % int(msg.get("hp", 0))])

	s.client.send(channel, data, _flags(channel))


func _load_world(s: Session, map_id: String) -> void:
	s.world = null
	if MapCatalog.is_community(map_id):
		var level := MapCatalog.load_community(map_id)
		if level.ok():
			s.world = level.world
	elif MapCatalog.has_map(map_id):
		var compiled := MapEngine.compile(MapCatalog.builtin_definition(map_id))
		s.world = MapBuilder.build_world(compiled)
	print("[map] %s: %s" % [map_id,
		"line-of-sight checks on" if s.world != null else "no collision world, walls are not checked"])


func _on_snap(s: Session, msg: Dictionary) -> void:
	var players: Array = msg.get("players", [])
	for p: Dictionary in players:
		var id := int(p["id"])
		var pos := Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		if s.prev_pos.has(id):
			var prev: Array = s.prev_pos[id]
			var dtp: float = _t - float(prev[1])
			if dtp > 0.001:
				var v: Vector3 = (pos - (prev[0] as Vector3)) / dtp
				# A respawn is a teleport, not a velocity.
				s.vel[id] = v if v.length() < TELEPORT_SPEED else Vector3.ZERO
		s.prev_pos[id] = [pos, _t]
		if id == s.my_id:
			s.my_team = int(p["team"])
	s.players = players
	s.snap_at = _t


# ── aiming ──────────────────────────────────────────────────────────────

## Nearest enemy whose head is in line of sight from origin. Humans are
## rewound by the server, so lag_ms is chosen to land on the snapshot we
## aimed at; bots are not rewound, so they are led by their snap velocity.
func _pick_target(s: Session, origin: Vector3) -> Dictionary:
	if s.snap_at < 0.0 or s.my_team == Protocol.TEAM_NONE:
		return {}
	var age := _t - s.snap_at
	var rtt := float(s.up_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	var lag_ms := int(clampf(rtt + age * 1000.0, 0.0, REWIND_CAP_MS))
	var lead := rtt * 0.0005 + age

	var best := {}
	var best_d := INF
	for p: Dictionary in s.players:
		var id := int(p["id"])
		if id == s.my_id:
			continue
		var flags := int(p["flags"])
		if (flags & Protocol.PFLG_ALIVE) == 0 or (flags & Protocol.PFLG_PROTECTED) != 0:
			continue
		var team := int(p["team"])
		if team == Protocol.TEAM_NONE or team == s.my_team:
			continue
		var pos := Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		if (flags & Protocol.PFLG_BOT) != 0:
			pos += (s.vel.get(id, Vector3.ZERO) as Vector3) * lead
		var crouched := (flags & Protocol.PFLG_CROUCHED) != 0
		var head := pos + Vector3(0.0, Hitbox.CROUCH_HEAD_Y if crouched else Hitbox.STAND_HEAD_Y, 0.0)
		var d := origin.distance_to(head)
		if d < 0.05 or d >= best_d or d > SHOT_RANGE:
			continue
		var dir := (head - origin).normalized()
		if s.world != null and s.world.ray_distance(origin, dir, d, _trace, CollisionWorld.MASK_SOLID) < d - 0.05:
			continue
		best = {"id": id, "dir": dir, "dist": d, "lag_ms": lag_ms}
		best_d = d
	return best


func _aimed_shot(s: Session, msg: Dictionary, raw: PackedByteArray) -> PackedByteArray:
	var origin := Vector3(float(msg["origin_x"]), float(msg["origin_y"]), float(msg["origin_z"]))
	var pick := _pick_target(s, origin)
	if pick.is_empty():
		print("[aim] no visible enemy, shot forwarded as fired")
		return raw
	var dir: Vector3 = pick["dir"]
	print("[aim] shot re-aimed at id %d, %.1f m, lag %d ms" % [pick["id"], pick["dist"], pick["lag_ms"]])
	return Protocol.encode_shot(origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, int(pick["lag_ms"]))


## Melee and the special use the server-side yaw, so turn the pawn toward
## the target on the wire just before those go through.
func _face_target(s: Session) -> void:
	var origin := s.pos + Vector3(0.0, Hitbox.eye_height(s.crouched), 0.0)
	var pick := _pick_target(s, origin)
	if pick.is_empty():
		return
	var dir: Vector3 = pick["dir"]
	var yaw := rad_to_deg(atan2(-dir.x, -dir.z))
	var pitch := rad_to_deg(-asin(clampf(dir.y, -1.0, 1.0)))
	_send_up(s, Protocol.CH_UNRELIABLE,
		Protocol.encode_state(s.pos.x, s.pos.y, s.pos.z, yaw, pitch, s.crouched, s.grounded))
