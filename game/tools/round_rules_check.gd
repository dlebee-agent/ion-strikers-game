extends SceneTree

# Drives live matches through every way a round can finish: a wipe, a team
# emptying out, the clock running out ahead / level / behind, and the
# deathmatch match clock. Also pins down what must NOT end a round, since
# a lobby that awards rounds while it is still filling is the failure mode
# these rules invite.
# Run: godot --headless --path game --script res://tools/round_rules_check.gd

const DT := 1.0 / 60.0

var failed := 0
var _ends: Array[Dictionary] = []


func _initialize() -> void:
	_wipe_ends_round()
	_leaving_ends_round()
	_lone_team_waits()
	_clock_decides_on_who_is_left()
	_clock_draw_when_level()
	_dm_has_no_round_clock()
	_dm_match_clock_ends_it()
	_clock_counts_down()

	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


# ── cases ────────────────────────────────────────────────────────────────

func _wipe_ends_round() -> void:
	var inst := _match("classic")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	inst.tick(DT)
	_kill(inst, 2)
	inst.tick(DT)
	_ended("wipe", Protocol.TEAM_BLUE, Protocol.END_ELIMINATION)
	_expect("wipe", inst.match_state.score_blue == 1, "blue scored")
	_free(inst)


func _leaving_ends_round() -> void:
	var inst := _match("classic")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	inst.tick(DT)
	# Off to the stands, which is the case a wipe check alone never sees:
	# nobody died, and the side simply has no one on it any more.
	inst.participants[2].team = Protocol.TEAM_NONE
	inst.tick(DT)
	_ended("forfeit", Protocol.TEAM_BLUE, Protocol.END_FORFEIT)
	_free(inst)


func _lone_team_waits() -> void:
	var inst := _match("classic")
	_join(inst, 1, Protocol.TEAM_BLUE)
	# Two full round lengths with nobody to play against.
	_run(inst, MatchState.ROUND_TIME_S * 2.0)
	_expect("lone team", _ends.is_empty(), "no round awarded while a side is empty")
	_expect("lone team", inst.match_state.score_blue == 0, "no score")
	print("  %-10s %d rounds awarded over two round lengths" % ["lone team", _ends.size()])
	_free(inst)


func _clock_decides_on_who_is_left() -> void:
	var inst := _match("classic")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_RED)
	inst.tick(DT)
	_kill(inst, 2)
	# Wounded before the clock expires, not after: by then the round is
	# already decided and the damage would land too late to count.
	# One a side leaves it down to health.
	(inst.pawns[1] as ServerPawn).hp = 40
	(inst.pawns[3] as ServerPawn).hp = 90
	_run(inst, MatchState.ROUND_TIME_S + 1.0)
	_ended("clock", Protocol.TEAM_RED, Protocol.END_TIME)
	_free(inst)


func _clock_draw_when_level() -> void:
	var inst := _match("classic")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_run(inst, MatchState.ROUND_TIME_S + 1.0)
	_ended("draw", Protocol.TEAM_NONE, Protocol.END_TIME)
	_expect("draw", inst.match_state.score_blue == 0 and inst.match_state.score_red == 0,
		"a draw scores for neither side")
	_free(inst)


func _dm_has_no_round_clock() -> void:
	var inst := _match("dm")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_run(inst, MatchState.ROUND_TIME_S + 5.0)
	_expect("dm", _ends.is_empty(), "no round ends on the classic round clock")
	_expect("dm", inst.match_state.round_state == Protocol.RS_ACTIVE, "still running")
	print("  %-10s %d rounds ended past a classic round length" % ["dm", _ends.size()])
	_free(inst)


func _dm_match_clock_ends_it() -> void:
	var inst := _match("dm")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	inst.match_state.score_red = 3
	_run(inst, MatchState.DM_TIME_S + 2.0)
	_ended("dm clock", Protocol.TEAM_RED, Protocol.END_TIME)
	_expect("dm clock", inst.match_state.round_state == Protocol.RS_OVER, "match over")
	_free(inst)


func _clock_counts_down() -> void:
	var inst := _match("classic")
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	inst.tick(DT)
	var first := _snap_clock(inst)
	_expect("countdown", first[1], "classic clock counts down")
	_expect("countdown", first[0] <= int(MatchState.ROUND_TIME_S),
		"starts at the round length")
	_run(inst, 10.0)
	var later := _snap_clock(inst)
	_expect("countdown", later[0] < first[0],
		"reads lower ten seconds in (%d then %d)" % [first[0], later[0]])
	print("  %-10s %d then %d, counting %s" % [
		"countdown", first[0], later[0], "down" if later[1] else "up"])
	_free(inst)


# ── harness ──────────────────────────────────────────────────────────────

func _match(mode: String) -> GameInstance:
	var inst := GameInstance.new({
		"map_id": "grid_arena", "mode": mode, "bots": false,
		"kills": 999, "rounds": 99,
	})
	root.add_child(inst)
	inst.setup_map()
	inst.match_state.round_state = Protocol.RS_ACTIVE
	_ends = []
	inst.event_broadcast.connect(_on_event)
	return inst


func _join(inst: GameInstance, pid: int, team: int) -> void:
	var p := Participant.new(pid, "P%d" % pid, false)
	p.team = team
	inst.participants[pid] = p
	inst._spawn_pawn(pid)


func _kill(inst: GameInstance, pid: int) -> void:
	inst._apply_damage(pid, 0, 1000, false, Protocol.CAUSE_VOID)


func _run(inst: GameInstance, seconds: float) -> void:
	var steps := int(seconds / DT)
	for i in steps:
		inst.tick(DT)


func _snap_clock(inst: GameInstance) -> Array:
	var snap := Protocol.decode(inst.build_snap())
	return [int(snap.get("clock_s", -1)), bool(snap.get("clock_down", false))]


func _free(inst: GameInstance) -> void:
	inst.event_broadcast.disconnect(_on_event)
	inst.queue_free()


func _on_event(_channel: int, data: PackedByteArray, _except_id: int) -> void:
	var msg := Protocol.decode(data)
	if int(msg.get("t", -1)) == Protocol.Msg.ROUND_END:
		_ends.append(msg)


func _ended(label: String, winner: int, reason: int) -> void:
	if _ends.is_empty():
		print("  %-10s FAIL: the round never ended" % label)
		failed += 1
		return
	var e: Dictionary = _ends[0]
	var got_w := int(e.get("winner", -1))
	var got_r := int(e.get("reason", -1))
	var ok := got_w == winner and got_r == reason
	print("  %-10s winner=%s reason=%s%s" % [
		label, _team(got_w), _reason(got_r),
		"" if ok else "   FAIL (wanted %s / %s)" % [_team(winner), _reason(reason)]])
	if not ok:
		failed += 1


func _expect(label: String, cond: bool, what: String) -> void:
	if cond:
		return
	print("    FAIL: %s — %s" % [label, what])
	failed += 1


static func _team(t: int) -> String:
	match t:
		Protocol.TEAM_BLUE: return "blue"
		Protocol.TEAM_RED: return "red"
		Protocol.TEAM_NONE: return "draw"
		_: return "?"


static func _reason(r: int) -> String:
	match r:
		Protocol.END_ELIMINATION: return "elimination"
		Protocol.END_TIME: return "time"
		Protocol.END_FORFEIT: return "forfeit"
		_: return "?"
