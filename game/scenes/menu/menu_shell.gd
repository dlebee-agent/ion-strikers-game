extends Control

const MAPS: Array[Dictionary] = [
	{"id": "parkour", "name": "Parkour Yard", "desc": "Mirrored stairs & jump blocks. Movement + jump test bed."},
]

var callsign_screen: Control
var home_screen: Control
var join_screen: Control
var create_screen: Control
var settings_screen: Control
var menu_chrome: Control
var stage_glows: Control
var live_blip: ColorRect
var live_blip_chrome: ColorRect
var callsign_input: LineEdit
var callsign_go: Button
var callsign_count: Label
var callsign_val: Label
var join_meta: Label
var designer_btn: Button
var server_filter: LineEdit
var server_list: VBoxContainer
var result_line: Label
var rounds_label: Label
var rounds_row: HBoxContainer
var kills_row: HBoxContainer
var bots_dev_wrap: Control
var brief_shoot_row: Control
var brief_host: Label
var sum_network: Label
var sum_mode: Label
var sum_limit: Label
var sum_cap: Label
var sum_spec: Label
var brief_bots: Label
var brief_bots_shoot: Label
var sum_total: Label
var server_in: LineEdit
var launch_note: Label
var invert_y_check: Button
var binds_container: VBoxContainer
var master_slider: HSlider
var sfx_slider: HSlider
var music_slider: HSlider
var sens_slider: HSlider
var master_val: Label
var sfx_val: Label
var music_val: Label
var sens_val: Label

var _callsign: String = ""
var _settings_cfg := ConfigFile.new()
var _listening_action: String = ""
var _listening_slot: int = -1
var _listening_button: Button
var _blip_t: float = 0.0

var selected_hosting: String = "lan"
var selected_mode: String = "classic"
var selected_map: String = "parkour"
var selected_rounds: int = 10
var selected_kills: int = 50
var selected_cap: int = 12
var selected_spec: int = 12
var selected_bots: bool = true
var selected_bots_shoot: bool = true
var invert_y: bool = false

var _mode_btns: Array[Button] = []
var _hosting_btns: Array[Button] = []
var _map_select: OptionButton
var _round_btns: Array[Button] = []
var _kill_btns: Array[Button] = []
var _cap_btns: Array[Button] = []
var _spec_btns: Array[Button] = []
var _bot_yes: Button
var _bot_no: Button
var _shoot_yes: Button
var _shoot_no: Button
var _local_dedicated: LocalDedicated
var _game_client: GameClient
var _connecting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	UiRoot.register_screen("callsign", callsign_screen)
	UiRoot.register_screen("menu", home_screen)
	UiRoot.register_screen("settings", settings_screen)
	UiRoot.register_screen("join", join_screen)
	UiRoot.register_screen("create", create_screen)
	UiRoot.register_floating_layer("menuchrome", menu_chrome, ["menu", "join", "create", "settings"])
	UiRoot.screen_changed.connect(_on_screen_changed)

	_load_callsign()
	_load_input_settings()
	_setup_settings_ui()
	_rebuild_binds_ui()
	InputBinds.bindings_changed.connect(_rebuild_binds_ui)
	_refresh_brief()
	_render_server_list()

	AudioMix.play_menu()

	if _callsign.is_empty():
		UiRoot.show("callsign")
		callsign_input.grab_focus()
	else:
		callsign_val.text = _callsign
		brief_host.text = _callsign
		UiRoot.show("menu")


func _process(dt: float) -> void:
	_blip_t += dt
	var a := 0.25 + 0.75 * absf(sin(_blip_t * PI))
	if live_blip:
		live_blip.modulate.a = a
	if live_blip_chrome:
		live_blip_chrome.modulate.a = a
	if not _listening_action.is_empty() and _listening_button:
		_listening_button.modulate.a = 0.35 + 0.65 * absf(sin(_blip_t * TAU))


func _on_screen_changed(screen_name: String) -> void:
	stage_glows.visible = screen_name == "menu"
	if screen_name == "callsign":
		callsign_input.grab_focus()


func _build() -> void:
	add_child(MenuLook.shader_rect(MenuLook.SH_BG))

	stage_glows = Control.new()
	stage_glows.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_glows.anchor_left = 0.54
	stage_glows.anchor_top = 0.26
	stage_glows.anchor_right = 1.0
	stage_glows.anchor_bottom = 0.96
	stage_glows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glows := HBoxContainer.new()
	MenuLook.fill(glows)
	glows.add_child(MenuLook.glow_rect(false))
	glows.add_child(MenuLook.glow_rect(true))
	stage_glows.add_child(glows)
	add_child(stage_glows)

	var floor_fade := MenuLook.shader_rect(MenuLook.SH_FADE)
	floor_fade.anchor_top = 0.54
	add_child(floor_fade)

	_build_callsign()
	_build_home()
	_build_join()
	_build_create()
	_build_settings()

	var scan := MenuLook.shader_rect(MenuLook.SH_SCAN)
	add_child(scan)

	_build_chrome()


func _screen() -> Control:
	var s := Control.new()
	MenuLook.fill(s)
	s.visible = false
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(s)
	return s


func _page(parent: Control, center_v := false, scroll := false) -> VBoxContainer:
	var host: Control = parent
	if scroll:
		var sc := ScrollContainer.new()
		MenuLook.fill(sc)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		parent.add_child(sc)
		host = sc
	var page := MarginContainer.new()
	if scroll:
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		MenuLook.fill(page)
	MenuLook.page_margins(page)
	host.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if center_v:
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
	else:
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_child(col)
	return col


