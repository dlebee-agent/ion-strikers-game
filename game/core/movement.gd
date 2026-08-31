class_name Movement
extends RefCounted

# Movement inspired by Counter-Strike and Quake.
const UNIT_SCALE := 0.0254

const RUN_SPEED := 260.0 * UNIT_SCALE
const WALK_MOD := 0.52
const DUCK_MOD := 0.34
const ACCEL := 5.5
const AIR_ACCEL := 12.0
const AIR_SPEED_CAP := 30.0 * UNIT_SCALE
const FRICTION := 5.2
const STOP_SPEED := 80.0 * UNIT_SCALE
const GRAVITY := 800.0 * UNIT_SCALE
const JUMP_VEL := 301.993377 * UNIT_SCALE

const PLAYER_RADIUS := 0.4
const STEP_HEIGHT := 0.6
const STEP_LIP := 0.35
# Feet are parked this far above whatever they rest on, so contact is never a
# floating-point coin toss between touching and penetrating.
const GROUND_SKIN := 0.001
const EYE_STAND := 1.6
const EYE_CROUCH := 0.9
const STAND_HEIGHT := 1.79
const CROUCH_HEIGHT := 1.31

const STEP_VIEW_SPEED := 4.0
const STEP_VIEW_MAX := STEP_LIP + 0.05

const FIRE_DELAY_MS := 140.0
const PREP_TIME_MS := 2200.0

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var on_ground := true
var is_crouching := false
var jump_latch := false
var crouch_fraction := 0.0

var _step_view_offset := 0.0

func eye_height() -> float:
	return lerpf(EYE_STAND, EYE_CROUCH, crouch_fraction)

func player_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_fraction)

func get_forward() -> Vector3:
	var rad_yaw := deg_to_rad(yaw)
	return Vector3(-sin(rad_yaw), 0.0, -cos(rad_yaw))

func get_right() -> Vector3:
	var rad_yaw := deg_to_rad(yaw)
	return Vector3(cos(rad_yaw), 0.0, -sin(rad_yaw))

func update(dt: float, wish_forward: float, wish_side: float, want_jump: bool,
		want_crouch: bool, want_walk: bool, colliders: Array[AABB]) -> void:
	_update_crouch(dt, want_crouch)

	var speed_mod := 1.0
	if is_crouching:
		speed_mod = DUCK_MOD
	elif want_walk:
		speed_mod = WALK_MOD

	var wish_speed := RUN_SPEED * speed_mod
	var fwd := get_forward()
	var right := get_right()

	var wish_dir := fwd * wish_forward + right * wish_side
	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()

	if on_ground:
		if want_jump and not jump_latch:
			velocity.y = JUMP_VEL
			on_ground = false
			jump_latch = true
		else:
			_apply_friction(dt)
			_accelerate(wish_dir, wish_speed, ACCEL, dt)
	else:
		_air_accelerate(wish_dir, wish_speed, dt)
		velocity.y -= GRAVITY * dt

	if not want_jump:
		jump_latch = false

	var old_y := position.y
	_move_and_collide(dt, colliders)

	var step_delta := position.y - old_y
	if on_ground and absf(step_delta) > 0.01 and absf(step_delta) < STEP_VIEW_MAX:
		# Clamped, or a staircase taken faster than the eye catches up stacks step
		# on step until the view is looking out of the player's knees.
		_step_view_offset = clampf(_step_view_offset - step_delta,
			-STEP_VIEW_MAX, STEP_VIEW_MAX)

	if absf(_step_view_offset) > 0.001:
		var recover := STEP_VIEW_SPEED * dt
		if _step_view_offset > 0.0:
			_step_view_offset = maxf(0.0, _step_view_offset - recover)
		else:
			_step_view_offset = minf(0.0, _step_view_offset + recover)

func get_eye_position() -> Vector3:
	return Vector3(position.x, position.y + eye_height() + _step_view_offset, position.z)

func _update_crouch(dt: float, want_crouch: bool) -> void:
	var target := 1.0 if want_crouch else 0.0
	crouch_fraction = move_toward(crouch_fraction, target, dt * 8.0)
	is_crouching = crouch_fraction > 0.5

func _apply_friction(dt: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control := maxf(speed, STOP_SPEED)
	var drop := control * FRICTION * dt
	var new_speed := maxf(0.0, speed - drop) / speed
	velocity.x *= new_speed
	velocity.z *= new_speed

func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, dt: float) -> void:
	var cur_speed := velocity.x * wish_dir.x + velocity.z * wish_dir.z
	var add_speed := wish_speed - cur_speed
	if add_speed <= 0.0:
		return
	var accel_speed := minf(accel * wish_speed * dt, add_speed)
	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z

