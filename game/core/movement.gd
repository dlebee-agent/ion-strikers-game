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
# Steepest surface still counted as ground, about 45 degrees. Every surface in
# the box-built maps is either 1.0 or 0.0, so this only starts to matter once
# imported brush geometry brings real slopes.
const MIN_WALK_NORMAL := 0.7
# Passes the slide takes before giving up. Four is enough to resolve a corner.
const SLIDE_ITERATIONS := 4
# Lift off a surface after clipping to it, so the next sweep in the same move
# does not start exactly on that plane and immediately re-hit it.
const SURFACE_NUDGE := 0.0005
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

var _trace := TraceResult.new()
var _slide_pos := Vector3.ZERO
var _slide_vel := Vector3.ZERO
var _slide_blocked := false
# Set for the one frame a jump is launched. Rising velocity alone cannot mean
# airborne, because climbing a slope produces exactly that.
var _jumped := false

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
		want_crouch: bool, want_walk: bool, world: CollisionWorld) -> void:
	_update_crouch(dt, want_crouch, world)

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
			_jumped = true
		else:
			_apply_friction(dt)
			_accelerate(wish_dir, wish_speed, ACCEL, dt)
	else:
		_air_accelerate(wish_dir, wish_speed, dt)
		velocity.y -= GRAVITY * dt

	if not want_jump:
		jump_latch = false

	var old_y := position.y
	_move_and_collide(dt, world)

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

func _update_crouch(dt: float, want_crouch: bool, world: CollisionWorld) -> void:
	var target := 1.0 if want_crouch else 0.0
	if target < crouch_fraction and not _has_headroom(world, crouch_fraction):
		target = crouch_fraction
	crouch_fraction = move_toward(crouch_fraction, target, dt * 8.0)
	is_crouching = crouch_fraction > 0.5


# Whether the player could be a little less crouched than they are without their
# box ending up inside something.
func _has_headroom(world: CollisionWorld, from_fraction: float) -> bool:
	var probe := maxf(0.0, from_fraction - 0.15)
	var h := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, probe)
	var half := Vector3(PLAYER_RADIUS, h * 0.5, PLAYER_RADIUS)
	return not world.box_overlaps(position + Vector3(0.0, half.y, 0.0), half)

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

func _move_and_collide(dt: float, world: CollisionWorld) -> void:
	var half := Vector3(PLAYER_RADIUS, player_height() * 0.5, PLAYER_RADIUS)
	var was_on_ground := on_ground

	# Free the player before moving them. A sweep that starts inside geometry has
	# no surface to slide along, and there is no position for it to report but
	# the one it started from, so an embedded player would simply stop existing
	# as a moving thing. Spawns arrive with their feet exactly on the floor, so
	# this is the normal case rather than the exceptional one.
	var escape := world.depenetrate(position + Vector3(0.0, half.y, 0.0), half)
	if escape != Vector3.ZERO:
		position += escape

	var start_pos := position
	var start_vel := velocity

	_slide(world, half, dt, start_pos, start_vel)
	var best_pos := _slide_pos
	var best_vel := _slide_vel
	var blocked := _slide_blocked

	# A wall a grounded player walked into might be a step they can walk up, so
	# run the whole slide again from a raised start and drop back down. The
	# result is kept only when it got further along the ground, which is what
	# keeps a real wall a wall.
	if blocked and was_on_ground:
		var lifted := _sweep(world, half, start_pos, start_pos + Vector3(0.0, STEP_HEIGHT, 0.0))
		_slide(world, half, dt, lifted, Vector3(start_vel.x, 0.0, start_vel.z))
		var over := _slide_pos
		var over_vel := _slide_vel
		var dropped := _sweep(world, half, over, over - Vector3(0.0, STEP_HEIGHT * 2.0, 0.0))
		var landed_walkable := _trace.hit() and _trace.normal.y >= MIN_WALK_NORMAL
		if landed_walkable and _ground_gain(start_pos, dropped) > _ground_gain(start_pos, best_pos) + 0.0001:
			best_pos = dropped
			best_vel = Vector3(over_vel.x, best_vel.y, over_vel.z)

	position = best_pos
	velocity = best_vel

	_settle_ground(world, half, was_on_ground)
	_jumped = false


# How far a candidate move actually carried the player across the floor. The
# step retry is judged on this alone, because it always wins on height.
static func _ground_gain(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


# Advances along `vel` for `dt`, clipping to each surface hit and continuing
# along it. Leaves the outcome in _slide_pos / _slide_vel / _slide_blocked.
func _slide(world: CollisionWorld, half: Vector3, dt: float, from: Vector3, vel: Vector3) -> void:
	var pos := from
	var v := vel
	var remaining := dt
	_slide_blocked = false

	for _iteration in SLIDE_ITERATIONS:
		if remaining <= 0.0 or v.length_squared() < 0.000001:
			break
		var target := pos + v * remaining
		pos = _sweep(world, half, pos, target)

		if _trace.start_solid:
			# Embedded, so there is no surface to slide along. Stop here rather
			# than letting the move through: passing an embedded player straight
			# to the target is a hole in the world, and _move_and_collide has
			# already pushed them out of anything they were genuinely inside.
			break
		if not _trace.hit():
			break

		_slide_blocked = true
		remaining *= 1.0 - _trace.fraction
		pos += _trace.normal * SURFACE_NUDGE
		v = v.slide(_trace.normal)

	_slide_pos = pos
	_slide_vel = v


# Sweeps the player box between two FOOT positions. The world works in box-centre
# space, so both ends are lifted by half the box height and the result dropped
# back down.
func _sweep(world: CollisionWorld, half: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var lift := Vector3(0.0, half.y, 0.0)
	world.trace_box(from + lift, to + lift, half, _trace)
	return _trace.end_pos - lift


# Decides whether the player is standing on something and, if so, parks them on
# it. A player at rest penetrates nothing, so contact cannot be read off the
# move above and has to be probed for.
func _settle_ground(world: CollisionWorld, half: Vector3, was_on_ground: bool) -> void:
	on_ground = false
	# Only a jump gives up the ground. Rising velocity does not, because walking
	# up a slope produces rising velocity every frame: the slide clips motion to
	# the slope, which tilts it upward. Reading that as airborne un-grounds the
	# player, gravity pulls them back down, and they re-ground the next frame,
	# which feels like slipping the whole way up.
	if _jumped:
		return

	# An already grounded player probes a full step down, which walks them onto
	# the next tread instead of launching them off each stair nose. Someone
	# arriving through the air only gets a contact-width probe, or stepping off a
	# ledge would snap them straight back to it.
	var reach := STEP_HEIGHT if was_on_ground else GROUND_SKIN * 4.0
	var landed := _sweep(world, half, position, position - Vector3(0.0, reach, 0.0))
	if not _trace.hit() or _trace.start_solid:
		return
	if _trace.normal.y < MIN_WALK_NORMAL:
		# Too steep to hold. Slide down it rather than standing on the wall.
		return

	position = landed
	on_ground = true
	# Lay velocity along whatever is underfoot, so none of it points into the
	# surface or off it. On flat ground that zeroes the vertical component, as
	# before; on a slope it leaves exactly the along-slope motion that carries
	# the player up or down it.
	velocity = velocity.slide(_trace.normal)
