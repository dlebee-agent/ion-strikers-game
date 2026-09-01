class_name MapBuilder
extends RefCounted

const _SkyCubemap := preload("res://maps/sky_cubemap.gd")
const _SkyDrift := preload("res://maps/sky_drift.gd")

const LAYER_WORLD := 1
const LAYER_PAWNS := 2

# Builds a compiled map into meshes + colliders.  Client calls build_visual()
# for the full scene; server only needs build_colliders() for AABB physics.


static func build_colliders(compiled: Dictionary) -> Array[AABB]:
	var out: Array[AABB] = []
	var half := floor_half(compiled)
	# Floor slab: top at y=0
	out.append(AABB(Vector3(-half.x, -2.0, -half.y), Vector3(half.x * 2, 2.0, half.y * 2)))
	for b: Dictionary in compiled["walls"]:
		out.append(_box_to_aabb(b))
	for b: Dictionary in compiled["cover"]:
		out.append(_box_to_aabb(b))
	return out


# The same solids as build_colliders, as a brush world. Movement traces against
# this; the AABB list is still what hitscan and bot nav consume until they move
# over too. Imported .map geometry will add real brushes here rather than boxes.
static func build_world(compiled: Dictionary) -> CollisionWorld:
	var world := CollisionWorld.new()
	for box: AABB in build_colliders(compiled):
		var index := world.add_box(box)
		if Hitbox.special_blocks(box):
			world.tag_brush(index, CollisionWorld.CONTENT_SPECIAL)
	world.build()
	return world


# Lighting and sky, without any of the geometry build_visual also does.
# Imported levels bring their own brushes but still want the same treatment.
static func build_ambience(parent: Node3D, compiled: Dictionary) -> void:
	_build_lighting(parent)
	_build_environment(parent, compiled)


static func build_physics(parent: Node3D, compiled: Dictionary) -> void:
	var half := floor_half(compiled)

	_add_static_box(parent, Vector3(0.0, -1.0, 0.0), Vector3(half.x * 2, 2.0, half.y * 2))

	for b: Dictionary in compiled["walls"]:
		_add_static_box(parent, _box_center(b), _box_size(b))

	for b: Dictionary in compiled["cover"]:
		_add_static_box(parent, _box_center(b), _box_size(b))


static func _add_static_box(parent: Node3D, pos: Vector3, sz: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


static func build_visual(parent: Node3D, compiled: Dictionary) -> Array[AABB]:
	var arena: float = compiled["arena"]
	var half := floor_half(compiled)
	var colliders := build_colliders(compiled)

	_build_floor(parent, half)
	_build_grid(parent, arena, half)
	var edges := _EdgeBatch.new()
	var palette := _edge_palette()
	_build_walls(parent, compiled["walls"], arena, edges, palette)
	_build_cover(parent, compiled["cover"], arena, edges, palette)
	edges.commit(parent)
	_build_pads(parent, compiled.get("pads", []))
	_build_lighting(parent)
	_build_environment(parent, compiled)

	return colliders


# Half extents of the floor: square at the arena size unless the map gives
# rectangular [half_x, half_z] extents.
static func floor_half(compiled: Dictionary) -> Vector2:
	var arena: float = compiled["arena"]
	var f: Array = compiled.get("floor", [])
	if f.size() >= 2:
		return Vector2(float(f[0]), float(f[1]))
	return Vector2(arena, arena)


static func _box_to_aabb(b: Dictionary) -> AABB:
	var x: float = b["x"]
	var z: float = b["z"]
	var sx: float = b["sx"]
	var sz: float = b["sz"]
	var h: float = b["h"]
	var y0: float = b.get("y0", 0.0)
	return AABB(Vector3(x - sx * 0.5, y0, z - sz * 0.5), Vector3(sx, h - y0, sz))


static func _hex(c: int) -> Color:
	var r := ((c >> 16) & 0xFF) / 255.0
	var g := ((c >> 8) & 0xFF) / 255.0
	var b := (c & 0xFF) / 255.0
	return Color(r, g, b)


static func _std_mat(c: int, metallic := 0.0, roughness := 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _hex(c)
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


# Team colour lives on edges, not surfaces. The map body is slate so that a
# player, who wears their colour at full brightness, is the brightest thing
# of that colour in view; a deck top glowing solid blue hid a blue player
# standing on it. An edge line keeps the hue dark and the glow low, enough
# to say whose ground this is without competing.
static func _edge_mat(c: int, energy := 0.16) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var col := _hex(c)
	mat.albedo_color = col.darkened(0.55)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	# Thin bars are seen from every side; no winding to get wrong.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _add_box_mesh(parent: Node3D, pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


# ---- edge outlines ----

## Width of an edge bar across the top face, its height above it, and how
## far its outer face sits in from the box's own side. The inset is what
## keeps it off that side, which is coplanar at zero, and keeps the bars of
## two boxes that meet edge to edge from ever touching.
const EDGE_W := 0.07
const EDGE_H := 0.05
const EDGE_INSET := 0.015

# All edge bars of one colour go into one mesh. A map outlines a few hundred
# boxes at four bars apiece, which as separate instances is a draw call per
# bar; batched it is one per colour.
class _EdgeBatch:
	extends RefCounted
	var _tools: Dictionary = {}
	var _mats: Dictionary = {}

	func bar(mat: StandardMaterial3D, mn: Vector3, mx: Vector3) -> void:
		var key := mat.get_instance_id()
		if not _tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_tools[key] = st
			_mats[key] = mat
		var st: SurfaceTool = _tools[key]
		# Top and four sides. The bottom sits on the box top, hidden.
		_quad(st, Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z),
			Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3.UP)
		_quad(st, Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z),
			Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3.FORWARD)
		_quad(st, Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z),
			Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mn.y, mx.z), Vector3.BACK)
		_quad(st, Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z),
			Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3.LEFT)
		_quad(st, Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z),
			Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3.RIGHT)

	static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)

	func commit(parent: Node3D) -> void:
		for key in _tools:
			var st: SurfaceTool = _tools[key]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = _mats[key]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)


