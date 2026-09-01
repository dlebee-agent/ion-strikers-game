class_name BspImporter
extends RefCounted

# Turns a compiled GoldSrc BSP into the same TbLevel the .map importer produces,
# so the mesh, the collision world, spawns and the sky downstream never learn
# which format the level arrived in.
#
# This exists next to the .map path because a released Quake-lineage map almost
# always ships compiled and nothing else — there is no brush list left to solve.
# So the two halves of the level come from different places:
#
#   Drawing  reads the face lump directly. Faces are already planar polygons
#            with texture axes attached, which is less work than solving brushes,
#            not more.
#
#   Collision walks the BSP tree and emits one convex hull per solid leaf. Every
#            leaf is by construction the intersection of the half-spaces on its
#            path from the root, so the hulls are exact rather than approximated.
#            Crucially this reads hull 0, the unexpanded tree. Hulls 1 to 3 in
#            the clipnode lump are pre-swept for Half-Life's own 32x32x72 player
#            box and would leave this game's player floating off every surface —
#            which is the objection wad_pack.gd raises against taking collision
#            from a BSP, and the reason it is answered here rather than ignored.

const Bsp = preload("res://maps/bsp/bsp_file.gd")

# Quake spawn classes. Counter-Strike puts terrorists on info_player_deathmatch
# and counter-terrorists on info_player_start, which is why a CS map looks like
# it has no team spawns at all until you know that.
const TEAM_CLASSES := {
	"info_player_deathmatch": "red",
	"info_player_start": "blue",
	"info_player_team1": "blue",
	"info_player_team2": "red",
}

# Surfaces that are markers rather than geometry. The sky texture names a hole
# the engine fills with its own backdrop, so drawing it would paint a wall
# across the opening.
const SKIP_EXTRA := ["sky", "aaatrigger", "origin", "null"]

const TEAMS := ["blue", "red"]

# A BSP face already winds the way Godot wants, so unlike the .map path — where
# TbGeometry solves rings the other way round and TbMesh has to reverse them —
# the ring is emitted as read. tools/bsp_check.gd holds this down by deriving
# normals from both orientations and checking them against the plane each face
# was cut from; as-read agrees with 99.6% of faces, reversed with 0.2%.
const REVERSE_WINDING := false

# How far past the world model the sealing hulls reach. The outermost solid
# leaves are unbounded, so they need a lid to be finite; without real thickness
# a fast player can tunnel through it.
const SEAL_MARGIN := 128.0 * TbMap.UNIT_SCALE

# Below this a hull is a compile artefact rather than a wall.
const MIN_HULL_SIZE := 0.002

const PLANE_EPS := 0.0005


static func import_file(path: String) -> TbLevel:
	var level := TbLevel.new()
	level.id = path.get_file().get_basename()

	var bsp: Bsp = Bsp.load_file(path)
	level.warnings.append_array(bsp.warnings)
	if not bsp.ok():
		if bsp.warnings.is_empty():
			level.warnings.append("%s held no usable geometry" % path)
		return level

	var ents := _parse_entities(bsp.entities)
	var world := _find_worldspawn(ents)
	level.name = String(world.get("message", level.id))
	level.sky_id = String(world.get("skyname", world.get("sky", "parkour")))

	level.world = CollisionWorld.new()
	_build_collision(bsp, level)
	if level.world.brush_count() == 0:
		level.warnings.append("%s produced no solid hulls" % path)
		return level
	level.world.build()
	level.bounds = level.world.bounds
	level.arena = maxf(level.bounds.size.x, level.bounds.size.z) * 0.5

	var materials := TbMaterials.new(bsp.textures)
	level.mesh = _build_mesh(bsp, materials)
	level.warnings.append_array(materials.warnings)

	_read_spawns(ents, level)
	return level


# ── Drawing ──────────────────────────────────────────────────────────────

