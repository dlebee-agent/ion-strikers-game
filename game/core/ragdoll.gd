class_name Ragdoll
extends RefCounted

# Verlet ragdoll over the mannequin's Skeleton3D — ported from Mathias's
# laser-arena/public/ragdoll.js.  Bones become point masses joined by distance
# constraints; an impulse shaped by death cause launches them; they fall under
# gravity against the map's brush geometry.  Cosmetic and client-only.

const GRAVITY := 20.32
const DAMP := 0.985
const GROUND_FRICTION := 0.7
const ITERATIONS := 6
const SETTLE_SPEED := 0.06
const SETTLE_TIME := 0.45
const MAX_STEP := 1.0 / 60.0
const MIN_LENGTH_FACTOR := 0.55
const BRACE_STIFFNESS := 0.35

const BONE_NAMES: Array[String] = [
	"pelvis", "spine_02", "spine_03", "neck_01", "Head",
	"upperarm_l", "lowerarm_l", "hand_l",
	"upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l",
	"thigh_r", "calf_r", "foot_r",
]

const CHAIN: Array[Array] = [
	["pelvis", "spine_02"], ["spine_02", "spine_03"],
	["spine_03", "neck_01"], ["neck_01", "Head"],
	["spine_03", "upperarm_l"], ["upperarm_l", "lowerarm_l"],
	["lowerarm_l", "hand_l"],
	["spine_03", "upperarm_r"], ["upperarm_r", "lowerarm_r"],
	["lowerarm_r", "hand_r"],
	["pelvis", "thigh_l"], ["thigh_l", "calf_l"], ["calf_l", "foot_l"],
	["pelvis", "thigh_r"], ["thigh_r", "calf_r"], ["calf_r", "foot_r"],
]

const BRACE: Array[Array] = [
	["upperarm_l", "upperarm_r"], ["thigh_l", "thigh_r"],
	["upperarm_l", "thigh_r"], ["upperarm_r", "thigh_l"],
	["spine_03", "thigh_l"], ["spine_03", "thigh_r"],
	["neck_01", "upperarm_l"], ["neck_01", "upperarm_r"],
]

const LIMIT: Array[Array] = [
	["upperarm_l", "hand_l"], ["upperarm_r", "hand_r"],
	["thigh_l", "foot_l"], ["thigh_r", "foot_r"],
	["pelvis", "Head"],
]

const RADIUS := {
	"pelvis": 0.17, "spine_02": 0.15, "spine_03": 0.15,
	"neck_01": 0.10, "Head": 0.13,
	"upperarm_l": 0.08, "lowerarm_l": 0.07, "hand_l": 0.06,
	"upperarm_r": 0.08, "lowerarm_r": 0.07, "hand_r": 0.06,
	"thigh_l": 0.10, "calf_l": 0.08, "foot_l": 0.08,
	"thigh_r": 0.10, "calf_r": 0.08, "foot_r": 0.08,
}

const UPPER: Array[String] = [
	"spine_02", "spine_03", "neck_01", "Head",
	"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
	"hand_l", "hand_r",
]
const LOWER: Array[String] = [
	"thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r",
]

# --- per-particle state ---
# Indexed by bone name.  Each entry: { pos: Vector3, prev: Vector3, r: float, grounded: bool }
var parts: Dictionary = {}

# --- constraint links ---
# Array of { a: String, b: String, d: float, kind: String }
var links: Array[Dictionary] = []

# --- rest-pose data for skeleton write-back ---
# bone name -> { rot: Quaternion, axis: Vector3 or null }
var rest: Dictionary = {}
# bone name -> child bone name (first child in CHAIN)
var child_of: Dictionary = {}

# --- skeleton refs ---
var _skeleton: Skeleton3D
var _bone_idx: Dictionary = {}  # bone name -> Skeleton3D bone index
var _anim_player: AnimationPlayer

var settled := false
var calm := 0.0
var dead := false

# The world-space position of the Head particle, updated every apply().
var head_pos := Vector3.ZERO