# Outlines the top face of a box: two bars the full length along z, two
# between them along x, so the frame's corners are covered once. A box too
# narrow to frame gets one bar down its middle instead.
static func _outline_top(edges: _EdgeBatch, mat: StandardMaterial3D, b: Dictionary) -> void:
	var hx: float = b["sx"] * 0.5
	var hz: float = b["sz"] * 0.5
	var y0: float = b["h"]
	var y1 := y0 + EDGE_H
	var x0: float = b["x"] - hx + EDGE_INSET
	var x1: float = b["x"] + hx - EDGE_INSET
	var z0: float = b["z"] - hz + EDGE_INSET
	var z1: float = b["z"] + hz - EDGE_INSET
	var frame_min := EDGE_W * 2.0 + 0.04
	if x1 - x0 < frame_min or z1 - z0 < frame_min:
		if x1 - x0 < frame_min:
			var cx: float = b["x"]
			var w := minf(EDGE_W, maxf(x1 - x0, 0.02))
			edges.bar(mat, Vector3(cx - w * 0.5, y0, z0), Vector3(cx + w * 0.5, y1, z1))
		else:
			var cz: float = b["z"]
			var w := minf(EDGE_W, maxf(z1 - z0, 0.02))
			edges.bar(mat, Vector3(x0, y0, cz - w * 0.5), Vector3(x1, y1, cz + w * 0.5))
		return
	edges.bar(mat, Vector3(x0, y0, z0), Vector3(x0 + EDGE_W, y1, z1))
	edges.bar(mat, Vector3(x1 - EDGE_W, y0, z0), Vector3(x1, y1, z1))
	edges.bar(mat, Vector3(x0 + EDGE_W, y0, z0), Vector3(x1 - EDGE_W, y1, z0 + EDGE_W))
	edges.bar(mat, Vector3(x0 + EDGE_W, y0, z1 - EDGE_W), Vector3(x1 - EDGE_W, y1, z1))


# ---- floor ----

static func _build_floor(parent: Node3D, half: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half.x * 2, half.y * 2)
	plane.material = _std_mat(0x1c2230,0.4, 0.4)
	mi.mesh = plane
	mi.position = Vector3.ZERO
	parent.add_child(mi)


# ---- grid ----

static func _build_grid(parent: Node3D, arena: float, half: Vector2) -> void:
	# Dark lines, not a glowing floor: the grid still says which half you are
	# on without the whole ground reading as team colour.
	var grid_blue := _edge_mat(0x1c6cff, 0.1)
	var grid_red := _edge_mat(0xff2d3f, 0.1)
	var grid_mid := _edge_mat(0x2aa0c0, 0.08)
	# Fixed cell size so the floor reads the same density at any arena size.
	var step := 1.4

	var nz := int(round((half.y * 2.0) / step))
	for i in nz + 1:
		var p := -half.y + i * step
		# Lines running along X: tinted by their z position
		var z_mat := _z_tint(p, arena, grid_blue, grid_red, grid_mid)
		_add_grid_line(parent, Vector3(0, 0.015, p), Vector3(half.x * 2, 0.02, 0.04), z_mat)

	var nx := int(round((half.x * 2.0) / step))
	for i in nx + 1:
		var p := -half.x + i * step
		# Lines running along Z: split into 3 tinted segments
		_add_grid_line(parent, Vector3(p, 0.015, -half.y * 0.6), Vector3(0.04, 0.02, half.y * 0.8), grid_blue)
		_add_grid_line(parent, Vector3(p, 0.015, 0), Vector3(0.04, 0.02, half.y * 0.44), grid_mid)
		_add_grid_line(parent, Vector3(p, 0.015, half.y * 0.6), Vector3(0.04, 0.02, half.y * 0.8), grid_red)

	# Bright center line
	_add_grid_line(parent, Vector3(0, 0.015, 0), Vector3(half.x * 2, 0.02, 0.18), _edge_mat(0x9effff, 0.14))