static func _build_mesh(bsp: Bsp, materials: TbMaterials) -> ArrayMesh:
	# One SurfaceTool per texture, so a level of a thousand faces sharing nine
	# textures costs nine draw calls.
	var groups: Dictionary = {}

	for fi in bsp.face_count:
		var b := fi * Bsp.FACE_STRIDE
		var ti: int = bsp.faces[b + Bsp.FACE_TEXINFO]
		if ti < 0 or ti >= bsp.texinfo_miptex.size():
			continue
		var mip: int = bsp.texinfo_miptex[ti]
		if mip < 0 or mip >= bsp.texture_names.size():
			continue
		var tex: String = bsp.texture_names[mip]
		if tex.is_empty() or TbMaterials.is_skipped(tex) or SKIP_EXTRA.has(tex):
			continue

		var ring := _face_ring(bsp, fi)
		if ring.size() < 3:
			continue

		if not groups.has(tex):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[tex] = st
		var size: Vector2 = materials.resolve(tex)["size"]
		_add_face(groups[tex], bsp, ti, ring, size)

	var mesh := ArrayMesh.new()
	for tex: String in groups:
		var st: SurfaceTool = groups[tex]
		# No set_normal anywhere above, so these come from the winding alone,
		# which is what makes tools/bsp_check.gd's winding audit meaningful.
		st.generate_normals()
		st.generate_tangents()
		var surface := st.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
			materials.resolve(tex)["material"])
	return mesh


# The vertex ring of a face, still in Quake units because the texture solve is
# defined against them. Surfedges are signed: a negative index means walk that
# edge backwards, which is how a ring stays continuous across shared edges.
static func _face_ring(bsp: Bsp, face: int) -> PackedVector3Array:
	var b := face * Bsp.FACE_STRIDE
	var first: int = bsp.faces[b + Bsp.FACE_FIRSTEDGE]
	var count: int = bsp.faces[b + Bsp.FACE_NUMEDGES]
	var out := PackedVector3Array()
	if count < 3 or first < 0 or first + count > bsp.surfedges.size():
		return out

	for i in count:
		var se: int = bsp.surfedges[first + i]
		var edge := absi(se)
		if edge * 2 + 1 >= bsp.edges.size():
			return PackedVector3Array()
		var vi: int = bsp.edges[edge * 2] if se >= 0 else bsp.edges[edge * 2 + 1]
		if vi < 0 or vi >= bsp.vertexes.size():
			return PackedVector3Array()
		out.append(bsp.vertexes[vi])
	return out


static func _add_face(st: SurfaceTool, bsp: Bsp, ti: int,
		ring: PackedVector3Array, size: Vector2) -> void:
	var s: Vector3 = bsp.texinfo_s[ti]
	var t: Vector3 = bsp.texinfo_t[ti]
	var sd: float = bsp.texinfo_sd[ti]
	var td: float = bsp.texinfo_td[ti]
	var w := maxf(1.0, size.x)
	var h := maxf(1.0, size.y)

	var n := ring.size()
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in n:
		var q := ring[i]
		points.append(TbMap.to_godot(q))
		uvs.append(Vector2((q.dot(s) + sd) / w, (q.dot(t) + td) / h))

	# Fan from the first vertex. BSP faces are convex by construction, so a fan
	# is safe and needs no ear clipping.
	for i in range(1, n - 1):
		var order := [0, i + 1, i] if REVERSE_WINDING else [0, i, i + 1]
		for k: int in order:
			st.set_uv(uvs[k])
			st.add_vertex(points[k])


# ── Collision ────────────────────────────────────────────────────────────

static func _build_collision(bsp: Bsp, level: TbLevel) -> void:
	var lo := TbMap.to_godot(bsp.world_mins)
	var hi := TbMap.to_godot(bsp.world_maxs)
	# The axis swap can put either corner low, so rebuild the box from extremes
	# rather than assuming mins stayed mins.
	var box := AABB(
		Vector3(minf(lo.x, hi.x), minf(lo.y, hi.y), minf(lo.z, hi.z)),
		Vector3(absf(hi.x - lo.x), absf(hi.y - lo.y), absf(hi.z - lo.z)))
	box = box.grow(SEAL_MARGIN)

	var planes: Array[Plane] = []
	_descend(bsp, bsp.headnode, planes, box, level, 0)


