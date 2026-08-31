class_name SpectatorCam
extends Node3D

const Movement = preload("res://core/movement.gd")
const RemotePawn = preload("res://core/remote_pawn.gd")

enum ViewMode { FREE_FLY, FPV }
enum FollowState { NONE, DEATH_SETTLE, TEAMMATE, IDLE_ORBIT }

const FLY_SPEED := 14.0
const FLY_BOOST := 2.2
const PITCH_LIMIT := 89.0

const SPEC_FLY_SPEED := 26.0
const SPEC_FLY_MIN := 0.35
const SPEC_FLY_MAX := 1.2

const DEATH_PULLBACK := 2.6
const DEATH_SETTLE_SPEED := 0.7
const DEATH_RIGIDITY := 0.4
const DEATH_REVEAL := 0.8
const DEATH_KILLER_BIAS := 0.55
const DEATH_SKIM := 0.3
const DEATH_LOOK_INTERVAL := 0.25

const ORBIT_RADIUS := 26.0
const ORBIT_HEIGHT := 22.0

var _camera: Camera3D
var _pos := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _arena_size := 28.0

var view_mode: ViewMode = ViewMode.FREE_FLY
var follow_state: FollowState = FollowState.NONE
var _fpv_inited := false

var _target_id: int = 0
var _hidden_id: int = 0
var _last_target_id: int = 0

var _fly_active := false
var _fly_from := Vector3.ZERO
var _fly_from_rot := Quaternion.IDENTITY
var _fly_t := 0.0
var _fly_dur := 0.0
var _fly_arc := 0.0

var _death_settle_t := 0.0
var _death_body_pos := Vector3.ZERO
var _death_start_pos := Vector3.ZERO
var _death_can_leave := false

var _death_ragdoll: Ragdoll
var _death_world: CollisionWorld = null
var _death_probe := TraceResult.new()
var _death_killer_pos: Variant = null  # Vector3 or null
var _death_look := Vector3.ZERO
var _death_look_t := 0.0
var _death_shown := false
var _death_mannequin: Node3D  # set externally when ragdoll hides body

var _remotes: Dictionary = {}
var _my_team: int = 0


func _init() -> void:
	_camera = Camera3D.new()
	_camera.fov = 90.0
	_camera.near = 0.05
	_camera.far = 500.0
	add_child(_camera)


func activate() -> void:
	_camera.current = true


func deactivate() -> void:
	_camera.current = false


func start_watch(arena_size: float) -> void:
	_arena_size = arena_size
	view_mode = ViewMode.FREE_FLY
	follow_state = FollowState.NONE
	_fpv_inited = false
	_pos = Vector3(0.0, arena_size * 0.9, arena_size * 0.9)
	_yaw = 0.0
	_pitch = -40.0
	_fly_active = false
	_target_id = 0
	_last_target_id = 0
	_clear_hidden()
	activate()


func start_death(body_pos: Vector3, eye_pos: Vector3) -> void:
	follow_state = FollowState.DEATH_SETTLE
	_death_settle_t = 0.0
	_death_body_pos = body_pos
	_death_start_pos = eye_pos
	_death_can_leave = false
	_pos = eye_pos
	_fly_active = false
	_target_id = 0
	_last_target_id = 0
	_clear_hidden()
	var dir := (_death_body_pos - _pos)
	if dir.length_squared() > 0.001:
		_yaw = rad_to_deg(atan2(-dir.x, -dir.z))
		_pitch = rad_to_deg(asin(clampf(dir.y / dir.length(), -1.0, 1.0)))
	activate()


