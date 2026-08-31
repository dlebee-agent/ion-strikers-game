class_name CollisionWorld
extends RefCounted

# The world's solid geometry as convex brushes, plus the swept-box and ray
# queries that movement, ragdolls, hitscan and bot navigation all run against.
#
# A brush is an intersection of half-spaces. An axis-aligned box is just a brush
# with six axis-aligned planes, so the boxes the declarative maps compile to and
# the arbitrary hulls a TrenchBroom .map parses to share one representation and
# one trace, with no legacy branch.
#
# Sweeps use the Quake method: each plane is pushed outward by the box's extent
# along that plane's normal, which reduces a moving box against a solid hull to a
# point against an expanded hull, and that is a segment-vs-convex clip. It is
# exact for a box, unlike the same trick applied to a capsule.
#
# All of this is plain deterministic float math on a fixed iteration order,
# because the server and the client's prediction both have to produce bit-equal
# results from the same inputs.

# Nudge kept between the swept box and the surface it stops against, so contact
# is never a floating-point coin toss between touching and penetrating.
const SURFACE_OFFSET := 0.001
# Planes flatter than this are treated as parallel to the sweep.
const PARALLEL_EPSILON := 0.0001
# How close to a plane still counts as outside it rather than embedded behind it.
# Plane normals are float32 in a PackedVector3Array while distances are float64,
# so a box resting exactly on a surface lands a few times 1e-8 on the wrong side
# of it. Without this slack that reads as embedded and the trace reports solid
# for a player who is merely standing on the ground.
const TOUCH_EPSILON := 0.0005

# What a brush is made of, so one world can answer different questions. Every
# solid blocks movement and ordinary shots; only some of them stop the special
# beam, which punches through low cover but not through a wall.
const CONTENT_SOLID := 1
const CONTENT_SPECIAL := 2
# Traces default to caring about anything solid.
const MASK_SOLID := CONTENT_SOLID
const MASK_SPECIAL := CONTENT_SPECIAL

# Planes of every brush, concatenated. A brush owns the slice described by its
# entry in _brush_first / _brush_count.
var _plane_normals := PackedVector3Array()
var _plane_dists := PackedFloat64Array()
var _brush_first := PackedInt32Array()
var _brush_count := PackedInt32Array()
var _brush_bounds: Array[AABB] = []
var _brush_mask := PackedInt32Array()

# Uniform XZ grid over the brush set. Arena maps are far wider than they are
# tall, so splitting on Y as well would buy nothing.
var _cell_size := 4.0
var _grid: Dictionary = {}
var _built := false

# Every brush's bounds unioned; ZERO-sized until the first brush lands.
var bounds := AABB()
var _has_bounds := false

# Scratch reused by the broadphase so a query allocates nothing.
var _visited: Dictionary = {}


func brush_count() -> int:
	return _brush_first.size()


func bounds_of(index: int) -> AABB:
	return _brush_bounds[index]


# Adds `bits` to a brush's contents, for classification the caller can only make
# once the brush's own extents are known.
func tag_brush(index: int, bits: int) -> void:
	_brush_mask[index] = _brush_mask[index] | bits


# Adds a convex hull. `planes` must face outward and enclose a bounded volume;
# `box` is the hull's own bounds, which the caller already knows from the vertex
# solve and so is not recomputed here. Returns the brush index.
func add_brush(planes: Array[Plane], box: AABB, mask := CONTENT_SOLID) -> int:
	var index := _brush_first.size()
	_brush_mask.append(mask)
	_brush_first.append(_plane_normals.size())

	var all := planes.duplicate()
	_add_bevels(all, box)

	_brush_count.append(all.size())
	for p: Plane in all:
		_plane_normals.append(p.normal)
		_plane_dists.append(p.d)
	_brush_bounds.append(box)
	_grow_bounds(box)
	_built = false
	return index


# Adds an axis-aligned box as a six-plane brush.
func add_box(box: AABB, mask := CONTENT_SOLID) -> int:
	var lo := box.position
	var hi := box.end
	var planes: Array[Plane] = [
		Plane(Vector3(1, 0, 0), hi.x),
		Plane(Vector3(-1, 0, 0), -lo.x),
		Plane(Vector3(0, 1, 0), hi.y),
		Plane(Vector3(0, -1, 0), -lo.y),
		Plane(Vector3(0, 0, 1), hi.z),
		Plane(Vector3(0, 0, -1), -lo.z),
	]
	return add_brush(planes, box, mask)


# Convenience for the declarative maps, whose compiler still emits AABBs.
func add_boxes(boxes: Array[AABB], mask := CONTENT_SOLID) -> void:
	for b: AABB in boxes:
		add_box(b, mask)


