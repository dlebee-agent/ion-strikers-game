class_name BotNav
extends RefCounted

## Per-map sight and walk data, built once and shared by every bot on it.
##
## Both halves come off the same brush world the hitscan shoots against, so a bot
## can never believe it sees a target the laser cannot reach, and never plan a
## route the collision resolver will refuse to walk.

const CELL := 1.0
const BODY_RADIUS := 0.4
## Mirrors Movement.STEP_LIP: the tallest rise a body walks up without jumping.
const STEP_UP := 0.35
## Bots do not jump, so anything taller than this is a one-way drop they take
## rather than a ledge they could ever come back up.
const MAX_DROP := 2.6
## Mirrors Movement.MIN_WALK_NORMAL: shallower than this is a wall, not a floor.
const MIN_WALK_NORMAL := 0.7
## Levels to look through in one column before giving up on it.
const MAX_LAYERS := 8
## Half-thickness of the pad surface_at drops, thin enough to read a surface
## height without catching on anything beside it.
const PAD_HALF_HEIGHT := 0.02
const BODY_HEIGHT := 1.7
const WALK_SAMPLE := 0.45

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var world: CollisionWorld = null
var arena: float = 28.0
## Every cell a bot can stand on and reach, as world positions. Roam goals are
## drawn from here so a wandering bot never picks a spot inside a wall.
var open_points: PackedVector3Array = PackedVector3Array()

var _dim: int = 0
var _height: PackedFloat32Array = PackedFloat32Array()
## The surface normal under each cell. A rise bigger than a step is only
## walkable along a slope's own gradient, and the full normal is what says which
## way that runs.
var _normal: PackedVector3Array = PackedVector3Array()
var _probe := TraceResult.new()
var _open: PackedByteArray = PackedByteArray()
var _astar: AStar3D = null


func build(p_world: CollisionWorld, p_arena: float, seeds: Array[Vector3]) -> void:
	world = p_world
	arena = p_arena
	_dim = int(floor(arena * 2.0 / CELL)) + 1

	var count := _dim * _dim
	_height = PackedFloat32Array()
	_height.resize(count)
	_normal = PackedVector3Array()
	_normal.resize(count)
	_open = PackedByteArray()
	_open.resize(count)

	for iz in _dim:
		for ix in _dim:
			var idx := iz * _dim + ix
			var found := _standable(_axis_world(ix), _axis_world(iz))
			if found.is_empty():
				_open[idx] = 0
				_height[idx] = 0.0
				_normal[idx] = Vector3.UP
			else:
				_open[idx] = 1
				_height[idx] = found[0]
				_normal[idx] = found[1]

	_prune_to_reachable(seeds)
	_build_graph()


# ── visibility ───────────────────────────────────────────────────────────

## True when map geometry sits between the two points. Exact segment-vs-box,
## not a sampled one: a sample-based test walks straight past a thin wall.
func blocked(from: Vector3, to: Vector3) -> bool:
	if world == null:
		return false
	world.raycast(from, to, _probe)
	return _probe.hit()


## Highest surface under the footprint that is no higher than `ceiling`.
## Doubles as the step-up target and the landing height, since both ask the same
## question: what is the highest thing within reach of these feet?
func surface_at(x: float, z: float, ceiling: float, radius := BODY_RADIUS) -> float:
	if world == null:
		return -INF
	# A thin pad, dropped from the ceiling. Sweeping the footprint rather than
	# reading bounding box tops is what lets this land partway up a ramp instead
	# of at its peak.
	#
	# The radius is a parameter because two different questions get asked of it.
	# The body-width pad answers "is anything holding me up", which is what keeps
	# a bot on a ledge it is only half standing on. A narrow pad answers "is the
	# surface under me", which is what climbing has to be judged against — see
	# BotDirector._apply_motion.
	var half := Vector3(radius, PAD_HALF_HEIGHT, radius)
	var basement := world.bounds.position.y - 1.0
	world.trace_box(Vector3(x, ceiling + half.y, z), Vector3(x, basement, z), half, _probe)
	if not _probe.hit() or _probe.start_solid:
		return -INF
	return _probe.end_pos.y - half.y


# ── routing ──────────────────────────────────────────────────────────────

