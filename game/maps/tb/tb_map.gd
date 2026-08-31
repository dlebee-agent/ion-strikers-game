class_name TbMap
extends RefCounted

# Parsed contents of a Quake .map file, the format TrenchBroom saves natively.
#
# The file is entities, each a block of key/value properties optionally followed
# by brushes. A brush is a set of faces, and each face is a plane given as three
# points plus how a texture is laid across it. The solid is the intersection of
# its faces' half-spaces, which is exactly the representation CollisionWorld
# wants, and the reason .map is worth reading directly rather than taking the
# compiled BSP.
#
# Quake is Z-up in units where the player is about 56 tall. Ion Strikers is Y-up
# in metres with UNIT_SCALE already set to 0.0254, so a map authored to normal
# Quake proportions converts straight across with no fudge factor.

# Map units to metres. Movement is already built on this scale.
const UNIT_SCALE := 0.0254


# Quake's axes to Godot's. Quake is X east, Y north, Z up; Godot is X right,
# Y up, Z toward the viewer. Swapping Y and Z and negating one of them keeps the
# basis right-handed, so cross products, and therefore face normals, survive the
# conversion without needing to be flipped afterwards.
static func to_godot(q: Vector3) -> Vector3:
	return Vector3(q.x, q.z, -q.y) * UNIT_SCALE


# A direction rather than a position: same axis swap, no scaling, because
# texture axes are directions and scaling them would change the UV rate.
static func dir_to_godot(q: Vector3) -> Vector3:
	return Vector3(q.x, q.z, -q.y)


class Face extends RefCounted:
	# The three points defining the plane, already in Godot space.
	var p0 := Vector3.ZERO
	var p1 := Vector3.ZERO
	var p2 := Vector3.ZERO
	# Texture name as written, e.g. "ion/metal_panel", "__TB_empty", "*water".
	var texture := ""
	# Valve 220 gives explicit U and V axes; the older format derives them from
	# the face normal and a rotation.
	var valve := false
	var u_axis := Vector3.ZERO
	var v_axis := Vector3.ZERO
	var u_offset := 0.0
	var v_offset := 0.0
	var rotation := 0.0
	var u_scale := 1.0
	var v_scale := 1.0

	# Outward plane of this face. Quake's winding is such that the cross product
	# below points out of the solid, and the axis conversion preserves handedness,
	# so no flip is needed here.
	func plane() -> Plane:
		var n := (p0 - p1).cross(p2 - p1)
		var len := n.length()
		if len < 0.000001:
			return Plane(Vector3.UP, 0.0)
		n /= len
		return Plane(n, n.dot(p0))

	# A face whose three points are collinear defines no plane and has to be
	# dropped rather than silently becoming a horizontal one.
	func degenerate() -> bool:
		return (p0 - p1).cross(p2 - p1).length() < 0.000001


class Brush extends RefCounted:
	var faces: Array[Face] = []

	func planes() -> Array[Plane]:
		var out: Array[Plane] = []
		for f: Face in faces:
			out.append(f.plane())
		return out


class Entity extends RefCounted:
	var properties: Dictionary = {}
	var brushes: Array[Brush] = []

	func classname() -> String:
		return properties.get("classname", "")

	func get_string(key: String, fallback := "") -> String:
		return properties.get(key, fallback)

	func get_float(key: String, fallback := 0.0) -> float:
		if not properties.has(key):
			return fallback
		return String(properties[key]).to_float()

	# Quake writes vectors as space separated numbers in one value, and they are
	# in map space, so they need the same conversion the geometry gets.
	func get_position(key: String, fallback := Vector3.ZERO) -> Vector3:
		if not properties.has(key):
			return fallback
		var parts := String(properties[key]).split(" ", false)
		if parts.size() < 3:
			return fallback
		return TbMap.to_godot(Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()))


var entities: Array[Entity] = []
# Non-fatal complaints: a malformed face, an unclosed block. Community maps are
# untrusted input, so parsing reports what it skipped rather than failing whole.
var warnings: Array[String] = []


func worldspawn() -> Entity:
	for e: Entity in entities:
		if e.classname() == "worldspawn":
			return e
	return null


# Every entity with the given classname, in file order.
func by_class(name: String) -> Array[Entity]:
	var out: Array[Entity] = []
	for e: Entity in entities:
		if e.classname() == name:
			out.append(e)
	return out


func brush_count() -> int:
	var n := 0
	for e: Entity in entities:
		n += e.brushes.size()
	return n
