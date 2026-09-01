extends SceneTree

# Drives a live GameInstance and checks that leaving the map kills, that
# staying on it does not, and that the death lands like any other: counted,
# reported as the void, and respawned in deathmatch.
# Run: godot --headless --path game --script res://tools/void_kill_check.gd

var failed := 0
var _events: Array[Dictionary] = []


func _initialize() -> void:
	_case("under the map", "skydeck", Vector3(0.0, -40.0, 0.0), true)
	_case("past the side wall", "skydeck", Vector3(40.0, 1.0, 0.0), true)
	_case("past the end wall", "skydeck", Vector3(0.0, 1.0, 40.0), true)
	# Grid arena's floor is 41.2 x 60: a spot outside a square read of its
	# arena size, but on the map, and it must survive.
	_case("wide but on the floor", "skydeck", Vector3(0.0, 3.5, -28.0), false)
	_case("on the sky ring", "skydeck", Vector3(5.8, 7.0, 0.0), false)
	_case("under the map", "parkour", Vector3(0.0, -40.0, 0.0), true)
	_case("on the floor", "parkour", Vector3(0.0, 0.0, 0.0), false)

	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


func _case(label: String, map_id: String, at: Vector3, want_dead: bool) -> void:
	var inst := GameInstance.new({
		"map_id": map_id, "mode": "dm", "bots": false, "kills": 999,
	})
	root.add_child(inst)
	inst.setup_map()
	inst.match_state.round_state = Protocol.RS_ACTIVE

	_events = []
	inst.event_broadcast.connect(_on_event)

	var p := Participant.new(1, "Tester", false)
	p.team = Protocol.TEAM_BLUE
	inst.participants[1] = p
	inst._spawn_pawn(1)
	(inst.pawns[1] as ServerPawn).position = at

	inst.tick(1.0 / 60.0)

	var pawn: ServerPawn = inst.pawns[1]
	var ok := pawn.alive != want_dead
	print("  %-22s %-11s %s%s" % [
		label, map_id,
		"died" if not pawn.alive else "survived",
		"" if ok else "   FAIL (wanted %s)" % ("death" if want_dead else "survival")])
	if not ok:
		failed += 1

	if want_dead:
		_expect(label, p.deaths == 1, "death counted")
		_expect(label, pawn.respawn_at > 0.0, "deathmatch respawn scheduled")
		_expect(label, _saw_void_hit(), "kill feed carries CAUSE_VOID")

	inst.event_broadcast.disconnect(_on_event)
	inst.queue_free()


func _on_event(_channel: int, data: PackedByteArray, _except_id: int) -> void:
	_events.append(Protocol.decode(data))


func _saw_void_hit() -> bool:
	for e in _events:
		if int(e.get("t", -1)) == Protocol.Msg.HIT \
				and int(e.get("cause", -1)) == Protocol.CAUSE_VOID \
				and bool(e.get("killed", false)):
			return true
	return false


func _expect(label: String, cond: bool, what: String) -> void:
	if cond:
		return
	print("    FAIL: %s — %s" % [label, what])
	failed += 1
