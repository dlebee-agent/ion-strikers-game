class_name LocalPawn
extends Node3D

const Movement = preload("res://core/movement.gd")
const CameraRig = preload("res://core/camera_rig.gd")
const AnimDriver = preload("res://core/anim_driver.gd")
const WeaponPresenter = preload("res://core/weapon_presenter.gd")
const TeamTint = preload("res://core/team_tint.gd")
const SpecialBeam = preload("res://core/special_beam.gd")
const ChargeOrb = preload("res://core/charge_orb.gd")
const RigPalm = preload("res://core/rig_palm.gd")

# Owns Movement, AnimDriver, WeaponPresenter, and CameraRig. There is no
# second mover; the designer, the viewer, and a networked match all drive
# this same object.

var movement: Movement
var camera_rig: CameraRig
var anim_driver: AnimDriver
var weapon: WeaponPresenter

var _mannequin_instance: Node3D
var _fp_arms_instance: Node3D
var _fp_gun_instance: Node3D
var _tp_gun_instance: Node3D
var _fp_skeleton: Skeleton3D
var _tp_skeleton: Skeleton3D
var _fp_anim_player: AnimationPlayer
var _colliders: Array[AABB] = []
var team_color: String = "blue"
# Bumped to abandon a queued return-to-idle, standing in for clearTimeout().
var _fp_once_gen := 0
# Both bodies get an orb: only one is on screen at a time, but switching view
# mid-charge should not lose the light.
var _fp_charge_orb: ChargeOrb
var _tp_charge_orb: ChargeOrb

# Ported from the original viewer constants
const FP_ARMS_POS := Vector3(0.0, -1.5, 0.14)
const FP_ARMS_ROT_Y := 180.0

# A one-handed pistol, because the rig only ships pistol aim clips; a two-handed
# rifle never lines up with those poses.
const GUN_MODEL_PATH := "res://assets/guns/pistol_2.gltf"
# The hand seat cancels hand_r's own axes rather than nudging them: solved as the
# bone's inverse world rotation in the Pistol_Idle pose composed with a 180 yaw,
# which lands the barrel on forward with the magazine down.
const GUN_HAND_POS := Vector3(-0.001, 0.078, 0.028)
const GUN_HAND_ROT := Vector3(79.36, -2.68, -1.25)
const GUN_HAND_SCALE := 0.32
# The gun models are authored +X-forward while the rig aims down -Z.
const GUN_MODEL_YAW := 90.0
const HAND_BONE_NAMES := ["hand_r", "Hand_R", "mixamorig:RightHand"]

const FP_IDLE_CLIP := "Pistol_Idle"
const FP_SHOOT_CLIP := "Pistol_Shoot"
const FP_MELEE_CLIP := "Punch_Jab"
const FP_SPELL_ENTER_CLIP := "Spell_Simple_Enter"
const FP_SPELL_CHANNEL_CLIP := "Spell_Simple_Idle"
const FP_SPELL_FIRE_CLIP := "Spell_Simple_Shoot"

# The recoil kick is a clipped, sped-up slice of the shoot clip rather than the
# whole thing: at one shot every 140ms the full swing would never finish, and a
# half-played animation reads as a stutter instead of a kick.
const FP_SHOOT_SPEED := 2.0
const FP_SHOOT_HOLD := 0.2
const FP_MELEE_SPEED := 1.4
const FP_MELEE_HOLD := 0.48
const FP_SPELL_HANDOFF_LEAD := 0.12

# How far the special's beam reaches when it hits nothing. Must match the
# server's SPECIAL_RANGE so the blast you see is the blast that kills.
const SPECIAL_RANGE := 45.0

# The rig is authored facing +Z (toes point +Z), but a yaw of 0 in this game means
# facing -Z, so the body carries a half turn on top of its aim yaw.
const BODY_YAW_OFFSET := 180.0

const FP_BLEND_ONCE := 0.05
const FP_BLEND_IDLE := 0.12
const FP_BLEND_SPELL := 0.08
const FP_BLEND_CHANNEL := 0.15

func _init() -> void:
	movement = Movement.new()