func _build_callsign() -> void:
	callsign_screen = _screen()
	var center := CenterContainer.new()
	MenuLook.fill(center)
	callsign_screen.add_child(center)
	var gate := VBoxContainer.new()
	gate.add_theme_constant_override("separation", 0)
	gate.custom_minimum_size.x = 420
	center.add_child(gate)

	var brand := HBoxContainer.new()
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 0)
	brand.add_child(MenuLook.heading("ION", 44, MenuLook.INK))
	brand.add_child(MenuLook.heading("STRIKERS", 44, MenuLook.CY))
	gate.add_child(brand)

	var sub := MenuLook.kicker("blue vs red · pick a side", MenuLook.MUTE_2, 10)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("margin_top", 8)
	var sub_pad := MarginContainer.new()
	sub_pad.add_theme_constant_override("margin_top", 8)
	sub_pad.add_child(sub)
	gate.add_child(sub_pad)

	var card := PanelContainer.new()
	var card_pad := MarginContainer.new()
	card_pad.add_theme_constant_override("margin_top", 34)
	gate.add_child(card_pad)
	card_pad.add_child(card)
	MenuLook.apply_panel(card, 22)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	card.add_child(cv)
	var kick := MenuLook.kicker("Choose your callsign")
	kick.add_theme_constant_override("margin_bottom", 10)
	var kick_m := MarginContainer.new()
	kick_m.add_theme_constant_override("margin_bottom", 10)
	kick_m.add_child(kick)
	cv.add_child(kick_m)

	callsign_input = LineEdit.new()
	callsign_input.placeholder_text = "Player"
	callsign_input.max_length = 16
	callsign_input.alignment = HORIZONTAL_ALIGNMENT_LEFT
	callsign_input.custom_minimum_size.y = 44
	MenuLook.apply_field(callsign_input)
	cv.add_child(callsign_input)

	var note := HBoxContainer.new()
	var note_m := MarginContainer.new()
	note_m.add_theme_constant_override("margin_top", 8)
	note_m.add_child(note)
	cv.add_child(note_m)
	var hint := MenuLook.mono("3–16 characters", 10, MenuLook.MUTE_3)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_child(hint)
	callsign_count = MenuLook.mono("0/16", 10, MenuLook.MUTE_3)
	note.add_child(callsign_count)

	callsign_go = Button.new()
	callsign_go.text = "ENTER ARENA"
	callsign_go.disabled = true
	callsign_go.custom_minimum_size.y = 44
	MenuLook.apply_primary(callsign_go)
	var go_m := MarginContainer.new()
	go_m.add_theme_constant_override("margin_top", 16)
	go_m.add_child(callsign_go)
	cv.add_child(go_m)

	var live := _make_liveline()
	live.alignment = BoxContainer.ALIGNMENT_CENTER
	live_blip = live.get_node("Blip") as ColorRect
	var live_m := MarginContainer.new()
	live_m.add_theme_constant_override("margin_top", 22)
	live_m.add_child(live)
	gate.add_child(live_m)

	callsign_go.pressed.connect(_on_callsign_go)
	callsign_input.text_changed.connect(_on_callsign_text_changed)
	callsign_input.text_submitted.connect(func(_t: String) -> void: _on_callsign_go())


func _build_home() -> void:
	home_screen = _screen()
	var col := _page(home_screen, true)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.custom_minimum_size.x = 860

	var t1 := MenuLook.heading("DROP IN.", 40, MenuLook.INK)
	col.add_child(t1)
	var t2 := MenuLook.heading("LIGHT THEM UP.", 40, MenuLook.CY)
	col.add_child(t2)

	var tag_m := MarginContainer.new()
	tag_m.add_theme_constant_override("margin_top", 12)
	var tag := MenuLook.kicker("One laser gun · blue vs red · first team to 10 rounds", MenuLook.MUTE_2, 11)
	tag_m.add_child(tag)
	col.add_child(tag_m)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	var cards_m := MarginContainer.new()
	cards_m.add_theme_constant_override("margin_top", 34)
	cards_m.add_child(cards)
	col.add_child(cards_m)

	var join_btn := _make_big_card("Server browser", "JOIN LOBBY", "Live matches. You land in the stands and pick a side.", "NO SERVER IN THIS BUILD", false)
	join_meta = join_btn.get_meta("meta_label")
	join_btn.pressed.connect(func() -> void: UiRoot.show("join"))
	cards.add_child(join_btn)

	var create_btn := _make_big_card("Host", "CREATE GAME", "Your mode, your map, your rules.", "2 MODES · PARKOUR YARD →", true)
	create_btn.pressed.connect(func() -> void: UiRoot.show("create"))
	cards.add_child(create_btn)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 16)
	var tiles_m := MarginContainer.new()
	tiles_m.add_theme_constant_override("margin_top", 16)
	tiles_m.add_child(tiles)
	col.add_child(tiles_m)

	designer_btn = _make_tile("Designer", "Sandbox")
	designer_btn.visible = DevMode.active
	designer_btn.pressed.connect(_on_designer_pressed)
	tiles.add_child(designer_btn)

	var settings_btn := _make_tile("Settings", "Audio · binds")
	settings_btn.pressed.connect(func() -> void: UiRoot.show("settings"))
	tiles.add_child(settings_btn)

	var quit_btn := _make_tile("Quit", "Exit the game")
	quit_btn.pressed.connect(func() -> void:
		ConfirmPrompt.ask("Quit Ion Strikers?", func() -> void: get_tree().quit()))
	tiles.add_child(quit_btn)