# Build from the skeleton's current (posed) state.  Returns null via the static
# helper when a required bone is missing.
static func try_build(skeleton: Skeleton3D, anim_player: AnimationPlayer) -> Ragdoll:
	if not skeleton:
		return null
	var idx_map := {}
	for bone_name: String in BONE_NAMES:
		var idx := skeleton.find_bone(bone_name)
		if idx == -1:
			return null
		idx_map[bone_name] = idx

	var rag := Ragdoll.new()
	rag._skeleton = skeleton
	rag._bone_idx = idx_map
	rag._anim_player = anim_player

	# Seed particles from the current global pose (the pose they died in).
	var skel_xform := skeleton.global_transform
	for bone_name: String in BONE_NAMES:
		var gp: Transform3D = skel_xform * skeleton.get_bone_global_pose(idx_map[bone_name])
		var world_pos := gp.origin
		rag.parts[bone_name] = {
			"pos": world_pos,
			"prev": Vector3(world_pos.x, world_pos.y, world_pos.z),
			"r": float(RADIUS.get(bone_name, 0.08)),
			"grounded": false,
		}

	# Build links from current inter-bone distances.
	for pair: Array in CHAIN:
		rag._add_link(pair[0], pair[1], "rigid")
	for pair: Array in BRACE:
		rag._add_link(pair[0], pair[1], "brace")
	for pair: Array in LIMIT:
		rag._add_link(pair[0], pair[1], "min")

	# First child in CHAIN per bone, for rotation write-back.
	for pair: Array in CHAIN:
		if not rag.child_of.has(pair[0]):
			rag.child_of[pair[0]] = pair[1]

	# Rest rotation + local axis toward child, measured from the death pose.
	for bone_name: String in BONE_NAMES:
		var gp: Transform3D = skel_xform * skeleton.get_bone_global_pose(idx_map[bone_name])
		var rot := gp.basis.get_rotation_quaternion()
		var axis: Variant = null
		if rag.child_of.has(bone_name):
			var child_name: String = rag.child_of[bone_name]
			var cp: Transform3D = skel_xform * skeleton.get_bone_global_pose(idx_map[child_name])
			var dir := (cp.origin - gp.origin).normalized()
			var inv_rot := rot.inverse()
			var local_dir := inv_rot * dir
			axis = local_dir.normalized()
		rag.rest[bone_name] = { "rot": rot, "axis": axis }

	# Stop the AnimationPlayer so clips cannot fight the pose overrides.
	if anim_player and anim_player.is_playing():
		anim_player.stop()

	rag.head_pos = rag.parts["Head"]["pos"]
	return rag


func _add_link(a: String, b: String, kind: String) -> void:
	var dist := (parts[a]["pos"] as Vector3).distance_to(parts[b]["pos"] as Vector3)
	links.append({ "a": a, "b": b, "d": dist, "kind": kind })


# --- kick: cause-shaped impulse ---------------------------------------------------

func kick(dir: Vector3, cause: String, vel: Vector3) -> void:
	var h_dir := Vector3(dir.x, 0.0, dir.z)
	if h_dir.length_squared() > 0.0001:
		h_dir = h_dir.normalized()
	else:
		h_dir = Vector3.ZERO

	var spin := (randf() - 0.5) * 2.0

	# Victim momentum on every bone.
	for bone_name: String in BONE_NAMES:
		_push(bone_name, vel.x, vel.y * 0.6, vel.z)

	if cause == "head":
		_push("Head", h_dir.x * 7.5, 3.2, h_dir.z * 7.5)
		_push("neck_01", h_dir.x * 5.0, 2.0, h_dir.z * 5.0)
		for n: String in UPPER:
			_push(n, h_dir.x * 1.8, 0.5, h_dir.z * 1.8)
		for n: String in LOWER:
			_push(n, h_dir.x * 0.6, 0.0, h_dir.z * 0.6)
	elif cause == "melee":
		for n: String in UPPER:
			_push(n, h_dir.x * 5.5, 1.6, h_dir.z * 5.5)
		for n: String in LOWER:
			_push(n, h_dir.x * 2.0, 0.2, h_dir.z * 2.0)
	elif cause == "meteor":
		for bone_name: String in BONE_NAMES:
			_push(bone_name, h_dir.x * 4.5, 7.0 + randf() * 2.0, h_dir.z * 4.5)
	elif cause == "special":
		for n: String in UPPER:
			_push(n, h_dir.x * 7.0, 2.6, h_dir.z * 7.0)
		for n: String in LOWER:
			_push(n, h_dir.x * 3.4, 1.2, h_dir.z * 3.4)
	else:
		# laser (default)
		_push("spine_03", h_dir.x * 3.4, 0.8, h_dir.z * 3.4)
		for n: String in UPPER:
			_push(n, h_dir.x * 2.0, 0.4, h_dir.z * 2.0)
		for n: String in LOWER:
			_push(n, h_dir.x * 0.7, 0.0, h_dir.z * 0.7)

	# Tumble: opposite sideways kicks on upper vs lower body.
	var side := Vector3(-h_dir.z, 0.0, h_dir.x)
	var t := 1.1 * spin
	for n: String in UPPER:
		_push(n, side.x * t, 0.0, side.z * t)
	for n: String in LOWER:
		_push(n, -side.x * t, 0.0, -side.z * t)


func _push(bone_name: String, vx: float, vy: float, vz: float) -> void:
	if not parts.has(bone_name):
		return
	var p: Dictionary = parts[bone_name]
	p["prev"] = (p["prev"] as Vector3) - Vector3(vx, vy, vz) * MAX_STEP


# --- simulation ----------------------------------------------------------------

