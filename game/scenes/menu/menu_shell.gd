extends Control

const BUILTIN_MAPS: Array[Dictionary] = [
	{"id": "parkour", "name": "Parkour Yard", "desc": "Mirrored stairs & jump blocks. Movement + jump test bed."},
]

const MenuStage = preload("res://scenes/menu/menu_stage.gd")
const _GameApiClient = preload("res://net/game_api.gd")


# Built-in maps plus whatever .map files are sitting in maps/community. The
# community ones are imported to read their name, which also surfaces a broken
# map here in the lobby rather than at the start of a match.
static func map_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = BUILTIN_MAPS.duplicate()
	for id: String in MapCatalog.list_community():
		var level := MapCatalog.load_community(id)
		if not level.ok():
			continue
		out.append({
			"id": id,
			"name": level.name if level.name != "" else MapCatalog.display_name(id),
			"desc": "Community map · %d brushes · %d spawns" % [
				level.world.brush_count(), level.spawn_count()],
		})
	return out

var callsign_screen: Control
var home_screen: Control
var join_screen: Control
var create_screen: Control
var settings_screen: SettingsScreen
var menu_chrome: Control
var stage_glows: Control
var stage_host: SubViewportContainer
var _menu_stage
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
var brief_move_row: Control
var brief_host: Label
var sum_network: Label
var sum_mode: Label
var sum_limit: Label
var sum_cap: Label
var sum_spec: Label
var brief_bots: Label
var brief_bots_shoot: Label
var brief_bots_move: Label
var sum_total: Label
var server_in: LineEdit
var launch_note: Label
var _foot_binds: Label

var _callsign: String = ""
var _blip_t: float = 0.0

var selected_hosting: String = "hosted"
var selected_mode: String = "classic"
var selected_map: String = "parkour"
var selected_rounds: int = 10
var selected_kills: int = 50
var selected_cap: int = 12
var selected_spec: int = 12
var selected_bots: bool = true
var selected_bots_shoot: bool = true
var selected_bots_move: bool = true

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
var _move_yes: Button
var _move_no: Button
var _local_dedicated: LocalDedicated
var _game_client: GameClient
var _api
var _games: Array = []
var _list_gen: int = 0
var _connecting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_api = _GameApiClient.new()
	add_child(_api)
	UiRoot.register_screen("callsign", callsign_screen)
	UiRoot.register_screen("menu", home_screen)
	UiRoot.register_screen("settings", settings_screen)
	UiRoot.register_screen("join", join_screen)
	UiRoot.register_screen("create", create_screen)
	UiRoot.register_floating_layer("menuchrome", menu_chrome, ["menu", "join", "create", "settings"])
	UiRoot.screen_changed.connect(_on_screen_changed)

	_load_callsign()
	InputBinds.bindings_changed.connect(_refresh_bind_chrome)
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


func _on_screen_changed(screen_name: String) -> void:
	var on_home := screen_name == "menu"
	stage_glows.visible = on_home
	if stage_host:
		stage_host.visible = on_home
		var vp := stage_host.get_child(0) as SubViewport
		if vp:
			vp.render_target_update_mode = (
				SubViewport.UPDATE_ALWAYS if on_home else SubViewport.UPDATE_DISABLED)
	if _menu_stage:
		_menu_stage.set_active(on_home)
	if screen_name == "callsign":
		callsign_input.grab_focus()
	if screen_name == "settings":
		settings_screen.refresh()
	if screen_name == "join":
		_fetch_games()


