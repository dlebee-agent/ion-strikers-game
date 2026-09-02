extends CanvasLayer

const ConsoleLogger = preload("res://core/console_logger.gd")

var _root: Control
var _log: RichTextLabel
var _input_line: LineEdit
var _visible := false
var _saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _logger: ConsoleLogger
var _history: Array[String] = []
var _history_idx: int = -1
const HISTORY_MAX := 50
const LOG_MAX_LINES := 500

var server_password: String = ""
var cheats_enabled: bool = false

const COLOR_INK := Color("#e9edf6")
const COLOR_WARN := Color("#ffe066")
const COLOR_ERR := Color("#f54e5e")
const COLOR_CMD := Color("#4ee2f5")
const COLOR_MUTE := Color("#6d7d9c")
const BG_COLOR := Color(0.02, 0.016, 0.043, 0.92)

var _commands: Dictionary = {}


func _ready() -> void:
	layer = 70
	visible = false

	_logger = ConsoleLogger.new()
	OS.add_logger(_logger)

	_build_ui()
	_register_builtins()


func is_open() -> bool:
	return _visible


func open() -> void:
	if _visible:
		return
	_visible = true
	visible = true
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_match_chat()
	_input_line.grab_focus()


func close() -> void:
	if not _visible:
		return
	_visible = false
	visible = false
	Input.mouse_mode = _saved_mouse_mode


func log_line(text: String, color: Color = COLOR_INK) -> void:
	if _log.get_line_count() > LOG_MAX_LINES:
		_log.remove_paragraph(0)
	_log.push_color(color)
	_log.add_text(text)
	_log.pop()
	_log.newline()


func register_command(cmd_name: String, fn: Callable, description: String = "") -> void:
	_commands[cmd_name] = {"fn": fn, "desc": description}


func clear_session() -> void:
	server_password = ""
	cheats_enabled = false


