class_name SuitMaterial
extends RefCounted

## Paints the suit design onto a mannequin or arms mesh. The design lives in
## suit.gdshader and is drawn from the rest-pose position, which Godot does not
## hand a shader once a mesh is skinned; so the first time a mesh comes through
## here it is rebuilt with its bind-pose position and normal baked into the
## CUSTOM0 and CUSTOM1 vertex streams. The rebuilt mesh and the materials are
## cached, so every pawn shares one mesh and one material per team and style.

const SHADER := preload("res://assets/characters/suit.gdshader")
const REST_META := "suit_rest_baked"

const DARK_BODY := Color("#14161c")
const WHITE_BODY := Color("#dfe4ee")
const SEAM_DARK := Color(0.03, 0.032, 0.04)

## The gun's accent glows, but nowhere near as hard as a suit seam: a seam is a
## line a few millimetres wide, while this covers a whole panel, and at seam
## energy it blows out to white and loses the team colour entirely.
const GUN_ACCENT_EMISSION := 0.55

static var _rest_meshes: Dictionary = {}    # source Mesh -> ArrayMesh with CUSTOM0/1
static var _body_materials: Dictionary = {} # "team/style" -> ShaderMaterial
static var _joint_material: StandardMaterial3D
static var _gun_accents: Dictionary = {}    # team -> StandardMaterial3D
static var _gun_chassis: Dictionary = {}    # "base"/"lift" -> StandardMaterial3D


## Paints one mesh instance: the body surface gets the suit shader, the
## mannequin's separate joint pieces go glossy black in either style.
static func paint(mi: MeshInstance3D, team: String, style: String) -> void:
	var mesh := with_rest_pose(mi)
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var mat_name := src.resource_name.to_lower() if src else ""
		if mat_name.contains("joint"):
			mi.set_surface_override_material(i, joint_material())
		else:
			mi.set_surface_override_material(i, body_material(team, style))


## Swaps the instance's mesh for a copy carrying the rest pose, once.
static func with_rest_pose(mi: MeshInstance3D) -> Mesh:
	var mesh := mi.mesh
	if mesh == null:
		return null
	if mesh.has_meta(REST_META):
		return mesh
	if not _rest_meshes.has(mesh):
		_rest_meshes[mesh] = _bake_rest(mesh)
	mi.mesh = _rest_meshes[mesh]
	return mi.mesh


static func _bake_rest(mesh: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.set_meta(REST_META, true)
	var custom_flags: int = (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var rest := PackedFloat32Array()
		var restn := PackedFloat32Array()
		rest.resize(verts.size() * 3)
		restn.resize(verts.size() * 3)
		for v in verts.size():
			var p := verts[v]
			rest[v * 3] = p.x
			rest[v * 3 + 1] = p.y
			rest[v * 3 + 2] = p.z
			var n := normals[v] if v < normals.size() else Vector3.UP
			restn[v * 3] = n.x
			restn[v * 3 + 1] = n.y
			restn[v * 3 + 2] = n.z
		arrays[Mesh.ARRAY_CUSTOM0] = rest
		arrays[Mesh.ARRAY_CUSTOM1] = restn
		# Keep the bone-weight width the importer chose; everything else about
		# the layout is implied by the arrays themselves.
		var flags: int = custom_flags | (mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays, [], {}, flags)
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out


static func body_material(team: String, style: String) -> ShaderMaterial:
	var s := SuitStyle.normalize(style)
	var key := "%s/%s" % [team, s]
	if _body_materials.has(key):
		return _body_materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var body: Color = TeamTint.BODY_RED if team == "red" else TeamTint.BODY_BLUE
	var glow: Color = TeamTint.GUN_RED if team == "red" else TeamTint.GUN_BLUE
	match s:
		SuitStyle.DARK:
			mat.set_shader_parameter("body_color", DARK_BODY)
			mat.set_shader_parameter("body_emission", 0.0)
		SuitStyle.WHITE:
			mat.set_shader_parameter("body_color", WHITE_BODY)
			mat.set_shader_parameter("body_emission", 0.05)
		_:
			mat.set_shader_parameter("body_color", body)
			# The old tint's faint self-lit glow, so a player still reads as
			# friend or foe standing in shadow.
			mat.set_shader_parameter("body_emission", TeamTint.BODY_EMISSION)
	if SuitStyle.seams_carry_team(s):
		# A black or white suit has no team in its body, so the seams glow in it.
		mat.set_shader_parameter("seam_color", glow)
		mat.set_shader_parameter("seam_roughness", 0.3)
		mat.set_shader_parameter("seam_glow", glow)
		mat.set_shader_parameter("seam_glow_energy", 2.5)
		mat.set_shader_parameter("visor_edge_energy", 1.0)
	elif s == SuitStyle.COLOUR_HOT:
		mat.set_shader_parameter("seam_color", Color.WHITE)
		mat.set_shader_parameter("seam_roughness", 0.3)
		mat.set_shader_parameter("seam_glow", Color.WHITE)
		mat.set_shader_parameter("seam_glow_energy", 2.4)
		mat.set_shader_parameter("visor_edge_energy", 1.0)
	else:
		mat.set_shader_parameter("seam_color", SEAM_DARK)
		mat.set_shader_parameter("seam_roughness", 0.12)
		mat.set_shader_parameter("seam_glow", Color.WHITE)
		mat.set_shader_parameter("seam_glow_energy", 0.0)
		mat.set_shader_parameter("visor_edge_energy", 0.0)
	mat.set_shader_parameter("core_color", Color.WHITE)
	mat.set_shader_parameter("core_energy", 1.8)
	_body_materials[key] = mat
	return mat


## The gun body: the same black the dark suit is painted in, on a harder finish
## so it still reads as machined metal rather than a second skin. The model's
## black and grey chassis surfaces both land here; the grey keeps a slight lift
## so the panel breaks the artist drew do not flatten into one shape.
static func gun_chassis_material(lift: bool = false) -> StandardMaterial3D:
	var key := "lift" if lift else "base"
	if _gun_chassis.has(key):
		return _gun_chassis[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DARK_BODY.lightened(0.12) if lift else DARK_BODY
	mat.metallic = 0.35
	mat.roughness = 0.32
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.6
	mat.clearcoat_roughness = 0.3
	_gun_chassis[key] = mat
	return mat


## The gun's lit accents, in the team colour the suit's seams glow in.
static func gun_accent_material(team: String) -> StandardMaterial3D:
	if _gun_accents.has(team):
		return _gun_accents[team]
	var glow: Color = TeamTint.GUN_RED if team == "red" else TeamTint.GUN_BLUE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = glow
	mat.metallic = 0.0
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = GUN_ACCENT_EMISSION
	_gun_accents[team] = mat
	return mat


static func joint_material() -> StandardMaterial3D:
	if _joint_material == null:
		_joint_material = StandardMaterial3D.new()
		_joint_material.albedo_color = Color("#0a0b10")
		_joint_material.metallic = 0.4
		_joint_material.roughness = 0.22
		_joint_material.clearcoat_enabled = true
		_joint_material.clearcoat = 1.0
		_joint_material.clearcoat_roughness = 0.15
	return _joint_material
