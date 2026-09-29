class_name SettingsScreen
extends Control

## The one settings page in the game. The menu registers it as a screen and a
## match lays the same node over its HUD, so neither copy can drift from the
## other. In a match the backdrop is opaque: the world behind it must not show
## through while you are reading a key list.

signal close_requested

const SuitSettings := preload("res://core/suit_settings.gd")
const BACKDROP := Color(0.043, 0.039, 0.086, 1.0)
const BIND_ROW_BG := Color(0.043, 0.039, 0.086, 0.55)
const KEY_COL_W := 96

var _master_slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _sens_slider: HSlider
var _size_slider: HSlider
var _thick_slider: HSlider
var _gap_slider: HSlider
var _alpha_slider: HSlider
var _master_val: Label
var _sfx_val: Label
var _music_val: Label
var _sens_val: Label
var _size_val: Label
var _thick_val: Label
var _gap_val: Label
var _alpha_val: Label
var _invert_check: Button
var _voice_enable: Button
var _voice_open_mic: Button
var _voice_out_slider: HSlider
var _voice_out_val: Label
var _voice_gain_slider: HSlider
var _voice_gain_val: Label
var _voice_squelch_slider: HSlider
var _voice_squelch_val: Label
var _suit_btns: Dictionary = {}
var _suit_desc: Label
var _suit_preview: SuitPreview
var _color_buttons: Dictionary = {}
var _binds_container: VBoxContainer
var _tab_btns: Dictionary = {}
var _pages: Dictionary = {}
var _current_tab: String = "controls"

var _listening_action: String = ""
var _listening_slot: int = -1
var _listening_button: Button
var _pulse_t: float = 0.0


func _init(back_text: String = "◀  MAIN MENU", opaque: bool = false) -> void:
	MenuLook.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build(back_text, opaque)


func _ready() -> void:
	add_to_group("settings_screens")
	refresh()
	_rebuild_binds()
	InputBinds.bindings_changed.connect(_rebuild_binds)
	CrosshairSettings.changed.connect(_sync_crosshair_controls)
	visibility_changed.connect(_sync_preview_active)


## Pulls every control back in line with the stored settings. Worth calling on
## the way in: audio and binds can be changed from elsewhere between visits.
func refresh() -> void:
	_master_slider.set_value_no_signal(AudioMix.master_pct)
	_sfx_slider.set_value_no_signal(AudioMix.sfx_pct)
	_music_slider.set_value_no_signal(AudioMix.music_pct)
	_master_val.text = "%d%%" % AudioMix.master_pct
	_sfx_val.text = "%d%%" % AudioMix.sfx_pct
	_music_val.text = "%d%%" % AudioMix.music_pct
	_sens_slider.set_value_no_signal(InputSettings.slider_value())
	_sens_val.text = "%.2f" % InputSettings.sensitivity
	_invert_check.set_pressed_no_signal(InputSettings.invert_y)
	_paint_suit_btns()
	_suit_desc.text = SuitStyle.blurb_for(SuitSettings.style)
	if _suit_preview:
		_suit_preview.set_style(SuitSettings.style)
	_sync_crosshair_controls()
	_sync_preview_active()


func is_listening() -> bool:
	return not _listening_action.is_empty()


func cancel_listening() -> void:
	if is_listening():
		_stop_listening()


# ── Layout ───────────────────────────────────────────────────────────────

