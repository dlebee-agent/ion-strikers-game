extends SceneTree

# Wire checks for the HELLO handshake: the map list survives a round trip,
# and a message type from a newer build than the decoder falls through to an
# ignorable stub instead of an error, which is what lets a v6 client shrug
# off the HELLO a v7 server opens with.
# Run: godot --headless --path game --script res://tools/protocol_check.gd

var failed := 0


func _initialize() -> void:
	var maps := ["parkour", "grid_arena", "community/arena1"]
	var decoded := Protocol.decode(Protocol.encode_hello(maps))
	_check(int(decoded.get("t", -1)) == Protocol.Msg.HELLO, "hello type")
	_check(int(decoded.get("v", 0)) == Protocol.PROTOCOL_VERSION, "hello version")
	_check(Array(decoded.get("maps", [])) == Array(maps), "hello map list")

	var empty := Protocol.decode(Protocol.encode_hello([]))
	_check(Array(empty.get("maps", ["x"])).is_empty(), "hello with no maps")

	# The score bar clock rides the snap, so it has to survive the trip
	# alongside the player list rather than only on its own.
	var snap := Protocol.decode(Protocol.encode_snap(
		3, 4, 2, Protocol.RS_ACTIVE, Protocol.MODE_CLASSIC, 50, 10, [],
		95, Protocol.CLOCK_DOWN))
	_check(int(snap.get("clock_s", -1)) == 95, "snap carries the clock")
	_check(int(snap.get("clock_mode", -1)) == Protocol.CLOCK_DOWN, "snap carries the clock mode")
	_check(int(snap.get("round_num", -1)) == 2, "snap fields after the clock still read")

	# A drawn round: no winner, and a reason that is not elimination.
	var drawn := Protocol.decode(Protocol.encode_round_end(
		Protocol.TEAM_NONE, 5, 5, false, false, 7, Protocol.END_TIME))
	_check(int(drawn.get("winner", -1)) == Protocol.TEAM_NONE, "round end carries a draw")
	_check(int(drawn.get("reason", -1)) == Protocol.END_TIME, "round end carries its reason")
	_check(int(drawn.get("round_num", -1)) == 7, "round end number survives")

	# A type value one past everything this build knows: decode must hand back
	# just the header, the shape older builds see when a HELLO arrives.
	var b := StreamPeerBuffer.new()
	b.big_endian = false
	b.put_u8(Protocol.Msg.HELLO + 1)
	b.put_u8(0)
	b.put_u8(99)
	var unknown := Protocol.decode(b.data_array)
	_check(unknown.keys().size() == 2 and unknown.has("t") and unknown.has("flags"),
		"unknown type decodes to an ignorable stub")

	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


func _check(cond: bool, label: String) -> void:
	print("  %s: %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		failed += 1
