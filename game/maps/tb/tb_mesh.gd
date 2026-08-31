class_name TbMesh
extends RefCounted

# Builds the drawable mesh for a set of solved brushes.
#
# Faces are grouped by material rather than by brush, so a level of several
# hundred brushes sharing a handful of textures costs a handful of draw calls
# instead of several hundred.

# Godot treats a clockwise ring as front facing when seen from the front, and
# TbGeometry winds counter-clockwise about the outward normal, so the ring is
# emitted in reverse. tools/tb_render_check.gd pins this down by asking
# SurfaceTool to derive normals from the winding and comparing them against the
# planes they came from.
const REVERSE_WINDING := true


# Builds one ArrayMesh from every face of every solid. `materials` resolves
# texture names; faces carrying a marker texture are left out of the mesh.
static func build(solids: Array[TbGeometry.Solid], materials: TbMaterials) -> ArrayMesh:
	# Texture name to the SurfaceTool accumulating it.
	var groups: Dictionary = {}

	for solid: TbGeometry.Solid in solids:
		for face: TbGeometry.FaceGeometry in solid.faces:
			var texture := face.source.texture
			if TbMaterials.is_skipped(texture):
				continue
			var key := texture.to_lower()
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = st
			_add_face(groups[key], face, materials.resolve(texture)["size"])

	var mesh := ArrayMesh.new()
	for key: String in groups:
		var st: SurfaceTool = groups[key]
		st.generate_tangents()
		var surface := st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		var index := mesh.get_surface_count() - 1
		mesh.surface_set_material(index, materials.resolve(key)["material"])
		mesh.surface_set_name(index, key)
	return mesh


# Fans a convex face into triangles. A convex polygon fans from any one of its
# corners without any triangle falling outside it, so no ear clipping is needed.
static func _add_face(st: SurfaceTool, face: TbGeometry.FaceGeometry,
		texture_size: Vector2) -> void:
	var ring := face.vertices
	var n := ring.size()
	if n < 3:
		return

	var normal := face.plane.normal
	for i in range(1, n - 1):
		var tri := [ring[0], ring[i], ring[i + 1]]
		if REVERSE_WINDING:
			tri.reverse()
		for v: Vector3 in tri:
			st.set_normal(normal)
			st.set_uv(face.source.uv_for(v, texture_size))
			st.add_vertex(v)


# Collision brushes for the same solids. Faces marked as non-drawing still
# collide, which is how a clip brush does its job: invisible, but solid.
static func add_to_world(solids: Array[TbGeometry.Solid], world: CollisionWorld) -> void:
	for solid: TbGeometry.Solid in solids:
		world.add_brush(solid.planes, solid.bounds)
