class_name TeamTint
extends RefCounted

# Where a pawn gets its team colours. Both halves now hand off to SuitMaterial:
# the body is the painted suit, the gun is black with lit accents. What survives
# from the original tintMannequin()/attachGunModel() is the palette below — the
# bright saturated body colour with its faint self-lit glow, which keeps a player
# readable as friend or foe even standing in shadow.

const BODY_RED := Color8(255, 59, 72)
const BODY_BLUE := Color8(58, 144, 255)
const GUN_RED := Color8(255, 45, 63)
const GUN_BLUE := Color8(24, 160, 255)

const BODY_EMISSION := 0.28

# The body is the painted suit (see suit.gdshader): the team colour and the
# self-lit glow above survive as its base, and the chosen suit style decides
# whether that colour is the body or the seams.
static func apply_body(root: Node, team: String, style: String = SuitStyle.DEFAULT) -> void:
	for mi in _mesh_instances(root, true):
		SuitMaterial.paint(mi, team, style)

# The gun wears the suit's kit: the same black the dark body is painted in, with
# the two accent surfaces glowing in the team colour the seams glow in, so the
# weapon reads as lit trim rather than a solid block of red or blue. This is not
# one of the suit finishes — the settings style repaints the body only, and the
# gun stays the same against all four so it never disappears into the suit.
static func apply_gun(root: Node, team: String) -> void:
	for mi in _mesh_instances(root, false):
		var mesh := mi.mesh
		if not mesh:
			continue
		for i in mesh.get_surface_count():
			# Read the name off the mesh, never off an override we set earlier:
			# the overrides carry no surface name, so a team switch would stop
			# recognising the accents and paint the whole gun as chassis.
			var src := mesh.surface_get_material(i)
			var mat_name := src.resource_name.to_lower() if src else ""
			match mat_name:
				# Only 'Main' lights up. 'White' used to be tinted too, and
				# together the pair covers most of the slide — a solid block of
				# team colour, which is what the black suit is not.
				"main":
					mi.set_surface_override_material(i, SuitMaterial.gun_accent_material(team))
				"white", "grey":
					mi.set_surface_override_material(i, SuitMaterial.gun_chassis_material(true))
				_:
					mi.set_surface_override_material(i, SuitMaterial.gun_chassis_material())

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