func _build_join() -> void:
	join_screen = _screen()
	var col := _page(join_screen, false, true)
	col.add_theme_constant_override("separation", 0)

	var back := _add_back(col)
	back.pressed.connect(func() -> void: UiRoot.show("menu"))

	col.add_child(MenuLook.kicker("Server browser"))
	var title := MenuLook.heading("JOIN A LOBBY", 40)
	var title_m := MarginContainer.new()
	title_m.add_theme_constant_override("margin_top", 4)
	title_m.add_child(title)
	col.add_child(title_m)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	var fr_m := MarginContainer.new()
	fr_m.add_theme_constant_override("margin_top", 18)
	fr_m.add_theme_constant_override("margin_bottom", 16)
	fr_m.add_child(filter_row)
	col.add_child(fr_m)

	server_filter = LineEdit.new()
	server_filter.placeholder_text = "Filter server or map"
	server_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_filter.custom_minimum_size.y = 40
	MenuLook.apply_field(server_filter)
	filter_row.add_child(server_filter)

	var refresh := Button.new()
	refresh.text = "REFRESH"
	refresh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	MenuLook.apply_ghost(refresh)
	refresh.pressed.connect(_render_server_list)
	filter_row.add_child(refresh)

	var quick := Button.new()
	quick.text = "QUICK JOIN"
	quick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	MenuLook.apply_ghost(quick)
	quick.pressed.connect(_on_quick_join)
	filter_row.add_child(quick)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_panel(panel, 0)
	col.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 0)
	panel.add_child(pv)

	var head := _join_row(true, ["Server", "Map", "Mode", "Players", "Spectators", ""])
	pv.add_child(head)
	server_list = VBoxContainer.new()
	server_list.add_theme_constant_override("separation", 0)
	pv.add_child(server_list)

	var foot := HBoxContainer.new()
	var foot_pad := MarginContainer.new()
	foot_pad.add_theme_constant_override("margin_left", 16)
	foot_pad.add_theme_constant_override("margin_right", 16)
	foot_pad.add_theme_constant_override("margin_top", 11)
	foot_pad.add_theme_constant_override("margin_bottom", 11)
	foot_pad.add_child(foot)
	pv.add_child(foot_pad)
	result_line = MenuLook.kicker("—", MenuLook.MUTE_3, 10)
	result_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(result_line)
	var host_link := Button.new()
	host_link.text = "NOTHING GOOD? HOST YOUR OWN →"
	host_link.size_flags_horizontal = Control.SIZE_SHRINK_END
	MenuLook.apply_ghost(host_link, 10)
	host_link.pressed.connect(func() -> void: UiRoot.show("create"))
	foot.add_child(host_link)

	server_filter.text_changed.connect(func(_t: String) -> void: _render_server_list())


