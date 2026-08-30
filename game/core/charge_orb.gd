class_name ChargeOrb
extends BoneAttachment3D

const FxUtil = preload("res://core/fx_util.gd")
const SpecialBlast = preload("res://core/special_blast.gd")
const RigPalm = preload("res://core/rig_palm.gd")

# A charging player grows a light in their palm. It rides the hand bone, so the
# spell animation carries it: as the arm comes up, the light comes up with it.
#
# This is a BoneAttachment3D rather than something parented to one, so freeing it
# takes the whole rig off the skeleton with it and there is no seat left behind.

# How long the build takes to reach full intensity.
const SURGE_FULL := 1.1

const ORB_OPACITY := 0.92
const HALO_OPACITY := 0.3

# The first-person hand is about half a metre from the camera rather than several.
# The same orb that reads as a spark in a palm across the arena fills the whole
# screen from there, so the first-person one is roughly a quarter the size. Same
# effect, sized for the distance it is seen at.
const FP_BASE_SIZE := 0.012
const FP_GROWTH := 0.05
const FP_HALO_FACTOR := 2.1
const TP_BASE_SIZE := 0.03
const TP_GROWTH := 0.13
const TP_HALO_BASE := 2.6
const TP_HALO_GROWTH := 0.9

var _first_person := false
var _orb: MeshInstance3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _elapsed := 0.0


# The spell clips throw the LEFT arm forward, so that is the hand a charge glows in.
# Returns null when the rig has no palm bone, so callers can carry on without it.
static func attach(skeleton: Skeleton3D, team: String, first_person: bool) -> ChargeOrb:
	var right := false
	var bone := RigPalm.find_hand(skeleton, right)
	if bone == -1:
		right = true
		bone = RigPalm.find_hand(skeleton, right)
	if bone == -1:
		return null

	var orb := ChargeOrb.new()
	orb._first_person = first_person
	skeleton.add_child(orb)
	# Set once parented, so the node also resolves its bone_name from the skeleton.
	orb.bone_idx = bone
	orb._build(team, right)
	return orb


func _build(team: String, right: bool) -> void:
	# This node tracks the wrist, so the palm offset rides on a seat inside it.
	var seat := Node3D.new()
	seat.position = RigPalm.local_offset(right)
	add_child(seat)

	_orb = FxUtil.sphere(FxUtil.emissive(Color.WHITE, ORB_OPACITY))
	seat.add_child(_orb)

	_halo_mat = FxUtil.emissive(SpecialBlast.hot_color(team), HALO_OPACITY)
	_halo = FxUtil.sphere(_halo_mat)
	seat.add_child(_halo)

	_apply(0.0)


func _process(delta: float) -> void:
	_elapsed += delta
	_apply(minf(1.0, _elapsed / SURGE_FULL))


func _apply(k: float) -> void:
	# Grows, and flickers faster the closer it gets to going off.
	var period_ms := 60.0 - k * 34.0
	var pulse := 1.0 + sin(_elapsed * 1000.0 / period_ms) * (0.06 + k * 0.14)

	var size := 0.0
	var halo_factor := 0.0
	if _first_person:
		size = (FP_BASE_SIZE + k * FP_GROWTH) * pulse
		halo_factor = FP_HALO_FACTOR
	else:
		size = (TP_BASE_SIZE + k * TP_GROWTH) * pulse
		halo_factor = TP_HALO_BASE + k * TP_HALO_GROWTH

	_orb.scale = Vector3.ONE * size
	_halo.scale = Vector3.ONE * (size * halo_factor)
	FxUtil.set_alpha(_halo_mat, 0.14 + k * 0.26)
