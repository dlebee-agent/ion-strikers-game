class_name GameClient
extends Node

# ENet client that connects to a game server, performs JoinDirect, and
# relays Init/Snap to the match scene.

signal connected_to_lobby(init_data: Dictionary)
signal snap_received(players: Array)
signal connection_failed(reason: String)

var _host: ENetConnection
var _peer: ENetPacketPeer
var _connected := false
var _authed := false
var _callsign: String = "Player"
var _target_host: String = "127.0.0.1"
var _target_port: int = 7777


func connect_to_server(host: String, port: int, callsign: String) -> void:
	_target_host = host
	_target_port = port
	_callsign = callsign

	_host = ENetConnection.new()
	var err := _host.create_host(1, 2)
	if err != OK:
		connection_failed.emit("Failed to create ENet host: " + error_string(err))
		return

	_peer = _host.connect_to_host(_target_host, _target_port, 2)
	if _peer == null:
		connection_failed.emit("Failed to connect to %s:%d" % [_target_host, _target_port])
		return


func disconnect_from_server() -> void:
	if _peer and _connected:
		var buf := Protocol.encode(Protocol.leave_msg())
		_peer.send(Protocol.CHANNEL_RELIABLE, buf, ENetPacketPeer.FLAG_RELIABLE)
	if _host:
		_host.flush()
		_host.destroy()
		_host = null
	_peer = null
	_connected = false
	_authed = false


func send_state(pos: Vector3, yaw: float, pitch: float) -> void:
	if not _authed or _peer == null:
		return
	var buf := Protocol.encode(Protocol.state_msg(pos, yaw, pitch))
	_peer.send(Protocol.CHANNEL_UNRELIABLE, buf, ENetPacketPeer.FLAG_UNSEQUENCED)


func _process(_dt: float) -> void:
	if _host == null:
		return
	while true:
		var ev := _host.service(0)
		var event_type: int = ev[0]
		if event_type == ENetConnection.EVENT_NONE:
			break

		if event_type == ENetConnection.EVENT_CONNECT:
			_connected = true
			var buf := Protocol.encode(Protocol.join_direct(_callsign))
			_peer.send(Protocol.CHANNEL_RELIABLE, buf, ENetPacketPeer.FLAG_RELIABLE)

		elif event_type == ENetConnection.EVENT_DISCONNECT:
			_connected = false
			_authed = false
			connection_failed.emit("Disconnected from server.")

		elif event_type == ENetConnection.EVENT_RECEIVE:
			var peer: ENetPacketPeer = ev[1]
			var data: PackedByteArray = peer.get_packet()
			_on_receive(data)


func _on_receive(data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	if msg.is_empty():
		return

	var t: int = int(msg.get("t", -1))

	if t == Protocol.Msg.INIT:
		_authed = true
		connected_to_lobby.emit(msg)

	elif t == Protocol.Msg.SNAP:
		snap_received.emit(msg.get("players", []))

	elif t == Protocol.Msg.JOIN_ERROR:
		connection_failed.emit(str(msg.get("reason", "Join rejected.")))
