class_name SettingsScreen
extends Control

## The one settings page in the game. The menu registers it as a screen and a
## match lays the same node over its HUD, so neither copy can drift from the
## other. In a match the backdrop is opaque: the world behind it must not show
## through while you are reading a key list.

signal close_requested

const BACKDROP := Color(0.043, 0.039, 0.086, 1.0)
const BIND_ROW_BG := Color(0.043, 0.039, 0.086, 0.55)
const KEY_COL_W := 96

var _master_slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _sens_slider: HSlider
var _master_val: Label
var _sfx_val: Label
var _music_val: Label
var _sens_val: Label
var _invert_check: Button
var _binds_container: VBoxContainer

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
	refresh()
	_rebuild_binds()
	InputBinds.bindings_changed.connect(_rebuild_binds)


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

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid_m := MarginContainer.new()
	grid_m.add_theme_constant_override("margin_top", 18)
	grid_m.add_child(grid)
	col.add_child(grid_m)

	grid.add_child(_build_audio_panel())
	grid.add_child(_build_binds_panel())


func _build_audio_panel() -> PanelContainer:
	var vol := PanelContainer.new()
	vol.custom_minimum_size.x = 320
	MenuLook.apply_panel(vol, 18)
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

	var mouse_k := MarginContainer.new()
	mouse_k.add_theme_constant_override("margin_top", 24)
	mouse_k.add_child(MenuLook.kicker("Mouse"))
	vv.add_child(mouse_k)

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

	return vol


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


func _slider_row(parent: VBoxContainer, label: String, hint: String, value: float,
		on_change: Callable, min_v := 0.0, max_v := 100.0, step := 1.0) -> HSlider:
	var row := HBoxContainer.new()
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_top", 14)
	rm.add_child(row)
	parent.add_child(rm)
	var l := MenuLook.body(label, 14, MenuLook.INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var percent := max_v == 100.0 and min_v == 0.0
	var val := MenuLook.mono("%d%%" % int(value) if percent else "%.2f" % (value / InputSettings.SLIDER_SCALE), 12, MenuLook.CY)
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
