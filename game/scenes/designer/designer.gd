extends Node3D

const LocalPawn = preload("res://core/local_pawn.gd")
const CameraRig = preload("res://core/camera_rig.gd")
const AnimDriver = preload("res://core/anim_driver.gd")
const HitboxDebugScript = preload("res://core/hitbox_debug.gd")
const SuitSettings = preload("res://core/suit_settings.gd")

# Long enough to cover the discharge clip plus its blend out.
const SPECIAL_DISCHARGE_HOLD := 0.55

func _fp_hint() -> String:
	return "WASD move · SHIFT walk · %s crouch · %s jump · click view to look · ESC frees cursor · %s controls" % [
		InputBinds.primary("crouch").to_upper(),
		InputBinds.primary("jump").to_upper(),
		InputBinds.primary("controls").to_upper(),
	]
const HINT_TP := "mouse orbits · WASD moves relative to camera (walk toward it to see the front) · scroll or +/− zooms · ESC frees cursor"
const HINT_PREVIEW := "drag to orbit · scroll or +/− to zoom · ◀ ▶ steps clips · ESC to leave"


@onready var hud: Control = %DesignerHUD
@onready var crosshair: Control = %Crosshair
@onready var hp_label: Label = %HPLabel
@onready var gun_label: Label = %GunLabel
@onready var dev_label: Label = %DevLabel
@onready var special_bar: ProgressBar = %SpecialBar
@onready var hint_label: Label = %HintLabel
@onready var controls_panel: PanelContainer = %ControlsPanel
@onready var controls_list: VBoxContainer = %ControlsList

@onready var toolbar: HBoxContainer = %Toolbar
@onready var back_btn: Button = %BackBtn
@onready var mode_fp: Button = %ModeFP
@onready var mode_tp: Button = %ModeTP
@onready var mode_preview: Button = %ModePreview
@onready var team_blue: Button = %TeamBlue
@onready var team_red: Button = %TeamRed
@onready var suit_select: OptionButton = %SuitSelect
@onready var special_btn: Button = %SpecialBtn
@onready var clip_prev_btn: Button = %ClipPrev
@onready var clip_next_btn: Button = %ClipNext
@onready var clip_select: OptionButton = %ClipSelect
@onready var clip_row: HBoxContainer = %ClipRow

var pawn: LocalPawn
var _world: CollisionWorld = null
var _controls_visible := false
var _current_clip_index := -1
var _clip_names: PackedStringArray = []
var _team := "blue"

func _ready() -> void:
	add_to_group("match_scene")
	AudioMix.fade_out_keep_place(400.0)
	_build_arena()
	_setup_pawn()
	_setup_toolbar()
	_setup_hud()
	_populate_clips()
	_set_team("blue")
	_set_mode(CameraRig.Mode.FIRST_PERSON)

	var _hitbox_debug := HitboxDebugScript.new()
	add_child(_hitbox_debug)

func _build_arena() -> void:
	_world = CollisionWorld.new()

	# No default sky: otherwise the mannequin picks up chrome reflections.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	$WorldEnv.environment = env

	var arena_size := 21.0
	var wall_height := 4.5
	var wall_thick := 0.5

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(arena_size * 2, arena_size * 2)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.04, 0.043, 0.06)
	floor_mat.metallic = 0.2
	floor_mat.roughness = 0.75
	plane.material = floor_mat
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3.ZERO
	add_child(floor_mesh)

	_add_solid(AABB(Vector3(-arena_size, -2.0, -arena_size), Vector3(arena_size * 2, 2.0, arena_size * 2)))

	var walls := [
		[Vector3(0, wall_height / 2.0, -arena_size), Vector3(arena_size * 2, wall_height, wall_thick)],
		[Vector3(0, wall_height / 2.0, arena_size), Vector3(arena_size * 2, wall_height, wall_thick)],
		[Vector3(-arena_size, wall_height / 2.0, 0), Vector3(wall_thick, wall_height, arena_size * 2)],
		[Vector3(arena_size, wall_height / 2.0, 0), Vector3(wall_thick, wall_height, arena_size * 2)],
	]
	for wall_data: Array in walls:
		var pos: Vector3 = wall_data[0]
		var sz: Vector3 = wall_data[1]
		_add_box(pos, sz, Color(0.12, 0.13, 0.18))
		_add_solid(AABB(pos - sz * 0.5, sz))

	var crate_color := Color(0.15, 0.12, 0.2)
	_add_box(Vector3(4, 0.75, -3), Vector3(1.5, 1.5, 1.5), crate_color)
	_add_solid(AABB(Vector3(3.25, 0, -3.75), Vector3(1.5, 1.5, 1.5)))
	_add_box(Vector3(-5, 1.0, 5), Vector3(2.0, 2.0, 1.0), crate_color)
	_add_solid(AABB(Vector3(-6.0, 0, 4.5), Vector3(2.0, 2.0, 1.0)))

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	key.light_energy = 0.8
	key.light_color = Color(1.0, 0.98, 0.95)
	key.shadow_enabled = true
	add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-4, 5, -4)
	fill.light_energy = 0.4
	fill.light_color = Color(0.35, 0.5, 0.85)
	fill.omni_range = 30.0
	add_child(fill)

	_draw_grid(arena_size)
	_world.build()

