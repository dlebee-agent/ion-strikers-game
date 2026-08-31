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

	# The directions this face lays its texture along, in Godot space, as
	# [u, v]. Valve 220 states them outright. The older format does not, so they
	# are derived the way Quake's compiler does it: take whichever of six axis
	# aligned pairs the face most nearly faces, then spin that pair by the
	# face's rotation. That derivation is why the old format shears a texture
	# across a slanted face and Valve 220 does not.
	func uv_axes() -> Array:
		if valve:
			return [u_axis, v_axis]

		# Quake's table is in Quake space, so the normal goes back there first.
		var n := plane().normal
		var qn := Vector3(n.x, -n.z, n.y)

		var bases := [
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
			[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
			[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
			[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		]
		var best := -2.0
		var pick := 0
		for i in bases.size():
			var d: float = qn.dot(bases[i][0])
			if d > best:
				best = d
				pick = i
		var qu: Vector3 = bases[pick][1]
		var qv: Vector3 = bases[pick][2]

		if rotation != 0.0:
			var ang := deg_to_rad(rotation)
			var sn := sin(ang)
			var cs := cos(ang)
			# Both axes spin within the same two components: the one the U axis
			# occupies and the one the V axis occupies. For an axis aligned pair
			# that is always exactly two of the three. Assigned back explicitly
			# rather than through a loop, because Vector3 is a value type and a
			# loop variable would be a copy.
			var su := 0 if qu.x != 0.0 else (1 if qu.y != 0.0 else 2)
			var sv := 0 if qv.x != 0.0 else (1 if qv.y != 0.0 else 2)
			var u_a := qu[su]
			var u_b := qu[sv]
			qu[su] = cs * u_a - sn * u_b
			qu[sv] = sn * u_a + cs * u_b
			var v_a := qv[su]
			var v_b := qv[sv]
			qv[su] = cs * v_a - sn * v_b
			qv[sv] = sn * v_a + cs * v_b

		return [TbMap.dir_to_godot(qu), TbMap.dir_to_godot(qv)]

	# Texture coordinate for a vertex, given the texture's pixel size. The dot
	# products are in map units, so the vertex is scaled back out of metres
	# first: the offsets and scales in the file are all in those units.
	func uv_for(vertex: Vector3, texture_size: Vector2) -> Vector2:
		var axes := uv_axes()
		var in_units := vertex / TbMap.UNIT_SCALE
		var u: float = in_units.dot(axes[0]) / u_scale + u_offset
		var v: float = in_units.dot(axes[1]) / v_scale + v_offset
		return Vector2(u / maxf(texture_size.x, 1.0), v / maxf(texture_size.y, 1.0))


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