func start_death_ragdoll(body_pos: Vector3, eye_pos: Vector3,
		rag: Ragdoll, world: CollisionWorld, killer_pos: Variant) -> void:
	follow_state = FollowState.DEATH_SETTLE
	_death_settle_t = 0.0
	_death_body_pos = body_pos
	_death_start_pos = eye_pos
	_death_can_leave = false
	_death_ragdoll = rag
	_death_world = world
	_death_killer_pos = killer_pos
	_death_look = Vector3.ZERO
	_death_look_t = 0.0
	_death_shown = false
	_pos = eye_pos
	_fly_active = false
	_target_id = 0
	_last_target_id = 0
	_clear_hidden()
	var dir := (body_pos - eye_pos)
	if dir.length_squared() > 0.001:
		_yaw = rad_to_deg(atan2(-dir.x, -dir.z))
		_pitch = rad_to_deg(asin(clampf(dir.y / dir.length(), -1.0, 1.0)))
	activate()


func start_teammate_follow() -> void:
	follow_state = FollowState.TEAMMATE
	_fly_active = false
	_target_id = 0
	_last_target_id = 0
	_clear_hidden()
	activate()


func stop() -> void:
	follow_state = FollowState.NONE
	_fly_active = false
	_death_can_leave = false
	_death_ragdoll = null
	_death_shown = false
	_death_mannequin = null
	_clear_hidden()
	deactivate()


func is_fpv_active() -> bool:
	if _fly_active or _target_id == 0:
		return false
	if follow_state == FollowState.TEAMMATE:
		return true
	if follow_state == FollowState.NONE and view_mode == ViewMode.FPV:
		return true
	return false


func handle_mouse_motion(rel: Vector2) -> void:
	var sens := InputSettings.sensitivity * InputSettings.CAMERA_SCALE
	var y_sign := -1.0 if InputSettings.invert_y else 1.0
	_yaw -= rel.x * sens
	_pitch = clampf(_pitch - rel.y * sens * y_sign, -PITCH_LIMIT, PITCH_LIMIT)


func toggle_view_mode() -> void:
	if view_mode == ViewMode.FREE_FLY:
		view_mode = ViewMode.FPV
	else:
		view_mode = ViewMode.FREE_FLY
		_clear_hidden()
	_fpv_inited = false


func cycle_target(dir: int, remotes: Dictionary, team_filter: int) -> void:
	var candidates := _get_living(remotes, team_filter)
	if candidates.is_empty():
		_target_id = 0
		return
	var idx := candidates.find(_target_id)
	if idx == -1:
		idx = 0
	else:
		idx = (idx + dir + candidates.size()) % candidates.size()
	_target_id = candidates[idx]


func has_death_can_leave() -> bool:
	return _death_can_leave


func leave_death_for_teammate(dir: int, remotes: Dictionary, my_team: int) -> bool:
	if follow_state == FollowState.DEATH_SETTLE:
		if not _death_can_leave:
			return false
		var mates := _get_living(remotes, my_team)
		if mates.is_empty():
			return false
		# Ensure the corpse is visible when we leave to spectate a teammate.
		if _death_mannequin and is_instance_valid(_death_mannequin):
			_death_mannequin.visible = true
		_death_ragdoll = null
		_death_mannequin = null
		follow_state = FollowState.TEAMMATE
		_target_id = 0
		_last_target_id = 0
		cycle_target(dir, remotes, my_team)
		return true

	if follow_state == FollowState.TEAMMATE or follow_state == FollowState.IDLE_ORBIT:
		cycle_target(dir, remotes, my_team)
		return true

	return false