func _build_create() -> void:
	create_screen = _screen()
	var col := _page(create_screen, false, true)

	var back := _add_back(col)
	back.pressed.connect(func() -> void: UiRoot.show("menu"))
	col.add_child(MenuLook.kicker("Host a match"))
	col.add_child(MenuLook.heading("CREATE GAME", 40))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid_m := MarginContainer.new()
	grid_m.add_theme_constant_override("margin_top", 18)
	grid_m.add_child(grid)
	col.add_child(grid_m)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	grid.add_child(left)

	left.add_child(_sec("Network", true))
	var hosting_row := HBoxContainer.new()
	hosting_row.add_theme_constant_override("separation", 10)
	_hosting_btns = [
		_make_opt("LAN", "This machine. Others can join your network.", "lan"),
		_make_opt("Hosted", "Public lobby on the Ion Strikers servers.", "hosted"),
	]
	_hosting_btns[0].set_meta("active", true)
	_hosting_btns[1].disabled = true
	_hosting_btns[1].modulate.a = 0.45
	for b in _hosting_btns:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hosting_row.add_child(b)
		b.pressed.connect(_on_hosting_picked.bind(b))
	left.add_child(hosting_row)
	_paint_opts(_hosting_btns)

	left.add_child(_sec("Game mode"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	_mode_btns = [
		_make_opt("Classic", "First to 10 rounds · no respawn", "classic"),
		_make_opt("Deathmatch", "Respawn 5s · first to 50 kills", "dm"),
	]
	_mode_btns[0].set_meta("active", true)
	for b in _mode_btns:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(b)
		b.pressed.connect(_on_mode_picked.bind(b))
	left.add_child(mode_row)
	_paint_opts(_mode_btns)

	left.add_child(_sec("Map"))
	_map_select = OptionButton.new()
	_map_select.custom_minimum_size = Vector2(0, 44)
	_map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_dropdown(_map_select)
	for i in MAPS.size():
		var m: Dictionary = MAPS[i]
		_map_select.add_item(str(m["name"]))
		_map_select.set_item_metadata(i, str(m["id"]))
		var selectable := str(m["id"]) == "parkour"
		_map_select.set_item_disabled(i, not selectable)
		if selectable:
			_map_select.select(i)
			selected_map = str(m["id"])
	_map_select.item_selected.connect(_on_map_selected)
	left.add_child(_map_select)
	var map_desc := MenuLook.mono(str(MAPS[0]["desc"]), 10, MenuLook.MUTE_3)
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var map_desc_m := MarginContainer.new()
	map_desc_m.add_theme_constant_override("margin_top", 8)
	map_desc_m.add_child(map_desc)
	left.add_child(map_desc_m)

	var rounds_wrap := _sec("Rounds to win")
	rounds_label = rounds_wrap.get_node("L") as Label
	left.add_child(rounds_wrap)
	rounds_row = HBoxContainer.new()
	rounds_row.add_theme_constant_override("separation", 8)
	for item in [[3, "quick"], [5, "short"], [10, "standard"], [15, "long"], [20, "marathon"]]:
		var b := _make_num(str(item[0]), str(item[1]), item[0])
		b.set_meta("active", item[0] == selected_rounds)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_rounds_picked.bind(b))
		_round_btns.append(b)
		rounds_row.add_child(b)
	left.add_child(rounds_row)
	_paint_nums(_round_btns)

	kills_row = HBoxContainer.new()
	kills_row.add_theme_constant_override("separation", 8)
	kills_row.visible = false
	for item in [[10, "sprint"], [25, "quick"], [50, "standard"], [75, "long"], [100, "marathon"]]:
		var b := _make_num(str(item[0]), str(item[1]), item[0])
		b.set_meta("active", item[0] == selected_kills)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_kills_picked.bind(b))
		_kill_btns.append(b)
		kills_row.add_child(b)
	left.add_child(kills_row)
	_paint_nums(_kill_btns)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 16)
	var slots_m := MarginContainer.new()
	slots_m.add_theme_constant_override("margin_top", 22)
	slots_m.add_child(slots)
	left.add_child(slots_m)

	var cap_col := VBoxContainer.new()
	cap_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_col.add_child(_sec("Player slots", true))
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 8)
	for item in [[4, "duel"], [8, "small"], [12, "standard"], [16, "full"]]:
		var b := _make_num(str(item[0]), str(item[1]), item[0])
		b.set_meta("active", item[0] == selected_cap)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_cap_picked.bind(b))
		_cap_btns.append(b)
		cap_row.add_child(b)
	cap_col.add_child(cap_row)
	slots.add_child(cap_col)
	_paint_nums(_cap_btns)

	var spec_col := VBoxContainer.new()
	spec_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spec_col.add_child(_sec("Extra spectators", true))
	var spec_row := HBoxContainer.new()
	spec_row.add_theme_constant_override("separation", 8)
	for item in [[1, "minimum"], [4, "a few"], [12, "match it"], [24, "crowd"]]:
		var b := _make_num("+" + str(item[0]), str(item[1]), item[0])
		b.set_meta("active", item[0] == selected_spec)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_spec_picked.bind(b))
		_spec_btns.append(b)
		spec_row.add_child(b)
	spec_col.add_child(spec_row)
	slots.add_child(spec_col)
	_paint_nums(_spec_btns)

	left.add_child(_sec("Fill empty slots with bots"))
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 10)
	_bot_yes = _make_yn("YES", true)
	_bot_no = _make_yn("NO", false)
	_bot_yes.set_meta("active", selected_bots)
	_bot_no.set_meta("active", not selected_bots)
	_bot_yes.pressed.connect(func() -> void: selected_bots = true; _paint_yn(); _refresh_brief())
	_bot_no.pressed.connect(func() -> void: selected_bots = false; _paint_yn(); _refresh_brief())
	bots.add_child(_bot_yes)
	bots.add_child(_bot_no)
	left.add_child(bots)

	bots_dev_wrap = VBoxContainer.new()
	var shoot_head := MarginContainer.new()
	shoot_head.add_theme_constant_override("margin_top", 22)
	shoot_head.add_theme_constant_override("margin_bottom", 10)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head_row.add_child(MenuLook.kicker("Bots shoot back"))
	var tag := MenuLook.kicker("DEV", Color("#ffd24a"), 9)
	var tag_box := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1.0, 0.824, 0.29, 0.16)
	ts.border_color = Color(1.0, 0.824, 0.29, 0.5)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(5)
	ts.content_margin_left = 6
	ts.content_margin_right = 6
	ts.content_margin_top = 1
	ts.content_margin_bottom = 1
	tag_box.add_theme_stylebox_override("panel", ts)
	tag_box.add_child(tag)
	head_row.add_child(tag_box)
	shoot_head.add_child(head_row)
	bots_dev_wrap.add_child(shoot_head)
	var shoot := HBoxContainer.new()
	shoot.add_theme_constant_override("separation", 10)
	_shoot_yes = _make_yn("YES", true)
	_shoot_no = _make_yn("NO", false)
	_shoot_yes.set_meta("active", selected_bots_shoot)
	_shoot_no.set_meta("active", not selected_bots_shoot)
	_shoot_yes.pressed.connect(func() -> void: selected_bots_shoot = true; _paint_yn(); _refresh_brief())
	_shoot_no.pressed.connect(func() -> void: selected_bots_shoot = false; _paint_yn(); _refresh_brief())
	shoot.add_child(_shoot_yes)
	shoot.add_child(_shoot_no)
	bots_dev_wrap.add_child(shoot)
	left.add_child(bots_dev_wrap)
	_paint_yn()

	var brief := PanelContainer.new()
	brief.custom_minimum_size.x = 320
	brief.size_flags_horizontal = Control.SIZE_SHRINK_END
	brief.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	MenuLook.apply_panel(brief, 18)
	grid.add_child(brief)
	var bv := VBoxContainer.new()
	brief.add_child(bv)
	bv.add_child(MenuLook.kicker("Match briefing"))
	var sum_m := MarginContainer.new()
	sum_m.add_theme_constant_override("margin_top", 8)
	sum_m.add_theme_constant_override("margin_bottom", 14)
	sum_mode = MenuLook.body("Classic · Parkour Yard", 15, MenuLook.INK)
	sum_mode.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum_m.add_child(sum_mode)
	bv.add_child(sum_m)

	brief_host = _kv(bv, "Host", "Guest")
	sum_network = _kv(bv, "Network", "LAN")
	sum_limit = _kv(bv, "Limit", "first to 10")
	sum_cap = _kv(bv, "Player slots", "12")
	sum_spec = _kv(bv, "Extra spectators", "+12")
	brief_bots = _kv(bv, "Bots", "On")
	brief_shoot_row = HBoxContainer.new()
	bv.add_child(brief_shoot_row)
	brief_bots_shoot = _kv_into(brief_shoot_row, "Bots shoot", "Yes")
	sum_total = _kv(bv, "Room holds", "12 + 12 = 24")

	server_in = LineEdit.new()
	server_in.placeholder_text = "Server name (blank = random)"
	server_in.max_length = 20
	server_in.custom_minimum_size.y = 42
	MenuLook.apply_field(server_in)
	var sin_m := MarginContainer.new()
	sin_m.add_theme_constant_override("margin_top", 16)
	sin_m.add_child(server_in)
	bv.add_child(sin_m)

	var launch := Button.new()
	launch.text = "LAUNCH MATCH"
	MenuLook.apply_primary(launch, true)
	launch.custom_minimum_size.y = 44
	launch.pressed.connect(_on_launch)
	var launch_m := MarginContainer.new()
	launch_m.add_theme_constant_override("margin_top", 12)
	launch_m.add_child(launch)
	bv.add_child(launch_m)

	var browse := Button.new()
	browse.text = "BROWSE LOBBIES INSTEAD"
	MenuLook.apply_ghost(browse)
	browse.pressed.connect(func() -> void: UiRoot.show("join"))
	var browse_m := MarginContainer.new()
	browse_m.add_theme_constant_override("margin_top", 8)
	browse_m.add_child(browse)
	bv.add_child(browse_m)

	launch_note = MenuLook.mono("", 10, MenuLook.RD_SOFT)
	launch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var note_m := MarginContainer.new()
	note_m.add_theme_constant_override("margin_top", 10)
	note_m.add_child(launch_note)
	bv.add_child(note_m)