func _add_solid(box: AABB) -> void:
	var index := _world.add_box(box)
	if Hitbox.special_blocks(box):
		_world.tag_brush(index, CollisionWorld.CONTENT_SPECIAL)

func _add_box(pos: Vector3, sz: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	box.material = mat
	mi.mesh = box
	mi.position = pos
	add_child(mi)

func _draw_grid(arena_size: float) -> void:
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(0.15, 0.18, 0.25, 0.4)
	grid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var step := 2.0
	var x := -arena_size
	while x <= arena_size:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.002, arena_size * 2)
		bm.material = grid_mat
		mi.mesh = bm
		mi.position = Vector3(x, 0.001, 0)
		add_child(mi)
		x += step
	var z := -arena_size
	while z <= arena_size:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(arena_size * 2, 0.002, 0.02)
		bm.material = grid_mat
		mi.mesh = bm
		mi.position = Vector3(0, 0.001, z)
		add_child(mi)
		z += step

func _setup_pawn() -> void:
	pawn = LocalPawn.new()
	pawn.suit_style = SuitSettings.style
	add_child(pawn)
	pawn.setup(_world)
	pawn.movement.position = Vector3(0, 0.1, 0)
	pawn.weapon.special_armed = true

func _setup_toolbar() -> void:
	back_btn.pressed.connect(_on_back)
	mode_fp.pressed.connect(func() -> void: _set_mode(CameraRig.Mode.FIRST_PERSON))
	mode_tp.pressed.connect(func() -> void: _set_mode(CameraRig.Mode.THIRD_PERSON))
	mode_preview.pressed.connect(func() -> void: _set_mode(CameraRig.Mode.PREVIEW))
	team_blue.pressed.connect(func() -> void: _set_team("blue"))
	team_red.pressed.connect(func() -> void: _set_team("red"))
	special_btn.button_down.connect(func() -> void: pawn.weapon.start_special())
	special_btn.button_up.connect(func() -> void: pawn.weapon.do_special_fire())
	pawn.weapon.special_fired.connect(_on_special_discharged)
	clip_prev_btn.pressed.connect(_clip_prev)
	clip_next_btn.pressed.connect(_clip_next)
	clip_select.item_selected.connect(_on_clip_selected)
	# Same preference as Settings, so a finish can be checked in each pose
	# and camera without hosting a game for it.
	suit_select.clear()
	for i in SuitStyle.STYLES.size():
		suit_select.add_item(SuitStyle.label_for(SuitStyle.STYLES[i]))
		suit_select.set_item_metadata(i, SuitStyle.STYLES[i])
	suit_select.select(SuitStyle.index_of(pawn.suit_style))
	suit_select.item_selected.connect(_on_suit_selected)

func _setup_hud() -> void:
	hp_label.text = "100"
	gun_label.text = "LASER RIFLE"
	dev_label.text = "DEV · DESIGNER"
	special_bar.value = 0
	controls_panel.visible = false

func _populate_clips() -> void:
	clip_select.clear()
	clip_select.add_item("— select clip —")
	if pawn and pawn.anim_driver:
		_clip_names = pawn.anim_driver.get_clip_list()
		for clip_name in _clip_names:
			clip_select.add_item(clip_name)

func _set_mode(mode: CameraRig.Mode) -> void:
	if not pawn or not pawn.camera_rig:
		return
	pawn.camera_rig.set_mode(mode)

	mode_fp.disabled = (mode == CameraRig.Mode.FIRST_PERSON)
	mode_tp.disabled = (mode == CameraRig.Mode.THIRD_PERSON)
	mode_preview.disabled = (mode == CameraRig.Mode.PREVIEW)

	if pawn:
		var is_fp := (mode == CameraRig.Mode.FIRST_PERSON)
		pawn.set_mannequin_visible(not is_fp)
		pawn.set_fp_arms_visible(is_fp)

	clip_row.visible = (mode == CameraRig.Mode.PREVIEW)
	hud.visible = (mode != CameraRig.Mode.PREVIEW)

	# Each mode drives the mouse differently, and nothing on screen would otherwise
	# say that the way to see the far side of a model is to come round to it.
	if mode == CameraRig.Mode.PREVIEW:
		hint_label.text = HINT_PREVIEW
	elif mode == CameraRig.Mode.THIRD_PERSON:
		hint_label.text = HINT_TP
	else:
		hint_label.text = _fp_hint()