func _build(back_text: String, opaque: bool) -> void:
	if opaque:
		var backdrop := ColorRect.new()
		MenuLook.fill(backdrop)
		backdrop.color = BACKDROP
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(backdrop)

	var scroll := ScrollContainer.new()
	MenuLook.fill(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var page := MarginContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	MenuLook.page_margins(page)
	scroll.add_child(page)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_child(col)

	var back_wrap := MarginContainer.new()
	back_wrap.add_theme_constant_override("margin_bottom", 14)
	back_wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var back := Button.new()
	back.text = back_text
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	MenuLook.apply_ghost(back)
	back.pressed.connect(func() -> void: close_requested.emit())
	back_wrap.add_child(back)
	col.add_child(back_wrap)

	col.add_child(MenuLook.kicker("Configuration"))
	col.add_child(MenuLook.heading("SETTINGS", 40))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tabs_m := MarginContainer.new()
	tabs_m.add_theme_constant_override("margin_top", 18)
	tabs_m.add_child(tabs)
	col.add_child(tabs_m)

	for pair in [
		["controls", "Controls"],
		["sound", "Sound"],
		["mouse", "Mouse"],
		["skins", "Skins"],
	]:
		var id: String = pair[0]
		var btn := Button.new()
		btn.text = str(pair[1]).to_upper()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_show_tab.bind(id))
		tabs.add_child(btn)
		_tab_btns[id] = btn

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack_m := MarginContainer.new()
	stack_m.add_theme_constant_override("margin_top", 14)
	stack_m.add_child(stack)
	col.add_child(stack_m)

	_pages["controls"] = _build_binds_panel()
	_pages["sound"] = _build_sound_panel()
	_pages["mouse"] = _build_mouse_panel()
	_pages["skins"] = _build_skins_panel()
	for page_id in _pages:
		stack.add_child(_pages[page_id])
	_show_tab(_current_tab)


func _show_tab(id: String) -> void:
	if id != "controls" and is_listening():
		cancel_listening()
	_current_tab = id
	for page_id in _pages:
		(_pages[page_id] as Control).visible = page_id == id
	for tab_id in _tab_btns:
		_apply_tab(_tab_btns[tab_id], tab_id == id)
	_sync_preview_active()


func _sync_preview_active() -> void:
	if _suit_preview:
		_suit_preview.set_active(is_visible_in_tree() and _current_tab == "skins")


func _apply_tab(btn: Button, active: bool) -> void:
	var border := MenuLook.CY if active else MenuLook.LINE
	var bg := MenuLook.CARD_BG if active else MenuLook.GHOST_BG
	var s := MenuLook.box(bg, border, 4)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	var hover := MenuLook.box(bg, Color(MenuLook.CY, 0.45) if not active else border, 4)
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	hover.content_margin_top = 11
	hover.content_margin_bottom = 11
	var col := MenuLook.CY if active else MenuLook.INK_2
	MenuLook.style_button(btn, s, hover, col, MenuLook.FONT_HEADING, 14)


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_panel(panel, 18)
	return panel


func _build_sound_panel() -> PanelContainer:
	var vol := _make_panel()
	var vv := VBoxContainer.new()
	vol.add_child(vv)
	vv.add_child(MenuLook.kicker("Volume"))

	_master_slider = _slider_row(vv, "Master", "All audio", AudioMix.master_pct, func(v: float) -> void:
		AudioMix.set_master(int(v))
		_master_val.text = "%d%%" % int(v))
	_master_val = vv.get_meta("last_val")
	_sfx_slider = _slider_row(vv, "SFX", "Weapons · impacts · announcer", AudioMix.sfx_pct, func(v: float) -> void:
		AudioMix.set_sfx(int(v))
		_sfx_val.text = "%d%%" % int(v))
	_sfx_val = vv.get_meta("last_val")
	_music_slider = _slider_row(vv, "Music", "Menu & match-over themes", AudioMix.music_pct, func(v: float) -> void:
		AudioMix.set_music(int(v))
		_music_val.text = "%d%%" % int(v))
	_music_val = vv.get_meta("last_val")

	_build_voice_rows(vv)
	return vol