func _build_settings() -> void:
	settings_screen = _screen()
	var col := _page(settings_screen, false, true)
	var back := _add_back(col)
	back.pressed.connect(func() -> void: UiRoot.show("menu"))
	col.add_child(MenuLook.kicker("Configuration"))
	col.add_child(MenuLook.heading("SETTINGS", 40))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid_m := MarginContainer.new()
	grid_m.add_theme_constant_override("margin_top", 18)
	grid_m.add_child(grid)
	col.add_child(grid_m)

	var vol := PanelContainer.new()
	vol.custom_minimum_size.x = 320
	MenuLook.apply_panel(vol, 18)
	grid.add_child(vol)
	var vv := VBoxContainer.new()
	vol.add_child(vv)
	vv.add_child(MenuLook.kicker("Volume"))
	master_slider = _vol_row(vv, "Master", "All audio", AudioMix.master_pct, func(v: float) -> void:
		AudioMix.set_master(int(v))
		master_val.text = "%d%%" % int(v))
	master_val = vv.get_meta("last_val")
	sfx_slider = _vol_row(vv, "SFX", "Weapons · impacts · announcer", AudioMix.sfx_pct, func(v: float) -> void:
		AudioMix.set_sfx(int(v))
		sfx_val.text = "%d%%" % int(v))
	sfx_val = vv.get_meta("last_val")
	music_slider = _vol_row(vv, "Music", "Menu & match-over themes", AudioMix.music_pct, func(v: float) -> void:
		AudioMix.set_music(int(v))
		music_val.text = "%d%%" % int(v))
	music_val = vv.get_meta("last_val")

	var mouse_k := MarginContainer.new()
	mouse_k.add_theme_constant_override("margin_top", 24)
	mouse_k.add_child(MenuLook.kicker("Mouse"))
	vv.add_child(mouse_k)
	sens_slider = _vol_row(vv, "Sensitivity", "Applies to looking around in a match", 100, func(v: float) -> void:
		var s := v / 20.0
		sens_val.text = "%.2f" % s
		_settings_cfg.set_value("input", "sensitivity", s)
		_save_input_settings(), 2.0, 100.0, 1.0)
	sens_val = vv.get_meta("last_val")
	sens_slider.min_value = 2.0
	sens_slider.max_value = 100.0
	sens_slider.step = 1.0

	invert_y_check = Button.new()
	invert_y_check.toggle_mode = true
	invert_y_check.text = "  Invert mouse Y"
	invert_y_check.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuLook.apply_ghost(invert_y_check, 14)
	invert_y_check.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	invert_y_check.toggled.connect(func(on: bool) -> void:
		invert_y = on
		_settings_cfg.set_value("input", "invert_y", on)
		_save_input_settings())
	var inv_m := MarginContainer.new()
	inv_m.add_theme_constant_override("margin_top", 18)
	inv_m.add_child(invert_y_check)
	vv.add_child(inv_m)

	var binds := PanelContainer.new()
	binds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_panel(binds, 18)
	grid.add_child(binds)
	var bv := VBoxContainer.new()
	binds.add_child(bv)
	var bh := HBoxContainer.new()
	bh.add_child(MenuLook.kicker("Key bindings"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	bh.add_child(MenuLook.kicker("Click a bind to change it · ESC cancels · DEL clears", MenuLook.MUTE_3, 10))
	bv.add_child(bh)
	binds_container = VBoxContainer.new()
	binds_container.add_theme_constant_override("separation", 0)
	var bc_m := MarginContainer.new()
	bc_m.add_theme_constant_override("margin_top", 12)
	bc_m.add_child(binds_container)
	bv.add_child(bc_m)
	var reset := Button.new()
	reset.text = "RESET DEFAULTS"
	MenuLook.apply_ghost(reset)
	reset.pressed.connect(_on_reset_binds)
	var reset_m := MarginContainer.new()
	reset_m.add_theme_constant_override("margin_top", 18)
	reset_m.add_child(reset)
	bv.add_child(reset_m)


func _build_chrome() -> void:
	menu_chrome = Control.new()
	MenuLook.fill(menu_chrome)
	menu_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_chrome.visible = false
	add_child(menu_chrome)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 58
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.02, 0.016, 0.039, 0.9)
	ts.border_color = MenuLook.LINE_SOFT
	ts.border_width_bottom = 1
	ts.content_margin_left = 26
	ts.content_margin_right = 26
	top.add_theme_stylebox_override("panel", ts)
	menu_chrome.add_child(top)

	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 18)
	top.add_child(th)

	var word := HBoxContainer.new()
	word.add_theme_constant_override("separation", 0)
	word.mouse_filter = Control.MOUSE_FILTER_STOP
	word.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	word.add_child(MenuLook.heading("ION", 18, MenuLook.INK))
	word.add_child(MenuLook.heading("STRIKERS", 18, MenuLook.CY))
	word.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			UiRoot.show("menu"))
	th.add_child(word)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(spacer)

	var live := _make_liveline()
	live_blip_chrome = live.get_node("Blip") as ColorRect
	th.add_child(live)

	var cs := Button.new()
	cs.text = " "
	var cs_s := MenuLook.box(MenuLook.GHOST_BG, MenuLook.LINE, 4)
	var cs_h := MenuLook.box(MenuLook.GHOST_BG, Color(MenuLook.CY, 0.45), 4)
	cs_s.content_margin_left = 14
	cs_s.content_margin_right = 14
	cs_s.content_margin_top = 7
	cs_s.content_margin_bottom = 7
	cs_h.content_margin_left = 14
	cs_h.content_margin_right = 14
	cs_h.content_margin_top = 7
	cs_h.content_margin_bottom = 7
	MenuLook.style_button(cs, cs_s, cs_h, Color(0, 0, 0, 0), MenuLook.FONT_HEADING, 14)
	cs.custom_minimum_size = Vector2(120, 42)
	var csv := VBoxContainer.new()
	csv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	csv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	csv.offset_left = 14
	csv.offset_right = -14
	csv.offset_top = 6
	csv.offset_bottom = -6
	csv.alignment = BoxContainer.ALIGNMENT_CENTER
	csv.add_theme_constant_override("separation", 2)
	var csl := MenuLook.kicker("Callsign", MenuLook.MUTE_3, 9)
	csl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	csv.add_child(csl)
	callsign_val = MenuLook.body("Guest", 14, MenuLook.INK)
	callsign_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	csv.add_child(callsign_val)
	cs.add_child(csv)
	cs.pressed.connect(func() -> void:
		callsign_input.text = _callsign
		_on_callsign_text_changed(callsign_input.text)
		UiRoot.show("callsign"))
	th.add_child(cs)

	var foot := PanelContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -44
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0)
	fs.border_color = MenuLook.LINE_SOFT
	fs.border_width_top = 1
	fs.content_margin_left = 26
	fs.content_margin_right = 26
	fs.content_margin_top = 14
	fs.content_margin_bottom = 14
	foot.add_theme_stylebox_override("panel", fs)
	menu_chrome.add_child(foot)
	var fh := HBoxContainer.new()
	foot.add_child(fh)
	fh.add_child(MenuLook.kicker("WASD move · SPACE jump · C crouch · Y chat · M team · F1 controls", MenuLook.MUTE_3, 10))
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(fsp)
	fh.add_child(MenuLook.kicker("Blue vs red", MenuLook.MUTE_3, 10))


