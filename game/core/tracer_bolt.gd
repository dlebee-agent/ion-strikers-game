class_name TracerBolt
extends Node3D

const ImpactFlash = preload("res://core/impact_flash.gd")

# Visible bolt starts this far from the muzzle — never draws in your face.
const BOLT_START := 3.2
const BOLT_SPEED := 130.0
const BOLT_LENGTH := 10.0

const CORE_RADIUS := 0.035
const GLOW_RADIUS := 0.1
const CORE_COLOR := Color(1.0, 1.0, 1.0, 0.95)

# The bolt carries its shooter's team colour. The lighter shade is what a wall
# hit flashes with; a body hit flashes the bolt colour itself, so the two read
# differently without needing a hit marker.
const BOLT_RED := Color8(255, 59, 70)
const BOLT_BLUE := Color8(53, 158, 255)
const GLOW_RED := Color8(255, 138, 144)
const GLOW_BLUE := Color8(174, 218, 255)

var _muzzle: Vector3
var _dir: Vector3
var _impact_dist: float
var _lead: float = BOLT_START
var _bolt_color := BOLT_BLUE
var _glow_color := GLOW_BLUE
var _hit_player := false

var _core: MeshInstance3D
var _glow: MeshInstance3D


static func bolt_color(team: String) -> Color:
	return BOLT_RED if team == "red" else BOLT_BLUE


static func glow_color(team: String) -> Color:
	return GLOW_RED if team == "red" else GLOW_BLUE


static func spawn(parent: Node, muzzle: Vector3, direction: Vector3, impact_dist: float,
		team: String = "blue", hit_player: bool = false) -> TracerBolt:
	var bolt := TracerBolt.new()
	# In the tree first: _setup orients the bolt, and look_at needs a global
	# transform to work from.
	parent.add_child(bolt)
	bolt._setup(muzzle, direction, impact_dist, team, hit_player)
	return bolt


func _setup(muzzle: Vector3, direction: Vector3, impact_dist: float, team: String,
		hit_player: bool) -> void:
	_muzzle = muzzle
	_dir = direction.normalized()
	_impact_dist = impact_dist
	_bolt_color = bolt_color(team)
	_glow_color = glow_color(team)
	_hit_player = hit_player

	_core = _make_segment(CORE_RADIUS, CORE_COLOR, 4.0)
	_glow = _make_segment(GLOW_RADIUS, Color(_bolt_color, 0.5), 3.0)
	add_child(_glow)
	add_child(_core)

	_orient_along(_dir)
	_update_segment(BOLT_START, 0.0)


func _make_segment(radius: float, color: Color, emission: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emission
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Depth testing stays on. With it off the bolt painted over every surface in
	# front of it, so a shot fired in the next room was visible through the wall
	# between.
	cyl.material = mat
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


func _process(delta: float) -> void:
	_lead += BOLT_SPEED * delta
	_lead = minf(_lead, _impact_dist)

	var tail := maxf(BOLT_START, _lead - BOLT_LENGTH)
	var seg := maxf(0.0, _lead - tail)
	_update_segment(tail, seg)

	if _lead >= _impact_dist - 0.01:
		# The pop belongs to the bolt getting there, so it is spawned here rather
		# than at fire time.
		var flash_color := _bolt_color if _hit_player else _glow_color
		ImpactFlash.spawn(get_parent(), _muzzle + _dir * _impact_dist, flash_color,
			_bolt_color, _hit_player)
		queue_free()


func _update_segment(tail: float, seg: float) -> void:
	var show := seg > 0.01
	_core.visible = show
	_glow.visible = show
	if not show:
		return

	global_position = _muzzle + _dir * (tail + seg * 0.5)
	_orient_along(_dir)
	_core.scale = Vector3(1.0, seg, 1.0)
	_glow.scale = Vector3(1.0, seg, 1.0)


func _orient_along(direction: Vector3) -> void:
	if absf(direction.dot(Vector3.UP)) < 0.999:
		look_at(global_position + direction, Vector3.UP)
		rotate_object_local(Vector3.RIGHT, PI * 0.5)