## `kill_y` is where the world gives up on a body that fell out of it. A
## world of null falls back to a flat floor at y=0, which is what the menu
## mannequin and the tests stand on.
func update(dt: float, world: CollisionWorld, kill_y: float = -INF) -> void:
	if settled or dead:
		return
	var remain := minf(dt, 0.1)
	while remain > 0.0001:
		var step_dt := minf(remain, MAX_STEP)
		_step(step_dt, world, kill_y)
		remain -= step_dt
	_apply()


func _step(dt: float, world: CollisionWorld, kill_y: float) -> void:
	var moved := 0.0
	for bone_name: String in BONE_NAMES:
		var p: Dictionary = parts[bone_name]
		var pos: Vector3 = p["pos"]
		var prev: Vector3 = p["prev"]
		var v := (pos - prev) * DAMP
		p["prev"] = pos
		var new_pos := pos + v
		new_pos.y -= GRAVITY * dt * dt
		if p["grounded"]:
			new_pos.x -= v.x * GROUND_FRICTION
			new_pos.z -= v.z * GROUND_FRICTION
		p["pos"] = new_pos
		moved += absf(v.x) + absf(v.y) + absf(v.z)

	for _it in ITERATIONS:
		_solve_constraints()
		_collide(world, kill_y)

	calm = calm + dt if moved / (BONE_NAMES.size() * dt) < SETTLE_SPEED else 0.0
	if calm > SETTLE_TIME:
		settled = true


func _solve_constraints() -> void:
	for L: Dictionary in links:
		var pa: Dictionary = parts[L["a"]]
		var pb: Dictionary = parts[L["b"]]
		var a_pos: Vector3 = pa["pos"]
		var b_pos: Vector3 = pb["pos"]
		var delta := b_pos - a_pos
		var d := delta.length()
		if d < 1e-6:
			d = 1e-6

		var kind: String = L["kind"]
		var rest_d: float = L["d"]

		if kind == "min" and d >= rest_d * MIN_LENGTH_FACTOR:
			continue

		var target: float = rest_d * MIN_LENGTH_FACTOR if kind == "min" else rest_d
		var stiff: float = BRACE_STIFFNESS if kind == "brace" else 1.0
		var diff := ((d - target) / d) * 0.5 * stiff
		var offset := delta * diff
		pa["pos"] = a_pos + offset
		pb["pos"] = b_pos - offset


func _collide(world: CollisionWorld, kill_y: float) -> void:
	for bone_name: String in BONE_NAMES:
		var p: Dictionary = parts[bone_name]
		var pos: Vector3 = p["pos"]
		var r: float = p["r"]
		p["grounded"] = false

		if world == null:
			if pos.y - r < 0.0:
				pos.y = r
				p["grounded"] = true
		else:
			# The bone is pushed out as a cube of its own radius rather than a
			# sphere. A cube is what the brush world resolves exactly, and it is
			# what lets a body settle on a ramp face instead of on the flat top
			# of the ramp's bounding box.
			var push := world.depenetrate(pos, Vector3(r, r, r))
			if push != Vector3.ZERO:
				pos += push
				if push.y > 0.001:
					p["grounded"] = true

		if kill_y > -1e8 and pos.y < kill_y:
			dead = true

		p["pos"] = pos



func _apply() -> void:
	var skel_inv := _skeleton.global_transform.affine_inverse()
	for bone_name: String in BONE_NAMES:
		var p: Dictionary = parts[bone_name]
		var pos: Vector3 = p["pos"]
		var idx: int = _bone_idx[bone_name]
		var r_data: Dictionary = rest[bone_name]

		var rot: Quaternion = r_data["rot"]
		if child_of.has(bone_name) and r_data["axis"] != null:
			var child_name: String = child_of[bone_name]
			var child_pos: Vector3 = parts[child_name]["pos"]
			var world_dir := (child_pos - pos).normalized()
			var rest_axis: Vector3 = r_data["axis"]
			var cur_world := rot * rest_axis
			rot = _quat_from_to(cur_world, world_dir) * rot

		var world_xform := Transform3D(Basis(rot), pos)
		var local_xform := skel_inv * world_xform
		_skeleton.set_bone_global_pose_override(idx, local_xform, 1.0, true)

	head_pos = parts["Head"]["pos"]


static func _quat_from_to(a: Vector3, b: Vector3) -> Quaternion:
	var d := a.dot(b)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var perp := Vector3(1.0, 0.0, 0.0)
		if absf(a.x) > 0.9:
			perp = Vector3(0.0, 1.0, 0.0)
		var axis := a.cross(perp).normalized()
		return Quaternion(axis.x, axis.y, axis.z, 0.0)
	var c := a.cross(b)
	var q := Quaternion(c.x, c.y, c.z, 1.0 + d)
	return q.normalized()


# --- teardown ------------------------------------------------------------------

func end() -> void:
	for bone_name: String in BONE_NAMES:
		if _bone_idx.has(bone_name):
			_skeleton.set_bone_global_pose_override(_bone_idx[bone_name],
				Transform3D.IDENTITY, 0.0, false)
	if _anim_player:
		_anim_player.stop()