# Preview skips the locomotion state machine entirely, so the discharge would
# hold its last frame forever. Put the body back once the clip has run.
func _on_special_discharged() -> void:
	pawn.weapon.special_armed = true
	if pawn.camera_rig.mode != CameraRig.Mode.PREVIEW:
		return
	await get_tree().create_timer(SPECIAL_DISCHARGE_HOLD).timeout
	if pawn.camera_rig.mode != CameraRig.Mode.PREVIEW:
		return
	if _current_clip_index >= 0:
		pawn.anim_driver.play_clip(_clip_names[_current_clip_index])
	else:
		pawn.anim_driver.set_state(AnimDriver.State.IDLE)

func _set_team(color: String) -> void:
	_team = color
	pawn.set_team(color)
	team_blue.disabled = (color == "blue")
	team_red.disabled = (color == "red")

func _on_suit_selected(index: int) -> void:
	var id := str(suit_select.get_item_metadata(index))
	SuitSettings.set_style(id)
	pawn.suit_style = id
	# set_team repaints the body and arms with the new finish.
	pawn.set_team(_team)

func _on_back() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu/menu_shell.tscn")

func _clip_prev() -> void:
	if _clip_names.is_empty():
		return
	_current_clip_index = max(0, _current_clip_index - 1)
	clip_select.select(_current_clip_index + 1)
	pawn.anim_driver.play_clip(_clip_names[_current_clip_index])

func _clip_next() -> void:
	if _clip_names.is_empty():
		return
	_current_clip_index = min(_clip_names.size() - 1, _current_clip_index + 1)
	clip_select.select(_current_clip_index + 1)
	pawn.anim_driver.play_clip(_clip_names[_current_clip_index])

func _on_clip_selected(index: int) -> void:
	if index <= 0:
		_current_clip_index = -1
		return
	_current_clip_index = index - 1
	pawn.anim_driver.play_clip(_clip_names[_current_clip_index])

func _physics_process(dt: float) -> void:
	pawn.process_input(dt)
	special_bar.value = pawn.weapon.get_special_charge_fraction() * 100.0

# Looking around is read here rather than in _unhandled_input: the toolbar spans
# the top of the screen and would otherwise swallow motion events before they
# ever reach unhandled input.
func _input(event: InputEvent) -> void:
	if GameConsole.is_open():
		return
	if not (event is InputEventMouseMotion) or not pawn or not pawn.camera_rig:
		return
	var motion := event as InputEventMouseMotion
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pawn.camera_rig.handle_mouse_motion(motion.relative)
	elif pawn.camera_rig.mode == CameraRig.Mode.PREVIEW \
			and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		# Preview keeps the cursor free, so orbiting the model is a drag.
		pawn.camera_rig.handle_mouse_motion(motion.relative)

func _unhandled_input(event: InputEvent) -> void:
	if GameConsole.is_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Getting here means no HUD control took the click, so it landed in the
		# 3D view: take the cursor back for looking around.
		if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and pawn and pawn.camera_rig \
				and pawn.camera_rig.mode != CameraRig.Mode.PREVIEW:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if pawn and pawn.camera_rig:
				pawn.camera_rig.handle_scroll(mb.factor if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -mb.factor)

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and pawn and pawn.camera_rig:
			var orbiting := pawn.camera_rig.mode == CameraRig.Mode.PREVIEW \
				or pawn.camera_rig.mode == CameraRig.Mode.THIRD_PERSON
			if orbiting:
				if key.keycode == KEY_EQUAL or key.keycode == KEY_PLUS or key.keycode == KEY_KP_ADD:
					pawn.camera_rig.handle_zoom_key(true)
					get_viewport().set_input_as_handled()
				elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
					pawn.camera_rig.handle_zoom_key(false)
					get_viewport().set_input_as_handled()

	if event.is_action_pressed("game_controls"):
		_controls_visible = not _controls_visible
		controls_panel.visible = _controls_visible
		if _controls_visible:
			_populate_controls_list()
		if _controls_visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("ui_cancel"):
		if _controls_visible:
			_controls_visible = false
			controls_panel.visible = false
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# Free the cursor so the toolbar is clickable; click the view to look again.
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_on_back()

func _populate_controls_list() -> void:
	for child in controls_list.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.306, 0.886, 0.961, 1))
	controls_list.add_child(title)

	var close_hint := Label.new()
	close_hint.text = "%s or ESC to close" % InputBinds.fmt("controls")
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", Color(0.604, 0.651, 0.761, 0.6))
	controls_list.add_child(close_hint)

	for group_data: Array in InputBinds.BIND_GROUPS:
		var actions: Array = group_data[1]
		for action_name: String in actions:
			var row := HBoxContainer.new()
			var l := Label.new()
			l.text = InputBinds.BIND_LABELS.get(action_name, action_name)
			l.custom_minimum_size.x = 160
			l.add_theme_font_size_override("font_size", 13)
			row.add_child(l)
			var keys: Array = InputBinds.bindings[action_name]
			var v := Label.new()
			var parts: Array[String] = []
			for k in keys:
				if not (k as String).is_empty():
					parts.append(k)
			v.text = " / ".join(parts) if parts.size() > 0 else "—"
			v.add_theme_font_size_override("font_size", 13)
			row.add_child(v)
			controls_list.add_child(row)
