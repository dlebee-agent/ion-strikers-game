class_name SpecialBeam
extends Node3D

const FxUtil = preload("res://core/fx_util.gd")
const SpecialBlast = preload("res://core/special_blast.gd")

# The discharge is a SEQUENCE, not one flash: the beam leaves the hand, crosses to
# where it landed, and only then does the impact go off. Cause, then effect — which
# is the whole difference between reading as a laser and reading as a light bulb.

const BEAM_SPEED := 380.0        # m/s; crosses the full arena in ~120ms
const BEAM_HOLD := 0.165         # full-length, full-width, before it lets go
const BEAM_FADE := 0.34
const DEFAULT_RADIUS := 4.5

# Where YOUR OWN beam starts. The hand is centimetres from the camera, so drawing
# from there puts the camera inside the beam and whites out the screen; and a beam
# you are looking straight down is a cylinder seen end-on, which reads as a disc
# stuck on your crosshair. So your own beam only becomes visible well out in front,
# where its cross-section is a few pixels. It still runs from the hand — you just
# do not see the first stretch, which is the part you could never see anyway.
const FP_BEAM_START := 10.0

# Fat and dramatic seen from outside; slim for the one person looking straight down
# it. Components are core / body / glow diameters.
const WIDTH_SLIM := Vector3(0.05, 0.12, 0.28)
const WIDTH_FAT := Vector3(0.10, 0.26, 0.62)

const CORE_OPACITY := 0.98
const BODY_OPACITY := 0.75
const GLOW_OPACITY := 0.22
const HEAD_OPACITY := 0.9
const HEAD_SIZE_FACTOR := 1.5

enum Phase { TRAVEL, HOLD, FADE }

var _from := Vector3.ZERO
var _dir := Vector3.FORWARD
var _length := 0.001
var _team := "blue"
var _radius := DEFAULT_RADIUS
var _width := WIDTH_FAT

var _phase: Phase = Phase.TRAVEL
var _lead := 0.0
var _t := 0.0

var _shaft: Node3D
var _core: MeshInstance3D
var _body: MeshInstance3D
var _glow: MeshInstance3D
var _core_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _head: MeshInstance3D


static func spawn(parent: Node, from: Vector3, to: Vector3, team: String,
		radius: float, slim: bool) -> SpecialBeam:
	var fx := SpecialBeam.new()
	parent.add_child(fx)
	fx._setup(from, to, team, radius, slim)
	return fx


func _setup(from: Vector3, to: Vector3, team: String, radius: float, slim: bool) -> void:
	_from = from
	_team = team
	_radius = radius
	_width = WIDTH_SLIM if slim else WIDTH_FAT

	var delta := to - from
	_length = maxf(delta.length(), 0.001)
	_dir = delta / _length

	var col := SpecialBlast.hot_color(team)
	_shaft = Node3D.new()
	_shaft.basis = FxUtil.basis_along(_dir)
	add_child(_shaft)

	# Widest first: the glow has to draw behind the body and core.
	_glow_mat = FxUtil.emissive(col, GLOW_OPACITY)
	_glow = FxUtil.cylinder(_glow_mat)
	_shaft.add_child(_glow)

	_body_mat = FxUtil.emissive(col, BODY_OPACITY)
	_body = FxUtil.cylinder(_body_mat)
	_shaft.add_child(_body)

	_core_mat = FxUtil.emissive(Color.WHITE, CORE_OPACITY)
	_core = FxUtil.cylinder(_core_mat)
	_shaft.add_child(_core)

	# The leading edge is brighter than the shaft behind it, which is what sells
	# the direction of travel.
	_head = FxUtil.sphere(FxUtil.emissive(Color.WHITE, HEAD_OPACITY))
	add_child(_head)

	_layout()


func _process(delta: float) -> void:
	_t += delta

	match _phase:
		Phase.TRAVEL:
			_lead = minf(_length, _lead + BEAM_SPEED * delta)
			if _lead >= _length - 0.001:
				_phase = Phase.HOLD
				_t = 0.0
				_head.visible = false
				# The blast is spawned by the beam ARRIVING, not fired alongside it.
				SpecialBlast.spawn(get_parent(), _from + _dir * _length, _team,
					_radius, _dir)
		Phase.HOLD:
			if _t >= BEAM_HOLD:
				_phase = Phase.FADE
				_t = 0.0
		Phase.FADE:
			if _t >= BEAM_FADE:
				queue_free()
				return

	_layout()


func _layout() -> void:
	var seg := _lead if _phase == Phase.TRAVEL else _length
	# The shaft thins and dims as it lets go, rather than blinking out.
	var f := minf(1.0, _t / BEAM_FADE) if _phase == Phase.FADE else 0.0
	var w := 1.0 - f * 0.8

	_shaft.global_position = _from + _dir * (seg * 0.5)
	_core.scale = Vector3(_width.x * w, seg, _width.x * w)
	_body.scale = Vector3(_width.y * w, seg, _width.y * w)
	_glow.scale = Vector3(_width.z * w, seg, _width.z * w)
	FxUtil.set_alpha(_core_mat, CORE_OPACITY * (1.0 - f))
	FxUtil.set_alpha(_body_mat, BODY_OPACITY * (1.0 - f))
	FxUtil.set_alpha(_glow_mat, GLOW_OPACITY * (1.0 - f))

	if _head.visible:
		_head.scale = Vector3.ONE * (_width.z * HEAD_SIZE_FACTOR)
		_head.global_position = _from + _dir * _lead