func _make_liveline() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var blip := ColorRect.new()
	blip.name = "Blip"
	blip.custom_minimum_size = Vector2(6, 6)
	blip.color = MenuLook.CY
	blip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(blip)
	row.add_child(MenuLook.kicker("Local build", MenuLook.MUTE_2, 10))
	return row


func _add_back(parent: Control) -> Button:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_bottom", 14)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var b := Button.new()
	b.text = "◀  MAIN MENU"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	MenuLook.apply_ghost(b)
	wrap.add_child(b)
	parent.add_child(wrap)
	return b


func _make_big_card(kick: String, title: String, blurb: String, meta: String, red: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 148)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_card(btn, red, false)
	btn.add_child(MenuLook.wash_rect(red))
	var pad := MarginContainer.new()
	MenuLook.fill(pad)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 20)
	btn.add_child(pad)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	pad.add_child(v)
	v.add_child(MenuLook.kicker(kick))
	var t := MenuLook.heading(title, 26, MenuLook.INK)
	v.add_child(t)
	v.add_child(MenuLook.body(blurb, 13, MenuLook.MUTE, true))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var meta_l := MenuLook.kicker(meta, MenuLook.RD_SOFT if red else MenuLook.CY, 10)
	v.add_child(meta_l)
	btn.set_meta("meta_label", meta_l)
	btn.set_meta("red", red)
	btn.mouse_entered.connect(func() -> void: MenuLook.apply_card(btn, red, true))
	btn.mouse_exited.connect(func() -> void: MenuLook.apply_card(btn, red, false))
	return btn


func _make_tile(title: String, sub: String) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 64)
	MenuLook.apply_tile(btn)
	var pad := MarginContainer.new()
	MenuLook.fill(pad)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	btn.add_child(pad)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	pad.add_child(v)
	v.add_child(MenuLook.body(title, 16, MenuLook.INK))
	v.add_child(MenuLook.kicker(sub, MenuLook.MUTE_3, 10))
	return btn


func _make_opt(title: String, desc: String, id: String) -> Button:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 86)
	btn.set_meta("id", id)
	btn.set_meta("active", false)
	MenuLook.apply_opt(btn, false, "opt")
	var pad := MarginContainer.new()
	MenuLook.fill(pad)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 13)
	pad.add_theme_constant_override("margin_bottom", 13)
	btn.add_child(pad)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	pad.add_child(v)
	v.add_child(MenuLook.body(title.to_upper(), 15, MenuLook.INK))
	var d := MenuLook.mono(desc, 10, MenuLook.MUTE_3)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return btn


func _make_num(big: String, small: String, value: int) -> Button:
	var btn := Button.new()
	btn.set_meta("value", value)
	btn.set_meta("active", false)
	btn.custom_minimum_size = Vector2(0, 56)
	MenuLook.apply_opt(btn, false, "num")
	var pad := MarginContainer.new()
	MenuLook.fill(pad)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	btn.add_child(pad)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(v)
	var n := MenuLook.heading(big, 17, MenuLook.INK)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var s := MenuLook.mono(small.to_upper(), 9, MenuLook.MUTE_3)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	return btn


func _make_yn(text: String, is_yes: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(96, 42)
	btn.set_meta("yes", is_yes)
	btn.set_meta("active", false)
	MenuLook.apply_opt(btn, false, "yn")
	return btn


func _sec(text: String, no_top := false) -> MarginContainer:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 0 if no_top else 22)
	wrap.add_theme_constant_override("margin_bottom", 10)
	var l := MenuLook.kicker(text, MenuLook.MUTE_2, 10)
	l.name = "L"
	wrap.add_child(l)
	return wrap


func _kv(parent: VBoxContainer, k: String, v: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return _kv_into(row, k, v)


func _kv_into(row: HBoxContainer, k: String, v: String) -> Label:
	var ks := StyleBoxFlat.new()
	ks.bg_color = Color(0, 0, 0, 0)
	ks.border_color = MenuLook.LINE_SOFT
	ks.border_width_top = 1
	ks.content_margin_top = 7
	ks.content_margin_bottom = 7
	# Can't put style on HBox easily. Use a panel.
	var kl := MenuLook.kicker(k, MenuLook.MUTE_3, 10)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kl)
	var vl := MenuLook.kicker(v, MenuLook.INK_2, 10)
	row.add_child(vl)
	return vl


func _join_row(header: bool, cols: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 11)
	pad.add_theme_constant_override("margin_bottom", 11)
	pad.add_child(row)
	if header:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0)
		bg.border_color = MenuLook.LINE_SOFT
		bg.border_width_bottom = 1
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", bg)
		p.add_child(pad)
		_fill_join_cols(row, cols, true)
		return p
	_fill_join_cols(row, cols, false)
	return pad