## Voice lives under Volume rather than in a tab of its own: it is audio, and a
## player looking for "why can nobody hear me" looks at the sound settings.
##
## The whole block is absent when the engine build cannot record or play
## generated audio, rather than present and inert. An option that does nothing
## is worse than a missing one, because the player spends their time on it.
func _build_voice_rows(vv: VBoxContainer) -> void:
	if not VoiceSettings.is_supported():
		return

	var voice_k := MarginContainer.new()
	voice_k.add_theme_constant_override("margin_top", 24)
	voice_k.add_child(MenuLook.kicker("Voice"))
	vv.add_child(voice_k)

	_voice_enable = Button.new()
	_voice_enable.toggle_mode = true
	_voice_enable.button_pressed = VoiceSettings.enabled
	_voice_enable.text = "  Enable voice chat"
	_voice_enable.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuLook.apply_ghost(_voice_enable, 14)
	_voice_enable.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	_voice_enable.toggled.connect(func(on: bool) -> void:
		VoiceSettings.set_enabled(on)
		_sync_voice_rows())
	var en_m := MarginContainer.new()
	en_m.add_theme_constant_override("margin_top", 18)
	en_m.add_child(_voice_enable)
	vv.add_child(en_m)

	_voice_open_mic = Button.new()
	_voice_open_mic.toggle_mode = true
	_voice_open_mic.button_pressed = not VoiceSettings.is_push_to_talk()
	_voice_open_mic.text = "  Open mic (off = hold %s to talk)" % InputBinds.fmt("voice")
	_voice_open_mic.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuLook.apply_ghost(_voice_open_mic, 14)
	_voice_open_mic.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	_voice_open_mic.toggled.connect(func(on: bool) -> void:
		VoiceSettings.set_mode(
			VoiceSettings.Mode.OPEN_MIC if on else VoiceSettings.Mode.PUSH_TO_TALK)
		_sync_voice_rows())
	var om_m := MarginContainer.new()
	om_m.add_theme_constant_override("margin_top", 10)
	om_m.add_child(_voice_open_mic)
	vv.add_child(om_m)

	_voice_out_slider = _slider_row(vv, "Voice volume", "How loud other players are",
		VoiceSettings.output_pct, func(v: float) -> void:
			VoiceSettings.set_output_pct(int(v))
			_voice_out_val.text = "%d%%" % int(v))
	_voice_out_val = vv.get_meta("last_val")

	_voice_gain_slider = _slider_row(vv, "Mic gain", "Raise if others say you are quiet",
		VoiceSettings.mic_gain_pct, func(v: float) -> void:
			VoiceSettings.set_mic_gain_pct(int(v))
			_voice_gain_val.text = "%d%%" % int(v),
		0.0, 200.0, 5.0, func(v: float) -> String: return "%d%%" % int(v))
	_voice_gain_val = vv.get_meta("last_val")

	_voice_squelch_slider = _slider_row(vv, "Mic threshold",
		"Open mic only: how loud before it transmits",
		VoiceSettings.squelch_pct, func(v: float) -> void:
			VoiceSettings.set_squelch_pct(int(v))
			_voice_squelch_val.text = "%d%%" % int(v),
		0.0, 20.0, 1.0, func(v: float) -> String: return "%d%%" % int(v))
	_voice_squelch_val = vv.get_meta("last_val")

	_sync_voice_rows()


## Greys out what the current choices make irrelevant: everything when voice is
## off, and the threshold when push-to-talk is on, since that mode ignores it.
func _sync_voice_rows() -> void:
	var on: bool = VoiceSettings.enabled
	if _voice_open_mic:
		_voice_open_mic.disabled = not on
	if _voice_out_slider:
		_voice_out_slider.editable = on
	if _voice_gain_slider:
		_voice_gain_slider.editable = on
	if _voice_squelch_slider:
		_voice_squelch_slider.editable = on and not VoiceSettings.is_push_to_talk()