# Adds the six axis-aligned planes a brush does not already have.
#
# Pushing a face plane out by the box's reach along its normal is how a moving
# box becomes a moving point, but that is only exact where the brush's own faces
# bound it. The true swept volume is the Minkowski sum of the brush and the box,
# and that sum has faces the brush does not: axis-aligned ones, from the box's
# own faces. Leaving them out inflates the hull along every sloped edge, so a
# box near the top of a ramp reads as embedded while sitting in clear air above
# it, and a player standing there floats a finger's width off the surface.
#
# An axis-aligned brush already carries all six, so nothing is added to one and
# box maps are untouched.
static func _add_bevels(planes: Array[Plane], box: AABB) -> void:
	var axes: Array[Plane] = [
		Plane(Vector3(1, 0, 0), box.end.x),
		Plane(Vector3(-1, 0, 0), -box.position.x),
		Plane(Vector3(0, 1, 0), box.end.y),
		Plane(Vector3(0, -1, 0), -box.position.y),
		Plane(Vector3(0, 0, 1), box.end.z),
		Plane(Vector3(0, 0, -1), -box.position.z),
	]
	for bevel: Plane in axes:
		var have := false
		for p: Plane in planes:
			if p.normal.dot(bevel.normal) > 0.999:
				have = true
				break
		if not have:
			planes.append(bevel)


func _grow_bounds(box: AABB) -> void:
	if _has_bounds:
		bounds = bounds.merge(box)
	else:
		bounds = box
		_has_bounds = true


# Bins every brush into the XZ grid. Must be called after the last add_* and
# before the first query; the query path calls it if the caller forgot.
func build() -> void:
	_grid.clear()
	for i in _brush_first.size():
		var box := _brush_bounds[i]
		var x0 := int(floor(box.position.x / _cell_size))
		var x1 := int(floor(box.end.x / _cell_size))
		var z0 := int(floor(box.position.z / _cell_size))
		var z1 := int(floor(box.end.z / _cell_size))
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = PackedInt32Array()
				var cell: PackedInt32Array = _grid[key]
				cell.append(i)
				_grid[key] = cell
	_built = true


# Brush indices whose cells overlap `box`, each returned once. Iteration order is
# cell-major and then insertion order within a cell, which is stable for a given
# map build and so keeps traces deterministic.
func _candidates(box: AABB) -> PackedInt32Array:
	if not _built:
		build()
	var out := PackedInt32Array()
	_visited.clear()
	var x0 := int(floor(box.position.x / _cell_size))
	var x1 := int(floor(box.end.x / _cell_size))
	var z0 := int(floor(box.position.z / _cell_size))
	var z1 := int(floor(box.end.z / _cell_size))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				continue
			for i: int in _grid[key] as PackedInt32Array:
				if _visited.has(i):
					continue
				_visited[i] = true
				out.append(i)
	return out


# The volume a sweep from `start` to `target` with the given half extents can
# touch, used to pick broadphase cells.
static func _sweep_bounds(start: Vector3, target: Vector3, half: Vector3) -> AABB:
	var lo := Vector3(minf(start.x, target.x), minf(start.y, target.y), minf(start.z, target.z)) - half
	var hi := Vector3(maxf(start.x, target.x), maxf(start.y, target.y), maxf(start.z, target.z)) + half
	return AABB(lo, hi - lo)


# Sweeps a box, centred on `start` and moving to `target`, through the world.
# `half` is the box's half extents. Fills and returns `result`.
func trace_box(start: Vector3, target: Vector3, half: Vector3, result: TraceResult,
		mask := MASK_SOLID) -> TraceResult:
	result.reset(start, target)
	var sweep := _sweep_bounds(start, target, half)
	for i: int in _candidates(sweep):
		if (_brush_mask[i] & mask) == 0:
			continue
		if not _brush_bounds[i].intersects(sweep):
			continue
		_clip_to_brush(i, start, target, half, result)
		if result.all_solid:
			break
	result.end_pos = start + (target - start) * result.fraction
	return result


# Sweeps a zero-size point, i.e. a ray. Used by hitscan.
func raycast(from: Vector3, to: Vector3, result: TraceResult, mask := MASK_SOLID) -> TraceResult:
	return trace_box(from, to, Vector3.ZERO, result, mask)


# Distance along `dir` at which the world stops a ray, or `max_dist` when
# nothing does. This is the shape hitscan wants: it does not care what it hit.
func ray_distance(origin: Vector3, dir: Vector3, max_dist: float,
		result: TraceResult, mask := MASK_SOLID) -> float:
	raycast(origin, origin + dir * max_dist, result, mask)
	if not result.hit():
		return max_dist
	return result.fraction * max_dist


