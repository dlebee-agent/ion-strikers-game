class_name TeamPanel
extends CanvasLayer

## Match overlay for picking BLUE / RED / WATCH. Counts come from the
## server's teamOpts so the bars cannot drift from what setTeam will accept.

signal team_selected(team: int)
signal closed

const BLUE := Color("#4ea8f5")
const RED := Color("#f54e5e")
const WATCH := Color("#c6cee2")
const CARD_W := 268.0
const CARD_H := 168.0
const BAR_CAP := 12

var _root: Control
var _counts: Label
var _blue: PickCard
var _red: PickCard
var _spec: PickCard
var _deny: Label
var _deny_wrap: Control
var _foot_left: Label
var _foot_right: Label
var _auto: Button
var _is_open := false

# Latest counts from the server's teamOpts, so AUTO picks against the same
# numbers setTeam will be validated against.
var _blue_used := 0
var _red_used := 0
var _opts_seen := false


func _init() -> void:
	layer = 12


func _ready() -> void:
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	MenuLook.fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	MenuLook.fill(dim)
	dim.color = Color(0.02, 0.016, 0.039, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var centre := CenterContainer.new()
	MenuLook.fill(centre)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_STOP
	centre.add_child(col)

	var title := MenuLook.heading("CHOOSE A TEAM", 36, MenuLook.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_counts = MenuLook.kicker("", Color(MenuLook.CY, 0.78), 10)
	_counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var counts_m := MarginContainer.new()
	counts_m.add_theme_constant_override("margin_top", 8)
	counts_m.add_theme_constant_override("margin_bottom", 22)
	counts_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counts_m.add_child(_counts)
	col.add_child(counts_m)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)

	_blue = PickCard.new(Protocol.TEAM_BLUE, "BLUE", BLUE, 1)
	_blue.pressed.connect(func() -> void: _try_pick(Protocol.TEAM_BLUE))
	cards.add_child(_blue)

	_red = PickCard.new(Protocol.TEAM_RED, "RED", RED, 2)
	_red.pressed.connect(func() -> void: _try_pick(Protocol.TEAM_RED))
	cards.add_child(_red)

	_spec = PickCard.new(Protocol.TEAM_NONE, "WATCH", WATCH, 3)
	_spec.pressed.connect(func() -> void: _try_pick(Protocol.TEAM_NONE))
	cards.add_child(_spec)

	_auto = Button.new()
	_auto.focus_mode = Control.FOCUS_NONE
	_auto.custom_minimum_size = Vector2(CARD_W * 3 + 32, 40)
	_auto.text = MenuLook.tracked("[4]  AUTO \u00b7 JOIN THE LIGHTER SIDE")
	MenuLook.apply_ghost(_auto, 12)
	_auto.disabled = true
	_auto.pressed.connect(_pick_auto)
	var auto_m := MarginContainer.new()
	auto_m.add_theme_constant_override("margin_top", 12)
	auto_m.add_child(_auto)
	col.add_child(auto_m)

	_deny = MenuLook.kicker("", MenuLook.RD, 10)
	_deny.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var deny_m := MarginContainer.new()
	deny_m.add_theme_constant_override("margin_top", 16)
	deny_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deny_m.add_child(_deny)
	deny_m.visible = false
	col.add_child(deny_m)
	_deny_wrap = deny_m

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = MenuLook.LINE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_m := MarginContainer.new()
	rule_m.add_theme_constant_override("margin_top", 18)
	rule_m.add_theme_constant_override("margin_bottom", 12)
	rule_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_m.add_child(rule)
	col.add_child(rule_m)

	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	_foot_left = MenuLook.kicker("SWITCHING MID-ROUND COSTS YOU A LIFE", MenuLook.MUTE_3, 10)
	_foot_left.text = MenuLook.tracked("SWITCHING MID-ROUND COSTS YOU A LIFE")
	_foot_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_foot_left)
	_foot_right = MenuLook.kicker(_close_hint(), MenuLook.MUTE_3, 10)
	_foot_right.text = MenuLook.tracked(_close_hint())
	_foot_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(_foot_right)