func _build_mouse_panel() -> PanelContainer:
	var mouse := _make_panel()
	var vv := VBoxContainer.new()
	mouse.add_child(vv)
	vv.add_child(MenuLook.kicker("Look"))

	_sens_slider = _slider_row(vv, "Sensitivity", "Applies to looking around in a match",
		InputSettings.slider_value(), func(v: float) -> void:
			InputSettings.set_from_slider(v)
			_sens_val.text = "%.2f" % InputSettings.sensitivity,
		2.0, 100.0, 1.0)
	_sens_val = vv.get_meta("last_val")

	_invert_check = Button.new()
	_invert_check.toggle_mode = true
	_invert_check.text = "  Invert mouse Y"
	_invert_check.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuLook.apply_ghost(_invert_check, 14)
	_invert_check.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	_invert_check.toggled.connect(func(on: bool) -> void: InputSettings.set_invert_y(on))
	var inv_m := MarginContainer.new()
	inv_m.add_theme_constant_override("margin_top", 18)
	inv_m.add_child(_invert_check)
	vv.add_child(inv_m)

	var hair_k := MarginContainer.new()
	hair_k.add_theme_constant_override("margin_top", 24)
	hair_k.add_child(MenuLook.kicker("Crosshair"))
	vv.add_child(hair_k)

	vv.add_child(_build_crosshair_preview())

	_size_slider = _slider_row(vv, "Size", "Length of each arm", CrosshairSettings.size, func(v: float) -> void:
		CrosshairSettings.set_size(v)
		_size_val.text = "%d" % int(v),
		CrosshairSettings.SIZE_MIN, CrosshairSettings.SIZE_MAX, 1.0, _px_fmt)
	_size_val = vv.get_meta("last_val")

	_thick_slider = _slider_row(vv, "Thickness", "Width of each arm", CrosshairSettings.thickness, func(v: float) -> void:
		CrosshairSettings.set_thickness(v)
		_thick_val.text = "%d" % int(v),
		CrosshairSettings.THICKNESS_MIN, CrosshairSettings.THICKNESS_MAX, 1.0, _px_fmt)
	_thick_val = vv.get_meta("last_val")

	_gap_slider = _slider_row(vv, "Spacing", "Gap between opposite arms", CrosshairSettings.gap, func(v: float) -> void:
		CrosshairSettings.set_gap(v)
		_gap_val.text = "%d" % int(v),
		CrosshairSettings.GAP_MIN, CrosshairSettings.GAP_MAX, 1.0, _px_fmt)
	_gap_val = vv.get_meta("last_val")

	_alpha_slider = _slider_row(vv, "Opacity", "Lower is more translucent",
		CrosshairSettings.alpha * 100.0, func(v: float) -> void:
			CrosshairSettings.set_alpha(v / 100.0)
			_alpha_val.text = "%d%%" % int(v),
		CrosshairSettings.ALPHA_MIN * 100.0, CrosshairSettings.ALPHA_MAX * 100.0, 1.0, _pct_fmt)
	_alpha_val = vv.get_meta("last_val")

	_add_color_swatches(vv)
	return mouse


func _build_skins_panel() -> PanelContainer:
	var skins := _make_panel()
	var vv := VBoxContainer.new()
	skins.add_child(vv)
	vv.add_child(MenuLook.kicker("Suit"))
	var suit_note := MenuLook.mono("How every player looks on this machine.", 10, MenuLook.MUTE_3)
	suit_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.add_child(suit_note)

	_suit_preview = SuitPreview.new()
	_suit_preview.set_style(SuitSettings.style)
	var preview_m := MarginContainer.new()
	preview_m.add_theme_constant_override("margin_top", 14)
	preview_m.add_child(_suit_preview)
	vv.add_child(preview_m)
	vv.add_child(MenuLook.kicker("Drag to spin · blue · red", MenuLook.MUTE_3, 10))

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	var grid_m := MarginContainer.new()
	grid_m.add_theme_constant_override("margin_top", 12)
	grid_m.add_child(grid)
	vv.add_child(grid_m)
	var row: HBoxContainer = null
	for i in SuitStyle.STYLES.size():
		if i % 2 == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			grid.add_child(row)
		var id := SuitStyle.STYLES[i]
		var btn := Button.new()
		btn.text = SuitStyle.label_for(id)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_suit_picked.bind(id))
		row.add_child(btn)
		_suit_btns[id] = btn
	_paint_suit_btns()
	_suit_desc = MenuLook.mono(SuitStyle.blurb_for(SuitSettings.style), 10, MenuLook.MUTE_3)
	_suit_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.add_child(_suit_desc)
	return skins


