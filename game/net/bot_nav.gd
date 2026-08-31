class_name BotNav
extends RefCounted

## Per-map sight and walk data, built once and shared by every bot on it.
##
## Both halves come off the same AABB list the hitscan shoots against, so a bot
## can never believe it sees a target the laser cannot reach, and never plan a
## route the collision resolver will refuse to walk.

const CELL := 1.0
const BODY_RADIUS := 0.4
## Mirrors Movement.STEP_LIP: the tallest rise a body walks up without jumping.
const STEP_UP := 0.35
## Bots do not jump, so anything taller than this is a one-way drop they take
## rather than a ledge they could ever come back up.
const MAX_DROP := 2.6
const BODY_HEIGHT := 1.7
const WALK_SAMPLE := 0.45

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var colliders: Array[AABB] = []
var arena: float = 28.0
## Every cell a bot can stand on and reach, as world positions. Roam goals are
## drawn from here so a wandering bot never picks a spot inside a wall.
var open_points: PackedVector3Array = PackedVector3Array()

var _dim: int = 0
var _height: PackedFloat32Array = PackedFloat32Array()
var _open: PackedByteArray = PackedByteArray()
var _astar: AStar3D = null


func build(p_colliders: Array[AABB], p_arena: float, seeds: Array[Vector3]) -> void:
	colliders = p_colliders
	arena = p_arena
	_dim = int(floor(arena * 2.0 / CELL)) + 1

	var count := _dim * _dim
	_height = PackedFloat32Array()
	_height.resize(count)
	_open = PackedByteArray()
	_open.resize(count)

	for iz in _dim:
		for ix in _dim:
			var idx := iz * _dim + ix
			var h := _standable_height(_axis_world(ix), _axis_world(iz))
			if h == -INF:
				_open[idx] = 0
				_height[idx] = 0.0
			else:
				_open[idx] = 1
				_height[idx] = h

	_prune_to_reachable(seeds)
	_build_graph()


# ── visibility ───────────────────────────────────────────────────────────

## True when map geometry sits between the two points. Exact segment-vs-box,
## not a sampled one: a sample-based test walks straight past a thin wall.
func blocked(from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var lo := Vector3(minf(from.x, to.x), minf(from.y, to.y), minf(from.z, to.z))
	var hi := Vector3(maxf(from.x, to.x), maxf(from.y, to.y), maxf(from.z, to.z))

	for box in colliders:
		if box.end.x < lo.x or box.position.x > hi.x:
			continue
		if box.end.y < lo.y or box.position.y > hi.y:
			continue
		if box.end.z < lo.z or box.position.z > hi.z:
			continue
		if _segment_hits(from, d, box):
			return true
	return false


static func _segment_hits(from: Vector3, d: Vector3, box: AABB) -> bool:
	var t_min := 0.0
	var t_max := 1.0
	var lo := box.position
	var hi := box.end

	for axis in 3:
		var dd: float = d[axis]
		var o: float = from[axis]
		if absf(dd) < 1e-9:
			if o < lo[axis] or o > hi[axis]:
				return false
			continue
		var t1: float = (lo[axis] - o) / dd
		var t2: float = (hi[axis] - o) / dd
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return false

	return true


# ── standing ─────────────────────────────────────────────────────────────

## Top of the tallest box under the footprint that is no higher than `ceiling`.
## Doubles as the step-up target and the landing height, since both ask the same
## question: what is the highest thing within reach of these feet?
func surface_at(x: float, z: float, ceiling: float) -> float:
	var best := -INF
	for box in colliders:
		var top := box.end.y
		if top > ceiling or top <= best:
			continue
		if x <= box.position.x - BODY_RADIUS or x >= box.end.x + BODY_RADIUS:
			continue
		if z <= box.position.z - BODY_RADIUS or z >= box.end.z + BODY_RADIUS:
			continue
		best = top
	return best


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

	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var idx := _index_at(from.x + dx * t, from.z + dz * t)
		if idx < 0 or _open[idx] == 0:
			return false
		var h: float = _height[idx]
		if h - prev > STEP_UP or prev - h > MAX_DROP:
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


## Highest surface over this column that a standing body actually fits on. Walked
## from the top down so a catwalk wins over the floor beneath it, but a body
## squeezed under one still finds the floor.
func _standable_height(x: float, z: float) -> float:
	var tops: Array[float] = []
	for box in colliders:
		if x < box.position.x or x > box.end.x:
			continue
		if z < box.position.z or z > box.end.z:
			continue
		if not tops.has(box.end.y):
			tops.append(box.end.y)

	tops.sort()
	tops.reverse()
	for top in tops:
		if _fits(x, z, top):
			return top
	return -INF


## Nothing juts up through the body: anything more than a step above the feet and
## low enough to be in the way blocks the cell.
func _fits(x: float, z: float, feet: float) -> bool:
	for box in colliders:
		if box.end.y <= feet + STEP_UP or box.position.y >= feet + BODY_HEIGHT:
			continue
		if x <= box.position.x - BODY_RADIUS or x >= box.end.x + BODY_RADIUS:
			continue
		if z <= box.position.z - BODY_RADIUS or z >= box.end.z + BODY_RADIUS:
			continue
		return false
	return true


func _can_step(from_idx: int, to_idx: int) -> bool:
	var dh: float = _height[to_idx] - _height[from_idx]
	return dh <= STEP_UP and dh >= -MAX_DROP


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
