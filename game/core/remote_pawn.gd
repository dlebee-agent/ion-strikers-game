class_name RemotePawn
extends Node3D

const AnimDriver = preload("res://core/anim_driver.gd")
const TeamTint = preload("res://core/team_tint.gd")
const Movement = preload("res://core/movement.gd")
const ChargeOrb = preload("res://core/charge_orb.gd")
const RagdollScript = preload("res://core/ragdoll.gd")

const INTERP_DELAY_MS := 80.0
const MAX_SAMPLES := 10
const BODY_YAW_OFFSET := 180.0
const GUN_MODEL_PATH := "res://assets/guns/pistol_2.gd"
const GUN_HAND_POS := Vector3(-0.001, 0.078, 0.028)
const GUN_HAND_ROT := Vector3(79.36, -2.68, -1.25)
const GUN_HAND_SCALE := 0.32
const GUN_MODEL_YAW := 90.0
const HAND_BONE_NAMES := ["hand_r", "Hand_R", "mixamorig:RightHand"]

var peer_id: int = 0
var team: int = 0
var alive: bool = true
var display_name: String = ""
## Refreshed from the snapshot flags, because it stops being true the moment a
## dead player takes this body over.
var is_bot: bool = false

var _mannequin: Node3D
var _skeleton: Skeleton3D
var _gun: Node3D
var _anim_driver: AnimDriver
var _movement: Movement

var _samples: Array[Dictionary] = []
var _last_time: float = 0.0
var _render_time: float = 0.0

var _last_eye_x: float = 0.0
var _last_eye_y: float = 0.0
var _last_eye_z: float = 0.0
var _last_eye_yaw: float = 0.0
var _last_eye_pitch: float = 0.0
var _last_eye_crouched: bool = false

var _charge_orb: ChargeOrb
var ragdoll: Ragdoll
var _ragdoll_frozen := false
# True when this player was already dead in the first snapshot we saw of them,
# so their body is parked out of sight rather than ragdolled.
var _joined_dead := false


func setup(p_id: int, p_name: String, p_team: int) -> void:
	peer_id = p_id
	display_name = p_name
	team = p_team
	_load_mannequin()


# A player who was already dead when we first saw them has no death for us to
# play: there is no alive→dead edge for the ragdoll to hang off, so the body
# would stand in its idle pose looking like a live target that never takes a
# hit. Seed the dead state up front and keep the body off screen until they
# respawn.
func adopt_initial_alive(is_alive: bool) -> void:
	alive = is_alive
	if is_alive:
		return
	_ragdoll_frozen = true
	_joined_dead = true
	set_body_visible(false)


func _load_mannequin() -> void:
	var scene := load("res://assets/characters/mannequin.glb")
	if not scene:
		return
	_mannequin = scene.instantiate()
	_mannequin.scale = Vector3(0.98, 0.98, 0.98)
	add_child(_mannequin)

	_anim_driver = AnimDriver.new()
	add_child(_anim_driver)
	_anim_driver.setup(_mannequin)

	_movement = Movement.new()

	_skeleton = _find_skeleton(_mannequin)
	_attach_gun()
	_apply_tint()


func _attach_gun() -> void:
	if not _skeleton:
		return
	var gun_scene := load("res://assets/guns/pistol_2.gltf")
	if not gun_scene:
		return

	var bone_name := ""
	for candidate: String in HAND_BONE_NAMES:
		if _skeleton.find_bone(candidate) != -1:
			bone_name = candidate
			break
	if bone_name.is_empty():
		return

	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	_skeleton.add_child(attach)

	var seat := Node3D.new()
	seat.rotation_order = EULER_ORDER_ZYX
	seat.position = GUN_HAND_POS
	seat.rotation_degrees = GUN_HAND_ROT
	attach.add_child(seat)

	var model: Node3D = gun_scene.instantiate()
	model.rotation_degrees = Vector3(0.0, GUN_MODEL_YAW, 0.0)
	model.scale = Vector3.ONE * GUN_HAND_SCALE
	seat.add_child(model)
	_gun = model


func _apply_tint() -> void:
	var color_str := "blue" if team == Protocol.TEAM_BLUE else "red"
	TeamTint.apply_body(_mannequin, color_str)
	TeamTint.apply_gun(_gun, color_str)


## Faster than any pawn can travel under its own power. A gap wider than this
## between two snapshots was not walked, it was teleported.
const MAX_TRAVEL_SPEED := 16.0
const TELEPORT_FLOOR := 1.0