func _fill_join_cols(row: HBoxContainer, cols: Array, header: bool) -> void:
	var weights := [2.0, 1.2, 0.8, 0.8, 1.0, 1.4]
	for i in cols.size():
		var l := MenuLook.kicker(str(cols[i]), MenuLook.MUTE_3 if header else MenuLook.INK, 9 if header else 13)
		if not header:
			l.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
			l.add_theme_color_override("font_color", MenuLook.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = weights[i] if i < weights.size() else 1.0
		row.add_child(l)


func _vol_row(parent: VBoxContainer, label: String, hint: String, value: float, on_change: Callable, min_v := 0.0, max_v := 100.0, step := 1.0) -> HSlider:
	var row := HBoxContainer.new()
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_top", 14)
	rm.add_child(row)
	parent.add_child(rm)
	var l := MenuLook.body(label, 14, MenuLook.INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var val := MenuLook.mono("%d%%" % int(value) if max_v == 100.0 and min_v == 0.0 else "%.2f" % (value / 20.0), 12, MenuLook.CY)
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


func _paint_opts(btns: Array[Button]) -> void:
	for b in btns:
		MenuLook.apply_opt(b, b.get_meta("active", false), "opt")


func _paint_nums(btns: Array[Button]) -> void:
	for b in btns:
		MenuLook.apply_opt(b, b.get_meta("active", false), "num")


func _paint_yn() -> void:
	if _bot_yes == null:
		return
	_bot_yes.set_meta("active", selected_bots)
	_bot_no.set_meta("active", not selected_bots)
	MenuLook.apply_opt(_bot_yes, selected_bots, "yn")
	MenuLook.apply_opt(_bot_no, not selected_bots, "yn")
	if _shoot_yes == null:
		return
	_shoot_yes.set_meta("active", selected_bots_shoot)
	_shoot_no.set_meta("active", not selected_bots_shoot)
	MenuLook.apply_opt(_shoot_yes, selected_bots_shoot, "yn")
	MenuLook.apply_opt(_shoot_no, not selected_bots_shoot, "yn")


func _exclusive(btns: Array[Button], picked: Button) -> void:
	for b in btns:
		b.set_meta("active", b == picked)


func _on_mode_picked(b: Button) -> void:
	selected_mode = str(b.get_meta("id"))
	_exclusive(_mode_btns, b)
	_paint_opts(_mode_btns)
	_refresh_brief()


func _on_hosting_picked(b: Button) -> void:
	if b.disabled:
		return
	selected_hosting = str(b.get_meta("id"))
	_exclusive(_hosting_btns, b)
	_paint_opts(_hosting_btns)
	_refresh_brief()


func _on_map_selected(index: int) -> void:
	var id := str(_map_select.get_item_metadata(index))
	if id != "parkour":
		for i in _map_select.item_count:
			if str(_map_select.get_item_metadata(i)) == "parkour":
				_map_select.select(i)
				id = "parkour"
				break
	selected_map = id
	_refresh_brief()


func _on_rounds_picked(b: Button) -> void:
	selected_rounds = int(b.get_meta("value"))
	_exclusive(_round_btns, b)
	_paint_nums(_round_btns)
	_refresh_brief()


func _on_kills_picked(b: Button) -> void:
	selected_kills = int(b.get_meta("value"))
	_exclusive(_kill_btns, b)
	_paint_nums(_kill_btns)
	_refresh_brief()


func _on_cap_picked(b: Button) -> void:
	selected_cap = int(b.get_meta("value"))
	_exclusive(_cap_btns, b)
	_paint_nums(_cap_btns)
	_refresh_brief()


func _on_spec_picked(b: Button) -> void:
	selected_spec = int(b.get_meta("value"))
	_exclusive(_spec_btns, b)
	_paint_nums(_spec_btns)
	_refresh_brief()


func _refresh_brief() -> void:
	var classic := selected_mode == "classic"
	var map_name := "Parkour Yard"
	for m in MAPS:
		if str(m["id"]) == selected_map:
			map_name = str(m["name"])
			break
	sum_mode.text = ("%s · %s" % ["Classic" if classic else "Deathmatch", map_name])
	sum_limit.text = ("first to %d" % selected_rounds) if classic else ("first to %d kills" % selected_kills)
	sum_cap.text = str(selected_cap)
	sum_spec.text = "+%d" % selected_spec
	brief_bots.text = "On" if selected_bots else "Off"
	brief_bots_shoot.text = "Yes" if selected_bots_shoot else "No"
	sum_total.text = "%d + %d = %d" % [selected_cap, selected_spec, selected_cap + selected_spec]
	rounds_label.text = ("ROUNDS TO WIN" if classic else "KILLS TO WIN")
	rounds_row.visible = classic
	kills_row.visible = not classic
	var show_dev := DevMode.active and selected_bots
	bots_dev_wrap.visible = show_dev
	brief_shoot_row.visible = show_dev
	if brief_host:
		brief_host.text = _callsign if not _callsign.is_empty() else "Guest"
	if sum_network:
		sum_network.text = "LAN" if selected_hosting == "lan" else "Hosted"


func _render_server_list() -> void:
	for c in server_list.get_children():
		c.queue_free()
	var empty := MenuLook.kicker("No lobbies — no Game Server in this build", MenuLook.MUTE_3, 11)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 26)
	pad.add_child(empty)
	server_list.add_child(pad)
	result_line.text = "NO RESULTS"


func _on_quick_join() -> void:
	result_line.text = "NO SERVER TO JOIN"
	launch_note.text = "No Game Server in this build."
	UiRoot.show("create")


func _on_launch() -> void:
	if selected_hosting != "lan":
		launch_note.text = "Hosted games need the Game API — not in this build."
		return
	if _connecting:
		return
	_connecting = true
	launch_note.text = "Starting local server..."

	_local_dedicated = LocalDedicated.new()
	var sname := server_in.text.strip_edges()
	var port := _local_dedicated.start(selected_map, sname)
	if port < 0:
		launch_note.text = "Failed to start the local server."
		_connecting = false
		return

	# Give the server a moment to bind before connecting.
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		_cleanup_launch()
		return

	launch_note.text = "Connecting..."
	_game_client = GameClient.new()
	add_child(_game_client)
	_game_client.connected_to_lobby.connect(_on_lobby_joined)
	_game_client.connection_failed.connect(_on_connect_failed)
	_game_client.connect_to_server("127.0.0.1", port, _callsign)


func _on_lobby_joined(init_data: Dictionary) -> void:
	_connecting = false
	AudioMix.fade_out_keep_place(500.0)

	# Remove client from this scene tree so the match scene can own it.
	if _game_client:
		remove_child(_game_client)

	var packed: PackedScene = load("res://scenes/match/match.tscn")
	var match_scene = packed.instantiate()
	match_scene.init_data = init_data
	match_scene.game_client = _game_client

	# Stash the launcher so the menu can kill the server when it comes back.
	match_scene.set_meta("_local_dedicated", _local_dedicated)

	get_tree().root.add_child(match_scene)
	get_tree().current_scene = match_scene
	queue_free()


func _on_connect_failed(reason: String) -> void:
	_connecting = false
	launch_note.text = reason
	_cleanup_launch()


func _cleanup_launch() -> void:
	if _game_client:
		_game_client.disconnect_from_server()
		if _game_client.is_inside_tree():
			_game_client.queue_free()
		_game_client = null
	if _local_dedicated:
		_local_dedicated.stop()
		_local_dedicated = null


func _on_callsign_go() -> void:
	var name_text := callsign_input.text.strip_edges()
	if name_text.length() < 3 or name_text.length() > 16:
		return
	_callsign = name_text
	_save_callsign()
	callsign_val.text = _callsign
	brief_host.text = _callsign
	UiRoot.show("menu")


func _on_callsign_text_changed(new_text: String) -> void:
	callsign_count.text = "%d/16" % new_text.length()
	callsign_go.disabled = new_text.strip_edges().length() < 3
	callsign_go.modulate.a = 0.35 if callsign_go.disabled else 1.0


func _on_designer_pressed() -> void:
	AudioMix.fade_out_keep_place(500.0)
	get_tree().change_scene_to_file("res://scenes/designer/designer.tscn")


func _on_reset_binds() -> void:
	InputBinds.reset_to_defaults()
	_rebuild_binds_ui()


func _load_callsign() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://player.cfg") == OK:
		_callsign = cfg.get_value("player", "callsign", "")
		callsign_input.text = _callsign
		_on_callsign_text_changed(_callsign)


func _save_callsign() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "callsign", _callsign)
	cfg.save("user://player.cfg")


