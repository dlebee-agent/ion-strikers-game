class_name GameClient
extends Node

signal connected_to_lobby(init_data: Dictionary)
signal snap_received(snap: Dictionary)
signal connection_failed(reason: String)
signal hit_received(msg: Dictionary)
signal tracer_received(msg: Dictionary)
signal round_start_received(msg: Dictionary)
signal round_end_received(msg: Dictionary)
signal match_over_received(msg: Dictionary)
signal respawn_received(msg: Dictionary)
signal chat_received(msg: Dictionary)
signal special_received(msg: Dictionary)
signal announce_received(msg: Dictionary)
signal meteor_received(msg: Dictionary)
signal team_received(msg: Dictionary)
signal team_opts_received(msg: Dictionary)
signal team_denied_received(msg: Dictionary)
signal roster_received(msg: Dictionary)
signal cheats_changed(enabled: bool)
signal cheats_denied()

var _host: ENetConnection
var _peer: ENetPacketPeer
var _connected := false
var _authed := false
var _callsign: String = "Player"
var _target_host: String = "127.0.0.1"
var _target_port: int = 7777

var _create_settings: Dictionary = {}
var _should_create := false
var _join_token: Dictionary = {}

var my_id: int = 0
var rtt_ms: float = 0.0

const INTERP_DELAY_MS := 80.0


func connect_to_server(host: String, port: int, callsign: String) -> void:
	_target_host = host
	_target_port = port
	_callsign = callsign

	_host = ENetConnection.new()
	var err := _host.create_host(1, Protocol.MAX_CHANNELS)
	if err != OK:
		connection_failed.emit("Failed to create ENet host: " + error_string(err))
		return

	_peer = _host.connect_to_host(_target_host, _target_port, Protocol.MAX_CHANNELS)
	if _peer == null:
		connection_failed.emit("Failed to connect to %s:%d" % [_target_host, _target_port])
		return


func set_create_settings(settings: Dictionary) -> void:
	_create_settings = settings
	_should_create = true


func set_join_auth(token: Dictionary) -> void:
	_join_token = token


func disconnect_from_server() -> void:
	if _peer and _connected:
		var buf := Protocol.encode_leave()
		_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)
	if _host:
		_host.flush()
		_host.destroy()
		_host = null
	_peer = null
	_connected = false
	_authed = false
	GameConsole.clear_session()


func send_state(pos: Vector3, yaw: float, pitch: float, crouched: bool, grounded: bool) -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_state(pos.x, pos.y, pos.z, yaw, pitch, crouched, grounded)
	_peer.send(Protocol.CH_UNRELIABLE, buf, ENetPacketPeer.FLAG_UNSEQUENCED)


func send_shot(origin: Vector3, dir: Vector3) -> void:
	if not _authed or _peer == null:
		return
	var lag := int(INTERP_DELAY_MS + rtt_ms * 0.5)
	var buf := Protocol.encode_shot(origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, lag)
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_melee() -> void:
	if not _authed or _peer == null:
		return
	var lag := int(INTERP_DELAY_MS + rtt_ms * 0.5)
	var buf := Protocol.encode_melee(lag)
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_set_team(team: int) -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_set_team(team)
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_team_menu() -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_team_menu()
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_special_start() -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_special_start()
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_special_fire() -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_special_fire()
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_chat(text: String, team_only: bool) -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_chat(my_id, _callsign, 0, text, team_only, false)
	_peer.send(Protocol.CH_EVENTS, buf, ENetPacketPeer.FLAG_RELIABLE)


func send_set_cheats(enabled: bool, password: String) -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode_set_cheats(enabled, password)
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func _process(_dt: float) -> void:
	if _host == null:
		return

	if _peer and _connected:
		rtt_ms = _peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)

	# Handlers below emit signals whose listeners may call disconnect_from_server(),
	# which destroys the host. Re-check each pass rather than servicing freed memory.
	while _host != null:
		var ev := _host.service(0)
		var event_type: int = ev[0]
		if event_type == ENetConnection.EVENT_NONE:
			break

		if event_type == ENetConnection.EVENT_CONNECT:
			_connected = true
			if not _join_token.is_empty():
				var auth := Protocol.encode_join_auth(_callsign, _join_token)
				_peer.send(Protocol.CH_HANDSHAKE, auth, ENetPacketPeer.FLAG_RELIABLE)
			else:
				if _should_create:
					_send_create_game()
				var buf := Protocol.encode_join_direct(_callsign)
				_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)

		elif event_type == ENetConnection.EVENT_DISCONNECT:
			_connected = false
			_authed = false
			GameConsole.clear_session()
			connection_failed.emit("Disconnected from server.")

		elif event_type == ENetConnection.EVENT_RECEIVE:
			var peer: ENetPacketPeer = ev[1]
			var data: PackedByteArray = peer.get_packet()
			var channel: int = ev[3]
			_on_receive(channel, data)


func _send_create_game() -> void:
	var buf := Protocol.encode_create_game(
		str(_create_settings.get("map", "parkour")),
		str(_create_settings.get("mode", "classic")),
		int(_create_settings.get("rounds", 10)),
		int(_create_settings.get("kills", 50)),
		int(_create_settings.get("max_players", 12)),
		int(_create_settings.get("max_spectators", 12)),
		bool(_create_settings.get("bots", true)),
		bool(_create_settings.get("bots_shoot", true)),
		bool(_create_settings.get("bots_move", true)),
		BotSkill.index_of(str(_create_settings.get("bot_skill", BotSkill.DEFAULT_LEVEL))),
		str(_create_settings.get("display_name", "")))
	_peer.send(Protocol.CH_HANDSHAKE, buf, ENetPacketPeer.FLAG_RELIABLE)


func _on_receive(channel: int, data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	if msg.is_empty():
		return

	var t: int = int(msg.get("t", -1))

	if channel == Protocol.CH_UNRELIABLE:
		if t == Protocol.Msg.SNAP:
			snap_received.emit(msg)

	elif channel == Protocol.CH_HANDSHAKE:
		match t:
			Protocol.Msg.INIT:
				my_id = int(msg.get("id", 0))
				_authed = true
				connected_to_lobby.emit(msg)
			Protocol.Msg.JOIN_ERROR:
				connection_failed.emit(str(msg.get("reason", "Join rejected.")))
			Protocol.Msg.TEAM:
				team_received.emit(msg)
			Protocol.Msg.TEAM_OPTS:
				team_opts_received.emit(msg)
			Protocol.Msg.TEAM_DENIED:
				team_denied_received.emit(msg)
			Protocol.Msg.SET_CHEATS_DENIED:
				cheats_denied.emit()

	elif channel == Protocol.CH_EVENTS:
		match t:
			Protocol.Msg.HIT:
				hit_received.emit(msg)
			Protocol.Msg.TRACER:
				tracer_received.emit(msg)
			Protocol.Msg.ROUND_START:
				round_start_received.emit(msg)
			Protocol.Msg.ROUND_END:
				round_end_received.emit(msg)
			Protocol.Msg.MATCH_OVER:
				match_over_received.emit(msg)
			Protocol.Msg.RESPAWN:
				respawn_received.emit(msg)
			Protocol.Msg.CHAT:
				chat_received.emit(msg)
			Protocol.Msg.SPECIAL:
				special_received.emit(msg)
			Protocol.Msg.ANNOUNCE:
				announce_received.emit(msg)
			Protocol.Msg.METEOR:
				meteor_received.emit(msg)
			Protocol.Msg.ROSTER:
				roster_received.emit(msg)
			Protocol.Msg.CHEATS:
				cheats_changed.emit(bool(msg.get("enabled", false)))