func open() -> void:
	_is_open = true
	_root.visible = true
	_clear_deny()
	_foot_right.text = MenuLook.tracked(_close_hint())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	closed.emit()


func is_open() -> bool:
	return _is_open


func update_opts(current_team: int, blue_used: int, blue_max: int,
		red_used: int, red_max: int, spec_used: int, spec_max: int) -> void:
	_counts.text = MenuLook.tracked("BLUE %d" % blue_used) \
		+ "   ·   " + MenuLook.tracked("RED %d" % red_used) \
		+ "   ·   " + MenuLook.tracked("SPECTATORS %d/%d" % [spec_used, spec_max])
	_blue.set_state(current_team == Protocol.TEAM_BLUE, blue_used, blue_max)
	_red.set_state(current_team == Protocol.TEAM_RED, red_used, red_max)
	_spec.set_state(current_team == Protocol.TEAM_NONE, spec_used, spec_max)
	_blue_used = blue_used
	_red_used = red_used
	_opts_seen = true
	# AUTO stays dead until the first teamOpts lands, or its "lighter side"
	# would be a coin flip against counts of 0 and 0.
	_auto.disabled = false
	_clear_deny()


func show_denied(reason: String) -> void:
	_deny.text = MenuLook.tracked(reason.to_upper())
	_deny_wrap.visible = true


func _clear_deny() -> void:
	_deny.text = ""
	_deny_wrap.visible = false


func _try_pick(team: int) -> void:
	var card := _card_for(team)
	if card == null or card.is_current:
		return
	if card.is_full:
		show_denied("Team is full." if team != Protocol.TEAM_NONE else "Stands are full.")
		return
	team_selected.emit(team)


# Fewer humans wins; a tie is a coin flip. The server counts humans only, so
# bots never make a side look heavy, and picking the lighter side can never trip
# its "teams would be unbalanced" check.
func _pick_auto() -> void:
	if not _opts_seen:
		return
	var first := Protocol.TEAM_BLUE
	var second := Protocol.TEAM_RED
	if _red_used < _blue_used or (_red_used == _blue_used and randi() % 2 == 1):
		first = Protocol.TEAM_RED
		second = Protocol.TEAM_BLUE

	for team in [first, second]:
		var card := _card_for(team)
		if card.is_current:
			close()
			return
		if not card.is_full:
			team_selected.emit(team)
			return
	show_denied("Both teams are full.")


func _card_for(team: int) -> PickCard:
	match team:
		Protocol.TEAM_BLUE:
			return _blue
		Protocol.TEAM_RED:
			return _red
		_:
			return _spec


func _close_hint() -> String:
	var key := "M"
	if InputBinds and InputBinds.bindings.has("team_menu"):
		var slots: Array = InputBinds.bindings["team_menu"]
		if slots.size() > 0 and str(slots[0]) != "":
			key = str(slots[0])
	return "%s OR ESC TO CLOSE" % key.to_upper()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_team_menu"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.physical_keycode:
			KEY_1, KEY_KP_1:
				_try_pick(Protocol.TEAM_BLUE)
				get_viewport().set_input_as_handled()
			KEY_2, KEY_KP_2:
				_try_pick(Protocol.TEAM_RED)
				get_viewport().set_input_as_handled()
			KEY_3, KEY_KP_3:
				_try_pick(Protocol.TEAM_NONE)
				get_viewport().set_input_as_handled()
			KEY_4, KEY_KP_4:
				_pick_auto()
				get_viewport().set_input_as_handled()


