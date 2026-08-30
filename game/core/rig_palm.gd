class_name RigPalm
extends RefCounted

# Where a spell leaves a hand.
#
# Measured off the rig rather than guessed. A hand bone sits at the WRIST, with its
# local +Y running 0.122m out to the knuckles and its local +X passing out through
# the palm (mirrored to -X on the right hand). So anything placed at the bone origin
# hangs off the end of the forearm, which reads as a charge in the arm rather than
# in the hand. These offsets put it mid-palm and just clear of the skin, so a small
# orb is not buried inside the mesh.
const ALONG_PALM := 0.065
const OUT_OF_PALM := 0.04

# Names in rig order of preference, since the arms and body rigs are the same rig
# but other rigs may not be.
const LEFT_BONES: Array[String] = ["hand_l", "Hand_L", "mixamorig:LeftHand"]
const RIGHT_BONES: Array[String] = ["hand_r", "Hand_R", "mixamorig:RightHand"]

# Returns -1 when the rig has no such hand.
static func find_hand(skeleton: Skeleton3D, right: bool) -> int:
	if not skeleton:
		return -1
	for name in (RIGHT_BONES if right else LEFT_BONES):
		var idx := skeleton.find_bone(name)
		if idx != -1:
			return idx
	return -1

# The palm, in the hand bone's own space.
static func local_offset(right: bool) -> Vector3:
	return Vector3(-OUT_OF_PALM if right else OUT_OF_PALM, ALONG_PALM, 0.0)

static func world_point(skeleton: Skeleton3D, bone_idx: int, right: bool) -> Vector3:
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	return pose * local_offset(right)

# The palm to fire from: whichever one the animation has thrown out toward the
# target, which for the spell clips is the left. Falls back to the given point
# while a rig is still loading, so a discharge always draws something.
static func aim_point(skeleton: Skeleton3D, from: Vector3, dir: Vector3,
		fallback: Vector3) -> Vector3:
	if not skeleton or not skeleton.is_inside_tree():
		return fallback
	var best := fallback
	var best_reach := -INF
	for right in [false, true]:
		var idx := find_hand(skeleton, right)
		if idx == -1:
			continue
		var point := world_point(skeleton, idx, right)
		var reach := (point - from).dot(dir)
		if reach > best_reach:
			best_reach = reach
			best = point
	return best
