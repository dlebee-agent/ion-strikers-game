extends SceneTree

# Drives voice over a real ENet socket, because voice_check.gd stops at the
# GameInstance boundary and the parts below it are where a wiring mistake hides:
# the channel a frame goes out on, the send flags that channel picks, and the
# server-side dispatch that has to recognise VOICE arriving on CH_BULK. A unit
# test cannot catch a frame sent reliably on the wrong channel.
#
# The peers here are raw ENetConnection rather than GameClient, for two reasons.
# GameClient reaches for the GameConsole autoload, which --script does not load.
# More usefully, hand-rolling the client side makes this an independent second
# implementation of the wire, so it cannot share a bug with the one it tests.
#
# Run: godot --headless --path game --script res://tools/voice_wire_check.gd

const PORT := 7951
const SETTLE_FRAMES := 180

var failed := 0
var _server: Node
# Ids live in two spaces and the test has to keep them apart.
#
# Participant ids server-side are Node.get_instance_id(), which is 64-bit, but
# INIT and SNAP both write ids with put_32 — so what a client knows is the low
# 32 bits. That is self-consistent for the real game, since VOICE_DATA truncates
# the same way and the client only ever matches wire ids against wire ids. A
# test that seats pawns has to use the full server-side id, and match received
# audio against the truncated one.
var _peers: Array = []   # [{ name, host, peer, server_id, wire_id, voice, off_channel }]


func _initialize() -> void:
	await _run()
	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  ok    %s" % label)
	else:
		print("  FAIL  %s" % label)
		failed += 1


