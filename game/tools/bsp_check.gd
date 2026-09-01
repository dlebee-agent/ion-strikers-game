extends SceneTree

# Audits the GoldSrc BSP importer against a real level.
# Run: godot --headless --path game --script res://tools/bsp_check.gd
#
# Three things can be wrong in ways that still "load": the mesh can be inside
# out, the hulls can be inverted so the map is solid, and the import can be slow
# enough to blow the connect handshake. Each gets a hard check here.

const Bsp = preload("res://maps/bsp/bsp_file.gd")

# client_build_check.gd's budget, for the same reason: a slower build stalls the
# handshake past its timeout.
const BUDGET_MS := 2000

var failed := 0


func _initialize() -> void:
	for map_id in MapCatalog.list_community():
		if MapCatalog.map_path(map_id).get_extension().to_lower() == "bsp":
			_audit(map_id)
	print("\nFAILURES: ", failed)
	quit(1 if failed > 0 else 0)


func _fail(msg: String) -> void:
	print("  FAIL: ", msg)
	failed += 1


func _audit(map_id: String) -> void:
	print("== ", map_id)
	var path := MapCatalog.map_path(map_id)

	var t0 := Time.get_ticks_msec()
	var level := MapCatalog.load_community(map_id)
	var ms := Time.get_ticks_msec() - t0
	print("  import        %6d ms  (budget %d)" % [ms, BUDGET_MS])
	if ms > BUDGET_MS:
		_fail("import takes %d ms, over the handshake budget" % ms)

	if not level.ok():
		_fail("level not ok(): world=%s brushes=%d spawns=%d"
			% [level.world != null,
				level.world.brush_count() if level.world else 0,
				level.spawn_count()])
		for w in level.warnings:
			print("     warn: ", w)
		return

	print("  name          %s" % level.name)
	print("  sky           %s" % level.sky_id)
	print("  hulls         %d" % level.world.brush_count())
	print("  surfaces      %d" % level.mesh.get_surface_count())
	print("  spawns        blue=%d red=%d"
		% [(level.spawns["blue"] as Array).size(), (level.spawns["red"] as Array).size()])
	print("  bounds        %.1f x %.1f x %.1f m"
		% [level.bounds.size.x, level.bounds.size.y, level.bounds.size.z])
	print("  arena         %.1f" % level.arena)
	for w in level.warnings:
		print("     warn: ", w)

	_check_winding(path)
	_check_solidity(level)
	_check_spawns_clear(level)
	_check_sky(level)
	_check_playable(map_id, level)


# Every face knows the plane it was cut from, so the emitted winding can be
# checked rather than eyeballed: derive a normal from the triangle we actually
# build and compare it with the plane the face sits on.
func _check_winding(path: String) -> void:
	var bsp: Bsp = Bsp.load_file(path)
	var forward := _winding_match(bsp, false)
	var reversed := _winding_match(bsp, true)
	print("  winding       as-read %.1f%% face out, reversed %.1f%%"
		% [forward * 100.0, reversed * 100.0])

	var want_reverse := reversed > forward
	var best := maxf(forward, reversed)
	if best < 0.99:
		_fail("neither winding orientation faces out (%.1f%% / %.1f%%)"
			% [forward * 100.0, reversed * 100.0])
		return
	if want_reverse != BspImporter.REVERSE_WINDING:
		_fail("mesh is inside out; set BspImporter.REVERSE_WINDING = %s"
			% want_reverse)


# Fraction of faces whose winding-derived normal agrees with the plane the face
# was cut from. SurfaceTool.generate_normals applies Godot's own front-face
# convention, so this asks the engine rather than restating the rule.
func _winding_match(bsp: Bsp, reversed: bool) -> float:
	var matched := 0
	var total := 0
	for fi in bsp.face_count:
		var b := fi * Bsp.FACE_STRIDE
		var pi: int = bsp.faces[b + Bsp.FACE_PLANE]
		if pi < 0 or pi >= bsp.planes_n.size():
			continue
		var expected := TbMap.dir_to_godot(bsp.planes_n[pi]).normalized()
		if bsp.faces[b + Bsp.FACE_SIDE] != 0:
			expected = -expected

		var ring := BspImporter._face_ring(bsp, fi)
		if ring.size() < 3:
			continue
		var pts: Array[Vector3] = []
		for q: Vector3 in ring:
			pts.append(TbMap.to_godot(q))

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(1, pts.size() - 1):
			var tri: Array = [pts[0], pts[i], pts[i + 1]]
			if reversed:
				tri.reverse()
			for v: Vector3 in tri:
				st.add_vertex(v)
		st.generate_normals()
		var normals: PackedVector3Array = st.commit_to_arrays()[Mesh.ARRAY_NORMAL]
		total += 1
		if normals.size() > 0 and normals[0].dot(expected) > 0.99:
			matched += 1
	return 0.0 if total == 0 else float(matched) / float(total)