func _build_binds_panel() -> PanelContainer:
	var binds := PanelContainer.new()
	binds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_panel(binds, 18)
	var bv := VBoxContainer.new()
	binds.add_child(bv)

	var bh := HBoxContainer.new()
	bh.add_child(MenuLook.kicker("Key bindings"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	bh.add_child(MenuLook.kicker("Click a bind to change it · ESC cancels · DEL clears", MenuLook.MUTE_3, 10))
	bv.add_child(bh)

	_binds_container = VBoxContainer.new()
	_binds_container.add_theme_constant_override("separation", 0)
	var bc_m := MarginContainer.new()
	bc_m.add_theme_constant_override("margin_top", 12)
	bc_m.add_child(_binds_container)
	bv.add_child(bc_m)

	var reset := Button.new()
	reset.text = "RESET DEFAULTS"
	MenuLook.apply_ghost(reset)
	reset.pressed.connect(func() -> void: InputBinds.reset_to_defaults())
	var reset_m := MarginContainer.new()
	reset_m.add_theme_constant_override("margin_top", 18)
	reset_m.add_child(reset)
	bv.add_child(reset_m)

	return binds


func _on_suit_picked(id: String) -> void:
	SuitSettings.set_style(id)
	_suit_desc.text = SuitStyle.blurb_for(id)
	if _suit_preview:
		_suit_preview.set_style(id)
	_paint_suit_btns()


func _paint_suit_btns() -> void:
	var current := SuitSettings.style
	for id in _suit_btns:
		_apply_tab(_suit_btns[id], str(id) == current)


func _px_fmt(value: float) -> String:
	return "%d" % int(value)


func _pct_fmt(value: float) -> String:
	return "%d%%" % int(value)


func _sync_crosshair_controls() -> void:
	if _size_slider == null:
		return
	_size_slider.set_value_no_signal(CrosshairSettings.size)
	_thick_slider.set_value_no_signal(CrosshairSettings.thickness)
	_gap_slider.set_value_no_signal(CrosshairSettings.gap)
	_alpha_slider.set_value_no_signal(CrosshairSettings.alpha * 100.0)
	_size_val.text = "%d" % int(CrosshairSettings.size)
	_thick_val.text = "%d" % int(CrosshairSettings.thickness)
	_gap_val.text = "%d" % int(CrosshairSettings.gap)
	_alpha_val.text = "%d%%" % int(round(CrosshairSettings.alpha * 100.0))
	_style_color_swatches()


func _build_crosshair_preview() -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 108)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.016, 0.02, 0.035, 1.0)
	bg.border_color = MenuLook.LINE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", bg)
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 96)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(wrap)
	var preview := Crosshair.new()
	MenuLook.fill(preview)
	wrap.add_child(preview)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 14)
	m.add_child(frame)
	return m


