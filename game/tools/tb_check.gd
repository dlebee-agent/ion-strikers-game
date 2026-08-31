extends SceneTree

# Throwaway harness for the .map parser and brush solver.
# Run: godot --headless --path game --script res://tools/tb_check.gd

const FIXTURES := "/Volumes/Workspaces/claude-learning/TrenchBroom/lib/TbAppLib/test/fixture"

# A real box as TrenchBroom writes it, Valve 220 UVs and all. Quake extents are
# (-32,144,16) to (-16,256,32), so 16 x 112 x 16 units.
const BOX := """
{
"mapversion" "220"
"classname" "worldspawn"
{
( -32 144 16 ) ( -32 145 16 ) ( -32 144 17 ) __TB_empty [ 0 -1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -32 144 16 ) ( -32 144 17 ) ( -31 144 16 ) __TB_empty [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -32 144 16 ) ( -31 144 16 ) ( -32 145 16 ) __TB_empty [ -1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -16 256 32 ) ( -16 257 32 ) ( -15 256 32 ) __TB_empty [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -16 224 32 ) ( -15 224 32 ) ( -16 224 33 ) __TB_empty [ -1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -16 256 32 ) ( -16 256 33 ) ( -16 257 32 ) __TB_empty [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
}
}
"""

# The same box in the older Quake texture layout, to prove both parse.
const BOX_STANDARD := """
{
"classname" "worldspawn"
{
( -32 144 16 ) ( -32 145 16 ) ( -32 144 17 ) STONE1 0 0 0 1 1
( -32 144 16 ) ( -32 144 17 ) ( -31 144 16 ) STONE1 0 0 0 1 1
( -32 144 16 ) ( -31 144 16 ) ( -32 145 16 ) STONE1 0 0 0 1 1
( -16 256 32 ) ( -16 257 32 ) ( -15 256 32 ) STONE1 0 0 0 1 1
( -16 224 32 ) ( -15 224 32 ) ( -16 224 33 ) STONE1 0 0 0 1 1
( -16 256 32 ) ( -16 256 33 ) ( -16 257 32 ) STONE1 0 0 0 1 1
}
}
"""

var _fails := 0


func _ok(label: String, got, want, tol := 0.001) -> void:
	var pass_: bool
	if got is float and want is float:
		pass_ = absf(got - want) <= tol
	elif got is Vector3 and want is Vector3:
		pass_ = (got - want).length() <= tol
	else:
		pass_ = got == want
	if not pass_:
		_fails += 1
	print("  %-46s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


func _initialize() -> void:
	var u := TbMap.UNIT_SCALE

	print("-- parsing a TrenchBroom box --")
	var m := TbParser.new().parse(BOX)
	_ok("no warnings", m.warnings, [] as Array[String])
	_ok("one entity", m.entities.size(), 1)
	_ok("it is worldspawn", m.worldspawn() != null, true)
	_ok("mapversion carried through", m.worldspawn().get_string("mapversion"), "220")
	_ok("one brush", m.brush_count(), 1)
	var brush: TbMap.Brush = m.worldspawn().brushes[0]
	_ok("six faces", brush.faces.size(), 6)
	_ok("read as Valve 220", brush.faces[0].valve, true)
	_ok("U axis converted to Godot space", brush.faces[0].u_axis, Vector3(0, 0, 1))

	print("-- solving it into geometry --")
	var solid := TbGeometry.solve(brush)
	_ok("solid is valid", solid.valid, true)
	_ok("six polygons", solid.faces.size(), 6)
	# The planes, not the points written on them, bound the brush: the fifth
	# plane sits at Quake y=224, so this is 16 x 80 x 16 units. Quake
	# (-32,144,16)..(-16,224,32) maps to Godot x[-32,-16] y[16,32] z[-224,-144].
	_ok("bounds position", solid.bounds.position, Vector3(-32, 16, -224) * u)
	_ok("bounds size", solid.bounds.size, Vector3(16, 16, 80) * u)
	var corners := 0
	for f: TbGeometry.FaceGeometry in solid.faces:
		corners += f.vertices.size()
	_ok("each face is a quad", corners, 24)

	print("-- normals point out of the solid --")
	var centre := solid.bounds.position + solid.bounds.size * 0.5
	var all_out := true
	for f: TbGeometry.FaceGeometry in solid.faces:
		if f.plane.distance_to(centre) > -0.0001:
			all_out = false
	_ok("every face plane has the centre behind it", all_out, true)

	print("-- the older texture layout --")
	var std := TbParser.new().parse(BOX_STANDARD)
	_ok("parses without warnings", std.warnings, [] as Array[String])
	var std_brush: TbMap.Brush = std.worldspawn().brushes[0]
	_ok("not flagged as Valve", std_brush.faces[0].valve, false)
	_ok("texture name kept", std_brush.faces[0].texture, "STONE1")
	_ok("solves to the same box", TbGeometry.solve(std_brush).bounds.size, Vector3(16, 16, 80) * u)

	print("-- it drives the collider --")
	var world := CollisionWorld.new()
	world.add_brush(solid.planes, solid.bounds)
	world.build()
	var res := TraceResult.new()
	# Fire across the box from outside; it must stop at the near face.
	var y := centre.y
	world.raycast(Vector3(-2.0, y, centre.z), Vector3(2.0, y, centre.z), res)
	_ok("ray stops at the box", res.hit(), true)
	_ok("hit on the -X face", res.end_pos.x, -32.0 * u, 0.01)

	print("-- real TrenchBroom fixtures --")
	var checked := 0
	var failed := 0
	for name in ["ui/ExtrudeTool/splitBrushes.map", "ui/ExtrudeTool/findDragFaces_noCoplanarFaces.map",
			"ui/ExtrudeTool/findDragFaces_twoCoplanarFaces.map", "ui/MapDocument/emptyValveMap.map"]:
		var path := "%s/%s" % [FIXTURES, name]
		if not FileAccess.file_exists(path):
			print("    (missing %s)" % name)
			continue
		var fm := TbParser.new().parse_file(path)
		checked += 1
		var solids := TbGeometry.solve_all(_all_brushes(fm), fm.warnings)
		var bad := fm.warnings.size()
		if bad > 0:
			failed += 1
			print("    %s: %d entities, %d brushes, %d solids, warnings=%s" % [
				name, fm.entities.size(), fm.brush_count(), solids.size(), fm.warnings])
		else:
			print("    %s: %d entities, %d brushes, %d solids" % [
				name, fm.entities.size(), fm.brush_count(), solids.size()])
	_ok("fixtures were found", checked > 0, true)
	_ok("every fixture parsed and solved cleanly", failed, 0)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)


func _all_brushes(m: TbMap) -> Array:
	var out: Array = []
	for e: TbMap.Entity in m.entities:
		for b: TbMap.Brush in e.brushes:
			out.append(b)
	return out
