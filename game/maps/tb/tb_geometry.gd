class_name TbGeometry
extends RefCounted

# Solves a brush's half-spaces into actual polygons.
#
# A .map brush states only the planes its faces lie in, never where the corners
# are, so the corners have to be found: every triple of planes meets at a point,
# and the points that survive being tested against all the other planes are the
# hull's vertices. Each one is then handed to whichever faces it lies on, and
# those vertices sorted around the face normal give the polygon to draw.
#
# Tolerances are in metres. They are loose relative to float32, which is what
# Vector3 stores, because a map corner 100 m from the origin only resolves to
# about a hundredth of a millimetre there. They are tight relative to real
# brushwork, where the smallest feature anyone builds is centimetres across.

# A vertex within this of a plane is treated as lying on it.
const ON_PLANE := 0.001
# Slack when rejecting a candidate for being outside the hull.
const INSIDE_SLACK := 0.001
# Candidates closer together than this are the same corner.
const WELD := 0.0005
# Below this the three planes are too close to parallel to meet in a point.
const DENOM_EPSILON := 0.0001
# Planes this similar are the same plane, and duplicates break the triple solve.
const PLANE_DOT := 0.9999
const PLANE_DIST := 0.001


class FaceGeometry extends RefCounted:
	var plane := Plane()
	# Hull corners on this face, wound counter-clockwise about plane.normal, so
	# counter-clockwise seen from outside the solid.
	var vertices := PackedVector3Array()
	# The parsed face this came from, for its texture and UV axes.
	var source: TbMap.Face = null


class Solid extends RefCounted:
	# Every plane of the brush, including any that bound nothing. Redundant
	# planes cannot change a convex hull, and keeping them costs one dot product
	# in the trace while dropping them risks discarding one that did matter.
	var planes: Array[Plane] = []
	# Only the faces that turned out to have a polygon, which is what gets drawn.
	var faces: Array[FaceGeometry] = []
	var bounds := AABB()
	# False when the planes enclose nothing, which is a malformed brush.
	var valid := false


# Solves one parsed brush.
static func solve(brush: TbMap.Brush) -> Solid:
	var solid := Solid.new()

	var faces: Array[TbMap.Face] = []
	var planes: Array[Plane] = []
	for f: TbMap.Face in brush.faces:
		var p := f.plane()
		if _duplicate_plane(planes, p):
			continue
		planes.append(p)
		faces.append(f)
	solid.planes = planes

	if planes.size() < 4:
		return solid

	# Corners, as the points where three planes meet that no fourth plane cuts off.
	var corners: Array[Vector3] = []
	var count := planes.size()
	for i in count:
		for j in range(i + 1, count):
			for k in range(j + 1, count):
				# Variant, not Vector3: three near-parallel planes meet nowhere
				# and _intersect says so with null.
				var point: Variant = _intersect(planes[i], planes[j], planes[k])
				if point == null:
					continue
				var v: Vector3 = point
				if not _inside_all(v, planes):
					continue
				if not _already_have(corners, v):
					corners.append(v)

	if corners.is_empty():
		return solid

	# Hand each corner to every face it lies on. These are plain Arrays, not
	# PackedVector3Arrays: a packed array is a value type, so indexing one out of
	# a container hands back a copy and appending to it changes nothing.
	var per_face: Array[Array] = []
	for i in count:
		per_face.append([])
	for v: Vector3 in corners:
		for i in count:
			if absf(planes[i].distance_to(v)) <= ON_PLANE:
				per_face[i].append(v)

	var lo := corners[0]
	var hi := corners[0]
	for v: Vector3 in corners:
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	solid.bounds = AABB(lo, hi - lo)

	for i in count:
		var ring: Array = per_face[i]
		if ring.size() < 3:
			# A plane that bounds nothing. It stays in `planes` for the collider
			# but there is no polygon here to draw.
			continue
		var fg := FaceGeometry.new()
		fg.plane = planes[i]
		fg.source = faces[i]
		fg.vertices = _wind(ring, planes[i].normal)
		solid.faces.append(fg)

	solid.valid = solid.faces.size() >= 4
	return solid


# Solves every brush in a map, skipping malformed ones.
static func solve_all(brushes: Array, warnings: Array[String]) -> Array[Solid]:
	var out: Array[Solid] = []
	var dropped := 0
	for b: TbMap.Brush in brushes:
		var s := solve(b)
		if not s.valid:
			dropped += 1
			continue
		out.append(s)
	if dropped > 0:
		warnings.append("%d brush(es) enclosed no volume and were skipped" % dropped)
	return out


static func _duplicate_plane(seen: Array[Plane], p: Plane) -> bool:
	for q: Plane in seen:
		if q.normal.dot(p.normal) > PLANE_DOT and absf(q.d - p.d) < PLANE_DIST:
			return true
	return false


# Where three planes meet, or null when they do not meet in a single point.
# Untyped return because it is Vector3 or null; Godot's own Plane.intersect_3
# does the same, but with a fixed epsilon that is too tight for float32 corners
# a hundred metres out.
static func _intersect(a: Plane, b: Plane, c: Plane) -> Variant:
	var bc := b.normal.cross(c.normal)
	var denom := a.normal.dot(bc)
	if absf(denom) < DENOM_EPSILON:
		return null
	var ca := c.normal.cross(a.normal)
	var ab := a.normal.cross(b.normal)
	return (bc * a.d + ca * b.d + ab * c.d) / denom


static func _inside_all(v: Vector3, planes: Array[Plane]) -> bool:
	for p: Plane in planes:
		if p.distance_to(v) > INSIDE_SLACK:
			return false
	return true


static func _already_have(corners: Array[Vector3], v: Vector3) -> bool:
	for c: Vector3 in corners:
		if c.distance_squared_to(v) < WELD * WELD:
			return true
	return false


# Orders a face's corners counter-clockwise about the normal, by angle around
# their own centroid. A convex polygon is star-shaped about its centroid, so the
# angle order is the boundary order.
static func _wind(ring: Array, normal: Vector3) -> PackedVector3Array:
	var centre := Vector3.ZERO
	for v: Vector3 in ring:
		centre += v
	centre /= float(ring.size())

	# Any two perpendicular directions in the plane will do, as long as
	# u cross v is the normal, which is what makes increasing angle mean
	# counter-clockwise rather than clockwise.
	var u := normal.cross(Vector3.UP)
	if u.length_squared() < 0.0001:
		u = normal.cross(Vector3.RIGHT)
	u = u.normalized()
	var v_axis := normal.cross(u)

	var indexed: Array = []
	for v: Vector3 in ring:
		var d := v - centre
		indexed.append([atan2(d.dot(v_axis), d.dot(u)), v])
	indexed.sort_custom(func(a, b): return a[0] < b[0])

	var out := PackedVector3Array()
	for entry in indexed:
		out.append(entry[1])
	return out
