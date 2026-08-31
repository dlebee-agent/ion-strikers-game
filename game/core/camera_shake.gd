class_name CameraShake
extends RefCounted

const MAX_AMP := 2.6
const RANGE := 44.0

var _amp := 0.0
var _t := 0.0


func add(amp: float) -> void:
	_amp = minf(MAX_AMP, _amp + amp)


func add_at_distance(dist: float) -> void:
	var k := maxf(0.0, 1.0 - dist / RANGE)
	add(MAX_AMP * k * k)


func apply(camera: Camera3D, dt: float) -> void:
	if _amp <= 0.0005:
		_amp = 0.0
		return
	_t += dt * 44.0
	var a := _amp
	var pos := camera.global_position
	camera.global_position = Vector3(
		pos.x + sin(_t * 1.7) * a * 0.32,
		pos.y + sin(_t * 2.9) * a * 0.38,
		pos.z + cos(_t * 2.1) * a * 0.32,
	)
	var rot := camera.rotation_degrees
	var ang := minf(7.5, a * 4.2)
	camera.rotation_degrees = Vector3(
		rot.x + sin(_t * 2.3) * ang,
		rot.y + cos(_t * 1.9) * ang,
		rot.z + sin(_t * 3.1) * ang * 1.7,
	)
	_amp -= dt * (0.9 + _amp * 0.5)
	if _amp < 0.0:
		_amp = 0.0
