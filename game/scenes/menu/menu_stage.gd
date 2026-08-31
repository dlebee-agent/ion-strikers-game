class_name MenuStage
extends Node3D

const TeamTint = preload("res://core/team_tint.gd")

# Three live match bodies on the home screen. Teams are a 2-vs-1 split so the
# stage never reads as a fair 1v1, and each body cycles a looping pose so the
# panel stays in motion without freezing mid-air on a one-shot clip.

const FIGHTER_COUNT := 3
const POSE_HOLD := 5.0
const POSE_HOLD_JITTER := 2.0

const STAGE_POSES: Array[AnimDriver.State] = [
	AnimDriver.State.IDLE,
	AnimDriver.State.WALK,
	AnimDriver.State.RUN,
	AnimDriver.State.DANCE,
	AnimDriver.State.CROUCH_IDLE,
	AnimDriver.State.CROUCH_WALK,
]

const SLOTS: Array[Vector3] = [
	Vector3(-1.15, 0.0, 0.14),
	Vector3(0.0, 0.0, -0.16),
	Vector3(1.15, 0.0, 0.14),
]
const YAWS: Array[float] = [18.0, 0.0, -18.0]

const GUN_MODEL_PATH := "res://assets/guns/pistol_2.gltf"
const GUN_HAND_POS := Vector3(-0.001, 0.078, 0.028)
const GUN_HAND_ROT := Vector3(79.36, -2.68, -1.25)
const GUN_HAND_SCALE := 0.32
const GUN_MODEL_YAW := 90.0
const HAND_BONE_NAMES := ["hand_r", "Hand_R", "mixamorig:RightHand"]

const RIM_BLUE := Color(0.31, 0.89, 0.96)
const RIM_RED := Color(0.96, 0.25, 0.37)

class Fighter:
	var root: Node3D
	var anim: AnimDriver
	var player: AnimationPlayer
	var pose: AnimDriver.State = AnimDriver.State.IDLE
	var due := 0.0

var teams: PackedStringArray = PackedStringArray()

var _fighters: Array[Fighter] = []


func _init() -> void:
	_roll_teams()


func _ready() -> void:
	_build_world()
	_spawn_fighters()
	_roll_all_poses(true)
	set_process(false)


func set_active(on: bool) -> void:
	set_process(on)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for f in _fighters:
		if now < f.due:
			continue
		_play_pose(f, _pick_pose(f.pose, _poses_except(f)), true)
		f.due = now + _next_hold()


func _roll_teams() -> void:
	teams = PackedStringArray()
	var majority := "blue" if randi() % 2 == 0 else "red"
	var minority := "red" if majority == "blue" else "blue"
	var loner := randi() % FIGHTER_COUNT
	for i in FIGHTER_COUNT:
		teams.append(minority if i == loner else majority)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 1.05
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.position = Vector3(0.0, 1.38, 5.05)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.92, 0.0))
	cam.current = true

	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.95)
	key.light_energy = 2.15
	key.spot_range = 18.0
	key.spot_angle = 48.0
	key.shadow_enabled = true
	key.position = Vector3(0.35, 6.4, 5.2)
	add_child(key)
	key.look_at(Vector3(0.0, 1.0, 0.0))

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.78, 0.92)
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)


func _spawn_fighters() -> void:
	for i in FIGHTER_COUNT:
		var team := teams[i]
		var f := _make_fighter(team)
		if f == null:
			continue
		f.root.position = SLOTS[i]
		f.root.rotation_degrees.y = YAWS[i]
		add_child(f.root)
		_add_rim(SLOTS[i], team)
		_fighters.append(f)


func _make_fighter(team: String) -> Fighter:
	var scene := load("res://assets/characters/mannequin.glb")
	if not scene:
		push_warning("Menu stage: could not load mannequin.glb")
		return null

	var f := Fighter.new()
	f.root = Node3D.new()
	var mannequin: Node3D = scene.instantiate()
	mannequin.scale = Vector3(0.98, 0.98, 0.98)
	f.root.add_child(mannequin)

	f.anim = AnimDriver.new()
	f.root.add_child(f.anim)
	f.anim.setup(mannequin)
	f.player = _find_animation_player(mannequin)

	var skeleton := _find_skeleton(mannequin)
	var gun := _attach_gun(skeleton)
	TeamTint.apply_body(mannequin, team)
	if gun:
		TeamTint.apply_gun(gun, team)
	return f


func _add_rim(at: Vector3, team: String) -> void:
	var rim := OmniLight3D.new()
	rim.light_color = RIM_RED if team == "red" else RIM_BLUE
	rim.light_energy = 1.55
	rim.omni_range = 7.5
	rim.position = at + Vector3(0.0, 1.65, -1.35)
	add_child(rim)


func _attach_gun(skeleton: Skeleton3D) -> Node3D:
	if not skeleton:
		return null
	var gun_scene := load(GUN_MODEL_PATH)
	if not gun_scene:
		return null
	var bone_name := ""
	for candidate: String in HAND_BONE_NAMES:
		if skeleton.find_bone(candidate) != -1:
			bone_name = candidate
			break
	if bone_name.is_empty():
		return null

	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	skeleton.add_child(attach)

	var seat := Node3D.new()
	seat.rotation_order = EULER_ORDER_ZYX
	seat.position = GUN_HAND_POS
	seat.rotation_degrees = GUN_HAND_ROT
	attach.add_child(seat)

	var model: Node3D = gun_scene.instantiate()
	model.rotation_degrees = Vector3(0.0, GUN_MODEL_YAW, 0.0)
	model.scale = Vector3.ONE * GUN_HAND_SCALE
	seat.add_child(model)
	return model


func _roll_all_poses(force: bool) -> void:
	var used: Array[AnimDriver.State] = []
	var now := Time.get_ticks_msec() / 1000.0
	for f in _fighters:
		var pose := _pick_pose(f.pose, used)
		used.append(pose)
		_play_pose(f, pose, force)
		f.due = now + _next_hold() * (0.35 + randf() * 0.7)


func _play_pose(f: Fighter, pose: AnimDriver.State, force: bool) -> void:
	if force and pose == f.anim.current_state:
		f.anim.reset_locomotion()
	f.anim.set_state(pose)
	f.pose = pose
	if f.player and f.player.is_playing():
		var length := f.player.current_animation_length
		if length > 0.2:
			f.player.seek(randf() * length)
			f.player.advance(0.0)


func _poses_except(skip: Fighter) -> Array[AnimDriver.State]:
	var used: Array[AnimDriver.State] = []
	for f in _fighters:
		if f != skip:
			used.append(f.pose)
	return used


func _pick_pose(current: AnimDriver.State, used: Array[AnimDriver.State]) -> AnimDriver.State:
	var fresh: Array[AnimDriver.State] = []
	var others: Array[AnimDriver.State] = []
	for pose in STAGE_POSES:
		if pose == current:
			continue
		if used.has(pose):
			others.append(pose)
		else:
			fresh.append(pose)
	if not fresh.is_empty():
		return fresh.pick_random()
	if not others.is_empty():
		return others.pick_random()
	return STAGE_POSES.pick_random()


func _next_hold() -> float:
	return POSE_HOLD + (randf() * 2.0 - 1.0) * POSE_HOLD_JITTER


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
