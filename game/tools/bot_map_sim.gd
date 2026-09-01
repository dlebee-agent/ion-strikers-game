extends SceneTree

# Runs a bots-only match on every map and reports how far each bot actually
# gets. A bot that circles covers many metres but few cells.
# Run: godot --headless --path game --script res://tools/bot_map_sim.gd

const SECONDS := 45
var _frame := 0


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var maps: Array[String] = ["parkour"]
	maps.append_array(MapCatalog.list_community())
	for map_id in maps:
		_run(map_id)
	quit(0)
	return true


func _run(map_id: String) -> void:
	seed(20260901)
	var inst = GameInstance.new({
		"map_id": map_id, "mode": "classic", "bots": true, "bot_skill": "regular",
	})
	root.add_child(inst)
	inst.setup_map()
	# Bots only fill in around a human, so park one where it cannot matter.
	var human = Participant.new(1, "Tester", false)
	human.team = Protocol.TEAM_BLUE
	inst.participants[1] = human
	inst._manage_bots()
	inst._start_round()
	inst.pawns[1].position = Vector3(0.0, 500.0, 0.0)
	inst.pawns[1].protected_until = 1e9

	var dt := 1.0 / 60.0
	var travelled: Dictionary = {}
	var cells: Dictionary = {}
	var prev: Dictionary = {}
	var stuck: Dictionary = {}
	var kills := 0
	for i in SECONDS * 60:
		inst.tick(dt)
		inst.pawns[1].position = Vector3(0.0, 500.0, 0.0)
		inst.pawns[1].alive = true
		for pid: int in inst.pawns:
			if pid == 1:
				continue
			var pawn = inst.pawns[pid]
			if not pawn.alive:
				continue
			if not travelled.has(pid):
				travelled[pid] = 0.0
				cells[pid] = {}
			elif prev.has(pid):
				var hop: float = (pawn.position - (prev[pid] as Vector3)).length()
				travelled[pid] += hop
				var ai: Dictionary = inst.participants[pid].connection_session["ai"]
				if hop < 0.005 and (ai["wish"] as Vector3).length() > 0.5:
					stuck[pid] = int(stuck.get(pid, 0)) + 1
			prev[pid] = pawn.position
			(cells[pid] as Dictionary)[Vector2i(int(floor(pawn.position.x / 2.0)), int(floor(pawn.position.z / 2.0)))] = true
	for pid: int in inst.participants:
		kills += inst.participants[pid].kills

	print("== %s   bots %d   kills %d   round %d" % [map_id, travelled.size(), kills, inst.match_state.round_state])
	for pid: int in travelled:
		print("  bot %3d  travelled %6.1fm  cells(2m) %3d  stuck %4.1fs" % [
			pid, travelled[pid], (cells[pid] as Dictionary).size(), float(stuck.get(pid, 0)) / 60.0])
	inst.queue_free()
