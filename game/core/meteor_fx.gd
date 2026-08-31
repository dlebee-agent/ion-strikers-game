class_name MeteorFx
extends Node3D

const FxUtil = preload("res://core/fx_util.gd")

signal impacted(pos: Vector3, radius: float)

const HEAD_COLOR := Color8(255, 216, 168)
const TRAIL_COLOR := Color8(255, 122, 42)
const TRAIL_OPACITY := 0.55
const MARK_COLOR := Color8(255, 74, 42)
const MARK_OPACITY := 0.5
const FLASH_COLOR := Color8(255, 192, 112)
const FLASH_OPACITY := 0.9
const BLAST_DUR := 0.55
const HEAD_SCALE := 1.1
const BEARING_DIST := 30.0
const START_HEIGHT := 58.0

var _falling := true
var _t := 0.0
var _dur := 2.6
var _radius := 5.0
var _start := Vector3.ZERO
var _target := Vector3.ZERO
var _flight_dir := Vector3.DOWN

var _head: MeshInstance3D
var _head_mat: StandardMaterial3D
var _trail: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _mark: MeshInstance3D
var _mark_mat: StandardMaterial3D
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D


static func spawn(parent: Node, target: Vector3, lead_ms: int,
		radius: float) -> MeteorFx:
	var fx := MeteorFx.new()
	parent.add_child(fx)
	fx._setup(target, lead_ms, radius)
	return fx


func _setup(target: Vector3, lead_ms: int, radius: float) -> void:
	_target = target
	_radius = radius
	_dur = maxf(0.4, float(lead_ms) / 1000.0)

	var bearing := randf() * TAU
	_start = Vector3(
		target.x + cos(bearing) * BEARING_DIST,
		target.y + START_HEIGHT,
		target.z + sin(bearing) * BEARING_DIST,
	)
	_flight_dir = (_target - _start).normalized()

	_head_mat = FxUtil.emissive(HEAD_COLOR, 1.0)
	_head = FxUtil.sphere(_head_mat)
	_head.scale = Vector3.ONE * HEAD_SCALE
	add_child(_head)

	_trail_mat = FxUtil.emissive(TRAIL_COLOR, TRAIL_OPACITY)
	_trail = FxUtil.cylinder(_trail_mat)
	add_child(_trail)

	_mark_mat = FxUtil.emissive(MARK_COLOR, MARK_OPACITY)
	_mark = FxUtil.cylinder(_mark_mat)
	_mark.scale = Vector3(radius * 2.0, 0.02, radius * 2.0)
	_mark.position = Vector3(target.x, target.y + 0.07, target.z)
	add_child(_mark)


func _process(delta: float) -> void:
	_t += delta
	if _falling:
		_update_fall()
	else:
		_update_blast()


func _update_fall() -> void:
	var k := minf(1.0, _t / _dur)
	var e := k * k

	var head_pos := _start.lerp(_target, e)
	_head.position = head_pos

	var tl := minf(16.0, 4.0 + k * 14.0)
	_trail.basis = FxUtil.basis_along(_flight_dir)
	_trail.scale = Vector3(0.45, tl, 0.45)
	_trail.position = head_pos - _flight_dir * tl * 0.5

	var pulse := 0.3 + 0.45 * (0.5 + 0.5 * sin(_t * 16.0))
	FxUtil.set_alpha(_mark_mat, pulse * (0.3 + k))

	if k >= 1.0:
		_begin_blast()


func _begin_blast() -> void:
	_head.queue_free()
	_trail.queue_free()
	_mark.queue_free()

	_falling = false
	_t = 0.0

	_flash_mat = FxUtil.emissive(FLASH_COLOR, FLASH_OPACITY)
	_flash = FxUtil.sphere(_flash_mat)
	_flash.position = Vector3(_target.x, _target.y + 0.5, _target.z)
	add_child(_flash)

	impacted.emit(_target, _radius)


func _update_blast() -> void:
	var k := minf(1.0, _t / BLAST_DUR)
	var r := _radius * (0.35 + k * 1.9)
	_flash.scale = Vector3.ONE * r
	FxUtil.set_alpha(_flash_mat, FLASH_OPACITY * (1.0 - k))

	if k >= 1.0:
		queue_free()