static func _descend(bsp: Bsp, node: int, planes: Array[Plane], box: AABB,
		level: TbLevel, depth: int) -> void:
	# A cycle in a corrupt tree would otherwise recurse until the stack gives up.
	if depth > 128 or node < 0 or node >= bsp.node_count:
		return
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return

	var b := node * Bsp.NODE_STRIDE
	var pi: int = bsp.nodes[b]
	if pi < 0 or pi >= bsp.planes_n.size():
		return
	var normal := TbMap.dir_to_godot(bsp.planes_n[pi])
	if normal.length_squared() < 0.5:
		return
	normal = normal.normalized()
	var dist: float = bsp.planes_d[pi] * TbMap.UNIT_SCALE

	# Front half: n·x >= d, so the hull's outward face points the other way.
	# Back half: n·x <= d, and the plane already faces out of it.
	for side in 2:
		var child: int = bsp.nodes[b + 1 + side]
		var front := side == 0
		var outward := Plane(-normal, -dist) if front else Plane(normal, dist)

		var next := planes.duplicate()
		next.append(outward)
		var sub := _split(box, normal, dist, front)

		if child >= 0:
			_descend(bsp, child, next, sub, level, depth + 1)
			continue

		var leaf := -child - 1
		if leaf < 0 or leaf >= bsp.leaf_contents.size():
			continue
		var contents: int = bsp.leaf_contents[leaf]
		if contents != Bsp.CONTENTS_SOLID and contents != Bsp.CONTENTS_SKY:
			continue
		_emit_hull(next, sub, level)


# Narrows `box` to the half of it the child occupies. Only axis-aligned planes
# can do this exactly; a sloped one hands the box down untouched, which is an
# over-approximation and therefore safe — the plane set still describes the hull
# exactly, and the box is only ever a broadphase bound.
static func _split(box: AABB, normal: Vector3, dist: float, front: bool) -> AABB:
	var axis := -1
	for i in 3:
		if absf(absf(normal[i]) - 1.0) < 0.001:
			axis = i
			break
	if axis == -1:
		return box

	var positive := normal[axis] > 0.0
	# n·x >= d on a positive normal is a floor for that axis; every other
	# combination of side and sign flips it once.
	var is_lower := positive == front
	var bound := dist / normal[axis]

	var lo := box.position
	var hi := box.end
	if is_lower:
		lo[axis] = maxf(lo[axis], bound)
	else:
		hi[axis] = minf(hi[axis], bound)
	if hi[axis] <= lo[axis]:
		return AABB()
	return AABB(lo, hi - lo)


static func _emit_hull(planes: Array[Plane], box: AABB, level: TbLevel) -> void:
	# Most of the path's planes never touch this leaf's box. Dropping them keeps
	# the hull small, which every later sweep pays for.
	var kept: Array[Plane] = []
	for p: Plane in planes:
		if _plane_bounds_box(p, box):
			kept.append(p)

	var tight := _tight_bounds(kept, box)
	if tight.size.x < MIN_HULL_SIZE and tight.size.y < MIN_HULL_SIZE \
			and tight.size.z < MIN_HULL_SIZE:
		return

	var index := level.world.add_brush(kept, tight)
	level.colliders.append(level.world.bounds_of(index))


# True when the plane actually cuts the box. The far corner along the outward
# normal is the last point to leave the half-space, so if even that one is
# inside, the plane is doing nothing here.
static func _plane_bounds_box(p: Plane, box: AABB) -> bool:
	var far := Vector3(
		box.end.x if p.normal.x > 0.0 else box.position.x,
		box.end.y if p.normal.y > 0.0 else box.position.y,
		box.end.z if p.normal.z > 0.0 else box.position.z)
	return p.distance_to(far) > PLANE_EPS