func get_panel_info(remotes: Dictionary, team: int) -> Dictionary:
	var swap_key := _spec_swap_label()

	if follow_state == FollowState.DEATH_SETTLE:
		return {
			"who": "Your body",
			"sub": "CLICK / A D / \u2190 \u2192 to spectate a teammate",
			"color": Color("#9aa6b4"),
		}

	if follow_state == FollowState.TEAMMATE or follow_state == FollowState.IDLE_ORBIT:
		if _target_id != 0 and remotes.has(_target_id) and is_instance_valid(remotes[_target_id]):
			var rp: RemotePawn = remotes[_target_id]
			var team_color := Color("#5b9bff") if team == Protocol.TEAM_BLUE else Color("#ff6b74")
			return {
				"who": rp.display_name,
				"sub": "Teammate view \u00b7 CLICK / \u2190 \u2192 to switch",
				"color": team_color,
			}
		return {
			"who": "No living teammates",
			"sub": "Waiting for the next round\u2026",
			"color": Color("#8fd6ff"),
		}

	if view_mode == ViewMode.FREE_FLY:
		return {
			"who": "Free-fly",
			"sub": "%s \u2192 first-person" % swap_key,
			"color": Color("#8fd6ff"),
		}

	if _target_id != 0 and remotes.has(_target_id) and is_instance_valid(remotes[_target_id]):
		var rp: RemotePawn = remotes[_target_id]
		return {
			"who": rp.display_name,
			"sub": "First-person \u00b7 %s \u2192 free-fly \u00b7 CLICK / \u2190 \u2192 to switch player" % swap_key,
			"color": Color("#8fd6ff"),
		}

	return {
		"who": "Waiting for players",
		"sub": "First-person \u00b7 %s \u2192 free-fly" % swap_key,
		"color": Color("#8fd6ff"),
	}


func _spec_swap_label() -> String:
	if InputBinds and InputBinds.bindings.has("spec_swap"):
		var key: String = InputBinds.primary("spec_swap")
		if not key.is_empty():
			return key.to_upper()
	return "V"


# ── Update methods called from match.gd ──────────────────────────────────

func update_watch(dt: float, remotes: Dictionary) -> void:
	_remotes = remotes
	if view_mode == ViewMode.FREE_FLY:
		_update_free_fly(dt)
	else:
		_update_watch_fpv(dt, remotes)


func update_death_follow(dt: float, remotes: Dictionary, my_team: int) -> void:
	_remotes = remotes
	_my_team = my_team
	match follow_state:
		FollowState.DEATH_SETTLE:
			_update_death_settle(dt, remotes, my_team)
		FollowState.TEAMMATE:
			_update_teammate_follow(dt, remotes, my_team)
		FollowState.IDLE_ORBIT:
			_update_idle_orbit(dt, remotes, my_team)


# ── Free-fly ─────────────────────────────────────────────────────────────

func _update_free_fly(dt: float) -> void:
	var yaw_rad := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(_pitch)
	var sin_y := sin(yaw_rad)
	var cos_y := cos(yaw_rad)
	var cos_p := cos(pitch_rad)
	var sin_p := sin(pitch_rad)

	var fwd := Vector3(-sin_y * cos_p, sin_p, -cos_y * cos_p)
	var right := Vector3(cos_y, 0.0, -sin_y)

	var mx := 0.0
	var my := 0.0
	var mz := 0.0

	if InputBinds.is_action_pressed("forward"):
		mx += fwd.x; my += fwd.y; mz += fwd.z
	if InputBinds.is_action_pressed("back"):
		mx -= fwd.x; my -= fwd.y; mz -= fwd.z
	if InputBinds.is_action_pressed("right"):
		mx += right.x; mz += right.z
	if InputBinds.is_action_pressed("left"):
		mx -= right.x; mz -= right.z
	if InputBinds.is_action_pressed("jump"):
		my += 1.0
	if InputBinds.is_action_pressed("crouch"):
		my -= 1.0

	var boost := FLY_BOOST if InputBinds.is_action_pressed("walk") else 1.0
	var speed := FLY_SPEED * boost
	var ml := sqrt(mx * mx + my * my + mz * mz)
	if ml > 0.0:
		_pos.x += (mx / ml) * speed * dt
		_pos.y += (my / ml) * speed * dt
		_pos.z += (mz / ml) * speed * dt

	var lim := _arena_size * 2.2
	_pos.x = clampf(_pos.x, -lim, lim)
	_pos.z = clampf(_pos.z, -lim, lim)
	_pos.y = clampf(_pos.y, 1.5, _arena_size * 2.5)

	_camera.global_position = _pos
	_camera.rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	_clear_hidden()


