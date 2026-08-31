extends SceneTree

# Throwaway harness for UVs, materials and mesh winding.
# Run: godot --headless --path game --script res://tools/tb_render_check.gd

const BOX := """
{
"mapversion" "220"
"classname" "worldspawn"
{
( -32 144 16 ) ( -32 145 16 ) ( -32 144 17 ) arena_wall [ 0 -1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -32 144 16 ) ( -32 144 17 ) ( -31 144 16 ) arena_wall [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -32 144 16 ) ( -31 144 16 ) ( -32 145 16 ) ion/floor [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -16 256 32 ) ( -16 257 32 ) ( -15 256 32 ) ion/accent [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -16 224 32 ) ( -15 224 32 ) ( -16 224 33 ) missing_tex [ -1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -16 256 32 ) ( -16 256 33 ) ( -16 257 32 ) __TB_empty [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
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
	print("  %-48s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


# Fraction of faces whose winding-derived normal matches the plane they lie in.
func _winding_match(solid: TbGeometry.Solid, reversed: bool) -> float:
	var matched := 0
	for face: TbGeometry.FaceGeometry in solid.faces:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ring := face.vertices
		for i in range(1, ring.size() - 1):
			var tri := [ring[0], ring[i], ring[i + 1]]
			if reversed:
				tri.reverse()
			for v: Vector3 in tri:
				st.add_vertex(v)
		# No set_normal, so this derives the normal purely from the winding.
		st.generate_normals()
		var arrays := st.commit_to_arrays()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if normals.size() > 0 and normals[0].dot(face.plane.normal) > 0.99:
			matched += 1
	return float(matched) / float(solid.faces.size())


func _initialize() -> void:
	var m := TbParser.new().parse(BOX)
	var solid := TbGeometry.solve(m.worldspawn().brushes[0])
	_ok("solid built", solid.valid, true)

	print("-- winding matches Godot's front face convention --")
	var forward := _winding_match(solid, false)
	var reversed := _winding_match(solid, true)
	print("    counter-clockwise as solved: %d%% of faces face out" % [forward * 100])
	print("    reversed:                    %d%% of faces face out" % [reversed * 100])
	# Exactly one of the two must be right, and TbMesh must be using it.
	var want_reverse := reversed > forward
	_ok("one winding is unambiguously correct", maxf(forward, reversed), 1.0)
	_ok("TbMesh.REVERSE_WINDING agrees", TbMesh.REVERSE_WINDING, want_reverse)

	print("-- UVs --")
	var wad := WadPack.load_file("res://maps/community/arena1.wad")
	_ok("test WAD loaded", wad.size(), 3)
	var mats := TbMaterials.new(wad)

	# The -X face spans Quake y 144..224, and its U axis runs along that span, so
	# 80 units across a 64 pixel texture at scale 1 is 1.25 of a tile.
	for face: TbGeometry.FaceGeometry in solid.faces:
		if face.source.texture != "arena_wall":
			continue
		if absf(face.plane.normal.x + 1.0) > 0.01:
			continue
		var lo := INF
		var hi := -INF
		for v: Vector3 in face.vertices:
			var uv := face.source.uv_for(v, Vector2(64, 64))
			lo = minf(lo, uv.x)
			hi = maxf(hi, uv.x)
		_ok("80 units spans 1.25 tiles of a 64px texture", hi - lo, 1.25, 0.01)
		break

	print("-- material resolution --")
	var from_wad := mats.resolve("arena_wall")
	_ok("WAD name gets its texture", from_wad["material"].albedo_texture != null, true)
	_ok("and its real pixel size", from_wad["size"], Vector2(64, 64))
	var builtin := mats.resolve("ion/accent")
	_ok("ion/ name gets a built-in", builtin["material"].emission_enabled, true)
	_ok("unknown ion/ name warns", mats.resolve("ion/nonesuch")["material"] != null, true)
	var before := mats.warnings.size()
	mats.resolve("missing_tex")
	_ok("a missing texture is reported once", mats.warnings.size(), before + 1)
	mats.resolve("missing_tex")
	_ok("and not reported again", mats.warnings.size(), before + 1)
	_ok("marker textures are skipped", TbMaterials.is_skipped("__TB_empty"), true)
	_ok("real textures are not", TbMaterials.is_skipped("arena_wall"), false)

	print("-- mesh --")
	var solids: Array[TbGeometry.Solid] = [solid]
	var mesh := TbMesh.build(solids, mats)
	# Five drawn faces: six on the box, less the one wearing __TB_empty.
	_ok("one surface per distinct texture", mesh.get_surface_count(), 4)
	var total := 0
	for i in mesh.get_surface_count():
		total += mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()
	# Each drawn quad fans into two triangles, so six vertices per face.
	_ok("five quads worth of vertices", total, 30)
	_ok("mesh has real bounds", mesh.get_aabb().size.length() > 0.1, true)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