func _build() -> void:
	add_child(MenuLook.shader_rect(MenuLook.SH_BG))

	_menu_stage = MenuStage.new()

	stage_glows = Control.new()
	stage_glows.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_glows.anchor_left = 0.50
	stage_glows.anchor_top = 0.22
	stage_glows.anchor_right = 1.0
	stage_glows.anchor_bottom = 0.96
	stage_glows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_glows.visible = false
	var glows := HBoxContainer.new()
	MenuLook.fill(glows)
	for team in _menu_stage.teams:
		glows.add_child(MenuLook.glow_rect(team == "red"))
	stage_glows.add_child(glows)
	add_child(stage_glows)

	stage_host = SubViewportContainer.new()
	stage_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_host.anchor_left = 0.50
	stage_host.anchor_top = 0.16
	stage_host.anchor_right = 1.0
	stage_host.anchor_bottom = 0.96
	stage_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_host.stretch = true
	stage_host.visible = false
	var stage_vp := SubViewport.new()
	stage_vp.transparent_bg = true
	stage_vp.own_world_3d = true
	stage_vp.msaa_3d = Viewport.MSAA_2X
	stage_vp.handle_input_locally = false
	stage_vp.gui_disable_input = true
	stage_vp.audio_listener_enable_3d = false
	stage_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage_vp.size = Vector2i(960, 860)
	stage_vp.add_child(_menu_stage)
	stage_host.add_child(stage_vp)
	add_child(stage_host)

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

	var join_btn := _make_big_card("Server browser", "JOIN LOBBY", "Live matches. You land in the stands and pick a side.", "BROWSE LIVE LOBBIES →", false)
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
	refresh.pressed.connect(_fetch_games)
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
	_hosting_btns[1].set_meta("active", true)
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
	var entries := map_entries()
	for i in entries.size():
		var m: Dictionary = entries[i]
		_map_select.add_item(str(m["name"]))
		_map_select.set_item_metadata(i, str(m["id"]))
		if i == 0:
			_map_select.select(i)
			selected_map = str(m["id"])
	_map_select.item_selected.connect(_on_map_selected)
	left.add_child(_map_select)
	var map_desc := MenuLook.mono(str(BUILTIN_MAPS[0]["desc"]), 10, MenuLook.MUTE_3)
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
	var dev_head := MarginContainer.new()
	dev_head.add_theme_constant_override("margin_top", 22)
	dev_head.add_theme_constant_override("margin_bottom", 10)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head_row.add_child(MenuLook.kicker("Bot behaviour"))
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
	dev_head.add_child(head_row)
	bots_dev_wrap.add_child(dev_head)

	# Two switches side by side: a bot that neither shoots nor moves is a
	# stationary target, and each half is useful on its own.
	var dev_toggles := HBoxContainer.new()
	dev_toggles.add_theme_constant_override("separation", 28)

	_shoot_yes = _make_yn("YES", true)
	_shoot_no = _make_yn("NO", false)
	_shoot_yes.pressed.connect(func() -> void: selected_bots_shoot = true; _paint_yn(); _refresh_brief())
	_shoot_no.pressed.connect(func() -> void: selected_bots_shoot = false; _paint_yn(); _refresh_brief())
	dev_toggles.add_child(_yn_group("Shoot back", _shoot_yes, _shoot_no))

	_move_yes = _make_yn("YES", true)
	_move_no = _make_yn("NO", false)
	_move_yes.pressed.connect(func() -> void: selected_bots_move = true; _paint_yn(); _refresh_brief())
	_move_no.pressed.connect(func() -> void: selected_bots_move = false; _paint_yn(); _refresh_brief())
	dev_toggles.add_child(_yn_group("Move", _move_yes, _move_no))

	bots_dev_wrap.add_child(dev_toggles)
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
	brief_move_row = HBoxContainer.new()
	bv.add_child(brief_move_row)
	brief_bots_move = _kv_into(brief_move_row, "Bots move", "Yes")
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
	settings_screen = SettingsScreen.new()
	settings_screen.close_requested.connect(func() -> void: UiRoot.show("menu"))
	add_child(settings_screen)


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
	fh.add_child(MenuLook.kicker(_footer_binds_text(), MenuLook.MUTE_3, 10))
	_foot_binds = fh.get_child(fh.get_child_count() - 1) as Label
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


