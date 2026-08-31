class_name ControlsCard
extends Control

## In-match overlay listing every bind. Rows are built from InputBinds so the
## card cannot drift from what the keys actually do.

const CARD_W := 980.0
const COL_SEP := 40.0
const ROW_SEP := 6.0

const SHEET_BG := Color(0.016, 0.023, 0.043, 0.97)
const ROW_BG := Color("#0d1420")
const CHIP_BG := Color("#161e2e")
const CHIP_LINE := Color(0.62, 0.71, 0.87, 0.28)
const CHIP_INK := Color("#dfe6f5")
const DESC_INK := Color("#c6cee2")

## Mouse buttons read as their real-world name on the card; "MOUSE2" tells a
## player nothing about which finger to use.
const KEY_DISPLAY := {
	"Mouse1": "LEFT CLICK",
	"Mouse2": "RIGHT CLICK",
	"Mouse3": "MIDDLE CLICK",
	"WheelUp": "WHEEL UP",
	"WheelDown": "WHEEL DOWN",
}

## Card wording, kept apart from BIND_LABELS: the settings list names an action
## in as few words as possible, this one explains how it plays.
const DESCRIPTIONS := {
	"jump": "Jump",
	"crouch": "Crouch",
	"walk": "Walk — quiet, slower",
	"fire": "Fire laser",
	"melee": "Melee",
	"special": "Special — hold to charge, 5 frags",
	"chat_all": "Chat — all players",
	"chat_team": "Chat — your team only",
	"scoreboard": "Scoreboard — hold",
	"team_menu": "Team menu — costs a life",
	"controls": "This controls card",
}

var _left_col: VBoxContainer
var _right_col: VBoxContainer
var _close: Label
var _is_open := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func is_open() -> bool:
	return _is_open


func present() -> void:
	_rebuild()
	_is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func dismiss() -> void:
	_is_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── Layout ───────────────────────────────────────────────────────────────

func _build() -> void:
	var sheet := ColorRect.new()
	MenuLook.fill(sheet)
	sheet.color = SHEET_BG
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)

	var centre := CenterContainer.new()
	MenuLook.fill(centre)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var col := VBoxContainer.new()
	col.custom_minimum_size.x = CARD_W
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(col)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	var title := MenuLook.heading("CONTROLS", 38, MenuLook.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var rebind := MenuLook.kicker("", MenuLook.MUTE_3, 10)
	rebind.text = MenuLook.tracked("REBIND IN SETTINGS")
	rebind.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rebind.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(rebind)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(COL_SEP))
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cols_m := MarginContainer.new()
	cols_m.add_theme_constant_override("margin_top", 26)
	cols_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols_m.add_child(cols)
	col.add_child(cols_m)

	_left_col = _column()
	cols.add_child(_left_col)
	_right_col = _column()
	cols.add_child(_right_col)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = MenuLook.LINE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_m := MarginContainer.new()
	rule_m.add_theme_constant_override("margin_top", 30)
	rule_m.add_theme_constant_override("margin_bottom", 16)
	rule_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_m.add_child(rule)
	col.add_child(rule_m)

	_close = MenuLook.kicker("", MenuLook.MUTE_3, 10)
	_close.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_close)


func _column() -> VBoxContainer:
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", int(ROW_SEP))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ── Content ──────────────────────────────────────────────────────────────

func _rebuild() -> void:
	for c in [_left_col, _right_col]:
		for child in c.get_children():
			c.remove_child(child)
			child.free()

	_group(_left_col, "MOVEMENT", MenuLook.CY, [
		[[_move_primary(), _move_alt()], "Move"],
		[_keys("jump"), DESCRIPTIONS["jump"]],
		[_keys("crouch"), DESCRIPTIONS["crouch"]],
		[_keys("walk"), DESCRIPTIONS["walk"]],
		[["MOUSE"], "Look"],
	])
	_group(_left_col, "COMMS", MenuLook.RD, [
		[_keys("chat_all"), DESCRIPTIONS["chat_all"]],
		[_keys("chat_team"), DESCRIPTIONS["chat_team"]],
		[["ESC"], "Cancel chat / close panel"],
	])

	_group(_right_col, "COMBAT", MenuLook.CY, [
		[_keys("fire"), DESCRIPTIONS["fire"]],
		[_keys("melee"), DESCRIPTIONS["melee"]],
		[_keys("special"), DESCRIPTIONS["special"]],
	])
	_group(_right_col, "GAME", MenuLook.CY, [
		[_keys("scoreboard"), DESCRIPTIONS["scoreboard"]],
		[_keys("team_menu"), DESCRIPTIONS["team_menu"]],
		[_keys("controls"), DESCRIPTIONS["controls"]],
	])

	# Clearing the bind leaves ESC as the only way out, so the footer says so.
	var close_key := InputBinds.primary("controls").to_upper()
	_close.text = MenuLook.tracked(
		"ESC TO CLOSE" if close_key.is_empty() else "%s OR ESC TO CLOSE" % close_key)


## Movement is one row on the card even though it is four binds: the primaries
## make the WASD cluster, the alts the arrow cluster.
func _move_primary() -> String:
	return _join(["forward", "left", "back", "right"], 0)


func _move_alt() -> String:
	return _join(["forward", "left", "back", "right"], 1)


func _join(actions: Array, slot: int) -> String:
	var parts: PackedStringArray = []
	for a: String in actions:
		var key: String = InputBinds.bindings[a][slot]
		if not key.is_empty():
			parts.append(_display(key))
	return " ".join(parts)


## One chip per bound key, so a primary and its alt read as two separate keys
## rather than one impossible combination.
func _keys(action_name: String) -> Array:
	var out: Array = []
	for key in InputBinds.bindings.get(action_name, []):
		if not (key as String).is_empty():
			out.append(_display(key))
	if out.is_empty():
		out.append("—")
	return out


func _display(key_name: String) -> String:
	return str(KEY_DISPLAY.get(key_name, key_name.to_upper()))


func _group(parent: VBoxContainer, title: String, accent: Color, rows: Array) -> void:
	var header := MenuLook.kicker("", accent, 10)
	header.text = MenuLook.tracked(title)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_top", 18 if parent.get_child_count() > 0 else 0)
	hm.add_theme_constant_override("margin_bottom", 6)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_child(header)
	parent.add_child(hm)

	for row: Array in rows:
		parent.add_child(_row(row[0], str(row[1]), accent))


func _row(chips: Array, what: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = ROW_BG
	st.border_color = accent
	st.border_width_left = 3
	st.set_corner_radius_all(3)
	st.content_margin_left = 12
	st.content_margin_right = 14
	st.content_margin_top = 9
	st.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	for chip_text: String in chips:
		if chip_text.is_empty():
			continue
		row.add_child(_chip(chip_text))

	var label := Label.new()
	label.text = what
	label.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", DESC_INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	return panel


func _chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = CHIP_BG
	st.border_color = CHIP_LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.content_margin_left = 9
	st.content_margin_right = 9
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", st)

	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", CHIP_INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip
