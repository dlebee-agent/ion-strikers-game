class_name SuitPreview
extends Control

## Two mannequins in the chosen finish, one per team, so the skins page can
## show how the suit reads as friend and foe without opening the designer.

const PREVIEW_H := 400
const SLOTS := [["blue", -0.62], ["red", 0.62]]
const GUN_MODEL_PATH := "res://assets/guns/pistol_2.gltf"
const GUN_HAND_POS := Vector3(-0.001, 0.078, 0.028)
const GUN_HAND_ROT := Vector3(79.36, -2.68, -1.25)
const GUN_HAND_SCALE := 0.32
const GUN_MODEL_YAW := 90.0
const HAND_BONE_NAMES := ["hand_r", "Hand_R", "mixamorig:RightHand"]
const LOOK_AT := Vector3(0.0, 0.95, 0.0)
const CAM_DIST := 3.45
const SPIN_DEG := 18.0
const DRAG_SENS := 0.4

var _vp: SubViewport
var _cam: Camera3D
var _mannequins: Array[Node3D] = []
var _style: String = SuitStyle.DEFAULT
var _spin := 0.0
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(0, PREVIEW_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE

	var frame := PanelContainer.new()
	MenuLook.fill(frame)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.016, 0.02, 0.035, 1.0)
	bg.border_color = MenuLook.LINE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", bg)
	add_child(frame)

	var host := SubViewportContainer.new()
	MenuLook.fill(host)
	host.stretch = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(host)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.audio_listener_enable_3d = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(720, PREVIEW_H)
	host.add_child(_vp)


func _ready() -> void:
	_build_world()
	set_style(_style)
	set_process(false)


func set_style(style: String) -> void:
	_style = SuitStyle.normalize(style)
	for i in _mannequins.size():
		TeamTint.apply_body(_mannequins[i], str(SLOTS[i][0]), _style)


func set_active(on: bool) -> void:
	if not on:
		_dragging = false
	set_process(on)
	if _vp:
		_vp.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mb.pressed
		accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false
	elif event is InputEventMouseMotion:
		_spin = fposmod(_spin - (event as InputEventMouseMotion).relative.x * DRAG_SENS, 360.0)
		_apply_spin()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if _dragging:
		return
	_spin = fposmod(_spin + dt * SPIN_DEG, 360.0)
	_apply_spin()


func _apply_spin() -> void:
	for i in _mannequins.size():
		var base := 12.0 if str(SLOTS[i][0]) == "blue" else -12.0
		_mannequins[i].rotation_degrees.y = base + _spin


func _apply_camera() -> void:
	if _cam == null:
		return
	var pitch_rad := deg_to_rad(5.0)
	var offset := Vector3(
		0.0,
		sin(pitch_rad) * CAM_DIST,
		cos(pitch_rad) * CAM_DIST)
	_cam.position = LOOK_AT + offset
	_cam.look_at(LOOK_AT)


func _build_world() -> void:
	var world := Node3D.new()
	_vp.add_child(world)

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
	world.add_child(world_env)

	_cam = Camera3D.new()
	_cam.fov = 32.0
	world.add_child(_cam)
	_cam.current = true
	_apply_camera()

	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.97, 0.95)
	key.light_energy = 2.15
	key.spot_range = 18.0
	key.spot_angle = 48.0
	key.shadow_enabled = true
	key.position = Vector3(0.35, 6.4, 5.2)
	world.add_child(key)
	key.look_at(Vector3(0.0, 1.0, 0.0))

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.78, 0.92)
	fill.light_energy = 0.22
	fill.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	world.add_child(fill)

	var scene := load("res://assets/characters/mannequin.glb")
	if not scene:
		return
	for slot in SLOTS:
		var team: String = slot[0]
		var body: Node3D = scene.instantiate()
		body.scale = Vector3(0.98, 0.98, 0.98)
		body.position = Vector3(slot[1], 0.0, 0.0)
		body.rotation_degrees.y = 12.0 if team == "blue" else -12.0
		world.add_child(body)
		var player := _find_animation_player(body)
		if player and player.has_animation("Pistol_Idle"):
			player.play("Pistol_Idle")
			player.seek(0.6, true)
		var gun := _attach_gun(body)
		if gun:
			TeamTint.apply_gun(gun, team)
		_add_rim(world, body.position, team)
		_mannequins.append(body)
	_apply_spin()


func _add_rim(world: Node3D, at: Vector3, team: String) -> void:
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.96, 0.25, 0.37) if team == "red" else Color(0.31, 0.89, 0.96)
	rim.light_energy = 1.55
	rim.omni_range = 7.5
	rim.position = at + Vector3(0.0, 1.65, -1.35)
	world.add_child(rim)


func _attach_gun(model: Node3D) -> Node3D:
	var skel := _find_skeleton(model)
	if skel == null:
		return null
	var bone_name := ""
	for candidate: String in HAND_BONE_NAMES:
		if skel.find_bone(candidate) != -1:
			bone_name = candidate
			break
	if bone_name.is_empty():
		return null
	var gun_scene := load(GUN_MODEL_PATH)
	if gun_scene == null:
		return null
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	skel.add_child(attach)
	var seat := Node3D.new()
	seat.rotation_order = EULER_ORDER_ZYX
	seat.position = GUN_HAND_POS
	seat.rotation_degrees = GUN_HAND_ROT
	attach.add_child(seat)
	var gun: Node3D = gun_scene.instantiate()
	gun.rotation_degrees = Vector3(0.0, GUN_MODEL_YAW, 0.0)
	gun.scale = Vector3.ONE * GUN_HAND_SCALE
	seat.add_child(gun)
	return gun


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
