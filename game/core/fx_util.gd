class_name FxUtil
extends RefCounted

# Shared construction for the beam/blast/impact effects, ported from the original's
# emissiveMat() plus its cylinder and sphere helpers.

# Unlit colour that ADDS to whatever is behind it, with depth writes off so
# overlapping shells and sparks do not cut holes in each other. Fading these
# effects means animating albedo_color.a.
static func emissive(color: Color, opacity: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, opacity)
	if opacity < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

# Unit DIAMETER and unit height, so scaling by (w, length, w) gives a beam exactly
# w across — the same convention the original's primitives use.
static func cylinder(mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.material = mat
	return _instance(mesh)

# Unit DIAMETER as well: scaling by r gives a sphere of radius r/2.
static func sphere(mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.material = mat
	return _instance(mesh)

static func _instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# Point a mesh authored along +Y down `dir`. Built as a basis rather than with
# look_at so it works on nodes that are not in the tree yet.
static func basis_along(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if d.is_zero_approx():
		return Basis.IDENTITY
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.999:
		up = Vector3.RIGHT
	var x := up.cross(d).normalized()
	return Basis(x, d, x.cross(d))

static func set_alpha(mat: StandardMaterial3D, alpha: float) -> void:
	mat.albedo_color.a = alpha