# ── Watch-only FPV ───────────────────────────────────────────────────────

func _update_watch_fpv(dt: float, remotes: Dictionary) -> void:
	var all := _get_living(remotes, -1)

	if _target_id == 0 or not all.has(_target_id):
		_target_id = all[0] if not all.is_empty() else 0

	if _target_id != 0 and remotes.has(_target_id):
		var rp: RemotePawn = remotes[_target_id]
		var eye := rp.sample_eye()
		_camera.global_position = Vector3(eye["x"], eye["y"] + eye["eye_h"], eye["z"])
		_camera.rotation_degrees = Vector3(eye["pitch"], eye["yaw"], 0.0)
		_set_hidden(_target_id, remotes)
	else:
		_clear_hidden()
		_camera.global_position = Vector3(0.0, _arena_size * 1.15, 0.01)
		_camera.look_at(Vector3.ZERO, Vector3.UP)


# ── Death settle ─────────────────────────────────────────────────────────

func _update_death_settle(dt: float, remotes: Dictionary, my_team: int) -> void:
	if _death_ragdoll:
		_update_death_ragdoll_cam(dt, remotes, my_team)
		return

	# Fallback: Death01 clip, simple pull-back.
	_death_settle_t = minf(1.0, _death_settle_t + dt * DEATH_SETTLE_SPEED)

	var back_dir := (_death_start_pos - _death_body_pos).normalized()
	if back_dir.length_squared() < 0.001:
		back_dir = Vector3(0.0, 0.5, 1.0).normalized()
	back_dir.y = maxf(back_dir.y, 0.3)
	back_dir = back_dir.normalized()

	var target_pos := _death_body_pos + back_dir * DEATH_PULLBACK + Vector3(0.0, 1.0, 0.0)
	var f := _smoothstep(_death_settle_t)
	_pos = _death_start_pos.lerp(target_pos, f)

	_camera.global_position = _pos
	_camera.look_at(_death_body_pos + Vector3(0.0, 0.5, 0.0), Vector3.UP)

	var mates := _get_living(remotes, my_team)
	var can_leave := _death_settle_t > 0.95 and not mates.is_empty()
	_death_can_leave = can_leave