func setup(colliders: Array[AABB]) -> void:
	_colliders = colliders
	movement.position = Vector3.ZERO
	movement.velocity = Vector3.ZERO
	movement.on_ground = true

	camera_rig = CameraRig.new()
	camera_rig.setup(movement)
	add_child(camera_rig)

	weapon = WeaponPresenter.new()
	add_child(weapon)

	anim_driver = AnimDriver.new()
	add_child(anim_driver)

	_load_mannequin()
	_load_fp_arms()
	_apply_team_tint()

	weapon.fired.connect(_on_weapon_fired)
	weapon.melee_hit.connect(_on_weapon_melee)
	weapon.special_started.connect(_on_special_started)
	weapon.special_fired.connect(_on_special_fired)

func _load_mannequin() -> void:
	var scene := load("res://assets/characters/mannequin.glb")
	if not scene:
		push_warning("Could not load mannequin.glb")
		return
	_mannequin_instance = scene.instantiate()
	_mannequin_instance.scale = Vector3(0.98, 0.98, 0.98)
	add_child(_mannequin_instance)
	anim_driver.setup(_mannequin_instance)
	_tp_skeleton = _find_skeleton(_mannequin_instance)
	_tp_gun_instance = _attach_gun(_tp_skeleton, "mannequin.glb")

func _load_fp_arms() -> void:
	var arms_scene := load("res://assets/characters/arms.glb")
	if not arms_scene:
		push_warning("Could not load arms.glb")
		return
	var cam := camera_rig.get_camera()
	if not cam:
		push_warning("Camera not available; first-person arms not attached")
		return

	_fp_arms_instance = arms_scene.instantiate()
	_fp_arms_instance.position = FP_ARMS_POS
	_fp_arms_instance.rotation_degrees = Vector3(0, FP_ARMS_ROT_Y, 0)
	cam.add_child(_fp_arms_instance)

	_fp_anim_player = _find_animation_player(_fp_arms_instance)
	_fp_play_idle()

	_fp_skeleton = _find_skeleton(_fp_arms_instance)
	_fp_gun_instance = _attach_gun(_fp_skeleton, "arms.glb")

# Seats the pistol in the rig's right hand. Two nested transforms, matching the
# original viewer: the seat cancels the bone's axes, and the model inside it
# carries the scale plus the yaw that turns +X-forward into -Z-forward.
func _attach_gun(skel: Skeleton3D, source: String) -> Node3D:
	if not skel:
		push_warning("No Skeleton3D found in " + source + "; gun not attached")
		return null

	var bone_name := ""
	for candidate in HAND_BONE_NAMES:
		if skel.find_bone(candidate) != -1:
			bone_name = candidate
			break
	if bone_name.is_empty():
		var all_bones: PackedStringArray = []
		for i in skel.get_bone_count():
			all_bones.append(skel.get_bone_name(i))
		push_warning("No hand bone in " + source + ". Bones: " + ", ".join(all_bones))
		return null

	var gun_scene := load(GUN_MODEL_PATH)
	if not gun_scene:
		push_warning("Could not load " + GUN_MODEL_PATH)
		return null

	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	skel.add_child(attach)

	var seat := Node3D.new()
	seat.name = "HandGun"
	# The seat angles were authored against a Z-Y-X composition, which is not
	# Godot's default order for euler assignment.
	seat.rotation_order = EULER_ORDER_ZYX
	seat.position = GUN_HAND_POS
	seat.rotation_degrees = GUN_HAND_ROT
	attach.add_child(seat)

	var model: Node3D = gun_scene.instantiate()
	model.rotation_degrees = Vector3(0.0, GUN_MODEL_YAW, 0.0)
	model.scale = Vector3.ONE * GUN_HAND_SCALE
	seat.add_child(model)
	return model

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

# ---- first-person arm animation ----
# The arms run their own one-shot-then-idle cycle rather than going through
# AnimDriver, because what the hands do and what the body does are different: the
# body never shows recoil, and these clips are only ever seen by their owner.

func _fp_play_idle() -> void:
	# Validity, not just null: a queued return-to-idle can outlive the scene.
	if is_instance_valid(_fp_anim_player) and _fp_anim_player.has_animation(FP_IDLE_CLIP):
		_fp_anim_player.play(FP_IDLE_CLIP, FP_BLEND_IDLE)
		_fp_anim_player.advance(0.0)

