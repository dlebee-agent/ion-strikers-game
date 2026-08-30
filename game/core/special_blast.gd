class_name SpecialBlast
extends Node3D

const FxUtil = preload("res://core/fx_util.gd")

# The impact, once the beam has actually got there: a hot core flash, a shell that
# expands to the radius the special really kills with, and sparks thrown out along
# the beam. Spheres rather than a ground disc, because the beam ends in mid-air as
# often as it ends on a floor.

const FLASH_DUR := 0.62
const SHELL_DUR := 0.52
const SPARK_DUR := 0.54
const SPARKS := 9

const FLASH_COLOR := Color8(255, 244, 208)
const SPARK_COLOR := Color8(255, 217, 160)
const HOT_RED := Color8(255, 106, 90)
const HOT_BLUE := Color8(122, 184, 255)

const FLASH_OPACITY := 0.95
const SHELL_OPACITY := 0.3
const SPARK_OPACITY := 0.85
const SPARK_WIDTH := 0.11

var _radius := 4.5
var _t := 0.0

var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
# Each spark keeps the direction it was thrown and how far it gets.
var _sparks: Array[Dictionary] = []


static func hot_color(team: String) -> Color:
	return HOT_RED if team == "red" else HOT_BLUE


static func spawn(parent: Node, at: Vector3, team: String, radius: float,
		beam_dir: Vector3) -> SpecialBlast:
	var fx := SpecialBlast.new()
	parent.add_child(fx)
	fx._setup(at, team, radius, beam_dir)
	return fx


func _setup(at: Vector3, team: String, radius: float, beam_dir: Vector3) -> void:
	_radius = radius
	global_position = at

	_flash_mat = FxUtil.emissive(FLASH_COLOR, FLASH_OPACITY)
	_flash = FxUtil.sphere(_flash_mat)
	add_child(_flash)

	_shell_mat = FxUtil.emissive(hot_color(team), SHELL_OPACITY)
	_shell = FxUtil.sphere(_shell_mat)
	add_child(_shell)

	_build_sparks(beam_dir)


# Thrown mostly forward, spraying off the axis the beam came in on.
func _build_sparks(beam_dir: Vector3) -> void:
	var d := beam_dir.normalized()
	var side := Vector3(1.0, 0.0, 0.0) if absf(d.y) > 0.9 else Vector3(-d.z, 0.0, d.x)
	var s1 := side.normalized()
	var s2 := d.cross(s1)

	for i in SPARKS:
		var a := (float(i) / float(SPARKS)) * TAU + randf() * 0.4
		var spread := 0.55 + randf() * 0.75
		var dir := (d * 0.35 + (s1 * cos(a) + s2 * sin(a)) * spread).normalized()

		var mat := FxUtil.emissive(SPARK_COLOR, SPARK_OPACITY)
		var mi := FxUtil.cylinder(mat)
		mi.basis = FxUtil.basis_along(dir)
		add_child(mi)
		_sparks.append({
			"node": mi,
			"mat": mat,
			"dir": dir,
			"reach": _radius * (0.7 + randf() * 0.9),
		})


func _process(delta: float) -> void:
	_t += delta

	# Fast out, and it never pretends to be bigger than the kill radius.
	var kf := minf(1.0, _t / FLASH_DUR)
	_flash.scale = Vector3.ONE * (_radius * (0.25 + pow(kf, 0.45) * 1.5))
	FxUtil.set_alpha(_flash_mat, FLASH_OPACITY * (1.0 - kf))

	# The mesh is unit DIAMETER, so scaling to 2x radius puts the shell exactly
	# where the damage is: the shell arrives where the kill volume is.
	var ks := minf(1.0, _t / SHELL_DUR)
	_shell.scale = Vector3.ONE * (_radius * 2.0 * pow(ks, 0.55))
	FxUtil.set_alpha(_shell_mat, SHELL_OPACITY * (1.0 - ks))

	var kp := minf(1.0, _t / SPARK_DUR)
	for spark in _sparks:
		var reach: float = spark["reach"]
		var dir: Vector3 = spark["dir"]
		var node: MeshInstance3D = spark["node"]
		var length := maxf(0.15, reach * 0.35 * (1.0 - kp))
		node.scale = Vector3(SPARK_WIDTH, length, SPARK_WIDTH)
		node.position = dir * (reach * pow(kp, 0.5))
		FxUtil.set_alpha(spark["mat"], SPARK_OPACITY * (1.0 - kp))

	if _t >= maxf(FLASH_DUR, maxf(SHELL_DUR, SPARK_DUR)):
		queue_free()