static func _z_tint(z: float, arena: float, blue: StandardMaterial3D, red: StandardMaterial3D, mid: StandardMaterial3D) -> StandardMaterial3D:
	if z < -arena * 0.18:
		return blue
	if z > arena * 0.18:
		return red
	return mid


static func _add_grid_line(parent: Node3D, pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---- walls ----

static func _build_walls(parent: Node3D, walls: Array, arena: float, edges: _EdgeBatch, palette: Array) -> void:
	var wall_mat := _std_mat(0x343a4c, 0.3, 0.55)
	for b: Dictionary in walls:
		_add_box_mesh(parent, _box_center(b), _box_size(b), wall_mat)
		_outline_top(edges, _edge_for(b["z"], arena, palette), b)


# ---- cover ----

static func _build_cover(parent: Node3D, cover_list: Array, arena: float, edges: _EdgeBatch, palette: Array) -> void:
	var cover_mat := _std_mat(0x3c4356, 0.3, 0.6)
	for b: Dictionary in cover_list:
		_add_box_mesh(parent, _box_center(b), _box_size(b), cover_mat)
		_outline_top(edges, _edge_for(b["z"], arena, palette), b)


# The three edge colours, made once so every bar of a colour shares one
# material and so lands in one batch.
static func _edge_palette() -> Array:
	return [_edge_mat(0x2a7cff), _edge_mat(0xff3a46), _edge_mat(0x39d6ff)]


static func _edge_for(z: float, arena: float, palette: Array) -> StandardMaterial3D:
	if z < -arena * 0.18:
		return palette[0]
	if z > arena * 0.18:
		return palette[1]
	return palette[2]


static func _box_center(b: Dictionary) -> Vector3:
	var y0: float = b.get("y0", 0.0)
	var h: float = b["h"]
	return Vector3(b["x"], (y0 + h) * 0.5, b["z"])


static func _box_size(b: Dictionary) -> Vector3:
	var y0: float = b.get("y0", 0.0)
	var h: float = b["h"]
	return Vector3(b["sx"], h - y0, b["sz"])


# ---- spawn pads ----

static func _build_pads(parent: Node3D, pads: Array) -> void:
	for p: Dictionary in pads:
		var is_red := str(p.get("team", "blue")) == "red"
		var pad_color := 0xff2d3f if is_red else 0x1c6cff
		var pad_mat := _edge_mat(pad_color, 0.18)
		# Pads sit on the ground unless the map raises them onto a deck.
		var y0: float = float(p.get("y", 0.0))

		# Outer ring. Radius covers the widest spawn offset (x=±3) with margin.
		var outer := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 3.8
		cyl.bottom_radius = 3.8
		cyl.height = 0.03
		cyl.material = pad_mat
		outer.mesh = cyl
		outer.position = Vector3(p["x"], y0 + 0.05, p["z"])
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(outer)

		# Inner dark disc
		var inner := MeshInstance3D.new()
		var icyl := CylinderMesh.new()
		icyl.top_radius = 3.2
		icyl.bottom_radius = 3.2
		icyl.height = 0.04
		icyl.material = _std_mat(0x1c2230,0.6, 0.4)
		inner.mesh = icyl
		inner.position = Vector3(p["x"], y0 + 0.06, p["z"])
		inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inner)


# ---- lighting ----

static func _build_lighting(parent: Node3D) -> void:
	# Cool key from the original match lighting, plus a rim from each end.
	# The rims used to be blue from one end and red from the other, which lit
	# each half of the map in its team's colour: the strongest single reason
	# a blue player vanished against blue ground. They are neutral now; the
	# edge lines carry the team colour instead.
	var key := DirectionalLight3D.new()
	key.rotation_order = EULER_ORDER_XYZ
	key.rotation_degrees = Vector3(58, 34, 0)
	key.light_energy = 1.15
	key.light_color = Color(0.8, 0.88, 1.0)
	key.shadow_enabled = true
	parent.add_child(key)

	for yaw: float in [0.0, 180.0]:
		var rim := DirectionalLight3D.new()
		rim.rotation_order = EULER_ORDER_XYZ
		rim.rotation_degrees = Vector3(-18, yaw, 0)
		rim.light_energy = 0.4
		rim.light_color = Color(0.62, 0.68, 0.8)
		rim.shadow_enabled = false
		parent.add_child(rim)


# ---- environment (sky + fog) ----

static func _build_environment(parent: Node3D, compiled: Dictionary) -> void:
	var env := Environment.new()
	var sky_spec: Dictionary = compiled.get("sky", {})
	if sky_spec.has("cubemap"):
		env.background_mode = Environment.BG_SKY
		env.sky = _SkyCubemap.make_sky(compiled)
		env.fog_sky_affect = 0.0
		var drift := _SkyDrift.new()
		drift.environment = env
		parent.add_child(drift)
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Lifted with the body colours: slate has to read as slate, not as the
	# black the old near-black surfaces sat at, or the edge lines are the
	# only thing on screen.
	env.ambient_light_color = Color(0.2, 0.22, 0.3)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.04, 0.09)
	env.fog_density = 0.006

	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