func _run() -> void:
	_boot_server()
	# add_child during _initialize defers the node's _ready to the first frame,
	# so the socket does not exist yet and actual_port is still 0.
	await _pump(2)
	if _server.actual_port <= 0:
		_ok("server bound on %d" % PORT, false)
		return
	_ok("server bound on port %d" % _server.actual_port, true)

	var host := _connect("host")
	await _pump(SETTLE_FRAMES)
	_send(host, Protocol.CH_HANDSHAKE, Protocol.encode_create_game(
		"parkour", "arena", 999, 999, 12, 12, false, false, false, 2, ""))
	_send(host, Protocol.CH_HANDSHAKE, Protocol.encode_join_direct("host"))
	await _pump(SETTLE_FRAMES)

	var mate := _connect("mate")
	var third := _connect("third")
	await _pump(SETTLE_FRAMES)
	for entry in [mate, third]:
		_send(entry, Protocol.CH_HANDSHAKE, Protocol.encode_join_direct(str(entry["name"])))
	await _pump(SETTLE_FRAMES)

	_ok("all three peers were admitted and got an id",
		int(host["wire_id"]) != 0 and int(mate["wire_id"]) != 0 and int(third["wire_id"]) != 0)

	var inst: GameInstance = _only_instance()
	if inst == null:
		_ok("a lobby exists", false)
		return
	_ok("the lobby holds all three (%d participants)" % inst.participants.size(),
		inst.participants.size() >= 3)

	_resolve_server_ids(inst)
	_ok("every peer resolved to a server-side participant",
		int(host["server_id"]) != 0 and int(mate["server_id"]) != 0
			and int(third["server_id"]) != 0)

	# host and third alive on opposite teams; mate dead.
	_seat(inst, host, Protocol.TEAM_BLUE, true)
	_seat(inst, third, Protocol.TEAM_RED, true)
	_seat(inst, mate, Protocol.TEAM_RED, false)
	_ok("the server agrees on who is alive",
		_liveness_is(inst, host, true) and _liveness_is(inst, third, true)
			and _liveness_is(inst, mate, false))
	inst.match_state.round_state = Protocol.RS_ACTIVE
	inst.match_state.freeze_until = 0.0

	var frame := _frame()

	print("arena over the wire")
	_clear()
	_send(host, Protocol.CH_BULK, Protocol.encode_voice(frame))
	await _pump(90)
	_ok("a live speaker reaches the live listener", _from(third, host) > 0)
	_ok("a live speaker reaches the dead listener", _from(mate, host) > 0)
	_ok("the speaker hears nothing back", _count(host) == 0)

	var got: Array = mate["voice"]
	if got.is_empty():
		_ok("the payload survives the round trip byte for byte", false)
	else:
		var msg: Dictionary = got[0]
		_ok("the payload survives the round trip byte for byte",
			(msg.get("audio", PackedByteArray()) as PackedByteArray) == frame)
		_ok("it still decodes to a full frame",
			VoiceCodec.decode(msg["audio"], Protocol.VOICE_FRAME_SAMPLES).size()
				== Protocol.VOICE_FRAME_SAMPLES)
		_ok("a live speaker is not flagged dead", not bool(msg.get("speaker_dead", true)))

	# The anti-ghost rule, arriving over a socket rather than asserted on a mock.
	_clear()
	_send(mate, Protocol.CH_BULK, Protocol.encode_voice(frame))
	await _pump(90)
	_ok("a dead speaker does NOT reach a live listener", _count(third) == 0)
	_ok("a dead speaker does NOT reach the other live listener", _count(host) == 0)

	# Kill host too, so there is a legitimate recipient to read the flag on.
	_seat(inst, host, Protocol.TEAM_BLUE, false)
	_clear()
	_send(mate, Protocol.CH_BULK, Protocol.encode_voice(frame))
	await _pump(90)
	if _count(host) == 0:
		_ok("a dead speaker reaches a dead listener", false)
	else:
		_ok("a dead speaker reaches a dead listener", true)
		_ok("and is flagged dead",
			bool((host["voice"][0] as Dictionary).get("speaker_dead", false)))

	print("deathmatch over the wire")
	inst.mode = "dm"
	_seat(inst, host, Protocol.TEAM_BLUE, true)
	_clear()
	_send(mate, Protocol.CH_BULK, Protocol.encode_voice(frame))
	await _pump(90)
	_ok("a dead speaker reaches the living",
		_from(host, mate) > 0 and _from(third, mate) > 0)

	print("plumbing")
	_ok("no voice arrived on a channel other than CH_BULK", _off_channel() == 0)

	# A flood has to be capped at the server, not merely survived.
	_clear()
	for _i in range(GameInstance.VOICE_RATE_MAX * 2):
		_send(host, Protocol.CH_BULK, Protocol.encode_voice(frame))
	await _pump(150)
	var relayed := _count(third)
	_ok("a flood of %d frames relays at most the window cap (%d got through)"
			% [GameInstance.VOICE_RATE_MAX * 2, relayed],
		relayed > 0 and relayed <= GameInstance.VOICE_RATE_MAX)

	for entry in _peers:
		_send(entry, Protocol.CH_HANDSHAKE, Protocol.encode_leave())
	await _pump(30)
	for entry in _peers:
		(entry["host"] as ENetConnection).destroy()


# ── harness ─────────────────────────────────────────────────────────────

func _boot_server() -> void:
	_server = load("res://net/game_server.gd").new()
	_server.name = "WireCheckServer"
	_server.bind_ip = "127.0.0.1"
	_server.allow_port_search = true
	_server.configure(PORT, -1, "")
	_server.set_max_lobbies(4)
	root.add_child(_server)


func _connect(callsign: String) -> Dictionary:
	var host := ENetConnection.new()
	host.create_host(1, Protocol.MAX_CHANNELS)
	var peer := host.connect_to_host("127.0.0.1", _server.actual_port, Protocol.MAX_CHANNELS)
	var entry := {
		"name": callsign, "host": host, "peer": peer,
		"server_id": 0, "wire_id": 0, "voice": [], "off_channel": 0,
	}
	_peers.append(entry)
	return entry


