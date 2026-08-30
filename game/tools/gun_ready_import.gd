@tool
extends EditorScenePostImport

# The Quaternius pack ships no pistol-carrying locomotion: Walk, Sprint and the
# crouches all swing both arms freely, so a player holding a gun only looks armed
# while standing still. laser-arena fixed that by rebuilding the clips at load
# (public/game.js, buildGunReadyTracks); here the same surgery runs once at
# import, so the game only ever plays a real Animation.
#
# A baked clip keeps the source's lower body untouched — pelvis lean, hips, legs,
# feet — and replaces everything from spine_01 up with Pistol_Idle's first frame,
# held for the whole clip. Freezing rather than looping the aim clip avoids a pop
# where two clips of different lengths wrap, and frame 0 is the exact pose the
# hand-gun seat in LocalPawn was solved against, so the pistol stays in the palm.
#
# spine_01 is the exception. Frozen there, its LOCAL rotation would inherit the
# source's pelvis pitch — Sprint leans about 30 degrees — and tip the whole torso
# head-down. It gets a per-frame counter-rotation instead: the local rotation
# whose WORLD orientation equals the aim pose's regardless of what the hips do.
#
#   spine_01(t) = inv(root(t) * pelvis(t)) * root_aim * pelvis_aim * spine_01_aim

const AIM_CLIP := "Pistol_Idle"
# Every bone at or under this one is upper body: spine, neck, head, both arms.
const UPPER_ROOT := "spine_01"
const HIP_BONE := "pelvis"
const RIG_ROOT := "root"
# Locomotion, plus the jump: a player caught mid-air is still holding the gun.
const GUN_READY := ["Walk", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump"]
const SUFFIX := "_GunReady"


func _post_import(scene: Node) -> Object:
	var skeleton := _find_skeleton(scene)
	var player := _find_animation_player(scene)
	if not skeleton or not player:
		push_warning("gun-ready bake skipped: no Skeleton3D/AnimationPlayer in " + get_source_file())
		return scene

	var library := _first_library(player)
	if not library or not library.has_animation(AIM_CLIP):
		push_warning("gun-ready bake skipped: no " + AIM_CLIP + " in " + get_source_file())
		return scene

	var aim := library.get_animation(AIM_CLIP)
	var upper := _upper_body_bones(skeleton)
	var frozen := _sample_pose(aim, 0.0)
	# The parent of spine_01 in the aim pose, as one world rotation.
	var aim_parent: Quaternion = frozen.rotation.get(RIG_ROOT, Quaternion()) \
		* frozen.rotation.get(HIP_BONE, Quaternion())
	var aim_spine: Quaternion = frozen.rotation.get(UPPER_ROOT, Quaternion())

	for clip_name: String in GUN_READY:
		if not library.has_animation(clip_name):
			push_warning("gun-ready bake: no clip named " + clip_name)
			continue
		var baked := _bake(library.get_animation(clip_name), upper, frozen,
			aim_parent * aim_spine)
		library.add_animation(clip_name + SUFFIX, baked)

	return scene


# Every bone whose chain passes through UPPER_ROOT, that bone included.
func _upper_body_bones(skeleton: Skeleton3D) -> Dictionary:
	var top := skeleton.find_bone(UPPER_ROOT)
	var upper := {}
	for i in skeleton.get_bone_count():
		var walk := i
		while walk != -1:
			if walk == top:
				upper[skeleton.get_bone_name(i)] = true
				break
			walk = skeleton.get_bone_parent(walk)
	return upper


# Bone name -> value at `time`, one dictionary per track type.
func _sample_pose(anim: Animation, time: float) -> Dictionary:
	var pose := {"position": {}, "rotation": {}, "scale": {}}
	for track in anim.get_track_count():
		var bone := _bone_of(anim, track)
		match anim.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				pose.position[bone] = anim.position_track_interpolate(track, time)
			Animation.TYPE_ROTATION_3D:
				pose.rotation[bone] = anim.rotation_track_interpolate(track, time)
			Animation.TYPE_SCALE_3D:
				pose.scale[bone] = anim.scale_track_interpolate(track, time)
	return pose


func _bake(source: Animation, upper: Dictionary, frozen: Dictionary,
		aim_spine_world: Quaternion) -> Animation:
	var baked: Animation = source.duplicate(true)
	var spine_track := -1

	for track in baked.get_track_count():
		var bone := _bone_of(baked, track)
		if not upper.has(bone):
			continue
		var track_type := baked.track_get_type(track)
		if bone == UPPER_ROOT and track_type == Animation.TYPE_ROTATION_3D:
			spine_track = track
			continue

		var key: String = {
			Animation.TYPE_POSITION_3D: "position",
			Animation.TYPE_ROTATION_3D: "rotation",
			Animation.TYPE_SCALE_3D: "scale",
		}.get(track_type, "")
		if key.is_empty() or not frozen[key].has(bone):
			continue

		_clear_keys(baked, track)
		match track_type:
			Animation.TYPE_POSITION_3D:
				baked.position_track_insert_key(track, 0.0, frozen.position[bone])
			Animation.TYPE_ROTATION_3D:
				baked.rotation_track_insert_key(track, 0.0, frozen.rotation[bone])
			Animation.TYPE_SCALE_3D:
				baked.scale_track_insert_key(track, 0.0, frozen.scale[bone])

	if spine_track != -1:
		_bake_spine(baked, spine_track, aim_spine_world)
	return baked


# Resample spine_01 against the source's own hips so the torso keeps the aim
# pose's world orientation. Keyed at the hip track's own times: that is where the
# lean actually changes, so the counter-rotation cannot drift between keys.
func _bake_spine(baked: Animation, spine_track: int, aim_spine_world: Quaternion) -> void:
	var hips := _rotation_track(baked, HIP_BONE)
	if hips == -1:
		return
	var rig_root := _rotation_track(baked, RIG_ROOT)

	var times: PackedFloat32Array = []
	for k in baked.track_get_key_count(hips):
		times.append(baked.track_get_key_time(hips, k))

	var values: Array[Quaternion] = []
	for time in times:
		var parent := baked.rotation_track_interpolate(hips, time)
		if rig_root != -1:
			parent = baked.rotation_track_interpolate(rig_root, time) * parent
		values.append(parent.inverse() * aim_spine_world)

	_clear_keys(baked, spine_track)
	for i in times.size():
		baked.rotation_track_insert_key(spine_track, times[i], values[i])


func _rotation_track(anim: Animation, bone: String) -> int:
	for track in anim.get_track_count():
		if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D \
				and _bone_of(anim, track) == bone:
			return track
	return -1


func _bone_of(anim: Animation, track: int) -> String:
	return String(anim.track_get_path(track)).get_slice(":", 1)


func _clear_keys(anim: Animation, track: int) -> void:
	for k in range(anim.track_get_key_count(track) - 1, -1, -1):
		anim.track_remove_key(track, k)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _first_library(player: AnimationPlayer) -> AnimationLibrary:
	for name in player.get_animation_library_list():
		return player.get_animation_library(name)
	return null
