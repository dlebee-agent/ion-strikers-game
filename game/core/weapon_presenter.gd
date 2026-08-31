class_name WeaponPresenter
extends Node3D

signal fired
signal melee_hit
signal special_started
signal special_fired

const FIRE_DELAY := 0.14
const MELEE_RANGE := 2.6
const MELEE_ARC := deg_to_rad(70.0)
const MELEE_COOLDOWN := 0.65
const SPECIAL_MIN_WINDUP := 0.3
const SPECIAL_AUTO_FIRE := 5.0
# One player per shot in flight. At 140ms between shots a single player would be
# restarted mid-clip and the laser would stutter instead of overlapping.
const LASER_POOL_SIZE := 6
# Visible beam leaves the gun, not the eye. Matches laser-arena MUZZLE offset.
const MUZZLE_FORWARD := 0.6
const MUZZLE_DOWN := 0.06
const TracerBolt = preload("res://core/tracer_bolt.gd")
const ImpactFlash = preload("res://core/impact_flash.gd")

# Colours the bolts and their impacts. Set by whoever owns this weapon.
var team: String = "blue"
# Match play only arms this after a five-frag streak; the designer leaves it on
# so the preview can fire without earning one.
var special_armed := false

var _fire_cooldown := 0.0
var _melee_cooldown := 0.0
var _special_charging := false
var _special_charge_time := 0.0
var _special_released := false
var is_shooting := false
var is_meleeing := false

var _laser_pool: Array[AudioStreamPlayer3D] = []
var _laser_idx := 0

func _ready() -> void:
	var laser_stream := load("res://assets/audio/laser.ogg")
	for _i in LASER_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		add_child(player)
		if laser_stream:
			player.stream = laser_stream
			player.max_db = -6.0
			player.bus = "SFX"
		_laser_pool.append(player)

func update(dt: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - dt)
	_melee_cooldown = maxf(0.0, _melee_cooldown - dt)
	is_shooting = false
	is_meleeing = false

	if _special_charging:
		_special_charge_time += dt
		var queued_release := _special_released and _special_charge_time >= SPECIAL_MIN_WINDUP
		if queued_release or _special_charge_time >= SPECIAL_AUTO_FIRE:
			_finish_special()

# Reused by every shot, so firing allocates nothing.
var _shot_trace := TraceResult.new()


func try_fire(origin: Vector3, direction: Vector3, world: CollisionWorld) -> void:
	if _fire_cooldown > 0.0 or _special_charging:
		return
	_fire_cooldown = FIRE_DELAY
	is_shooting = true
	fired.emit()
	var muzzle := _muzzle_point(origin, direction)
	play_laser(muzzle)
	_spawn_tracer(origin, muzzle, direction, world)

func play_laser(origin: Vector3) -> void:
	if _laser_pool.is_empty():
		return
	_laser_idx = (_laser_idx + 1) % _laser_pool.size()
	var player := _laser_pool[_laser_idx]
	player.global_position = origin
	player.play()

func try_melee() -> void:
	if _melee_cooldown > 0.0 or _special_charging:
		return
	_melee_cooldown = MELEE_COOLDOWN
	is_meleeing = true
	melee_hit.emit()

func start_special() -> void:
	if _special_charging or not special_armed:
		return
	_special_charging = true
	_special_released = false
	_special_charge_time = 0.0
	special_started.emit()

# Letting go early queues the shot rather than cancelling it: the wind-up cannot
# be skipped, but nor is it wasted. There is no cancel — once the charge starts
# the only ways out are the beam firing or dying.
func do_special_fire() -> void:
	if not _special_charging:
		return
	_special_released = true
	if _special_charge_time >= SPECIAL_MIN_WINDUP:
		_finish_special()

func _finish_special() -> void:
	_special_charging = false
	_special_released = false
	_special_charge_time = 0.0
	special_armed = false
	special_fired.emit()


func cancel_special() -> void:
	if not _special_charging:
		return
	_special_charging = false
	_special_released = false
	_special_charge_time = 0.0

func is_special_charging() -> bool:
	return _special_charging

# The bar tracks the run-up to the auto-fire, not the short windup, so it creeps
# rather than snapping full a third of a second in.
func get_special_charge_fraction() -> float:
	if not _special_charging:
		return 0.0
	return clampf(_special_charge_time / SPECIAL_AUTO_FIRE, 0.0, 1.0)

func is_special_releasable() -> bool:
	return _special_charging and _special_charge_time >= SPECIAL_MIN_WINDUP

func _muzzle_point(origin: Vector3, direction: Vector3) -> Vector3:
	var dir := direction.normalized()
	return origin + dir * MUZZLE_FORWARD + Vector3(0.0, -MUZZLE_DOWN, 0.0)


func _spawn_tracer(origin: Vector3, muzzle: Vector3, direction: Vector3, world: CollisionWorld) -> void:
	var dir := direction.normalized()
	var scene := get_tree().current_scene
	if not scene:
		return

	# The shot is traced along the aim line, from the eye, because that is the
	# line the server scores it on. The bolt is drawn from the muzzle, which sits
	# forward of and below the eye, so it has to be aimed at the impact point
	# rather than fired along a parallel line. Taking the aim distance and
	# subtracting the forward offset gave a streak that stayed parallel to the
	# aim line, which is how bolts ended up carrying on through walls the shot
	# had already stopped at.
	var impact := origin + dir * raycast_distance(origin, dir, world)
	var to_impact := impact - muzzle
	var travel := to_impact.length()
	var bolt_dir := to_impact / travel if travel > 0.0001 else dir

	# Nothing worth drawing at point-blank range, but the hit itself still has to
	# register: the flash goes off without a streak in front of it.
	if travel <= TracerBolt.BOLT_START:
		ImpactFlash.spawn(scene, impact,
			TracerBolt.glow_color(team), TracerBolt.bolt_color(team), false)
		return

	TracerBolt.spawn(scene, muzzle, bolt_dir, travel, team)


func raycast_distance(origin: Vector3, dir: Vector3, world: CollisionWorld) -> float:
	return _trace_world(origin, dir, world, 200.0, CollisionWorld.MASK_SOLID)


func raycast_special(origin: Vector3, dir: Vector3, world: CollisionWorld,
		max_dist: float) -> float:
	return _trace_world(origin, dir, world, max_dist, CollisionWorld.MASK_SPECIAL)


# Against brushes rather than their bounding boxes, so a tracer over a ramp ends
# where the slope actually is instead of in the air above it.
func _trace_world(origin: Vector3, dir: Vector3, world: CollisionWorld,
		max_dist: float, mask: int) -> float:
	if world == null:
		return max_dist
	return world.ray_distance(origin, dir.normalized(), max_dist, _shot_trace, mask)