func _add_color_swatches(parent: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_top", 14)
	hm.add_child(head)
	parent.add_child(hm)
	head.add_child(MenuLook.body("Color", 14, MenuLook.INK))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var group := ButtonGroup.new()
	group.allow_unpress = false
	for id in CrosshairSettings.COLOR_IDS:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(28, 28)
		btn.tooltip_text = id.capitalize()
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.set_pressed_no_signal(id == CrosshairSettings.color_id)
		var bound := id
		btn.pressed.connect(func() -> void: CrosshairSettings.set_color_id(bound))
		row.add_child(btn)
		_color_buttons[id] = btn
	_style_color_swatches()
	parent.add_child(MenuLook.kicker("Typical tints · opacity is separate", MenuLook.MUTE_3, 10))


func _style_color_swatches() -> void:
	for id in _color_buttons:
		var btn: Button = _color_buttons[id]
		var rgb: Color = CrosshairSettings.palette_rgb(str(id))
		var on := str(id) == CrosshairSettings.color_id
		btn.set_pressed_no_signal(on)
		var n := _swatch_box(rgb, Color.WHITE if on else Color(1, 1, 1, 0.22), 2 if on else 1)
		var h := _swatch_box(rgb, MenuLook.CY, 2)
		btn.add_theme_stylebox_override("normal", n)
		btn.add_theme_stylebox_override("hover", h)
		btn.add_theme_stylebox_override("pressed", n)
		btn.add_theme_stylebox_override("focus", n)


func _swatch_box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(3)
	return s


func _slider_row(parent: VBoxContainer, label: String, hint: String, value: float,
		on_change: Callable, min_v := 0.0, max_v := 100.0, step := 1.0,
		value_fmt: Callable = Callable()) -> HSlider:
	var row := HBoxContainer.new()
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_top", 14)
	rm.add_child(row)
	parent.add_child(rm)
	var l := MenuLook.body(label, 14, MenuLook.INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var percent := max_v == 100.0 and min_v == 0.0
	var text := ""
	if value_fmt.is_valid():
		text = str(value_fmt.call(value))
	elif percent:
		text = "%d%%" % int(value)
	else:
		text = "%.2f" % (value / InputSettings.SLIDER_SCALE)
	var val := MenuLook.mono(text, 12, MenuLook.CY)
	row.add_child(val)
	parent.set_meta("last_val", val)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = value
	MenuLook.apply_slider(sl)
	parent.add_child(sl)
	parent.add_child(MenuLook.kicker(hint, MenuLook.MUTE_3, 10))
	sl.value_changed.connect(on_change)
	return sl


# ── Key bindings ─────────────────────────────────────────────────────────

func _rebuild_binds() -> void:
	for child in _binds_container.get_children():
		child.queue_free()
	for group_data: Array in InputBinds.BIND_GROUPS:
		var group_name: String = group_data[0]
		var actions: Array = group_data[1]
		var header := MenuLook.kicker(group_name, MenuLook.CY if group_name != "Combat" else MenuLook.RD_SOFT, 10)
		var hm := MarginContainer.new()
		hm.add_theme_constant_override("margin_top", 20)
		hm.add_theme_constant_override("margin_bottom", 8)
		hm.add_child(header)
		_binds_container.add_child(hm)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var h1 := MenuLook.kicker("", MenuLook.MUTE_3, 9)
		h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(h1)
		var p := MenuLook.kicker("Primary", MenuLook.MUTE_3, 9)
		p.custom_minimum_size.x = KEY_COL_W
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(p)
		var a := MenuLook.kicker("Alt", MenuLook.MUTE_3, 9)
		a.custom_minimum_size.x = KEY_COL_W
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(a)
		_binds_container.add_child(head)
		for action_name: String in actions:
			_binds_container.add_child(_bind_row(InputBinds.BIND_LABELS.get(action_name, action_name), action_name))


func _bind_row(label: String, action_name: String) -> Control:
	var wrap := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = BIND_ROW_BG
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 12
	bg.content_margin_right = 12
	bg.content_margin_top = 7
	bg.content_margin_bottom = 7
	wrap.add_theme_stylebox_override("panel", bg)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)
	var lab := MenuLook.body(label, 14, MenuLook.INK)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lab)
	for slot in 2:
		var key_name: String = InputBinds.bindings[action_name][slot]
		var btn := Button.new()
		btn.text = InputBinds.get_display_name(key_name)
		btn.custom_minimum_size = Vector2(KEY_COL_W, 30)
		MenuLook.apply_bind_key(btn, key_name.is_empty(), false, false)
		var bound_action := action_name
		var bound_slot := slot
		btn.pressed.connect(func() -> void: _start_listening(bound_action, bound_slot, btn))
		row.add_child(btn)
	var gap := MarginContainer.new()
	gap.add_theme_constant_override("margin_bottom", 6)
	gap.add_child(wrap)
	return gap


func _start_listening(action_name: String, slot: int, btn: Button) -> void:
	_listening_action = action_name
	_listening_slot = slot
	_listening_button = btn
	_pulse_t = 0.0
	btn.text = "..."
	MenuLook.apply_bind_key(btn, false, true, false)


func _capture_bind_event(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			_stop_listening()
			return
		if key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE:
			InputBinds.set_bind(_listening_action, _listening_slot, "")
			_stop_listening()
			return
	var key_name := InputBinds.event_to_bind_name(event)
	if not key_name.is_empty():
		InputBinds.set_bind(_listening_action, _listening_slot, key_name)
	_stop_listening()


func _stop_listening() -> void:
	_listening_action = ""
	_listening_slot = -1
	if _listening_button:
		_listening_button.modulate.a = 1.0
	_listening_button = null
	_rebuild_binds()


func _process(dt: float) -> void:
	if not is_listening() or _listening_button == null:
		return
	_pulse_t += dt
	_listening_button.modulate.a = 0.35 + 0.65 * absf(sin(_pulse_t * TAU))


# A bind can be a mouse button, so clicks have to be swallowed here before the
# buttons underneath treat them as a press.
func _input(event: InputEvent) -> void:
	if not is_listening() or not (event is InputEventMouseButton):
		return
	if (event as InputEventMouseButton).pressed:
		_capture_bind_event(event)
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_listening():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_capture_bind_event(event)
		get_viewport().set_input_as_handled()