# Clips the sweep against one brush, tightening `result` when this brush stops
# the motion earlier than whatever already did.
func _clip_to_brush(index: int, start: Vector3, target: Vector3, half: Vector3,
		result: TraceResult) -> void:
	var first := _brush_first[index]
	var count := _brush_count[index]
	if count == 0:
		return

	# Latest entry into the hull and earliest exit from it. The sweep is inside
	# the hull only where enter < leave.
	var enter_frac := -1.0
	var leave_frac := 1.0
	var enter_normal := Vector3.ZERO
	# The sweep starts outside at least one plane, so it does not begin solid.
	var starts_out := false
	# The sweep ends outside at least one plane, so it does not end solid.
	var ends_out := false

	for k in count:
		var n := _plane_normals[first + k]
		var d := _plane_dists[first + k]
		# Push the plane out by the box's reach along this normal. For a box that
		# reach is the sum of the extents projected onto the normal, which makes
		# the expansion exact rather than the conservative sphere a capsule needs.
		var expanded := d + absf(n.x) * half.x + absf(n.y) * half.y + absf(n.z) * half.z
		var d_start := n.dot(start) - expanded
		var d_end := n.dot(target) - expanded

		if d_start > -TOUCH_EPSILON:
			starts_out = true
		if d_end > -TOUCH_EPSILON:
			ends_out = true

		# Wholly outside this plane, so wholly outside the hull. Kept strict so a
		# sweep that is barely inside is still tested rather than discarded.
		if d_start > 0.0 and d_end > 0.0:
			return
		# Wholly inside this plane; it cannot bound the crossing. A start that is
		# only within the slack counts as on the plane, not behind it, so the
		# surface a resting player stands on can still stop them.
		if d_start <= -TOUCH_EPSILON and d_end <= -TOUCH_EPSILON:
			continue

		if d_start > d_end:
			# Crossing inward: the last such plane is the one actually hit.
			var f := (d_start - SURFACE_OFFSET) / (d_start - d_end)
			if f > enter_frac:
				enter_frac = f
				enter_normal = n
		else:
			# Crossing outward: the first such plane is where the hull is left.
			var f := (d_start + SURFACE_OFFSET) / (d_start - d_end)
			if f < leave_frac:
				leave_frac = f

	if not starts_out:
		# Began embedded. Callers need to know, because the response is to push
		# out rather than to slide, and a solid start otherwise reports as a
		# zero-length move against a surface that is not really there.
		result.start_solid = true
		result.fraction = 0.0
		result.brush = index
		if not ends_out:
			result.all_solid = true
		return

	if enter_frac < leave_frac and enter_frac > -1.0 and enter_frac < result.fraction:
		result.fraction = maxf(enter_frac, 0.0)
		result.normal = enter_normal
		result.brush = index


# True when a box centred at `centre` overlaps any brush. Cheaper than a trace
# for the crouch-to-stand check, which only needs a yes or no.
func box_overlaps(centre: Vector3, half: Vector3) -> bool:
	var probe := AABB(centre - half, half * 2.0).grow(TOUCH_EPSILON)
	for i: int in _candidates(probe):
		if not _brush_bounds[i].intersects(probe):
			continue
		var first := _brush_first[i]
		var count := _brush_count[i]
		if count == 0:
			continue
		var inside := true
		for k in count:
			var n := _plane_normals[first + k]
			var d := _plane_dists[first + k]
			var expanded := d + absf(n.x) * half.x + absf(n.y) * half.y + absf(n.z) * half.z
			if n.dot(centre) - expanded > -TOUCH_EPSILON:
				inside = false
				break
		if inside:
			return true
	return false


# Smallest translation that frees a box embedded in solid geometry, or ZERO when
# it is already clear. A convex hull is left fastest through the plane the box
# sits least deep behind, so each overlapped brush contributes that one push.
# They are applied in turn because escaping one brush can push into its
# neighbour, which is what happens in a corner.
func depenetrate(centre: Vector3, half: Vector3, passes := 4) -> Vector3:
	var total := Vector3.ZERO
	var at := centre
	for _pass in passes:
		var push := _escape_one(at, half)
		if push == Vector3.ZERO:
			break
		total += push
		at += push
	return total


func _escape_one(centre: Vector3, half: Vector3) -> Vector3:
	var probe := AABB(centre - half, half * 2.0).grow(TOUCH_EPSILON)
	for i: int in _candidates(probe):
		if not _brush_bounds[i].intersects(probe):
			continue
		var first := _brush_first[i]
		var count := _brush_count[i]
		if count == 0:
			continue
		var shallowest := -INF
		var escape_normal := Vector3.ZERO
		var embedded := true
		for k in count:
			var n := _plane_normals[first + k]
			var d := _plane_dists[first + k]
			var expanded := d + absf(n.x) * half.x + absf(n.y) * half.y + absf(n.z) * half.z
			var dist := n.dot(centre) - expanded
			if dist > -TOUCH_EPSILON:
				embedded = false
				break
			if dist > shallowest:
				shallowest = dist
				escape_normal = n
		if not embedded or escape_normal == Vector3.ZERO:
			continue
		# Clear the surface by more than the slack, so the box lands strictly
		# outside rather than flush against it again.
		return escape_normal * (-shallowest + TOUCH_EPSILON * 2.0)
	return Vector3.ZERO