## Waypoints from `from` to `to`, already pulled taut so a bot cuts corners
## instead of tracing the grid. Empty when there is no route.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _astar == null:
		return PackedVector3Array()

	var start := nearest_id(from)
	var goal := nearest_id(to)
	if start < 0 or goal < 0:
		return PackedVector3Array()
	if start == goal:
		var single := PackedVector3Array()
		single.append(_astar.get_point_position(goal))
		return single

	var raw := _astar.get_point_path(start, goal)
	if raw.size() < 3:
		return raw
	return _string_pull(from, raw)


## Index of the nearest cell a body could stand in, or -1 when the whole
## neighbourhood is solid.
func nearest_id(pos: Vector3) -> int:
	var cx := _axis_index(pos.x)
	var cz := _axis_index(pos.z)

	for ring in 5:
		var best := -1
		var best_score := INF
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var ix := cx + dx
				var iz := cz + dz
				if ix < 0 or ix >= _dim or iz < 0 or iz >= _dim:
					continue
				var idx := iz * _dim + ix
				if _open[idx] == 0:
					continue
				var score := absf(_height[idx] - pos.y)
				if score < best_score:
					best_score = score
					best = idx
		if best >= 0:
			return best
	return -1


## True when a body can walk the straight line between two points: every cell it
## crosses is standable and no rise along the way is taller than a step.
func walk_clear(from: Vector3, to: Vector3) -> bool:
	var dx := to.x - from.x
	var dz := to.z - from.z
	var dist := sqrt(dx * dx + dz * dz)
	var steps := maxi(1, int(ceil(dist / WALK_SAMPLE)))
	var prev := from.y
	var step_dir := Vector2(dx, dz).normalized() if dist > 0.0001 else Vector2.ZERO

	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var idx := _index_at(from.x + dx * t, from.z + dz * t)
		if idx < 0 or _open[idx] == 0:
			return false
		var h: float = _height[idx]
		if prev - h > MAX_DROP:
			return false
		# Same allowance the graph uses, so a route over a ramp is not pulled
		# straight into one the walk test then rejects.
		if h - prev > STEP_UP + _slope_rise(_normal[idx], step_dir, WALK_SAMPLE):
			return false
		prev = h

	return true


# ── build helpers ────────────────────────────────────────────────────────

func _axis_world(i: int) -> float:
	return -arena + float(i) * CELL


func _axis_index(v: float) -> int:
	return clampi(int(round((v + arena) / CELL)), 0, _dim - 1)


func _index_at(x: float, z: float) -> int:
	if x < -arena - CELL or x > arena + CELL or z < -arena - CELL or z > arena + CELL:
		return -1
	return _axis_index(z) * _dim + _axis_index(x)


## Highest surface over this column that a standing body actually fits on, as
## [feet height, surface normal], or empty when there is nowhere to stand.
## Walked from the top down so a catwalk wins over the floor beneath it, but a
## body squeezed under one still finds the floor.
##
## This sweeps the body itself rather than reading the tops of bounding boxes.
## A ramp's bounding box has one top, its peak, so reading that gave every cell
## along the ramp the same height and made the floor-to-ramp join look like a
## cliff no bot would step up.
func _standable(x: float, z: float) -> Array:
	if world == null:
		return []
	var half := Vector3(BODY_RADIUS, BODY_HEIGHT * 0.5, BODY_RADIUS)
	var ceiling := world.bounds.end.y + 1.0
	var basement := world.bounds.position.y - 1.0
	var from_y := ceiling

	for _layer in MAX_LAYERS:
		if from_y <= basement:
			break
		world.trace_box(Vector3(x, from_y, z), Vector3(x, basement, z), half, _probe)
		if not _probe.hit():
			break
		var feet := _probe.end_pos.y - half.y
		if _probe.normal.y >= MIN_WALK_NORMAL and _fits(x, z, feet):
			return [feet, _probe.normal]
		# Too steep, or no headroom. Drop under this surface and keep looking.
		from_y = _probe.end_pos.y - 0.05

	return []


## Nothing overlaps a body standing here.
func _fits(x: float, z: float, feet: float) -> bool:
	if world == null:
		return false
	var half := Vector3(BODY_RADIUS, BODY_HEIGHT * 0.5, BODY_RADIUS)
	return not world.box_overlaps(Vector3(x, feet + half.y, z), half)