# An inverted hull set makes the whole map solid, which reads as "the level
# loaded" right up until nobody can move. Sample the playable volume.
func _check_solidity(level: TbLevel) -> void:
	var half := Vector3(0.3, 0.9, 0.3)
	var inside := 0
	var probes := 0
	for team: String in ["blue", "red"]:
		for entry: Dictionary in level.spawns[team]:
			var p: Vector3 = entry["position"]
			# A metre above the spawn is open air in any sane map.
			probes += 1
			if level.world.box_overlaps(p + Vector3(0, 1.0, 0), half):
				inside += 1
	print("  open at spawn %d/%d clear" % [probes - inside, probes])
	if inside > 0:
		_fail("%d of %d spawn probes are inside a hull" % [inside, probes])

	# And the opposite mistake: hulls that enclose nothing leave a map with no
	# floor. Well below the world should be solid.
	var below := level.bounds.position + Vector3(level.bounds.size.x * 0.5,
		0.05, level.bounds.size.z * 0.5)
	if not level.world.box_overlaps(below, Vector3(0.1, 0.1, 0.1)):
		_fail("the volume under the map is not solid; hulls may be inverted")
	else:
		print("  sealed        under-map volume is solid")


func _check_spawns_clear(level: TbLevel) -> void:
	# A spawn that starts embedded pushes the player through the floor on the
	# first depenetration pass, so it is worth knowing before a match does it.
	var half := Vector3(0.3, 0.9, 0.3)
	var bad := 0
	for team: String in ["blue", "red"]:
		for entry: Dictionary in level.spawns[team]:
			var p: Vector3 = entry["position"] + Vector3(0, half.y + 0.05, 0)
			if level.world.box_overlaps(p, half):
				bad += 1
	if bad > 0:
		_fail("%d spawn points stand inside geometry" % bad)
	else:
		print("  spawn bodies  all clear of geometry")


# A level that names an unbaked sky used to fall through to the procedural
# generator, which takes the better part of a minute and runs in the middle of
# a connect. Confirm this one is baked rather than borrowed.
func _check_sky(level: TbLevel) -> void:
	var baked := MapCatalog.has_baked_sky(level.sky_id)
	if baked:
		print("  sky           '%s' is baked" % level.sky_id)
	else:
		_fail("sky '%s' is not baked; it would borrow the fallback set"
			% level.sky_id)


# Importing clean is not the same as playing. Run a real GameInstance on the
# level with bots and see whether anyone can stand up, walk, and stay in the
# world — a map with inverted hulls imports perfectly and then drops everybody
# through the floor on the first tick.
func _check_playable(map_id: String, level: TbLevel) -> void:
	var inst := GameInstance.new({
		"map_id": map_id, "mode": "arena", "bots": true, "rounds": 99,
	})
	root.add_child(inst)
	inst.setup_map()

	for i in 6:
		var bot := Participant.new(-1 - i, "BOT %d" % i, true)
		bot.team = Protocol.TEAM_BLUE if i < 3 else Protocol.TEAM_RED
		inst.participants[bot.id] = bot
		inst.bot_director.init_ai(bot)
		inst._spawn_pawn(bot.id)
	inst.match_state.round_state = Protocol.RS_ACTIVE

	var start: Dictionary = {}
	for pid: int in inst.pawns:
		start[pid] = (inst.pawns[pid] as ServerPawn).position

	var floor_y := level.bounds.position.y
	var escaped := 0
	for i in 600:  # 10 seconds
		inst.tick(1.0 / 60.0)
		for pid: int in inst.pawns:
			var p: ServerPawn = inst.pawns[pid]
			if p.alive and p.position.y < floor_y - 5.0:
				escaped += 1

	var moved := 0.0
	var standing := 0
	for pid: int in inst.pawns:
		var p: ServerPawn = inst.pawns[pid]
		moved += p.position.distance_to(start[pid])
		if p.grounded:
			standing += 1

	print("  playable      %d/%d bots grounded, %.0f m walked in 10 s"
		% [standing, inst.pawns.size(), moved])
	if escaped > 0:
		_fail("a bot fell out of the world; hulls may not seal")
	if moved < 5.0:
		_fail("bots did not move; the map may be solid")
	if standing == 0:
		_fail("no bot found ground to stand on")
	inst.queue_free()