func _fp_play_once(clip: String, speed: float, hold: float) -> void:
	if not _fp_anim_player or not _fp_anim_player.has_animation(clip):
		return
	_fp_once_gen += 1
	var gen := _fp_once_gen
	_fp_anim_player.play(clip, FP_BLEND_ONCE, speed)
	# Restart from the top even if this clip is already running, so held fire keeps
	# kicking instead of settling into one long swing.
	_fp_anim_player.seek(0.0, true)
	await get_tree().create_timer(hold).timeout
	if gen != _fp_once_gen:
		return
	_fp_play_idle()

# Same two-part shape as the body: the raise plays once, then the channel loops
# until the discharge or death ends it.
func _fp_spell_charge() -> void:
	if not _fp_anim_player:
		return
	_fp_once_gen += 1
	var gen := _fp_once_gen

	var enter_length := 0.0
	if _fp_anim_player.has_animation(FP_SPELL_ENTER_CLIP):
		_fp_anim_player.play(FP_SPELL_ENTER_CLIP, FP_BLEND_SPELL)
		_fp_anim_player.seek(0.0, true)
		enter_length = _fp_anim_player.get_animation(FP_SPELL_ENTER_CLIP).length
	if not _fp_anim_player.has_animation(FP_SPELL_CHANNEL_CLIP):
		return

	await get_tree().create_timer(
		maxf(FP_SPELL_HANDOFF_LEAD, enter_length - FP_SPELL_HANDOFF_LEAD)).timeout
	if gen != _fp_once_gen or not is_instance_valid(_fp_anim_player):
		return
	_fp_anim_player.play(FP_SPELL_CHANNEL_CLIP, FP_BLEND_CHANNEL)

func _fp_spell_fire() -> void:
	var hold := 0.5
	if _fp_anim_player and _fp_anim_player.has_animation(FP_SPELL_FIRE_CLIP):
		hold = _fp_anim_player.get_animation(FP_SPELL_FIRE_CLIP).length
	_fp_play_once(FP_SPELL_FIRE_CLIP, 1.0, hold)

# Only the arms react to a shot. Third person stays recoil-free on purpose.
func _on_weapon_fired() -> void:
	_fp_play_once(FP_SHOOT_CLIP, FP_SHOOT_SPEED, FP_SHOOT_HOLD)

func _on_weapon_melee() -> void:
	_fp_play_once(FP_MELEE_CLIP, FP_MELEE_SPEED, FP_MELEE_HOLD)
	anim_driver.trigger_melee()

func _on_special_started() -> void:
	_fp_spell_charge()
	anim_driver.start_spell_charge()
	_attach_charge_orbs()

func _on_special_fired() -> void:
	_fp_spell_fire()
	anim_driver.fire_spell()
	_clear_charge_orbs()
	_spawn_special_beam()


func cancel_special() -> void:
	weapon.cancel_special()
	_fp_once_gen += 1
	_fp_play_idle()
	anim_driver.end_spell()
	_clear_charge_orbs()

func _attach_charge_orbs() -> void:
	_clear_charge_orbs()
	_fp_charge_orb = ChargeOrb.attach(_fp_skeleton, team_color, true)
	_tp_charge_orb = ChargeOrb.attach(_tp_skeleton, team_color, false)

# The light goes out when the charge leaves the hand — either as a discharge or
# because the wind-up was abandoned.
func _clear_charge_orbs() -> void:
	if is_instance_valid(_fp_charge_orb):
		_fp_charge_orb.queue_free()
	if is_instance_valid(_tp_charge_orb):
		_tp_charge_orb.queue_free()
	_fp_charge_orb = null
	_tp_charge_orb = null

func _spawn_special_beam() -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var eye := camera_rig.get_aim_origin()
	var dir := camera_rig.get_aim_direction()
	var dist := weapon.raycast_special(eye, dir, _colliders, SPECIAL_RANGE)
	var impact := eye + dir * dist
	var first_person := camera_rig.mode == CameraRig.Mode.FIRST_PERSON
	SpecialBeam.spawn(scene, _beam_origin(eye, dir, impact, first_person), impact,
		team_color, SpecialBeam.DEFAULT_RADIUS, first_person)
	weapon.play_laser(impact)