## A captioned YES/NO pair, so several of them can sit in one row without the
## reader losing track of which switch is which.
func _yn_group(caption: String, yes_btn: Button, no_btn: Button) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(MenuLook.kicker(caption, MenuLook.MUTE_3, 9))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(yes_btn)
	row.add_child(no_btn)
	col.add_child(row)
	return col


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
	_move_yes.set_meta("active", selected_bots_move)
	_move_no.set_meta("active", not selected_bots_move)
	MenuLook.apply_opt(_move_yes, selected_bots_move, "yn")
	MenuLook.apply_opt(_move_no, not selected_bots_move, "yn")


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
	selected_map = str(_map_select.get_item_metadata(index))
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
	for m in map_entries():
		if str(m["id"]) == selected_map:
			map_name = str(m["name"])
			break
	sum_mode.text = ("%s · %s" % ["Classic" if classic else "Deathmatch", map_name])
	sum_limit.text = ("first to %d" % selected_rounds) if classic else ("first to %d kills" % selected_kills)
	sum_cap.text = str(selected_cap)
	sum_spec.text = "+%d" % selected_spec
	brief_bots.text = "On" if selected_bots else "Off"
	brief_bots_shoot.text = "Yes" if selected_bots_shoot else "No"
	brief_bots_move.text = "Yes" if selected_bots_move else "No"
	sum_total.text = "%d + %d = %d" % [selected_cap, selected_spec, selected_cap + selected_spec]
	rounds_label.text = ("ROUNDS TO WIN" if classic else "KILLS TO WIN")
	rounds_row.visible = classic
	kills_row.visible = not classic
	var show_dev := DevMode.active and selected_bots
	bots_dev_wrap.visible = show_dev
	brief_shoot_row.visible = show_dev
	brief_move_row.visible = show_dev
	if brief_host:
		brief_host.text = _callsign if not _callsign.is_empty() else "Guest"
	if sum_network:
		sum_network.text = "LAN" if selected_hosting == "lan" else "Hosted"


func _render_server_list() -> void:
	for c in server_list.get_children():
		c.queue_free()

	var shown := _filtered_games()
	if shown.is_empty():
		var empty := MenuLook.kicker(
			"No lobbies listed — host one, or check the Game API is running",
			MenuLook.MUTE_3, 11)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", 26)
		pad.add_theme_constant_override("margin_bottom", 26)
		pad.add_child(empty)
		server_list.add_child(pad)
		result_line.text = "NO RESULTS"
		return

	for game in shown:
		server_list.add_child(_make_lobby_row(game))
	result_line.text = "%d LOBBY" % shown.size() if shown.size() == 1 else "%d LOBBIES" % shown.size()


func _filtered_games() -> Array:
	var q := server_filter.text.strip_edges().to_lower() if server_filter else ""
	var out: Array = []
	for game in _games:
		if typeof(game) != TYPE_DICTIONARY:
			continue
		var g: Dictionary = game
		# Host process rows land here with an empty map; they are not lobbies.
		if str(g.get("map", "")).strip_edges().is_empty():
			continue
		if not q.is_empty():
			var hay := ("%s %s %s" % [
				str(g.get("name", "")),
				str(g.get("map", "")),
				str(g.get("mode", "")),
			]).to_lower()
			if hay.find(q) < 0:
				continue
		out.append(g)
	return out


func _make_lobby_row(game: Dictionary) -> Control:
	var name_text := str(game.get("name", "")).strip_edges()
	if name_text.is_empty():
		name_text = str(game.get("game_id", "lobby"))
	var mode_text := "Classic" if str(game.get("mode", "")) != "dm" else "Deathmatch"
	var players := "%d/%d" % [int(game.get("humans", 0)), int(game.get("max", 0))]
	var specs := "%d/%d" % [int(game.get("spectators", 0)), int(game.get("spec_max", 0))]
	var row := _join_row(false, [
		name_text,
		_map_label(str(game.get("map", ""))),
		mode_text,
		players,
		specs,
	])
	var inner := row.get_child(0) as HBoxContainer
	if inner:
		var join := Button.new()
		join.text = "JOIN"
		join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		join.size_flags_stretch_ratio = 1.4
		MenuLook.apply_ghost(join, 10)
		join.pressed.connect(_on_join_game.bind(str(game.get("game_id", ""))))
		inner.add_child(join)
	return row


func _map_label(map_id: String) -> String:
	# map_entries() rather than the built-in list, so a hosted game running a
	# community map shows its name instead of its raw id.
	for m in map_entries():
		if str(m["id"]) == map_id:
			return str(m["name"])
	if MapCatalog.is_community(map_id):
		return MapCatalog.display_name(map_id)
	return map_id if not map_id.is_empty() else "—"


func _fetch_games() -> void:
	_list_gen += 1
	var gen := _list_gen
	result_line.text = "LOADING…"
	var res: Dictionary = await _api.list_games()
	if gen != _list_gen or not is_inside_tree():
		return
	if not res.get("ok", false):
		_games = []
		_render_server_list()
		result_line.text = str(res.get("error", "Could not list lobbies."))
		return
	var games = res.get("games", [])
	_games = games if games is Array else []
	_render_server_list()
	if join_meta:
		var n: int = _games.size()
		join_meta.text = ("1 LIVE LOBBY →" if n == 1 else "%d LIVE LOBBIES →" % n) if n > 0 else "BROWSE LIVE LOBBIES →"