func _update_death_ragdoll_cam(dt: float, remotes: Dictionary, my_team: int) -> void:
	var hp := _death_ragdoll.head_pos

	# Settle phase starts once the ragdoll stops moving.
	if _death_ragdoll.settled:
		_death_settle_t = minf(1.0, _death_settle_t + dt * DEATH_SETTLE_SPEED)

	# Update killer position if they are still on the field.
	if _death_killer_pos != null:
		var kid := 0
		for pid: int in remotes:
			var rp = remotes[pid]
			if is_instance_valid(rp) and rp.alive:
				var rp_pos := Vector3(rp._last_eye_x, rp._last_eye_y, rp._last_eye_z)
				if rp_pos.distance_squared_to(_death_killer_pos as Vector3) < 1.0:
					_death_killer_pos = rp_pos

	# Pick the look direction a few times a second — every frame twitches.
	_death_look_t += dt
	if _death_look == Vector3.ZERO or _death_look_t > DEATH_LOOK_INTERVAL:
		_death_look = _pick_death_look(hp, _death_killer_pos)
		_death_look_t = 0.0

	# Position: ride the Head while it tumbles; after settle, pull back along
	# the opposite of the look direction, skimmed off geometry.
	var want_back := DEATH_PULLBACK * _death_settle_t
	var target_pos := hp
	if want_back > 0.001:
		var bx := -_death_look.x
		var bz := -_death_look.z
		var by := 0.55
		var bl := sqrt(bx * bx + by * by + bz * bz)
		if bl > 0.001:
			var nb := Vector3(bx / bl, by / bl, bz / bl)
			var clearance := _ray_clearance(hp, nb, want_back)
			target_pos = hp + nb * clearance

	var cur := _camera.global_position
	var k := minf(1.0, dt * 26.0)
	_pos = cur.lerp(target_pos, k)
	_camera.global_position = _pos

	# Orientation: chase the head with killer bias, lean toward the body once settled.
	var look_target := hp + Vector3(_death_look.x, 0.12, _death_look.z)
	var aim_quat := Quaternion.IDENTITY
	var aim_dir := (look_target - _camera.global_position)
	if aim_dir.length_squared() > 0.001:
		_camera.look_at(look_target, Vector3.UP)
		aim_quat = _camera.quaternion

	if _death_settle_t > 0.001:
		var corpse_dir := (hp - _camera.global_position)
		if corpse_dir.length_squared() > 0.001:
			_camera.look_at(hp, Vector3.UP)
			var corpse_quat := _camera.quaternion
			aim_quat = aim_quat.slerp(corpse_quat, _death_settle_t)

	var rk := minf(1.0, dt * (4.0 + 26.0 * DEATH_RIGIDITY))
	_camera.quaternion = _camera.quaternion.slerp(aim_quat, rk)

	# Reveal the body once the camera has pulled away far enough.
	var cam_dist := _camera.global_position.distance_to(hp)
	var should_show := cam_dist > DEATH_REVEAL
	if should_show != _death_shown:
		_death_shown = should_show
		if _death_mannequin and is_instance_valid(_death_mannequin):
			_death_mannequin.visible = should_show

	var mates := _get_living(remotes, my_team)
	var can_leave := _death_settle_t > 0.999 and not mates.is_empty()
	_death_can_leave = can_leave


func _pick_death_look(hp: Vector3, killer_pos: Variant) -> Vector3:
	var base_yaw: float = 0.0
	var has_killer := killer_pos != null
	if has_killer:
		var kp: Vector3 = killer_pos as Vector3
		base_yaw = atan2(kp.x - hp.x, kp.z - hp.z)

	var best := Vector3(0.0, 0.0, 1.0)
	var best_score := -INF
	for i in 12:
		var yaw := base_yaw + float(i) / 12.0 * TAU
		var dx := sin(yaw)
		var dz := cos(yaw)
		var d := _ray_clearance(hp, Vector3(dx, 0.0, dz), 8.0)
		var clear := minf(d, 4.0)
		var toward := cos(yaw - base_yaw) if has_killer else 0.0
		var score := clear * 0.7 + toward * 3.2
		if score > best_score:
			best_score = score
			best = Vector3(dx, 0.0, dz)
	return best


func _ray_clearance(origin: Vector3, dir: Vector3, want: float) -> float:
	if _death_world == null:
		return want
	# Against brushes, so the death camera can sit over a ramp instead of being
	# shoved back by the empty air inside the ramp's bounding box.
	var hit := _death_world.ray_distance(origin, dir.normalized(), want + DEATH_SKIM, _death_probe)
	if hit >= want + DEATH_SKIM:
		return want
	return minf(want, maxf(0.0, hit - DEATH_SKIM))



func _update_teammate_follow(dt: float, remotes: Dictionary, my_team: int) -> void:
	var mates := _get_living(remotes, my_team)

	if _target_id == 0 or not mates.has(_target_id):
		_target_id = mates[0] if not mates.is_empty() else 0

	if _target_id != _last_target_id:
		_last_target_id = _target_id
		if _target_id != 0:
			_fly_active = true
			_fly_from = _camera.global_position
			_fly_from_rot = _camera.quaternion
			_fly_t = 0.0
			_fly_dur = 0.0
			_fly_arc = 0.0
		else:
			_fly_active = false

	if _target_id != 0 and remotes.has(_target_id) and is_instance_valid(remotes[_target_id]):
		var rp: RemotePawn = remotes[_target_id]
		var eye := rp.sample_eye()
		var dest := Vector3(eye["x"], eye["y"] + eye["eye_h"], eye["z"])

		if _fly_active:
			_do_fly_between(dt, dest, eye["pitch"], eye["yaw"], remotes)
		else:
			_camera.global_position = dest
			_camera.rotation_degrees = Vector3(eye["pitch"], eye["yaw"], 0.0)
			_set_hidden(_target_id, remotes)
	else:
		_fly_active = false
		_clear_hidden()
		follow_state = FollowState.IDLE_ORBIT
		_update_idle_orbit(dt, remotes, my_team)