class PickCard:
	extends Button

	var team: int
	var is_current := false
	var is_full := false

	var _accent: Color
	var _title: Label
	var _action: Label
	var _slots: Label
	var _bar: HBoxContainer
	var _hovered := false

	func _init(p_team: int, p_name: String, p_accent: Color, key_n: int) -> void:
		team = p_team
		_accent = p_accent
		custom_minimum_size = Vector2(TeamPanel.CARD_W, TeamPanel.CARD_H)
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_theme_color_override("font_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0))

		var body := HBoxContainer.new()
		MenuLook.fill(body)
		body.add_theme_constant_override("separation", 0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)

		var strip := Panel.new()
		strip.custom_minimum_size.x = 4
		strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var strip_s := StyleBoxFlat.new()
		strip_s.bg_color = p_accent
		strip_s.corner_radius_top_left = 6
		strip_s.corner_radius_bottom_left = 6
		strip.add_theme_stylebox_override("panel", strip_s)
		body.add_child(strip)

		var pad := MarginContainer.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override("margin_left", 16)
		pad.add_theme_constant_override("margin_right", 16)
		pad.add_theme_constant_override("margin_top", 16)
		pad.add_theme_constant_override("margin_bottom", 14)
		body.add_child(pad)

		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(v)

		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(head)
		_title = MenuLook.heading(p_name, 28, p_accent)
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_title)
		_action = MenuLook.kicker("JOIN", MenuLook.MUTE_2, 10)
		_action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(_action)

		_slots = MenuLook.mono("0 / 0 slots", 11, MenuLook.MUTE_2)
		v.add_child(_slots)

		_bar = HBoxContainer.new()
		_bar.add_theme_constant_override("separation", 4)
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.custom_minimum_size.y = 6
		v.add_child(_bar)

		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(spacer)

		var hint := MenuLook.kicker("PRESS %d" % key_n, MenuLook.MUTE_3, 10)
		hint.text = MenuLook.tracked("PRESS %d" % key_n)
		v.add_child(hint)

		mouse_entered.connect(func() -> void:
			_hovered = true
			_restyle()
		)
		mouse_exited.connect(func() -> void:
			_hovered = false
			_restyle()
		)
		_restyle()

	func set_state(current: bool, used: int, max_n: int) -> void:
		is_current = current
		is_full = (not current) and max_n > 0 and used >= max_n
		disabled = is_full
		mouse_default_cursor_shape = Control.CURSOR_ARROW if is_full else Control.CURSOR_POINTING_HAND
		modulate = Color(0.55, 0.55, 0.58) if is_full else Color.WHITE
		_action.text = MenuLook.tracked("CURRENT" if current else "JOIN")
		_action.add_theme_color_override("font_color", MenuLook.INK if current else MenuLook.MUTE_2)
		_slots.text = "%d / %d slots" % [used, max_n]
		_rebuild_bar(used, max_n)
		_restyle()

	func _rebuild_bar(used: int, max_n: int) -> void:
		for c in _bar.get_children():
			_bar.remove_child(c)
			c.free()
		var n := mini(max_n, TeamPanel.BAR_CAP)
		_bar.visible = n > 0
		for i in n:
			var pip := Panel.new()
			pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pip.custom_minimum_size = Vector2(0, 6)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var s := StyleBoxFlat.new()
			s.set_corner_radius_all(1)
			if i < used:
				s.bg_color = _accent
			else:
				s.bg_color = Color(1, 1, 1, 0.08)
			pip.add_theme_stylebox_override("panel", s)
			_bar.add_child(pip)

	func _restyle() -> void:
		var bg := Color(0.039, 0.047, 0.078, 0.94).lerp(Color(_accent, 1.0), 0.10)
		bg.a = 0.94
		var border := Color(_accent, 0.28)
		var glow := Color(_accent, 0.10)
		if is_current:
			border = Color(_accent, 0.7)
			glow = Color(_accent, 0.20)
		elif _hovered and not is_full:
			border = Color(_accent, 0.85)
			glow = Color(_accent, 0.24)
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.set_corner_radius_all(6)
		s.set_content_margin_all(0)
		s.shadow_color = glow
		s.shadow_size = 16
		add_theme_stylebox_override("normal", s)
		add_theme_stylebox_override("hover", s)
		add_theme_stylebox_override("pressed", s)
		add_theme_stylebox_override("focus", s)
		add_theme_stylebox_override("disabled", s)