func _send(entry: Dictionary, channel: int, body: PackedByteArray) -> void:
	var peer: ENetPacketPeer = entry["peer"]
	if peer == null:
		return
	# Mirrors the real client: unreliable-sequenced on the voice channel.
	var flags := 0 if channel == Protocol.CH_BULK else ENetPacketPeer.FLAG_RELIABLE
	peer.send(channel, body, flags)


## Services every peer and the server for a while, draining what arrives. The
## server node ticks itself from _process, so the frames have to actually pass.
func _pump(frames: int) -> void:
	for _i in range(frames):
		for entry in _peers:
			_service(entry)
		await process_frame


func _service(entry: Dictionary) -> void:
	var host: ENetConnection = entry["host"]
	while true:
		var ev := host.service(0)
		var kind: int = ev[0]
		if kind == ENetConnection.EVENT_NONE:
			break
		if kind != ENetConnection.EVENT_RECEIVE:
			continue
		var peer: ENetPacketPeer = ev[1]
		var channel: int = ev[3]
		var msg := Protocol.decode(peer.get_packet())
		var t := int(msg.get("t", -1))
		if t == Protocol.Msg.INIT:
			entry["wire_id"] = int(msg.get("id", 0))
		elif t == Protocol.Msg.JOIN_ERROR:
			print("    (%s refused: %s)" % [entry["name"], msg.get("reason", "?")])
		elif t == Protocol.Msg.VOICE_DATA:
			entry["voice"].append(msg)
			if channel != Protocol.CH_BULK:
				entry["off_channel"] = int(entry["off_channel"]) + 1


func _only_instance() -> GameInstance:
	var registry: GameRegistry = _server.get_registry()
	for gid: String in registry.instances:
		return registry.instances[gid]
	return null


## Resolves each peer's 64-bit participant id by callsign, since the id it was
## told over the wire is truncated and will not match a dictionary key.
func _resolve_server_ids(inst: GameInstance) -> void:
	for pid: int in inst.participants:
		var p: Participant = inst.participants[pid]
		if p.is_bot:
			continue
		for entry in _peers:
			if str(entry["name"]) == p.display_name:
				entry["server_id"] = pid


func _seat(inst: GameInstance, entry: Dictionary, team: int, alive: bool) -> void:
	var id := int(entry["server_id"])
	# Loud rather than silent: a no-op here reads downstream as "everyone is
	# dead", which every routing assertion then passes for the wrong reason.
	if id == 0 or not inst.participants.has(id):
		_ok("seat %s (id resolved)" % entry["name"], false)
		return
	(inst.participants[id] as Participant).team = team
	var pawn: ServerPawn = inst.pawns.get(id)
	if pawn == null:
		pawn = ServerPawn.new()
		pawn.participant_id = id
		pawn.position = Vector3(float(absi(id) % 10), 1.0, 0.0)
		inst.pawns[id] = pawn
	pawn.alive = alive
	pawn.protected_until = 0.0


func _frame() -> PackedByteArray:
	var samples := PackedInt32Array()
	for i in range(Protocol.VOICE_FRAME_SAMPLES):
		samples.append(int(sin(float(i) / 8000.0 * TAU * 440.0) * 9000.0))
	return VoiceCodec.encode(samples)


func _clear() -> void:
	for entry in _peers:
		(entry["voice"] as Array).clear()


func _count(entry: Dictionary) -> int:
	return (entry["voice"] as Array).size()


## Matches on the wire id, which is what VOICE_DATA carries.
func _from(listener: Dictionary, speaker: Dictionary) -> int:
	var n := 0
	for msg: Dictionary in listener["voice"]:
		if int(msg.get("speaker_id", 0)) == int(speaker["wire_id"]):
			n += 1
	return n


func _liveness_is(inst: GameInstance, entry: Dictionary, want: bool) -> bool:
	var liveness := inst._voice_liveness()
	return bool(liveness.get(int(entry["server_id"]), not want)) == want


func _off_channel() -> int:
	var n := 0
	for entry in _peers:
		n += int(entry["off_channel"])
	return n
