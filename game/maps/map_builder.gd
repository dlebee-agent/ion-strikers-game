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
	var arena: float = compiled["arena"]
	# Floor slab: top at y=0
	out.append(AABB(Vector3(-arena, -2.0, -arena), Vector3(arena * 2, 2.0, arena * 2)))
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
	var arena: float = compiled["arena"]

	_add_static_box(parent, Vector3(0.0, -1.0, 0.0), Vector3(arena * 2, 2.0, arena * 2))

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
	var colliders := build_colliders(compiled)

	_build_floor(parent, arena)
	_build_grid(parent, arena)
	_build_walls(parent, compiled["walls"], arena)
	_build_cover(parent, compiled["cover"], arena)
	_build_pads(parent, compiled.get("pads", []))
	_build_lighting(parent)
	_build_environment(parent, compiled)

	return colliders


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


static func _emissive_mat(c: int, energy := 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var col := _hex(c)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	return mat


static func _add_box_mesh(parent: Node3D, pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


# ---- floor ----

static func _build_floor(parent: Node3D, arena: float) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena * 2, arena * 2)
	plane.material = _std_mat(0x0b0e16, 0.4, 0.4)
	mi.mesh = plane
	mi.position = Vector3.ZERO
	parent.add_child(mi)


# ---- grid ----

static func _build_grid(parent: Node3D, arena: float) -> void:
	var grid_blue := _emissive_mat(0x1c6cff, 0.7)
	var grid_red := _emissive_mat(0xff2d3f, 0.7)
	var grid_mid := _emissive_mat(0x2aa0c0, 0.5)
	# Fixed cell size so the floor reads the same density at any arena size.
	var step := 1.4
	var n := int(round((arena * 2.0) / step))

	for i in n + 1:
		var p := -arena + i * step
		# Lines running along X: tinted by their z position
		var z_mat := _z_tint(p, arena, grid_blue, grid_red, grid_mid)
		_add_grid_line(parent, Vector3(0, 0.015, p), Vector3(arena * 2, 0.02, 0.04), z_mat)
		# Lines running along Z: split into 3 tinted segments
		_add_grid_line(parent, Vector3(p, 0.015, -arena * 0.6), Vector3(0.04, 0.02, arena * 0.8), grid_blue)
		_add_grid_line(parent, Vector3(p, 0.015, 0), Vector3(0.04, 0.02, arena * 0.44), grid_mid)
		_add_grid_line(parent, Vector3(p, 0.015, arena * 0.6), Vector3(0.04, 0.02, arena * 0.8), grid_red)

	# Bright center line
	_add_grid_line(parent, Vector3(0, 0.015, 0), Vector3(arena * 2, 0.02, 0.18), _emissive_mat(0x9effff, 0.9))


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

static func _build_walls(parent: Node3D, walls: Array, arena: float) -> void:
	var wall_mat := _std_mat(0x10141c, 0.6, 0.5)
	for b: Dictionary in walls:
		var pos := _box_center(b)
		var sz := _box_size(b)
		_add_box_mesh(parent, pos, sz, wall_mat)
		# Glowing top trim
		var trim := _trim_for(b["z"], arena)
		_add_box_mesh(parent, Vector3(b["x"], b["h"], b["z"]),
			Vector3(b["sx"] + 0.06, 0.12, b["sz"] + 0.06), trim)


# ---- cover ----

static func _build_cover(parent: Node3D, cover_list: Array, arena: float) -> void:
	var cover_mat := _std_mat(0x161b26, 0.5, 0.55)
	for b: Dictionary in cover_list:
		var pos := _box_center(b)
		var sz := _box_size(b)
		_add_box_mesh(parent, pos, sz, cover_mat)
		# Accent seam on top
		var trim := _trim_for(b["z"], arena)
		_add_box_mesh(parent, Vector3(b["x"], b["h"], b["z"]),
			Vector3(b["sx"] + 0.05, 0.08, b["sz"] + 0.05), trim)


static func _trim_for(z: float, arena: float) -> StandardMaterial3D:
	if z < -arena * 0.18:
		return _emissive_mat(0x2a7cff, 0.9)
	if z > arena * 0.18:
		return _emissive_mat(0xff3a46, 0.9)
	return _emissive_mat(0x39d6ff, 0.85)


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
		var pad_mat := _emissive_mat(pad_color, 0.6)

		# Outer ring. Radius covers the widest spawn offset (x=±3) with margin.
		var outer := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 3.8
		cyl.bottom_radius = 3.8
		cyl.height = 0.03
		cyl.material = pad_mat
		outer.mesh = cyl
		outer.position = Vector3(p["x"], 0.05, p["z"])
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(outer)

		# Inner dark disc
		var inner := MeshInstance3D.new()
		var icyl := CylinderMesh.new()
		icyl.top_radius = 3.2
		icyl.bottom_radius = 3.2
		icyl.height = 0.04
		icyl.material = _std_mat(0x0b0e16, 0.6, 0.4)
		inner.mesh = icyl
		inner.position = Vector3(p["x"], 0.06, p["z"])
		inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inner)


# ---- lighting ----

static func _build_lighting(parent: Node3D) -> void:
	# Cool key from the original match lighting, plus a rim from each team end.
	var key := DirectionalLight3D.new()
	key.rotation_order = EULER_ORDER_XYZ
	key.rotation_degrees = Vector3(58, 34, 0)
	key.light_energy = 1.15
	key.light_color = Color(0.8, 0.88, 1.0)
	key.shadow_enabled = true
	parent.add_child(key)

	var rim_blue := DirectionalLight3D.new()
	rim_blue.rotation_order = EULER_ORDER_XYZ
	rim_blue.rotation_degrees = Vector3(-18, 0, 0)
	rim_blue.light_energy = 0.55
	rim_blue.light_color = Color(0.25, 0.5, 1.0)
	rim_blue.shadow_enabled = false
	parent.add_child(rim_blue)

	var rim_red := DirectionalLight3D.new()
	rim_red.rotation_order = EULER_ORDER_XYZ
	rim_red.rotation_degrees = Vector3(-18, 180, 0)
	rim_red.light_energy = 0.55
	rim_red.light_color = Color(1.0, 0.28, 0.34)
	rim_red.shadow_enabled = false
	parent.add_child(rim_red)


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
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.04, 0.09)
	env.fog_density = 0.006

	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
