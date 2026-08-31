extends Node3D

const LocalPawn = preload("res://core/local_pawn.gd")
const CameraRig = preload("res://core/camera_rig.gd")

var pawn: LocalPawn
var client: GameClient
var _colliders: Array[AABB] = []
var _map_id: String = "parkour"

# Set before adding to tree by the launcher.
var init_data: Dictionary = {}
var game_client: GameClient


func _ready() -> void:
	AudioMix.fade_out_keep_place(400.0)

	_map_id = str(init_data.get("map", "parkour"))
	client = game_client

	_build_map()
	_setup_pawn()
	_build_hud()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if client:
		add_child(client)
		client.snap_received.connect(_on_snap)
		client.connection_failed.connect(_on_connection_failed)


func _build_map() -> void:
	var map_def: Dictionary
	if _map_id == "parkour":
		map_def = ParkourMap.definition()
	else:
		map_def = ParkourMap.definition()

	var compiled := MapEngine.compile(map_def)
	_colliders = MapBuilder.build_visual(self, compiled)


func _setup_pawn() -> void:
	pawn = LocalPawn.new()
	add_child(pawn)
	pawn.setup(_colliders)

	var sx: float = init_data.get("sx", 0.0)
	var sy: float = init_data.get("sy", 0.0)
	var sz: float = init_data.get("sz", 0.0)
	pawn.movement.position = Vector3(sx, sy, sz)
	pawn.movement.yaw = float(init_data.get("yaw", 180.0))

	pawn.set_team("blue")
	pawn.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	pawn.set_mannequin_visible(false)
	pawn.set_fp_arms_visible(true)


var _hud: Control
var _status_label: Label
var _leave_btn: Button


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	# Crosshair
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 24)
	cross.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0, 0.7))
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(cross)

	# Top-left status
	_status_label = Label.new()
	_status_label.text = "LOBBY · LAN · %s" % _map_id.to_upper()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.9, 0.8))
	_status_label.position = Vector2(20, 16)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_status_label)

	# Bottom hint
	var hint := Label.new()
	hint.text = "WASD move · SPACE jump · C crouch · ESC leave"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6, 0.6))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -30)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(hint)

	# Leave button (top-right, visible when cursor is free)
	_leave_btn = Button.new()
	_leave_btn.text = "LEAVE"
	_leave_btn.custom_minimum_size = Vector2(80, 36)
	_leave_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_leave_btn.position = Vector2(-100, 16)
	_leave_btn.pressed.connect(_request_leave)
	_leave_btn.visible = false
	_hud.add_child(_leave_btn)


func _physics_process(dt: float) -> void:
	if pawn and not ConfirmPrompt.is_open():
		pawn.process_input(dt)
		if client:
			client.send_state(pawn.movement.position, pawn.movement.yaw, pawn.movement.pitch)


func _input(event: InputEvent) -> void:
	if ConfirmPrompt.is_open():
		return
	if event is InputEventMouseMotion and pawn and pawn.camera_rig:
		var motion := event as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			pawn.camera_rig.handle_mouse_motion(motion.relative)


func _unhandled_input(event: InputEvent) -> void:
	if ConfirmPrompt.is_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_leave_btn.visible = false
			return
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_leave_btn.visible = true
		else:
			_request_leave()


func _on_snap(players: Array) -> void:
	# Future: update remote player positions. Single-player lobby for now.
	pass


func _on_connection_failed(reason: String) -> void:
	push_warning("Connection failed: " + reason)
	_on_leave()


func _request_leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_leave_btn.visible = true
	ConfirmPrompt.ask("Leave this lobby?", _on_leave)


func _on_leave() -> void:
	ConfirmPrompt.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if client:
		client.disconnect_from_server()
	var launcher = get_meta("_local_dedicated") if has_meta("_local_dedicated") else null
	if launcher:
		launcher.stop()
	get_tree().change_scene_to_file("res://scenes/menu/menu_shell.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		var launcher = get_meta("_local_dedicated") if has_meta("_local_dedicated") else null
		if launcher:
			launcher.stop()