func _on_quick_join() -> void:
	var shown := _filtered_games()
	for game in shown:
		if not _lobby_joinable(game):
			continue
		_on_join_game(str(game.get("game_id", "")))
		return
	result_line.text = "NO SERVER TO JOIN"
	UiRoot.show("create")


func _lobby_joinable(game: Dictionary) -> bool:
	var humans := int(game.get("humans", 0))
	var cap := int(game.get("max", 0)) + int(game.get("spec_max", 0))
	return cap <= 0 or humans < cap


func _on_join_game(game_id: String) -> void:
	if game_id.is_empty() or _connecting:
		return
	_connecting = true
	result_line.text = "JOINING…"
	var res: Dictionary = await _api.join_game(game_id)
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		_connecting = false
		result_line.text = str(res.get("error", "Join failed."))
		return
	_connect_hosted(res)


func _on_launch() -> void:
	if _connecting:
		return
	if selected_hosting == "hosted":
		await _launch_hosted()
		return
	_connecting = true
	launch_note.text = "Starting local server..."

	_local_dedicated = LocalDedicated.new()
	var port := _local_dedicated.start()
	if port < 0:
		launch_note.text = "Failed to start the local server."
		_connecting = false
		return

	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		_cleanup_launch()
		return

	launch_note.text = "Connecting..."
	_game_client = GameClient.new()
	_game_client.set_create_settings(_create_settings())
	add_child(_game_client)
	_game_client.connected_to_lobby.connect(_on_lobby_joined)
	_game_client.connection_failed.connect(_on_connect_failed)
	_game_client.connect_to_server("127.0.0.1", port, _callsign)


func _launch_hosted() -> void:
	_connecting = true
	launch_note.text = "Creating lobby..."
	var res: Dictionary = await _api.create_game(_create_settings())
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		_connecting = false
		launch_note.text = str(res.get("error", "Create failed."))
		return
	launch_note.text = "Connecting..."
	_connect_hosted(res)


func _create_settings() -> Dictionary:
	return {
		"map": selected_map,
		"mode": selected_mode,
		"rounds": selected_rounds,
		"kills": selected_kills,
		"max_players": selected_cap,
		"max_spectators": selected_spec,
		"bots": selected_bots,
		"bots_shoot": selected_bots_shoot,
		"bots_move": selected_bots_move,
		"display_name": server_in.text.strip_edges(),
	}


func _connect_hosted(info: Dictionary) -> void:
	var token: Variant = info.get("join_token", {})
	if typeof(token) != TYPE_DICTIONARY or (token as Dictionary).is_empty():
		_connecting = false
		launch_note.text = "Game API returned no join token."
		result_line.text = launch_note.text
		return
	_game_client = GameClient.new()
	_game_client.set_join_auth(token)
	add_child(_game_client)
	_game_client.connected_to_lobby.connect(_on_lobby_joined)
	_game_client.connection_failed.connect(_on_connect_failed)
	_game_client.connect_to_server(str(info.get("host", "127.0.0.1")), int(info.get("port", 7777)), _callsign)


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
	match_scene.local_callsign = _callsign

	# Stash the launcher so the menu can kill the server when it comes back.
	match_scene.set_meta("_local_dedicated", _local_dedicated)

	get_tree().root.add_child(match_scene)
	get_tree().current_scene = match_scene
	queue_free()


func _on_connect_failed(reason: String) -> void:
	_connecting = false
	launch_note.text = reason
	if result_line:
		result_line.text = reason
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


func _footer_binds_text() -> String:
	return "%s move · %s jump · %s crouch · %s chat · %s team · %s controls" % [
		"WASD",
		InputBinds.primary("jump").to_upper(),
		InputBinds.primary("crouch").to_upper(),
		InputBinds.primary("chat_all").to_upper(),
		InputBinds.primary("team_menu").to_upper(),
		InputBinds.primary("controls").to_upper(),
	]


func _refresh_bind_chrome() -> void:
	if _foot_binds:
		_foot_binds.text = _footer_binds_text()


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


func _input(event: InputEvent) -> void:
	if ConfirmPrompt.is_open():
		return
	if GameConsole.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		if UiRoot.current_screen != "menu" and UiRoot.current_screen != "callsign":
			if settings_screen.is_listening():
				settings_screen.cancel_listening()
			else:
				UiRoot.show("menu")