func _load_input_settings() -> void:
	_settings_cfg.load("user://settings.cfg")
	invert_y = _settings_cfg.get_value("input", "invert_y", false)
	var sens: float = _settings_cfg.get_value("input", "sensitivity", 1.0)
	if sens <= 1.0 and _settings_cfg.get_value("input", "sensitivity", 1.0) == 0.15:
		sens = 1.0
	if invert_y_check:
		invert_y_check.button_pressed = invert_y
	if sens_slider:
		sens_slider.value = clampf(sens, 0.1, 5.0) * 20.0
		sens_val.text = "%.2f" % sens


func _save_input_settings() -> void:
	_settings_cfg.save("user://settings.cfg")


func _setup_settings_ui() -> void:
	master_slider.value = AudioMix.master_pct
	sfx_slider.value = AudioMix.sfx_pct
	music_slider.value = AudioMix.music_pct
	master_val.text = "%d%%" % AudioMix.master_pct
	sfx_val.text = "%d%%" % AudioMix.sfx_pct
	music_val.text = "%d%%" % AudioMix.music_pct
	var sens: float = _settings_cfg.get_value("input", "sensitivity", 1.0)
	if sens <= 0.2:
		sens = 1.0
	sens_slider.value = clampf(sens, 0.1, 5.0) * 20.0
	sens_val.text = "%.2f" % (sens_slider.value / 20.0)
	invert_y_check.button_pressed = invert_y


func _rebuild_binds_ui() -> void:
	for child in binds_container.get_children():
		child.queue_free()
	for group_data: Array in InputBinds.BIND_GROUPS:
		var group_name: String = group_data[0]
		var actions: Array = group_data[1]
		var header := MenuLook.kicker(group_name, MenuLook.CY if group_name != "Combat" else MenuLook.RD_SOFT, 10)
		var hm := MarginContainer.new()
		hm.add_theme_constant_override("margin_top", 20)
		hm.add_theme_constant_override("margin_bottom", 8)
		hm.add_child(header)
		binds_container.add_child(hm)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var h1 := MenuLook.kicker("", MenuLook.MUTE_3, 9)
		h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(h1)
		var p := MenuLook.kicker("Primary", MenuLook.MUTE_3, 9)
		p.custom_minimum_size.x = 96
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(p)
		var a := MenuLook.kicker("Alt", MenuLook.MUTE_3, 9)
		a.custom_minimum_size.x = 96
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(a)
		binds_container.add_child(head)
		for action_name: String in actions:
			binds_container.add_child(_bind_row(InputBinds.BIND_LABELS.get(action_name, action_name), action_name))


func _bind_row(label: String, action_name: String) -> Control:
	var wrap := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.043, 0.039, 0.086, 0.55)
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
		btn.custom_minimum_size = Vector2(96, 30)
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
	btn.text = "..."
	MenuLook.apply_bind_key(btn, false, true, false)


func _unhandled_key_input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_capture_bind_event(event)


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
	_rebuild_binds_ui()


func _input(event: InputEvent) -> void:
	if ConfirmPrompt.is_open():
		return
	if not _listening_action.is_empty() and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_capture_bind_event(mb)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if UiRoot.current_screen != "menu" and UiRoot.current_screen != "callsign":
			if not _listening_action.is_empty():
				_stop_listening()
			else:
				UiRoot.show("menu")