# The beam leaves the casting PALM, not the eye and not the gun: the spell clips
# throw the empty left hand forward and drop the gun hand behind the hip, so firing
# from the pistol sends the beam out of the body's back. Your own view is the
# exception: the hand is inside the camera, so the beam only becomes visible further
# down the ray — but never past halfway, or a point-blank discharge draws nothing.
func _beam_origin(eye: Vector3, dir: Vector3, impact: Vector3, first_person: bool) -> Vector3:
	var skeleton := _fp_skeleton if first_person else _tp_skeleton
	var palm := RigPalm.aim_point(skeleton, eye, dir, eye)
	if not first_person:
		return palm

	var to_impact := impact - palm
	var length := to_impact.length()
	if length < 0.001:
		return palm
	return palm + (to_impact / length) * minf(SpecialBeam.FP_BEAM_START, length * 0.5)

func set_team(color: String) -> void:
	team_color = color
	if weapon:
		weapon.team = color
	_apply_team_tint()

func _apply_team_tint() -> void:
	TeamTint.apply_body(_mannequin_instance, team_color)
	TeamTint.apply_body(_fp_arms_instance, team_color)
	TeamTint.apply_gun(_tp_gun_instance, team_color)
	TeamTint.apply_gun(_fp_gun_instance, team_color)

func get_mannequin() -> Node3D:
	return _mannequin_instance

func set_mannequin_visible(vis: bool) -> void:
	if _mannequin_instance:
		_mannequin_instance.visible = vis

func set_fp_arms_visible(vis: bool) -> void:
	if _fp_arms_instance:
		_fp_arms_instance.visible = vis

func process_input(dt: float) -> void:
	# Cooldowns and the special's wind-up run in every mode: preview drives the
	# special from its own button, and a charge started there still has to resolve.
	weapon.update(dt)

	if camera_rig.mode == CameraRig.Mode.PREVIEW:
		# Preview inspects the body rather than plays it: it holds still and faces
		# the camera, and the orbit does all the moving. The camera still has to be
		# placed every frame, or dragging would change the orbit without the view
		# ever following it.
		_pose_for_preview()
		camera_rig.update_camera()
		return

	var wish_fwd := 0.0
	var wish_side := 0.0
	if InputBinds.is_action_pressed("forward"):
		wish_fwd += 1.0
	if InputBinds.is_action_pressed("back"):
		wish_fwd -= 1.0
	if InputBinds.is_action_pressed("right"):
		wish_side += 1.0
	if InputBinds.is_action_pressed("left"):
		wish_side -= 1.0

	var want_jump := InputBinds.is_action_pressed("jump")
	var want_crouch := InputBinds.is_action_pressed("crouch")
	var want_walk := InputBinds.is_action_pressed("walk")

	# Third person orbits freely, so WASD is camera-relative and the body turns to
	# face wherever it is heading. Walking toward the camera therefore shows you the
	# front, which is the only way to inspect an animation from the other side.
	if camera_rig.mode == CameraRig.Mode.THIRD_PERSON:
		var move_dir := camera_rig.get_ground_move_direction(wish_fwd, wish_side)
		wish_side = 0.0
		if move_dir == Vector3.ZERO:
			wish_fwd = 0.0
		else:
			movement.yaw = rad_to_deg(atan2(-move_dir.x, -move_dir.z))
			wish_fwd = 1.0

	movement.update(dt, wish_fwd, wish_side, want_jump, want_crouch, want_walk, _colliders)

	if InputBinds.is_action_pressed("fire"):
		weapon.try_fire(camera_rig.get_aim_origin(), camera_rig.get_aim_direction(),
			_colliders)

	# Auto-fire while held; melee is one punch per press so holding it does not
	# machine-gun once the cooldown lapses.
	if InputBinds.is_action_just_pressed("melee"):
		weapon.try_melee()

	if InputBinds.is_action_just_pressed("special"):
		weapon.start_special()
	if InputBinds.is_action_just_released("special"):
		weapon.do_special_fire()

	anim_driver.update_from_movement(movement)

	if _mannequin_instance:
		_mannequin_instance.global_position = movement.position
		_mannequin_instance.rotation_degrees.y = movement.yaw + BODY_YAW_OFFSET

	camera_rig.update_camera()

# The preview orbit starts on +Z and the rig is authored facing +Z, so leaving the
# body unrotated turns it toward the camera instead of showing you its back.
func _pose_for_preview() -> void:
	if not _mannequin_instance:
		return
	_mannequin_instance.global_position = movement.position
	_mannequin_instance.rotation_degrees.y = 0.0