# ── UI ────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.anchor_bottom = 0.5
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.anchor_bottom = 0.5
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	var header := MarginContainer.new()
	header.add_theme_constant_override("margin_left", 14)
	header.add_theme_constant_override("margin_top", 8)
	header.add_theme_constant_override("margin_bottom", 4)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "CONSOLE"
	title.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", COLOR_MUTE)
	header.add_child(title)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_left", 14)
	scroll_margin.add_theme_constant_override("margin_right", 14)
	vbox.add_child(scroll_margin)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.bbcode_enabled = false
	_log.selection_enabled = true
	_log.add_theme_font_override("normal_font", MenuLook.FONT_MONO_REG)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_color_override("default_color", COLOR_INK)
	var empty := StyleBoxEmpty.new()
	_log.add_theme_stylebox_override("normal", empty)
	_log.add_theme_stylebox_override("focus", empty)
	scroll_margin.add_child(_log)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.914, 0.929, 0.965, 0.1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var input_wrap := MarginContainer.new()
	input_wrap.add_theme_constant_override("margin_left", 10)
	input_wrap.add_theme_constant_override("margin_right", 10)
	input_wrap.add_theme_constant_override("margin_top", 4)
	input_wrap.add_theme_constant_override("margin_bottom", 6)
	vbox.add_child(input_wrap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	input_wrap.add_child(row)

	var prompt := Label.new()
	prompt.text = ">"
	prompt.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", COLOR_CMD)
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(prompt)

	_input_line = LineEdit.new()
	_input_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_line.placeholder_text = ""
	_input_line.max_length = 256
	_input_line.caret_blink = true
	_input_line.add_theme_font_override("font", MenuLook.FONT_MONO_REG)
	_input_line.add_theme_font_size_override("font_size", 13)
	_input_line.add_theme_color_override("font_color", COLOR_INK)
	_input_line.add_theme_color_override("caret_color", COLOR_CMD)
	_input_line.add_theme_color_override("font_placeholder_color", COLOR_MUTE)
	var le_empty := StyleBoxEmpty.new()
	_input_line.add_theme_stylebox_override("normal", le_empty)
	_input_line.add_theme_stylebox_override("focus", le_empty)
	_input_line.add_theme_stylebox_override("read_only", le_empty)
	row.add_child(_input_line)

	_input_line.text_submitted.connect(_on_submit)
	_input_line.gui_input.connect(_on_line_gui)


# ── Input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if ConfirmPrompt.is_open():
		return
	if _is_settings_listening():
		return
	if InputBinds.is_action_just_pressed("console"):
		if _visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return
	if _visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_line_gui(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_UP:
		_history_navigate(-1)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DOWN:
		_history_navigate(1)
		get_viewport().set_input_as_handled()


func _history_navigate(dir: int) -> void:
	if _history.is_empty():
		return
	_history_idx = clampi(_history_idx + dir, 0, _history.size() - 1)
	_input_line.text = _history[_history_idx]
	_input_line.caret_column = _input_line.text.length()


# ── Command execution ─────────────────────────────────────────────────────

func _on_submit(text: String) -> void:
	var trimmed := text.strip_edges()
	_input_line.text = ""
	if trimmed.is_empty():
		return

	log_line("> " + trimmed, COLOR_CMD)

	if not trimmed.begins_with("server_password"):
		_history.append(trimmed)
		if _history.size() > HISTORY_MAX:
			_history.pop_front()
	_history_idx = _history.size()

	var parts := trimmed.split(" ", false)
	var cmd_name := parts[0]
	var args: PackedStringArray = []
	for i in range(1, parts.size()):
		args.append(parts[i])

	if cmd_name in _commands:
		_commands[cmd_name]["fn"].call(args)
	else:
		log_line("unknown command: " + cmd_name, COLOR_ERR)


func _parse_bool(s: String) -> int:
	match s.to_lower():
		"1", "on", "true":
			return 1
		"0", "off", "false":
			return 0
		_:
			return -1


# ── Drain logger ──────────────────────────────────────────────────────────

func _process(_dt: float) -> void:
	if _logger == null:
		return
	var lines := _logger.drain()
	for entry: Dictionary in lines:
		var color := COLOR_INK
		match entry["level"]:
			"warning":
				color = COLOR_WARN
			"error":
				color = COLOR_ERR
		log_line(str(entry["text"]), color)


# ── Built-in commands ─────────────────────────────────────────────────────

func _register_builtins() -> void:
	register_command("clear", _cmd_clear, "Wipe the log view")
	register_command("version", _cmd_version, "Game version + Godot version")
	register_command("server_password", _cmd_server_password, "Set admin password for this session")
	register_command("server_enable_cheats", _cmd_server_enable_cheats, "Toggle cheats on the server")
	register_command("client_show_hitboxes", _cmd_client_show_hitboxes, "Show hitbox debug draw")
	register_command("client_crosshair_size", _cmd_crosshair_size, "Crosshair arm length")
	register_command("client_crosshair_thickness", _cmd_crosshair_thickness, "Crosshair arm width")
	register_command("client_crosshair_spacing", _cmd_crosshair_spacing, "Gap between opposite arms")
	register_command("client_crosshair_color", _cmd_crosshair_color, "Crosshair tint (%s)" % CrosshairSettings.color_names())
	register_command("client_crosshair_alpha", _cmd_crosshair_alpha, "Crosshair opacity 15-100")


func _cmd_clear(_args: PackedStringArray) -> void:
	_log.clear()


func _cmd_version(_args: PackedStringArray) -> void:
	var name_str: String = ProjectSettings.get_setting("application/config/name", "Ion Strikers")
	log_line("%s %s" % [name_str, BuildInfo.version()])
	log_line("Godot %s" % BuildInfo.godot_version(), COLOR_MUTE)
	log_line("protocol %d" % Protocol.PROTOCOL_VERSION, COLOR_MUTE)


func _cmd_server_password(args: PackedStringArray) -> void:
	if args.is_empty():
		log_line("server_password = %s" % ("(set)" if not server_password.is_empty() else "(not set)"))
		return
	server_password = args[0]
	if server_password.is_empty():
		log_line("server_password cleared")
	else:
		log_line("server_password set")


func _cmd_server_enable_cheats(args: PackedStringArray) -> void:
	var client := _find_game_client()
	if client == null:
		log_line("not in a game", COLOR_ERR)
		return
	if args.is_empty():
		log_line("server_enable_cheats = %d" % (1 if cheats_enabled else 0))
		return
	var val := _parse_bool(args[0])
	if val < 0:
		log_line("usage: server_enable_cheats 1|0", COLOR_ERR)
		return
	if server_password.is_empty():
		log_line("server_password is not set", COLOR_ERR)
		return
	client.send_set_cheats(val == 1, server_password)


func _cmd_crosshair_size(args: PackedStringArray) -> void:
	_cvar_float("client_crosshair_size", args,
		CrosshairSettings.SIZE_MIN, CrosshairSettings.SIZE_MAX,
		func(v: float) -> void: CrosshairSettings.set_size(v),
		func() -> float: return CrosshairSettings.size)


func _cmd_crosshair_thickness(args: PackedStringArray) -> void:
	_cvar_float("client_crosshair_thickness", args,
		CrosshairSettings.THICKNESS_MIN, CrosshairSettings.THICKNESS_MAX,
		func(v: float) -> void: CrosshairSettings.set_thickness(v),
		func() -> float: return CrosshairSettings.thickness)


func _cmd_crosshair_spacing(args: PackedStringArray) -> void:
	_cvar_float("client_crosshair_spacing", args,
		CrosshairSettings.GAP_MIN, CrosshairSettings.GAP_MAX,
		func(v: float) -> void: CrosshairSettings.set_gap(v),
		func() -> float: return CrosshairSettings.gap)


func _cmd_crosshair_alpha(args: PackedStringArray) -> void:
	var current := int(round(CrosshairSettings.alpha * 100.0))
	if args.is_empty():
		log_line("client_crosshair_alpha = %d" % current)
		return
	if not args[0].is_valid_float():
		log_line("usage: client_crosshair_alpha 15-100", COLOR_ERR)
		return
	var raw := float(args[0])
	if raw <= 1.0:
		raw *= 100.0
	CrosshairSettings.set_alpha(raw / 100.0)
	log_line("client_crosshair_alpha = %d" % int(round(CrosshairSettings.alpha * 100.0)))


func _cmd_crosshair_color(args: PackedStringArray) -> void:
	if args.is_empty():
		log_line("client_crosshair_color = %s" % CrosshairSettings.color_id)
		return
	var id := args[0].to_lower()
	if not CrosshairSettings.has_color(id):
		log_line("usage: client_crosshair_color %s" % CrosshairSettings.color_names(), COLOR_ERR)
		return
	CrosshairSettings.set_color_id(id)
	log_line("client_crosshair_color = %s" % CrosshairSettings.color_id)


func _cvar_float(cmd_name: String, args: PackedStringArray,
		min_v: float, max_v: float, setter: Callable, getter: Callable) -> void:
	if args.is_empty():
		log_line("%s = %d" % [cmd_name, int(getter.call())])
		return
	if not args[0].is_valid_float():
		log_line("usage: %s %d-%d" % [cmd_name, int(min_v), int(max_v)], COLOR_ERR)
		return
	setter.call(float(args[0]))
	log_line("%s = %d" % [cmd_name, int(getter.call())])


func _cmd_client_show_hitboxes(args: PackedStringArray) -> void:
	if args.is_empty():
		var current: bool = _get_hitbox_debug_active()
		log_line("client_show_hitboxes = %d" % (1 if current else 0))
		return
	var val := _parse_bool(args[0])
	if val < 0:
		log_line("usage: client_show_hitboxes 1|0", COLOR_ERR)
		return
	if val == 1 and not cheats_enabled:
		log_line("cheats are not enabled on the server", COLOR_ERR)
		return
	_set_hitbox_debug_active(val == 1)
	log_line("client_show_hitboxes = %d" % val)


func _find_game_client() -> GameClient:
	var nodes := get_tree().get_nodes_in_group("game_clients")
	if not nodes.is_empty():
		return nodes[0] as GameClient
	for node in get_tree().root.get_children():
		var client := _find_client_recursive(node)
		if client:
			return client
	return null


func _find_client_recursive(node: Node) -> GameClient:
	if node is GameClient:
		return node as GameClient
	for child in node.get_children():
		var result := _find_client_recursive(child)
		if result:
			return result
	return null


func _get_hitbox_debug_active() -> bool:
	var nodes := get_tree().get_nodes_in_group("hitbox_debug")
	if nodes.is_empty():
		return false
	return nodes[0].get("active") == true


func _set_hitbox_debug_active(on: bool) -> void:
	for node in get_tree().get_nodes_in_group("hitbox_debug"):
		node.active = on


func on_cheats_changed(enabled: bool) -> void:
	cheats_enabled = enabled
	if not enabled:
		var was_on := _get_hitbox_debug_active()
		_set_hitbox_debug_active(false)
		if was_on:
			log_line("client_show_hitboxes 0 (cheats disabled)", COLOR_WARN)


func _is_settings_listening() -> bool:
	for node in get_tree().get_nodes_in_group("settings_screens"):
		if node.has_method("is_listening") and node.is_listening():
			return true
	return false


func _close_match_chat() -> void:
	for node in get_tree().get_nodes_in_group("match_huds"):
		if node.has_method("close_chat") and node.has_method("is_chat_open"):
			if node.is_chat_open():
				node.close_chat()