func push_snapshot(data: Dictionary, recv_time: float) -> void:
	var pos := Vector3(
		float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))

	# A respawn moves a body across the level between two snapshots. Interpolating
	# that draws the bot travelling there in a straight line, through every wall
	# on the way — which is what a bot flying through geometry actually is. Drop
	# the history so the next frame starts fresh at the new place instead of
	# easing into it.
	if not _samples.is_empty():
		var prev: Dictionary = _samples[_samples.size() - 1]
		var gap: float = maxf(0.0, recv_time - float(prev["t"]))
		var moved := pos.distance_to(Vector3(prev["x"], prev["y"], prev["z"]))
		if moved > MAX_TRAVEL_SPEED * gap + TELEPORT_FLOOR:
			_samples.clear()

	_samples.append({
		"t": recv_time,
		"x": float(data.get("x", 0.0)),
		"y": float(data.get("y", 0.0)),
		"z": float(data.get("z", 0.0)),
		"yaw": float(data.get("yaw", 0.0)),
		"pitch": float(data.get("pitch", 0.0)),
		"crouched": bool(data.get("crouched", false)),
		"grounded": bool(data.get("grounded", true)),
		"alive": bool(data.get("alive", true)),
		"special_charging": bool(data.get("special_charging", false)),
	})
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()
	_last_time = recv_time


func interpolate(now: float) -> void:
	if _samples.size() < 2:
		if _samples.size() == 1:
			_apply_pose(_samples[0])
		return

	_render_time = now - INTERP_DELAY_MS / 1000.0

	# Render time before the buffer starts is a different situation from render
	# time after it ends, and the old search could not tell them apart: neither
	# case broke out of the loop, so both fell through holding the newest pair.
	# Ahead of the buffer that is right — hold the newest pose. Behind it, it
	# threw the buffer away and jumped the body forward to nearly-live.
	var a: Dictionary = _samples[0]
	var b: Dictionary = _samples[1]
	if _render_time <= float(_samples[0]["t"]):
		_apply_pose(_samples[0])
		return
	for i in range(_samples.size() - 1):
		a = _samples[i]
		b = _samples[i + 1]
		if _render_time >= a["t"] and _render_time <= b["t"]:
			break

	var span: float = b["t"] - a["t"]
	if span < 0.001:
		_apply_pose(b)
		return

	var f := clampf((_render_time - a["t"]) / span, 0.0, 1.0)
	var pose := {
		"x": lerpf(a["x"], b["x"], f),
		"y": lerpf(a["y"], b["y"], f),
		"z": lerpf(a["z"], b["z"], f),
		"yaw": lerp_angle(deg_to_rad(a["yaw"]), deg_to_rad(b["yaw"]), f),
		"pitch": lerpf(a["pitch"], b["pitch"], f),
		"crouched": b["crouched"],
		"grounded": b.get("grounded", true),
		"alive": b["alive"],
		"special_charging": b.get("special_charging", false),
		"vx": (b["x"] - a["x"]) / span,
		"vy": (b["y"] - a["y"]) / span,
		"vz": (b["z"] - a["z"]) / span,
	}
	pose["yaw"] = rad_to_deg(pose["yaw"])
	_apply_pose(pose)


func begin_special() -> void:
	if not _anim_driver:
		return
	var st := _anim_driver.current_state
	if st == AnimDriver.State.DEATH or st == AnimDriver.State.SPELL_FIRE:
		return
	if st == AnimDriver.State.SPELL_CHARGE or st == AnimDriver.State.SPELL_CHANNEL:
		return
	_anim_driver.start_spell_charge()
	_attach_charge_orb()


func fire_special() -> void:
	if not _anim_driver:
		return
	if _anim_driver.current_state == AnimDriver.State.DEATH:
		return
	_anim_driver.fire_spell()
	_clear_charge_orb()


func end_special() -> void:
	if _anim_driver:
		_anim_driver.end_spell()
	_clear_charge_orb()


func trigger_melee() -> void:
	if _anim_driver and _anim_driver.current_state != AnimDriver.State.DEATH:
		_anim_driver.trigger_melee()


func sample_eye() -> Dictionary:
	var eye_h: float = Movement.EYE_CROUCH if _last_eye_crouched else Movement.EYE_STAND
	return {
		"x": _last_eye_x,
		"y": _last_eye_y,
		"z": _last_eye_z,
		"yaw": _last_eye_yaw,
		"pitch": _last_eye_pitch,
		"eye_h": eye_h,
		"alive": alive,
	}


func set_body_visible(vis: bool) -> void:
	if _mannequin:
		_mannequin.visible = vis