# The hull's real extent. When every remaining plane is axis-aligned the split
# box is already exact, which is the common case in Quake-lineage geometry and
# worth not paying for. Otherwise solve the polytope's corners: with the box's
# own six planes in the set the region is closed, so its vertices are the points
# where three planes meet that no plane excludes.
static func _tight_bounds(planes: Array[Plane], box: AABB) -> AABB:
	var sloped := false
	for p: Plane in planes:
		if not _axis_aligned(p.normal):
			sloped = true
			break
	if not sloped:
		return box

	var all: Array[Plane] = planes.duplicate()
	all.append(Plane(Vector3(1, 0, 0), box.end.x))
	all.append(Plane(Vector3(-1, 0, 0), -box.position.x))
	all.append(Plane(Vector3(0, 1, 0), box.end.y))
	all.append(Plane(Vector3(0, -1, 0), -box.position.y))
	all.append(Plane(Vector3(0, 0, 1), box.end.z))
	all.append(Plane(Vector3(0, 0, -1), -box.position.z))

	var n := all.size()
	var found := false
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var pt = all[i].intersect_3(all[j], all[k])
				if pt == null:
					continue
				var point: Vector3 = pt
				var inside := true
				for p: Plane in all:
					if p.distance_to(point) > PLANE_EPS:
						inside = false
						break
				if not inside:
					continue
				if not found:
					found = true
					lo = point
					hi = point
				else:
					lo = Vector3(minf(lo.x, point.x), minf(lo.y, point.y), minf(lo.z, point.z))
					hi = Vector3(maxf(hi.x, point.x), maxf(hi.y, point.y), maxf(hi.z, point.z))
	if not found:
		return box
	return AABB(lo, hi - lo)


static func _axis_aligned(n: Vector3) -> bool:
	for i in 3:
		if absf(absf(n[i]) - 1.0) < 0.001:
			return true
	return false


# ── Entities ─────────────────────────────────────────────────────────────

# The entity lump is the map's text source for everything that is not geometry:
# blocks of quoted key/value pairs. Anything malformed is skipped rather than
# taken as a reason to refuse a level that is otherwise fine.
static func _parse_entities(text: String) -> Array:
	var out: Array = []
	var current: Dictionary = {}
	var key := ""
	var have_key := false
	var in_block := false

	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == "{":
			in_block = true
			current = {}
			have_key = false
			i += 1
			continue
		if c == "}":
			if in_block and not current.is_empty():
				out.append(current)
			in_block = false
			i += 1
			continue
		if c != "\"":
			i += 1
			continue

		var close := text.find("\"", i + 1)
		if close == -1:
			break
		var token := text.substr(i + 1, close - i - 1)
		i = close + 1
		if not in_block:
			continue
		if have_key:
			current[key] = token
			have_key = false
		else:
			key = token
			have_key = true
	return out


static func _find_worldspawn(ents: Array) -> Dictionary:
	for e: Dictionary in ents:
		if String(e.get("classname", "")) == "worldspawn":
			return e
	return {}


static func _read_spawns(ents: Array, level: TbLevel) -> void:
	for team: String in TEAMS:
		level.spawns[team] = []
	var neutral: Array = []

	for e: Dictionary in ents:
		var cls := String(e.get("classname", ""))
		if not TEAM_CLASSES.has(cls):
			continue
		if not e.has("origin"):
			level.warnings.append("%s has no origin, skipped" % cls)
			continue
		var entry := {
			"position": TbMap.to_godot(_parse_vector(String(e["origin"]))),
			# Quake measures its angle counter-clockwise from +X; this game's
			# yaw zero faces -Z, which is Quake's +Y, so the two are a quarter
			# turn apart. Same convention the .map importer uses.
			"yaw": _parse_float(e.get("angle", "90"), 90.0) - 90.0,
		}
		neutral.append(entry)
		(level.spawns[TEAM_CLASSES[cls]] as Array).append(entry)

	# A map with only one kind of spawn point still has to be playable, so a
	# side that got none falls back to every point on the map.
	for team: String in TEAMS:
		if (level.spawns[team] as Array).is_empty():
			level.spawns[team] = neutral.duplicate()

	if level.spawn_count() == 0:
		level.warnings.append("no spawn points of any kind")


static func _parse_vector(s: String) -> Vector3:
	var parts := s.split(" ", false)
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


static func _parse_float(v: Variant, fallback: float) -> float:
	var s := String(v).strip_edges()
	if s.is_empty() or not s.is_valid_float():
		return fallback
	return s.to_float()