func _can_step(from_idx: int, to_idx: int) -> bool:
	var dh: float = _height[to_idx] - _height[from_idx]
	if dh < -MAX_DROP:
		return false
	if dh <= STEP_UP:
		return true
	# A rise taller than a step is only walkable along a slope's own gradient.
	# Allowing it merely because the destination is sloped lets a bot walk at a
	# ramp's side wall, since the cell on top of that wall is sloped too, and
	# they get stuck trying to climb it sideways. What the surface would actually
	# rise over this step, given which way it tilts, is the test.
	var fx := from_idx % _dim
	var fz := from_idx / _dim
	var tx := to_idx % _dim
	var tz := to_idx / _dim
	var step := Vector2(tx - fx, tz - fz)
	if step.length_squared() < 0.0001:
		return false
	return dh <= STEP_UP + _slope_rise(_normal[to_idx], step.normalized(), CELL * step.length())


## How far the surface climbs over a step of `run` metres in horizontal direction
## `dir`, given its normal. Negative going downhill, zero across the gradient.
static func _slope_rise(normal: Vector3, dir: Vector2, run: float) -> float:
	if normal.y < 0.001:
		return 0.0
	# The normal leans downhill, so the height gained going `dir` is the
	# opposite of its lean along `dir`, scaled by how steeply it tilts.
	return -run * (normal.x * dir.x + normal.z * dir.y) / normal.y


## Diagonals may not clip a corner: both orthogonal cells have to be walkable
## from the same starting height too.
func _diagonal_ok(ix: int, iz: int, d: Vector2i, idx: int) -> bool:
	if d.x == 0 or d.y == 0:
		return true
	var a := iz * _dim + (ix + d.x)
	var b := (iz + d.y) * _dim + ix
	if _open[a] == 0 or _open[b] == 0:
		return false
	return _can_step(idx, a) and _can_step(idx, b)


## Wall tops and jump-only pillars pass the standing test but no bot can ever get
## to them, so the grid keeps only what is reachable on foot from a spawn.
## Reachability is judged on two-way edges: a ledge a bot could drop off but
## never climb back onto is not somewhere to send one.
func _prune_to_reachable(seeds: Array[Vector3]) -> void:
	var reached := PackedByteArray()
	reached.resize(_dim * _dim)

	var queue: Array[int] = []
	for seed_pos in seeds:
		var idx := nearest_id(seed_pos)
		if idx >= 0 and reached[idx] == 0:
			reached[idx] = 1
			queue.append(idx)

	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var ix := idx % _dim
		var iz := idx / _dim
		for d in NEIGHBORS:
			var nx := ix + d.x
			var nz := iz + d.y
			if nx < 0 or nx >= _dim or nz < 0 or nz >= _dim:
				continue
			var n_idx := nz * _dim + nx
			if reached[n_idx] == 1 or _open[n_idx] == 0:
				continue
			if not _can_step(idx, n_idx) or not _can_step(n_idx, idx):
				continue
			if not _diagonal_ok(ix, iz, d, idx):
				continue
			reached[n_idx] = 1
			queue.append(n_idx)

	for i in _open.size():
		if reached[i] == 0:
			_open[i] = 0


func _build_graph() -> void:
	_astar = AStar3D.new()
	_astar.reserve_space(_dim * _dim)
	open_points = PackedVector3Array()

	for iz in _dim:
		for ix in _dim:
			var idx := iz * _dim + ix
			if _open[idx] == 0:
				continue
			var pos := Vector3(_axis_world(ix), _height[idx], _axis_world(iz))
			_astar.add_point(idx, pos)
			open_points.append(pos)

	for iz in _dim:
		for ix in _dim:
			var idx := iz * _dim + ix
			if _open[idx] == 0:
				continue
			for d in NEIGHBORS:
				var nx := ix + d.x
				var nz := iz + d.y
				if nx < 0 or nx >= _dim or nz < 0 or nz >= _dim:
					continue
				var n_idx := nz * _dim + nx
				if _open[n_idx] == 0 or not _can_step(idx, n_idx):
					continue
				if not _diagonal_ok(ix, iz, d, idx):
					continue
				_astar.connect_points(idx, n_idx, false)


## Grid paths staircase around every corner. Keeping only the furthest waypoint
## still reachable in a straight line turns that back into the line a player
## would take. The look-ahead is capped so a long route stays cheap.
func _string_pull(start: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	const LOOK_AHEAD := 8
	var out := PackedVector3Array()
	var anchor := Vector3(start.x, start.y, start.z)
	var i := 0

	while i < path.size():
		var limit := mini(path.size() - 1, i + LOOK_AHEAD)
		var pick := i
		for j in range(limit, i, -1):
			if walk_clear(anchor, path[j]):
				pick = j
				break
		out.append(path[pick])
		anchor = path[pick]
		i = pick + 1

	return out