func _apply_pose(pose: Dictionary) -> void:
	var pos := Vector3(pose["x"], pose["y"], pose["z"])
	var yaw_val: float = pose["yaw"]

	var now_alive := bool(pose.get("alive", true))
	if not now_alive and alive:
		# Latch the death position before any subsequent snapshot can move it.
		_last_eye_x = pos.x
		_last_eye_y = pos.y
		_last_eye_z = pos.z
		_last_eye_yaw = yaw_val
		_last_eye_pitch = float(pose.get("pitch", 0.0))
		_last_eye_crouched = bool(pose.get("crouched", false))
		if _mannequin:
			_mannequin.global_position = pos
			_mannequin.rotation_degrees.y = yaw_val + BODY_YAW_OFFSET
		_clear_charge_orb()
		_ragdoll_frozen = true
	elif now_alive and not alive:
		end_ragdoll()
		if _anim_driver:
			_anim_driver.reset_locomotion()
		_ragdoll_frozen = false
		_joined_dead = false
		# Both a settled ragdoll and a join-while-dead leave the mannequin
		# hidden, and nothing else turns it back on. Without this a respawned
		# player is invisible for the rest of the match.
		set_body_visible(true)
	alive = now_alive
	visible = true

	# Corpse stays at the death transform; the solver writes bone positions directly.
	if _ragdoll_frozen:
		return

	_last_eye_x = pos.x
	_last_eye_y = pos.y
	_last_eye_z = pos.z
	_last_eye_yaw = yaw_val
	_last_eye_pitch = float(pose.get("pitch", 0.0))
	_last_eye_crouched = bool(pose.get("crouched", false))

	if _mannequin:
		_mannequin.global_position = pos
		_mannequin.rotation_degrees.y = yaw_val + BODY_YAW_OFFSET

	if _movement and _anim_driver and alive:
		_movement.position = pos
		_movement.yaw = yaw_val
		_movement.pitch = pose.get("pitch", 0.0)
		_movement.is_crouching = bool(pose.get("crouched", false))
		_movement.crouch_fraction = 1.0 if _movement.is_crouching else 0.0
		_movement.velocity = Vector3(
			float(pose.get("vx", 0.0)),
			float(pose.get("vy", 0.0)),
			float(pose.get("vz", 0.0)))
		# Reported by whoever owns the pawn, not guessed from vertical speed.
		# Climbing a ramp carries real upward speed, so the old threshold put
		# every body walking up one into the jump pose and left it there.
		_movement.on_ground = bool(pose.get("grounded", true))
		_drive_special(bool(pose.get("special_charging", false)))
		_anim_driver.update_from_movement(_movement)


# Snapshot-driven so a late joiner still sees the wind-up. SpellFire is excluded:
# the discharge packet lands a frame or two before the snapshot that clears
# charging, and without that guard this would put the body back into the raise.
func _drive_special(charging: bool) -> void:
	if not _anim_driver:
		return
	var st := _anim_driver.current_state
	if st == AnimDriver.State.DEATH or st == AnimDriver.State.SPELL_FIRE:
		return
	if charging:
		if st != AnimDriver.State.SPELL_CHARGE and st != AnimDriver.State.SPELL_CHANNEL:
			begin_special()
	elif st == AnimDriver.State.SPELL_CHARGE or st == AnimDriver.State.SPELL_CHANNEL:
		end_special()


func _attach_charge_orb() -> void:
	_clear_charge_orb()
	var color_str := "blue" if team == Protocol.TEAM_BLUE else "red"
	_charge_orb = ChargeOrb.attach(_skeleton, color_str, false)


func _clear_charge_orb() -> void:
	if is_instance_valid(_charge_orb):
		_charge_orb.queue_free()
	_charge_orb = null


func start_ragdoll(dir: Vector3, cause: String, vel: Vector3) -> bool:
	var anim_pl := _find_animation_player(_mannequin) if _mannequin else null
	var rag := RagdollScript.try_build(_skeleton, anim_pl)
	if not rag:
		if _anim_driver:
			_anim_driver.set_state(AnimDriver.State.DEATH)
		return false
	ragdoll = rag
	rag.kick(dir, cause, vel)
	return true


func end_ragdoll() -> void:
	if ragdoll:
		ragdoll.end()
		ragdoll = null


func tick_ragdoll(dt: float, world: CollisionWorld) -> void:
	if ragdoll:
		ragdoll.update(dt, world, world.void_y() if world != null else -INF)
		if ragdoll.dead:
			set_body_visible(false)
			end_ragdoll()


func get_last_velocity() -> Vector3:
	if _samples.size() >= 2:
		var a: Dictionary = _samples[_samples.size() - 2]
		var b: Dictionary = _samples[_samples.size() - 1]
		var span: float = b["t"] - a["t"]
		if span > 0.001:
			return Vector3(
				(b["x"] - a["x"]) / span,
				(b["y"] - a["y"]) / span,
				(b["z"] - a["z"]) / span)
	return Vector3.ZERO


func set_team_value(t: int) -> void:
	team = t
	_apply_tint()


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
