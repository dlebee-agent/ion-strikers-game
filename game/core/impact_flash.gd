class_name ImpactFlash
extends Node3D

const FxUtil = preload("res://core/fx_util.gd")

# The small collision pop where a bolt lands. It grows as it fades, which reads as
# a hit rather than as a light switching off, and it throws a brief omni light so
# the surface it landed on is actually lit by it.

const DURATION := 0.16
const START_SIZE := 0.05
const PLAYER_SIZE := 0.55
const WALL_SIZE := 0.35
# Brightness and reach happen to share the same pair of numbers, but they are not
# the same thing: energy is how hard it flashes, range is how far the light carries.
const PLAYER_ENERGY := 4.0
const WALL_ENERGY := 2.5
const PLAYER_RANGE := 4.0
const WALL_RANGE := 2.5
const BASE_OPACITY := 0.9

var _mat: StandardMaterial3D
var _sphere: MeshInstance3D
var _light: OmniLight3D
var _peak := WALL_SIZE
var _energy := WALL_ENERGY
var _t := 0.0


static func spawn(parent: Node, at: Vector3, color: Color, light_color: Color,
		hit_player: bool) -> ImpactFlash:
	var fx := ImpactFlash.new()
	parent.add_child(fx)
	fx._setup(at, color, light_color, hit_player)
	return fx


func _setup(at: Vector3, color: Color, light_color: Color, hit_player: bool) -> void:
	global_position = at
	_peak = PLAYER_SIZE if hit_player else WALL_SIZE
	_energy = PLAYER_ENERGY if hit_player else WALL_ENERGY

	_mat = FxUtil.emissive(color, BASE_OPACITY)
	_sphere = FxUtil.sphere(_mat)
	_sphere.scale = Vector3.ONE * START_SIZE
	add_child(_sphere)

	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = PLAYER_RANGE if hit_player else WALL_RANGE
	_light.light_energy = _energy
	_light.shadow_enabled = false
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	# Counts down, so f runs 1 -> 0: the flash is at its brightest the instant it
	# lands and at its widest as it disappears.
	var f := maxf(0.0, 1.0 - _t / DURATION)
	var size := _peak * (1.0 - f) + START_SIZE
	_sphere.scale = Vector3.ONE * size
	FxUtil.set_alpha(_mat, f)
	_light.light_energy = f * _energy
	if _t >= DURATION:
		queue_free()