func _air_accelerate(wish_dir: Vector3, wish_speed: float, dt: float) -> void:
	var wish_spd := minf(wish_speed, AIR_SPEED_CAP)
	var cur_speed := velocity.x * wish_dir.x + velocity.z * wish_dir.z
	var add_speed := wish_spd - cur_speed
	if add_speed <= 0.0:
		return
	var accel_speed := minf(AIR_ACCEL * wish_speed * dt, add_speed)
	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z

func _move_and_collide(dt: float, colliders: Array[AABB]) -> void:
	var move := velocity * dt
	var new_pos := position + move
	var h := player_height()
	var r := PLAYER_RADIUS

	var grounded := false
	for box in colliders:
		var overlap := _aabb_vs_capsule(box, new_pos, r, h)
		if overlap != Vector3.ZERO:
			new_pos += overlap
			if overlap.y > 0.001:
				grounded = true
				if velocity.y < 0.0:
					velocity.y = 0.0
			elif overlap.y < -0.001:
				if velocity.y > 0.0:
					velocity.y = 0.0

	# A player resting exactly on a surface penetrates nothing, so standing on
	# ground cannot be read off the push-out above; it has to be probed for. The
	# same probe walks the player down onto the next tread. It has to settle on the
	# HIGHEST surface in reach: on a staircase the treads overlap, so taking the
	# first one found alternates between two steps and vibrates the view.
	if on_ground and velocity.y <= 0.0:
		var support := _highest_support(new_pos, r, colliders)
		if support > -INF:
			new_pos.y = support + GROUND_SKIN
			grounded = true
			velocity.y = 0.0

	on_ground = grounded
	position = new_pos

# Top of the tallest box the player's footprint is over that sits within a step's
# reach below their feet, or -INF when there is nothing to stand on.
func _highest_support(pos: Vector3, radius: float, colliders: Array[AABB]) -> float:
	var best := -INF
	var lowest := pos.y - STEP_LIP
	for box in colliders:
		var top := box.end.y
		if top < lowest or top > pos.y + GROUND_SKIN or top <= best:
			continue
		if pos.x <= box.position.x - radius or pos.x >= box.end.x + radius:
			continue
		if pos.z <= box.position.z - radius or pos.z >= box.end.z + radius:
			continue
		best = top
	return best

func _aabb_vs_capsule(box: AABB, pos: Vector3, radius: float, height: float) -> Vector3:
	var foot_y := pos.y
	var head_y := pos.y + height

	# The player is treated as a vertical segment tested against the box grown by
	# the player radius, so the whole overlap is a single box-vs-segment problem
	# and the resolution can only ever move along one axis.
	var min_x := box.position.x - radius
	var max_x := box.end.x + radius
	var min_z := box.position.z - radius
	var max_z := box.end.z + radius

	if pos.x <= min_x or pos.x >= max_x:
		return Vector3.ZERO
	if pos.z <= min_z or pos.z >= max_z:
		return Vector3.ZERO
	if head_y <= box.position.y or foot_y >= box.end.y:
		return Vector3.ZERO

	var ledge_height := box.end.y - foot_y
	if on_ground and ledge_height > 0.0 and ledge_height <= STEP_LIP:
		return Vector3(0.0, ledge_height + GROUND_SKIN, 0.0)

	# A descending player always leaves through the top face, otherwise a deep
	# overlap on a thick slab would resolve downward and drop them through it.
	var pen_up := ledge_height
	var pen_down := head_y - box.position.y
	var vert_mag := pen_up
	var vert_sign := 1.0
	if velocity.y > 0.0 and pen_down < pen_up:
		vert_mag = pen_down
		vert_sign = -1.0

	var push := Vector3(0.0, vert_mag * vert_sign, 0.0)
	var best := vert_mag

	var pen_x_pos := max_x - pos.x
	if pen_x_pos < best:
		best = pen_x_pos
		push = Vector3(pen_x_pos, 0.0, 0.0)
	var pen_x_neg := pos.x - min_x
	if pen_x_neg < best:
		best = pen_x_neg
		push = Vector3(-pen_x_neg, 0.0, 0.0)
	var pen_z_pos := max_z - pos.z
	if pen_z_pos < best:
		best = pen_z_pos
		push = Vector3(0.0, 0.0, pen_z_pos)
	var pen_z_neg := pos.z - min_z
	if pen_z_neg < best:
		best = pen_z_neg
		push = Vector3(0.0, 0.0, -pen_z_neg)

	return push
