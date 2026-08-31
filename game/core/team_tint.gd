class_name TeamTint
extends RefCounted

# Ported from tintMannequin() and the tint half of attachGunModel().
#
# The body takes a bright, saturated team color with a faint self-lit glow, so a
# player stays readable as friend or foe even standing in shadow. Joints go to a
# darker shade of the same hue rather than a separate accent color. On the gun
# only the 'Main' and 'White' accents are tinted — the black and grey chassis is
# left alone, or the weapon reads as a solid block of team color.

const BODY_RED := Color8(255, 59, 72)
const BODY_BLUE := Color8(58, 144, 255)
const JOINT_RED := Color8(138, 28, 36)
const JOINT_BLUE := Color8(30, 78, 150)
const GUN_RED := Color8(255, 45, 63)
const GUN_BLUE := Color8(24, 160, 255)

const BODY_EMISSION := 0.28
const GUN_EMISSION := 0.4
# Original gloss 0.25 with metalness off. Godot roughness is 1 - gloss.
const TINT_ROUGHNESS := 0.75
# Godot still reflects the sky and draws a specular lobe at metallic=0 unless
# this is pulled down. 0.22 keeps the original's slight sheen without chrome.
const TINT_SPECULAR := 0.22

static func apply_body(root: Node, team: String) -> void:
	var body: Color = BODY_RED if team == "red" else BODY_BLUE
	var joint: Color = JOINT_RED if team == "red" else JOINT_BLUE
	for mi in _mesh_instances(root, true):
		var mesh := mi.mesh
		if not mesh:
			continue
		for i in mesh.get_surface_count():
			var mat := _clone_surface(mi, mesh, i)
			if not mat:
				continue
			if mat.resource_name.to_lower().contains("joint"):
				_paint(mat, joint, 0.0, TINT_ROUGHNESS)
			else:
				_paint(mat, body, BODY_EMISSION, TINT_ROUGHNESS)
			mi.set_surface_override_material(i, mat)

static func apply_gun(root: Node, team: String) -> void:
	var glow: Color = GUN_RED if team == "red" else GUN_BLUE
	for mi in _mesh_instances(root, false):
		var mesh := mi.mesh
		if not mesh:
			continue
		for i in mesh.get_surface_count():
			var mat := _clone_surface(mi, mesh, i)
			if not mat:
				continue
			var mat_name := mat.resource_name.to_lower()
			if mat_name == "main" or mat_name == "white":
				# Accents keep the authored roughness (0.5); only the colour and
				# glow change, matching attachGunModel().
				_paint(mat, glow, GUN_EMISSION, mat.roughness)
				mi.set_surface_override_material(i, mat)

# glTF surface materials are shared by every instance of the mesh, so tinting one
# player in place would repaint both teams. Always work on a copy set as an
# override; reading an earlier override back makes a team switch idempotent.
static func _clone_surface(mi: MeshInstance3D, mesh: Mesh, surface: int) -> StandardMaterial3D:
	var src: Material = mi.get_surface_override_material(surface)
	if not src:
		src = mesh.surface_get_material(surface)
	if not src is StandardMaterial3D:
		return null
	return src.duplicate() as StandardMaterial3D

static func _paint(mat: StandardMaterial3D, color: Color, emission: float, roughness: float) -> void:
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = roughness
	mat.metallic_specular = TINT_SPECULAR
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	else:
		mat.emission_enabled = false

static func _mesh_instances(root: Node, skip_attachments: bool = false) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if not root:
		return out
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child in root.get_children():
		# The pistol is seated on a BoneAttachment3D. Walking into it would paint
		# the gun the body colour; the original tints the body before the gun is
		# attached, then tints the gun on its own.
		if skip_attachments and child is BoneAttachment3D:
			continue
		out.append_array(_mesh_instances(child, skip_attachments))
	return out