func _do_fly_between(dt: float, dest: Vector3, dest_pitch: float, dest_yaw: float,
		remotes: Dictionary) -> void:
	if _fly_dur == 0.0:
		var d := _fly_from.distance_to(dest)
		_fly_dur = clampf(d / SPEC_FLY_SPEED, SPEC_FLY_MIN, SPEC_FLY_MAX)
		_fly_arc = minf(7.0, d * 0.16)

	_fly_t += dt
	var u := clampf(_fly_t / _fly_dur, 0.0, 1.0)
	var f := _smoothstep(u)

	var pos := _fly_from.lerp(dest, f)
	pos.y += sin(PI * f) * _fly_arc
	_camera.global_position = pos

	var dest_rot := Quaternion.from_euler(
		Vector3(deg_to_rad(dest_pitch), deg_to_rad(dest_yaw), 0.0))

	var gap := pos.distance_to(dest)
	var look_rot: Quaternion
	if gap > 0.02:
		_camera.look_at(dest, Vector3.UP)
		look_rot = _camera.quaternion
	else:
		look_rot = dest_rot

	var blend1 := _fly_from_rot.slerp(look_rot, clampf(f * 2.2, 0.0, 1.0))
	var final_rot := blend1.slerp(dest_rot, clampf((f - 0.55) / 0.45, 0.0, 1.0))
	_camera.quaternion = final_rot

	if f > 0.85:
		_set_hidden(_target_id, remotes)
	else:
		_set_hidden(0, remotes)

	if u >= 1.0:
		_fly_active = false


# ── Idle orbit (no teammates alive) ─────────────────────────────────────

func _update_idle_orbit(dt: float, remotes: Dictionary, my_team: int) -> void:
	var mates := _get_living(remotes, my_team)
	if not mates.is_empty():
		follow_state = FollowState.TEAMMATE
		_target_id = 0
		_last_target_id = 0
		return

	var t2 := float(Time.get_ticks_msec()) * 0.0002
	_camera.global_position = Vector3(
		sin(t2) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(t2) * ORBIT_RADIUS)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


# ── Helpers ──────────────────────────────────────────────────────────────

func _get_living(remotes: Dictionary, team_filter: int) -> Array[int]:
	var out: Array[int] = []
	for pid: int in remotes:
		var rp = remotes[pid]
		if not is_instance_valid(rp):
			continue
		if not rp.alive:
			continue
		if team_filter >= 0 and rp.team != team_filter:
			continue
		out.append(pid)
	return out


func _set_hidden(id: int, remotes: Dictionary) -> void:
	if _hidden_id == id:
		return
	if _hidden_id != 0 and remotes.has(_hidden_id):
		var prev = remotes[_hidden_id]
		if is_instance_valid(prev):
			prev.set_body_visible(true)
	_hidden_id = id
	if id != 0 and remotes.has(id):
		var cur = remotes[id]
		if is_instance_valid(cur):
			cur.set_body_visible(false)


func _clear_hidden() -> void:
	if _hidden_id != 0 and _remotes.has(_hidden_id):
		var prev = _remotes[_hidden_id]
		if is_instance_valid(prev):
			prev.set_body_visible(true)
	_hidden_id = 0


func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
