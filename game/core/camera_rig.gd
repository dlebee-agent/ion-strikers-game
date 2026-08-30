class_name CameraRig
extends Node3D

const Movement = preload("res://core/movement.gd")

enum Mode { FIRST_PERSON, THIRD_PERSON, PREVIEW }

@export var sensitivity: float = 0.15
@export var invert_y: bool = false
@export var tp_distance: float = 4.6
@export var tp_pitch: float = 12.0

const ORBIT_SENSITIVITY := 0.4
const ORBIT_PITCH_SENSITIVITY := 0.3
const ORBIT_PITCH_MIN := -10.0
const ORBIT_PITCH_MAX := 60.0
# The orbit swings around a point on the chest and looks slightly below it, so a
# standing body sits in frame rather than being centred on its feet.
const ORBIT_PIVOT_HEIGHT := 1.1
const ORBIT_LOOK_HEIGHT := 1.0

var mode: Mode = Mode.FIRST_PERSON
var orbit_yaw: float = 0.0
var orbit_pitch: float = 12.0

var _camera: Camera3D
var _movement: Movement

func _ready() -> void:
	_ensure_camera()

func setup(movement: Movement) -> void:
	_movement = movement
	orbit_pitch = tp_pitch
	_ensure_camera()

# The camera is what actually gets moved each frame, so anything that must track
# the view (the first-person viewmodel) parents to it rather than to this rig.
func _ensure_camera() -> void:
	if _camera:
		return
	_camera = Camera3D.new()
	_camera.fov = 90.0
	_camera.near = 0.05
	_camera.far = 500.0
	_camera.current = true
	add_child(_camera)

func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	if mode == Mode.FIRST_PERSON:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif mode == Mode.THIRD_PERSON:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif mode == Mode.PREVIEW:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		orbit_yaw = 0.0
		orbit_pitch = 12.0

func handle_mouse_motion(rel: Vector2) -> void:
	if not _movement:
		return
	var y_sign := -1.0 if invert_y else 1.0
	if mode == Mode.FIRST_PERSON:
		_movement.yaw -= rel.x * sensitivity
		_movement.pitch = clampf(_movement.pitch - rel.y * sensitivity * y_sign, -89.0, 89.0)
	else:
		# Third person and preview both orbit rather than steer. Keeping the camera
		# off the body's yaw is the whole point: it lets you walk a model toward the
		# lens and watch its front, instead of forever chasing its back.
		orbit_yaw -= rel.x * ORBIT_SENSITIVITY
		orbit_pitch = clampf(orbit_pitch + rel.y * ORBIT_PITCH_SENSITIVITY * y_sign,
			ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)

func handle_scroll(delta: float) -> void:
	if mode == Mode.PREVIEW or mode == Mode.THIRD_PERSON:
		tp_distance = clampf(tp_distance + sign(delta) * 0.4, 2.4, 8.0)

func update_camera() -> void:
	if not _movement:
		return

	if mode == Mode.FIRST_PERSON:
		var eye := _movement.get_eye_position()
		_camera.global_position = eye
		_camera.rotation_degrees = Vector3(_movement.pitch, _movement.yaw, 0.0)

	else:
		# Third person and preview are the same orbit; only whether the body is
		# allowed to move underneath it differs.
		_camera.global_position = _movement.position \
			+ Vector3(0.0, ORBIT_PIVOT_HEIGHT, 0.0) + _orbit_offset()
		_camera.look_at(_movement.position + Vector3(0.0, ORBIT_LOOK_HEIGHT, 0.0),
			Vector3.UP)

func _orbit_offset() -> Vector3:
	var yaw_rad := deg_to_rad(orbit_yaw)
	var pitch_rad := deg_to_rad(orbit_pitch)
	return Vector3(
		sin(yaw_rad) * cos(pitch_rad) * tp_distance,
		sin(pitch_rad) * tp_distance,
		cos(yaw_rad) * cos(pitch_rad) * tp_distance
	)

# WASD in an orbiting view is read relative to the CAMERA, not the body: forward
# means away from the viewer. Returns a flat world direction, or zero when idle.
func get_ground_move_direction(wish_forward: float, wish_side: float) -> Vector3:
	var yaw_rad := deg_to_rad(orbit_yaw)
	var toward_camera := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	var dir := -toward_camera * wish_forward + right * wish_side
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()

func get_camera() -> Camera3D:
	_ensure_camera()
	return _camera

# Only first person aims down the camera. Once the view orbits, the camera's own
# forward points AT the player, so shooting along it would fire back through them;
# the orbiting modes aim along the body's facing instead.
func get_aim_direction() -> Vector3:
	if mode == Mode.FIRST_PERSON:
		return -_camera.global_basis.z
	if mode == Mode.PREVIEW:
		# Preview pins the body facing +Z so it looks at the camera's start point.
		return Vector3.BACK
	return _movement.get_forward()

func get_aim_origin() -> Vector3:
	if mode == Mode.FIRST_PERSON:
		return _camera.global_position
	return _movement.get_eye_position()
