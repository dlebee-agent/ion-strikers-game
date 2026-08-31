class_name MatchHud
extends CanvasLayer

var _root: Control
var _score_bar: ScoreBar
var _combat_wrap: Control
var _hp_bar: ProgressBar
var _hp_label: Label
var _hp_tag: Label
var _hp_status: Label
var _hp_fill: StyleBoxFlat
var _crosshair: Label
var _kill_feed: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _round_end: RoundEndOverlay
var _special_box: PanelContainer
var _special_box_style: StyleBoxFlat
var _special_tag: Label
var _special_status: Label
var _special_pips: Array[Panel] = []
var _special_pip_styles: Array[StyleBoxFlat] = []
var _special_pip_flash: Array[float] = []
var _special_ready_tween: Tween
var _spec_armed := false
var _spec_charging := false
var _spec_charge := 0.0
var _spec_releasable := false
var _spec_streak := 0
var _spec_glow_t := 0.0
var _spec_last_filled := -1
var _meteor_warn: Label
var _chat_log: VBoxContainer
var _chat_wrap: Control
var _chat_input: LineEdit
var _chat_bar: PanelContainer
var _chat_mode_style: StyleBoxFlat
var _chat_mode_label: Label
var _chat_tab_hint: Label
var _scoreboard: Scoreboard
var _match_over: MatchOverOverlay
var _controls_card: ControlsCard
var _settings_screen: SettingsScreen
var _hint: Label
var _leave_btn: Button
var _team_btn: Button
var _keys_btn: Button
var _settings_btn: Button

var _spec_panel: PanelContainer
var _spec_who: Label
var _spec_sub: Label

var _banner_tween: Tween
var _is_in_stands: bool = true
var _local_team: int = Protocol.TEAM_NONE
var _scoreboard_visible: bool = false
var _scoreboard_pinned: bool = false
var _match_over_active: bool = false
var _chat_open: bool = false
var _chat_team_only: bool = false

signal leave_requested
signal lobby_requested
signal team_menu_requested
signal controls_requested
signal settings_requested
signal chat_submitted(text: String, team_only: bool)

const KILL_FEED_MAX := 6
const KILL_FEED_LIFETIME := 5.0
const BANNER_DURATION := 2.5
const CHAT_LOG_MAX := 6
const CHAT_LOG_MAX_END := 12
const CHAT_TTL := 14.0
const CHAT_BODY := Color("#f5f8ff")
const CHAT_BODY_GLOW := Color(0.78, 0.90, 1.0, 0.30)

const BLUE := Color("#4ea8f5")
const RED := Color("#f54e5e")
const WHITE := Color("#e9edf6")
const MUTE := Color("#6d7d9c")
const GREEN := Color("#35ff9e")
const YELLOW := Color("#ffe066")
const CYAN := Color("#5ce1f5")
const KILL_GOLD := Color("#ffcf3a")
const KILL_METEOR := Color("#ff8a3a")
const KILL_VOID := Color("#9a7fe0")
const KILL_WEAPON := Color("#9aa6c2")
const KILL_BLUE := Color("#5b9bff")
const KILL_RED := Color("#ff6b74")
const PIP_EMPTY := Color(0.10, 0.12, 0.16, 0.92)
const PIP_EMPTY_BORDER := Color(0.30, 0.36, 0.44, 0.45)
const PIP_HOT := Color(0.82, 0.99, 1.0)
const BAR_EMPTY := Color(0.14, 0.16, 0.20, 0.9)
const SPECIAL_PIP_COUNT := MatchState.SPECIAL_STREAK
const HP_CRITICAL := 35
const HP_WOUNDED := 60


func _init() -> void:
	layer = 10


func _ready() -> void:
	add_to_group("match_huds")
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_score()
	_build_combat()
	_build_crosshair()
	_build_kill_feed()
	_build_banner()
	_build_meteor_warn()
	_build_chat()
	_build_scoreboard()
	_build_match_over()
	_build_controls()
	_build_spec_panel()
	_build_round_end()
	_scoreboard.move_to_front()
	_chat_wrap.move_to_front()
	_controls_card.move_to_front()


func _build_score() -> void:
	_score_bar = ScoreBar.new()
	_score_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_bar.position = Vector2(-ScoreBar.BAR_W * 0.5, 10)
	_root.add_child(_score_bar)


func _build_combat() -> void:
	_combat_wrap = VBoxContainer.new()
	_combat_wrap.anchor_left = 0.0
	_combat_wrap.anchor_top = 1.0
	_combat_wrap.anchor_right = 0.0
	_combat_wrap.anchor_bottom = 1.0
	_combat_wrap.offset_left = 22.0
	_combat_wrap.offset_top = -188.0
	_combat_wrap.offset_right = 300.0
	_combat_wrap.offset_bottom = -36.0
	_combat_wrap.alignment = BoxContainer.ALIGNMENT_END
	_combat_wrap.add_theme_constant_override("separation", 8)
	_combat_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_combat_wrap)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_wrap.add_child(hp_row)

	_hp_label = _label("100", 52, CYAN)
	if MenuLook:
		_hp_label.add_theme_font_override("font", MenuLook.FONT_HEADING)
	_hp_label.add_theme_constant_override("outline_size", 6)
	_hp_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.75))
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_row.add_child(_hp_label)

	var hp_meta := VBoxContainer.new()
	hp_meta.alignment = BoxContainer.ALIGNMENT_CENTER
	hp_meta.add_theme_constant_override("separation", -2)
	hp_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_meta)

	_hp_tag = _label("HP", 11, MUTE)
	if MenuLook:
		_hp_tag.add_theme_font_override("font", MenuLook.FONT_MONO)
	hp_meta.add_child(_hp_tag)

	_hp_status = _label("STABLE", 11, MUTE)
	if MenuLook:
		_hp_status.add_theme_font_override("font", MenuLook.FONT_MONO)
	hp_meta.add_child(_hp_status)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(220, 7)
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = BAR_EMPTY
	bar_bg.set_corner_radius_all(1)
	_hp_bar.add_theme_stylebox_override("background", bar_bg)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = CYAN
	_hp_fill.set_corner_radius_all(1)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	_combat_wrap.add_child(_hp_bar)

	_special_box = PanelContainer.new()
	_special_box.custom_minimum_size = Vector2(220, 42)
	_special_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_special_box_style = StyleBoxFlat.new()
	_special_box_style.bg_color = Color(0.04, 0.05, 0.08, 0.55)
	_special_box_style.border_color = Color(MUTE, 0.4)
	_special_box_style.set_border_width_all(1)
	_special_box_style.set_corner_radius_all(2)
	_special_box_style.content_margin_left = 10
	_special_box_style.content_margin_right = 10
	_special_box_style.content_margin_top = 6
	_special_box_style.content_margin_bottom = 7
	_special_box.add_theme_stylebox_override("panel", _special_box_style)
	_combat_wrap.add_child(_special_box)

	var special_col := VBoxContainer.new()
	special_col.add_theme_constant_override("separation", 5)
	special_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_special_box.add_child(special_col)

	var special_inner := HBoxContainer.new()
	special_inner.add_theme_constant_override("separation", 12)
	special_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	special_col.add_child(special_inner)

	_special_tag = _label("SPECIAL", 10, MUTE)
	if MenuLook:
		_special_tag.add_theme_font_override("font", MenuLook.FONT_MONO)
	_special_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	special_inner.add_child(_special_tag)

	_special_status = _label("0/%d" % SPECIAL_PIP_COUNT, 14, MUTE)
	if MenuLook:
		_special_status.add_theme_font_override("font", MenuLook.FONT_HEADING)
	_special_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	special_inner.add_child(_special_status)

	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	special_col.add_child(pips)

	for _i in SPECIAL_PIP_COUNT:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(0, 9)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = PIP_EMPTY
		st.border_color = PIP_EMPTY_BORDER
		st.set_border_width_all(1)
		st.set_corner_radius_all(1)
		pip.add_theme_stylebox_override("panel", st)
		pips.add_child(pip)
		_special_pips.append(pip)
		_special_pip_styles.append(st)
		_special_pip_flash.append(0.0)

	set_special(false)
	_combat_wrap.visible = false
	set_process(false)


func _build_crosshair() -> void:
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 24)
	_crosshair.add_theme_color_override("font_color", Color(0.6, 1.0, 1.0, 0.7))
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)


func _build_kill_feed() -> void:
	_kill_feed = VBoxContainer.new()
	_kill_feed.anchor_left = 1.0
	_kill_feed.anchor_top = 0.0
	_kill_feed.anchor_right = 1.0
	_kill_feed.anchor_bottom = 0.0
	_kill_feed.offset_left = -460
	_kill_feed.offset_top = 56
	_kill_feed.offset_right = -16
	_kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_kill_feed.add_theme_constant_override("separation", 5)
	_kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_kill_feed)


func _build_banner() -> void:
	var wrap := VBoxContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	wrap.position.y = -60
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wrap)

	_banner = _label("", 32, WHITE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	wrap.add_child(_banner)

	_banner_sub = _label("", 14, MUTE)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.visible = false
	wrap.add_child(_banner_sub)


func _build_round_end() -> void:
	_round_end = RoundEndOverlay.new()
	_root.add_child(_round_end)


func _build_match_over() -> void:
	_match_over = MatchOverOverlay.new()
	_root.add_child(_match_over)
	_match_over.lobby_requested.connect(func() -> void: lobby_requested.emit())


func _build_meteor_warn() -> void:
	_meteor_warn = _label("METEOR INCOMING", 18, RED)
	_meteor_warn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_meteor_warn.position.y = 40
	_meteor_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meteor_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meteor_warn.visible = false
	_root.add_child(_meteor_warn)


func _build_chat() -> void:
	_chat_wrap = VBoxContainer.new()
	_chat_wrap.anchor_left = 0.0
	_chat_wrap.anchor_top = 1.0
	_chat_wrap.anchor_right = 0.0
	_chat_wrap.anchor_bottom = 1.0
	_chat_wrap.offset_left = 20.0
	_chat_wrap.offset_top = -280.0
	_chat_wrap.offset_right = 440.0
	_chat_wrap.offset_bottom = -36.0
	_chat_wrap.alignment = BoxContainer.ALIGNMENT_END
	_chat_wrap.add_theme_constant_override("separation", 6)
	_chat_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_wrap.clip_contents = true
	_root.add_child(_chat_wrap)

	_chat_log = VBoxContainer.new()
	_chat_log.add_theme_constant_override("separation", 3)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.alignment = BoxContainer.ALIGNMENT_END
	_chat_log.clip_contents = true
	_chat_wrap.add_child(_chat_log)

	_chat_bar = PanelContainer.new()
	_chat_bar.custom_minimum_size = Vector2(0, 32)
	_chat_bar.visible = false
	_chat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_st := StyleBoxFlat.new()
	bar_st.bg_color = Color(0.039, 0.043, 0.078, 0.92)
	bar_st.border_color = CYAN
	bar_st.set_border_width_all(1)
	bar_st.set_corner_radius_all(2)
	bar_st.content_margin_left = 6
	bar_st.content_margin_right = 8
	bar_st.content_margin_top = 4
	bar_st.content_margin_bottom = 4
	_chat_bar.add_theme_stylebox_override("panel", bar_st)
	_chat_wrap.add_child(_chat_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_chat_bar.add_child(row)

	var mode := PanelContainer.new()
	_chat_mode_style = StyleBoxFlat.new()
	_chat_mode_style.bg_color = CYAN
	_chat_mode_style.set_corner_radius_all(2)
	_chat_mode_style.content_margin_left = 6
	_chat_mode_style.content_margin_right = 6
	_chat_mode_style.content_margin_top = 2
	_chat_mode_style.content_margin_bottom = 2
	mode.add_theme_stylebox_override("panel", _chat_mode_style)
	mode.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mode)

	_chat_mode_label = _label("ALL", 10, Color("#04121a"))
	if MenuLook:
		_chat_mode_label.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	mode.add_child(_chat_mode_label)

	_chat_input = LineEdit.new()
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.max_length = 50
	_chat_input.caret_blink = true
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_right = 2
	_chat_input.add_theme_stylebox_override("normal", empty)
	_chat_input.add_theme_stylebox_override("focus", empty)
	_chat_input.add_theme_stylebox_override("read_only", empty)
	_chat_input.add_theme_color_override("font_color", CHAT_BODY)
	_chat_input.add_theme_color_override("caret_color", CYAN)
	_chat_input.add_theme_color_override("font_placeholder_color", MUTE)
	if MenuLook:
		_chat_input.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	_chat_input.add_theme_font_size_override("font_size", 13)
	row.add_child(_chat_input)
	_chat_input.text_submitted.connect(_on_chat_submit)
	_chat_input.gui_input.connect(_on_chat_input_gui)

	_chat_tab_hint = _label("TAB = TEAM", 9, MUTE)
	_chat_tab_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_chat_tab_hint)


func _build_scoreboard() -> void:
	_scoreboard = Scoreboard.new()
	_root.add_child(_scoreboard)


func _build_controls() -> void:
	_hint = _label(_hint_text(), 11, Color(0.4, 0.5, 0.6, 0.5))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(20, -24)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)

	_leave_btn = Button.new()
	_leave_btn.text = "LEAVE"
	_leave_btn.custom_minimum_size = Vector2(80, 36)
	_leave_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_leave_btn.position = Vector2(-100, 16)
	_leave_btn.pressed.connect(func() -> void: leave_requested.emit())
	_leave_btn.visible = false
	_root.add_child(_leave_btn)

	_team_btn = Button.new()
	_team_btn.text = "TEAM"
	_team_btn.custom_minimum_size = Vector2(80, 36)
	_team_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_team_btn.position = Vector2(-190, 16)
	_team_btn.pressed.connect(func() -> void: team_menu_requested.emit())
	_team_btn.visible = false
	_root.add_child(_team_btn)

	_keys_btn = Button.new()
	_keys_btn.text = "KEYS"
	_keys_btn.tooltip_text = "Controls (%s)" % InputBinds.fmt("controls")
	_keys_btn.custom_minimum_size = Vector2(80, 36)
	_keys_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_keys_btn.position = Vector2(-280, 16)
	_keys_btn.pressed.connect(func() -> void: controls_requested.emit())
	_keys_btn.visible = false
	_root.add_child(_keys_btn)

	_settings_btn = Button.new()
	_settings_btn.text = "SETTINGS"
	_settings_btn.tooltip_text = "Volume · mouse · rebind keys"
	_settings_btn.custom_minimum_size = Vector2(110, 36)
	_settings_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_btn.position = Vector2(-400, 16)
	_settings_btn.pressed.connect(func() -> void: settings_requested.emit())
	_settings_btn.visible = false
	_root.add_child(_settings_btn)

	_controls_card = ControlsCard.new()
	_root.add_child(_controls_card)

	# Sits beside _root rather than inside it, so opening settings can hide the
	# whole HUD without hiding the settings page along with it.
	_settings_screen = SettingsScreen.new("◀  RESUME", true)
	_settings_screen.close_requested.connect(func() -> void: settings_requested.emit())
	add_child(_settings_screen)

	if InputBinds:
		InputBinds.bindings_changed.connect(_on_bindings_changed)


func _build_spec_panel() -> void:
	_spec_panel = PanelContainer.new()
	_spec_panel.anchor_left = 0.5
	_spec_panel.anchor_right = 0.5
	_spec_panel.anchor_top = 1.0
	_spec_panel.anchor_bottom = 1.0
	_spec_panel.offset_left = -160.0
	_spec_panel.offset_right = 160.0
	_spec_panel.offset_top = -130.0
	_spec_panel.offset_bottom = -70.0
	_spec_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.016, 0.031, 0.055, 0.6)
	st.set_corner_radius_all(10)
	st.border_color = Color(0.133, 0.2, 0.2, 1.0)
	st.set_border_width_all(1)
	st.content_margin_left = 20
	st.content_margin_right = 20
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	_spec_panel.add_theme_stylebox_override("panel", st)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spec_panel.add_child(col)

	var header := _label("SPECTATING", 11, Color(1.0, 1.0, 1.0, 0.55))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if MenuLook:
		header.add_theme_font_override("font", MenuLook.FONT_MONO)
	col.add_child(header)

	_spec_who = _label("", 19, Color("#8fd6ff"))
	if MenuLook:
		_spec_who.add_theme_font_override("font", MenuLook.FONT_HEADING)
	_spec_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_spec_who)

	_spec_sub = _label("", 11, Color(1.0, 1.0, 1.0, 0.55))
	_spec_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_spec_sub)

	_spec_panel.visible = false
	_root.add_child(_spec_panel)


# ── Public API ───────────────────────────────────────────────────────────

func update_score(blue: int, red: int, round_num: int, mode: String, kill_target: int,
		round_state: int, win_rounds: int = 10,
		blue_alive: int = 0, red_alive: int = 0, clock: String = "") -> void:
	_score_bar.set_scores(blue, red)
	_score_bar.set_alive(blue_alive, red_alive, mode == "classic")

	if mode == "dm":
		_score_bar.set_center("DEATHMATCH", clock, "FIRST TO %d" % kill_target)
		return

	var top := "ROUND %d" % round_num
	if round_state == Protocol.RS_OVER:
		top = "MATCH OVER"
	elif round_state == Protocol.RS_ENDED:
		top = "ROUND END"
	_score_bar.set_center(top, clock, "FIRST TO %d" % win_rounds)


func update_hp(hp: int) -> void:
	hp = maxi(0, hp)
	_hp_bar.value = hp
	_hp_label.text = str(hp)
	var col := CYAN
	var status := "STABLE"
	if hp <= 0:
		col = RED
		status = "DOWN"
	elif hp <= HP_CRITICAL:
		col = RED
		status = "CRITICAL"
	elif hp <= HP_WOUNDED:
		col = YELLOW
		status = "WOUNDED"
	_hp_label.add_theme_color_override("font_color", col)
	_hp_fill.bg_color = col
	_hp_status.text = status


func set_stands_mode(in_stands: bool, team: int = -1) -> void:
	_is_in_stands = in_stands
	if team >= 0:
		_local_team = team
	_layout_chat()
	if _chat_open:
		_sync_chat_bar()
	if _match_over_active:
		_combat_wrap.visible = false
		_crosshair.visible = false
		return
	_combat_wrap.visible = not in_stands
	_crosshair.visible = not in_stands


func show_spectator_panel(who: String, sub: String, color: Color = Color("#8fd6ff")) -> void:
	if not _spec_panel:
		return
	_spec_who.text = who
	_spec_who.add_theme_color_override("font_color", color)
	_spec_sub.text = sub
	_spec_panel.visible = true


func hide_spectator_panel() -> void:
	if _spec_panel:
		_spec_panel.visible = false


func set_spectate_crosshair(vis: bool) -> void:
	_crosshair.visible = vis


func show_kill(killer_name: String, victim_name: String, cause: int, head: bool,
		killer_team: int = 0, victim_team: int = 0, involved: bool = false) -> void:
	var row := _make_kill_row(killer_name, victim_name, cause, head, killer_team, victim_team, involved)
	_kill_feed.add_child(row)

	if _kill_feed.get_child_count() > KILL_FEED_MAX:
		var old := _kill_feed.get_child(0)
		_kill_feed.remove_child(old)
		old.queue_free()

	var tw := create_tween()
	tw.tween_interval(KILL_FEED_LIFETIME)
	tw.tween_property(row, "modulate:a", 0.0, 0.45)
	tw.tween_callback(row.queue_free)


func show_banner(text: String, color: Color = WHITE, sub: String = "") -> void:
	if _round_end and _round_end.is_showing():
		return
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner.modulate.a = 1.0

	if not sub.is_empty():
		_banner_sub.text = sub
		_banner_sub.visible = true
		_banner_sub.modulate.a = 1.0
	else:
		_banner_sub.visible = false

	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_DURATION)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	if _banner_sub.visible:
		_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(func() -> void:
		_banner.visible = false
		_banner_sub.visible = false)


func hide_banner() -> void:
	if _banner_tween:
		_banner_tween.kill()
		_banner_tween = null
	_banner.visible = false
	_banner_sub.visible = false
	_banner.modulate.a = 1.0
	_banner_sub.modulate.a = 1.0


func show_round_end(winner: int, score_blue: int, score_red: int, round_num: int, match_over: bool) -> void:
	hide_banner()
	_round_end.present(winner, score_blue, score_red, round_num, match_over)
	_round_end.move_to_front()
	if _chat_wrap:
		_chat_wrap.move_to_front()


func hide_round_end() -> void:
	_round_end.dismiss()


func is_round_end_visible() -> bool:
	return _round_end.is_showing()


func present_match_over(winner: int, score_blue: int, score_red: int, mode: String) -> void:
	_match_over_active = true
	_scoreboard_pinned = true
	hide_banner()
	hide_spectator_panel()
	_combat_wrap.visible = false
	_crosshair.visible = false
	_kill_feed.visible = false
	_score_bar.visible = false
	_hint.visible = false
	_meteor_warn.visible = false
	_layout_chat()
	show_cursor_controls(false)
	if _controls_card.is_open():
		_controls_card.dismiss()
	_match_over.present(winner, score_blue, score_red, mode)
	set_scoreboard_visible(true)
	_scoreboard.set_post_match(true)
	# Dim behind the table, fanfare above it, chat always on top so Y/U still work.
	_match_over.move_to_front()
	_scoreboard.move_to_front()
	if _round_end.is_showing():
		_round_end.move_to_front()
	if _chat_wrap:
		_chat_wrap.move_to_front()


func is_match_over() -> bool:
	return _match_over_active


func set_special(armed: bool, charging: bool = false, charge: float = 0.0,
		releasable: bool = false, streak: int = 0) -> void:
	var was_armed := _spec_armed and not _spec_charging
	_spec_armed = armed
	_spec_charging = charging
	_spec_charge = charge
	_spec_releasable = releasable
	_spec_streak = maxi(streak, 0)
	if armed and not charging and not was_armed:
		_spec_glow_t = 0.2
	_apply_special_visuals()
	_set_ready_pulse(armed and not charging)
	set_process(_wants_special_anim())


func show_meteor_warning(show: bool) -> void:
	if _match_over_active:
		show = false
	_meteor_warn.visible = show


func add_chat_message(name_text: String, text: String, team: int, team_only: bool, sys: bool) -> void:
	var accent := _chat_accent(team, team_only, sys)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(3, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.color = _chat_shiny(accent)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	if team_only and not sys:
		row.add_child(_chat_chip("TEAM", _chat_shiny(accent)))

	if sys:
		var body := _chat_sys_line(text)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(body)
	else:
		var who := _chat_name_line("%s:" % name_text, accent)
		row.add_child(who)
		var body := _chat_body_line(text)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(body)

	_chat_log.add_child(row)
	_trim_chat_log()
	if not _match_over_active:
		var tw := create_tween()
		tw.tween_interval(CHAT_TTL)
		tw.tween_callback(_expire_chat_row.bind(row))


func open_chat(team_only: bool) -> void:
	_chat_open = true
	_chat_team_only = team_only
	_sync_chat_bar()
	_chat_bar.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_chat() -> void:
	_chat_open = false
	_chat_bar.visible = false
	_chat_input.release_focus()


func is_chat_open() -> bool:
	return _chat_open


func show_cursor_controls(vis: bool) -> void:
	if _match_over_active:
		vis = false
	_leave_btn.visible = vis
	_team_btn.visible = vis
	_keys_btn.visible = vis
	_settings_btn.visible = vis


func toggle_controls_card() -> void:
	if _controls_card.is_open():
		dismiss_controls_card()
	else:
		present_controls_card()


func present_controls_card() -> void:
	_controls_card.present()
	show_cursor_controls(true)


func dismiss_controls_card() -> void:
	_controls_card.dismiss()


func is_controls_visible() -> bool:
	return _controls_card.is_open()


func present_settings() -> void:
	_controls_card.dismiss()
	_settings_screen.refresh()
	_settings_screen.visible = true
	_root.visible = false


func dismiss_settings() -> void:
	_settings_screen.cancel_listening()
	_settings_screen.visible = false
	_root.visible = true
	show_cursor_controls(true)


func is_settings_open() -> bool:
	return _settings_screen.visible


func is_settings_listening_bind() -> bool:
	return _settings_screen.is_listening()


func _hint_text() -> String:
	if not InputBinds:
		return "ESC cursor · M team · Y chat · TAB score · H controls"
	return "ESC cursor · %s team · %s chat · %s score · %s controls" % [
		InputBinds.primary("team_menu").to_upper(),
		InputBinds.primary("chat_all").to_upper(),
		InputBinds.primary("scoreboard").to_upper(),
		InputBinds.primary("controls").to_upper(),
	]


func _on_bindings_changed() -> void:
	if _hint:
		_hint.text = _hint_text()
	if _keys_btn:
		_keys_btn.tooltip_text = "Controls (%s)" % InputBinds.fmt("controls")
	if _controls_card and _controls_card.is_open():
		_controls_card.present()


func update_scoreboard(info: Dictionary, players: Array) -> void:
	_scoreboard.update_data(info, players)


func set_scoreboard_visible(vis: bool) -> void:
	if _scoreboard_pinned:
		vis = true
	_scoreboard_visible = vis
	_scoreboard.visible = vis


func is_scoreboard_visible() -> bool:
	return _scoreboard_visible


# ── Internal ─────────────────────────────────────────────────────────────

func _on_chat_submit(text: String) -> void:
	if text.strip_edges().is_empty():
		close_chat()
		return
	chat_submitted.emit(text.strip_edges(), _chat_team_only)
	close_chat()


func _on_chat_input_gui(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_TAB:
			_chat_team_only = not _chat_team_only
			_sync_chat_bar()
			_chat_input.accept_event()


func _sync_chat_bar() -> void:
	_chat_mode_label.text = "TEAM" if _chat_team_only else "ALL"
	_chat_tab_hint.text = "TAB = ALL" if _chat_team_only else "TAB = TEAM"
	var chip := _chat_team_color(_local_team)
	_chat_mode_style.bg_color = chip
	_chat_mode_label.add_theme_color_override("font_color", Color("#04121a"))


func _layout_chat() -> void:
	if not _chat_wrap:
		return
	var above_combat := not _is_in_stands and not _match_over_active
	_chat_wrap.offset_bottom = -188.0 if above_combat else -36.0
	_chat_wrap.offset_top = -420.0 if above_combat else -280.0
	_trim_chat_log()


func _chat_cap() -> int:
	return CHAT_LOG_MAX_END if _match_over_active else CHAT_LOG_MAX


func _trim_chat_log() -> void:
	if not _chat_log:
		return
	var cap := _chat_cap()
	while _chat_log.get_child_count() > cap:
		_drop_chat_row(_chat_log.get_child(0))


func _drop_chat_row(row: Node) -> void:
	if row == null or row.get_parent() != _chat_log:
		return
	_chat_log.remove_child(row)
	row.queue_free()


func _expire_chat_row(row: Node) -> void:
	if _match_over_active:
		return
	_drop_chat_row(row)


func _chat_accent(team: int, _team_only: bool, sys: bool) -> Color:
	if sys:
		return MUTE
	return _chat_team_color(team)


func _chat_team_color(team: int) -> Color:
	if team == Protocol.TEAM_BLUE:
		return BLUE
	if team == Protocol.TEAM_RED:
		return RED
	return WHITE


func _chat_chip(text: String, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_corner_radius_all(2)
	st.content_margin_left = 5
	st.content_margin_right = 5
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(text, 9, Color("#04121a"))
	if MenuLook:
		l.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	p.add_child(l)
	return p


func _chat_shiny(accent: Color) -> Color:
	return accent.lightened(0.16).lerp(Color.WHITE, 0.12)


func _chat_name_line(text: String, accent: Color) -> Label:
	var col := _chat_shiny(accent)
	var l := _chat_line(text, 12, col)
	if MenuLook:
		l.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(accent, 0.44))
	return l


func _chat_body_line(text: String) -> Label:
	var l := _chat_line(text, 12, CHAT_BODY)
	if MenuLook:
		l.add_theme_font_override("font", MenuLook.FONT_HEADING_SB)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", CHAT_BODY_GLOW)
	return l


func _chat_sys_line(text: String) -> Label:
	var l := _chat_line(text, 12, MUTE.lightened(0.10))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(MUTE, 0.28))
	return l


func _chat_line(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.72))
	return l


func _process(dt: float) -> void:
	var dirty := false
	if _spec_armed and not _spec_charging:
		_spec_glow_t += dt
		dirty = true
	for i in _special_pip_flash.size():
		if _special_pip_flash[i] > 0.0:
			_special_pip_flash[i] = maxf(0.0, _special_pip_flash[i] - dt * 3.2)
			dirty = true
	if dirty:
		_apply_special_visuals()
	if not _wants_special_anim():
		set_process(false)


func _special_filled_count() -> int:
	if _spec_charging:
		var filled := int(round(clampf(_spec_charge, 0.0, 1.0) * float(SPECIAL_PIP_COUNT)))
		if filled == 0 and _spec_charge > 0.0:
			filled = 1
		return filled
	if _spec_armed:
		return SPECIAL_PIP_COUNT
	return clampi(_spec_streak, 0, SPECIAL_PIP_COUNT)


func _apply_special_visuals() -> void:
	var filled := _special_filled_count()
	if filled > _spec_last_filled and _spec_last_filled >= 0:
		for i in range(_spec_last_filled, filled):
			if i >= 0 and i < _special_pip_flash.size():
				_special_pip_flash[i] = 1.0
	_spec_last_filled = filled

	var ready := _spec_armed and not _spec_charging
	var pulse := 0.0
	if ready:
		pulse = 0.5 + 0.5 * sin(_spec_glow_t * TAU * 1.35)

	var status := "%d/%d" % [clampi(_spec_streak, 0, SPECIAL_PIP_COUNT), SPECIAL_PIP_COUNT]
	var status_col := MUTE
	var tag_col := MUTE
	if _spec_charging:
		status = "RELEASE" if _spec_releasable else "CHARGING"
		status_col = CYAN
		tag_col = CYAN
	elif ready:
		status = "READY"
		status_col = Color.WHITE.lerp(CYAN, 0.35 + 0.45 * pulse)
		tag_col = CYAN
	elif filled > 0:
		status_col = CYAN

	_special_status.text = status
	_special_status.add_theme_color_override("font_color", status_col)
	_special_tag.add_theme_color_override("font_color", tag_col)

	if ready:
		_special_box_style.bg_color = Color(0.05, 0.14, 0.18, 0.62 + 0.18 * pulse)
		_special_box_style.border_color = Color(CYAN, 0.55 + 0.45 * pulse)
		_special_box_style.shadow_color = Color(CYAN, 0.18 + 0.38 * pulse)
		_special_box_style.shadow_size = 4 + int(round(10.0 * pulse))
	elif _spec_charging:
		_special_box_style.bg_color = Color(0.05, 0.10, 0.14, 0.62)
		_special_box_style.border_color = Color(CYAN, 0.85)
		_special_box_style.shadow_color = Color(CYAN, 0.22)
		_special_box_style.shadow_size = 4
	elif filled > 0:
		_special_box_style.bg_color = Color(0.04, 0.06, 0.10, 0.58)
		_special_box_style.border_color = Color(CYAN, 0.28 + 0.12 * float(filled) / float(SPECIAL_PIP_COUNT))
		_special_box_style.shadow_color = Color(0, 0, 0, 0)
		_special_box_style.shadow_size = 0
	else:
		_special_box_style.bg_color = Color(0.04, 0.05, 0.08, 0.55)
		_special_box_style.border_color = Color(MUTE, 0.4)
		_special_box_style.shadow_color = Color(0, 0, 0, 0)
		_special_box_style.shadow_size = 0

	for i in _special_pip_styles.size():
		var st := _special_pip_styles[i]
		var on := i < filled
		if on:
			var fill_col := CYAN
			if ready:
				fill_col = CYAN.lerp(PIP_HOT, 0.25 + 0.75 * pulse)
			var flash := _special_pip_flash[i] if i < _special_pip_flash.size() else 0.0
			if flash > 0.0:
				fill_col = fill_col.lerp(Color.WHITE, flash)
			st.bg_color = fill_col
			st.border_color = Color(0.78, 0.97, 1.0, 0.55 + 0.45 * pulse)
			if ready:
				st.shadow_color = Color(CYAN, 0.15 + 0.45 * pulse)
				st.shadow_size = 2 + int(round(5.0 * pulse))
			else:
				st.shadow_color = Color(CYAN, 0.2)
				st.shadow_size = 2
		else:
			st.bg_color = PIP_EMPTY
			st.border_color = PIP_EMPTY_BORDER
			st.shadow_color = Color(0, 0, 0, 0)
			st.shadow_size = 0


func _wants_special_anim() -> bool:
	if _spec_armed and not _spec_charging:
		return true
	for f in _special_pip_flash:
		if f > 0.0:
			return true
	return false


func _set_ready_pulse(on: bool) -> void:
	if on:
		if _special_ready_tween and _special_ready_tween.is_running():
			return
		if _special_ready_tween:
			_special_ready_tween.kill()
		_special_status.modulate.a = 1.0
		_special_ready_tween = create_tween()
		_special_ready_tween.set_loops()
		_special_ready_tween.tween_property(_special_status, "modulate:a", 0.45, 0.42)
		_special_ready_tween.tween_property(_special_status, "modulate:a", 1.0, 0.42)
	else:
		if _special_ready_tween:
			_special_ready_tween.kill()
			_special_ready_tween = null
		_special_status.modulate.a = 1.0


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if MenuLook:
		l.add_theme_font_override("font", MenuLook.FONT_MONO)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_kill_row(killer_name: String, victim_name: String, cause: int, head: bool,
		killer_team: int, victim_team: int, involved: bool) -> Control:
	var meta := _kill_cause_meta(cause, head)
	var has_killer := not killer_name.is_empty() and cause != Protocol.CAUSE_VOID and cause != Protocol.CAUSE_METEOR
	var accent: Color = _kill_name_color(killer_team) if has_killer else Color(meta.accent)

	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.0, 0.0, 0.0, 0.42)
	st.set_corner_radius_all(5)
	st.border_color = accent
	st.border_width_right = 4
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(row)

	if has_killer:
		row.add_child(_kill_name_label(killer_name, killer_team))
	else:
		row.add_child(_kill_name_label(victim_name, victim_team))

	var glyph := KillGlyph.new(int(meta.kind), Color(meta.icon_color))
	row.add_child(glyph)

	var weapon := _label(str(meta.weapon), 12, Color(meta.weapon_color))
	if MenuLook:
		weapon.add_theme_font_override("font", MenuLook.FONT_MONO_REG)
	weapon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(weapon)

	if has_killer:
		row.add_child(_kill_name_label(victim_name, victim_team))

	if not involved:
		pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		return pill

	var wrap := PanelContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_END
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.border_color = GREEN
	outline.set_border_width_all(1)
	outline.set_corner_radius_all(6)
	wrap.add_theme_stylebox_override("panel", outline)
	wrap.add_child(pill)
	return wrap


func _kill_name_label(text: String, team: int) -> Label:
	var l := _label(text, 13, _kill_name_color(team))
	if MenuLook:
		l.add_theme_font_override("font", MenuLook.FONT_MONO_SB)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _kill_name_color(team: int) -> Color:
	if team == Protocol.TEAM_RED:
		return KILL_RED
	if team == Protocol.TEAM_BLUE:
		return KILL_BLUE
	return WHITE


func _kill_cause_meta(cause: int, head: bool) -> Dictionary:
	match cause:
		Protocol.CAUSE_MELEE:
			return {
				kind = KillGlyph.Kind.MELEE,
				weapon = "melee",
				icon_color = KILL_WEAPON,
				weapon_color = KILL_WEAPON,
				accent = KILL_WEAPON,
			}
		Protocol.CAUSE_SPECIAL:
			return {
				kind = KillGlyph.Kind.SPECIAL,
				weapon = "special",
				icon_color = KILL_GOLD,
				weapon_color = KILL_GOLD,
				accent = KILL_GOLD,
			}
		Protocol.CAUSE_METEOR:
			return {
				kind = KillGlyph.Kind.METEOR,
				weapon = "flattened by meteor",
				icon_color = KILL_METEOR,
				weapon_color = KILL_METEOR,
				accent = KILL_METEOR,
			}
		Protocol.CAUSE_VOID:
			return {
				kind = KillGlyph.Kind.VOID,
				weapon = "void",
				icon_color = KILL_VOID,
				weapon_color = KILL_VOID,
				accent = KILL_VOID,
			}
		_:
			if head:
				return {
					kind = KillGlyph.Kind.HEADSHOT,
					weapon = "hs",
					icon_color = KILL_GOLD,
					weapon_color = KILL_GOLD,
					accent = KILL_GOLD,
				}
			return {
				kind = KillGlyph.Kind.LASER,
				weapon = "laser",
				icon_color = KILL_WEAPON,
				weapon_color = KILL_WEAPON,
				accent = KILL_WEAPON,
			}


class KillGlyph extends Control:
	enum Kind { LASER, HEADSHOT, MELEE, SPECIAL, METEOR, VOID }

	var kind: Kind = Kind.LASER
	var color: Color = Color.WHITE

	func _init(p_kind: int = Kind.LASER, p_color: Color = Color.WHITE) -> void:
		kind = p_kind as Kind
		color = p_color
		custom_minimum_size = Vector2(14, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.42
		match kind:
			Kind.LASER:
				var pts := PackedVector2Array([
					c + Vector2(-s * 0.65, -s),
					c + Vector2(s, 0.0),
					c + Vector2(-s * 0.65, s),
				])
				draw_colored_polygon(pts, color)
			Kind.HEADSHOT:
				draw_arc(c, s * 0.78, 0.0, TAU, 28, color, 1.35, true)
				draw_line(c + Vector2(-s - 1.0, 0.0), c + Vector2(s + 1.0, 0.0), color, 1.2, true)
				draw_line(c + Vector2(0.0, -s - 1.0), c + Vector2(0.0, s + 1.0), color, 1.2, true)
			Kind.MELEE:
				draw_line(c + Vector2(-s, -s), c + Vector2(s, s), color, 1.7, true)
				draw_line(c + Vector2(s, -s), c + Vector2(-s, s), color, 1.7, true)
			Kind.SPECIAL:
				for i in 8:
					var a := float(i) * TAU / 8.0
					var length := s if i % 2 == 0 else s * 0.55
					draw_line(c, c + Vector2(cos(a), sin(a)) * length, color, 1.35, true)
			Kind.METEOR:
				var pts := PackedVector2Array([
					c + Vector2(0.0, s),
					c + Vector2(-s, -s * 0.62),
					c + Vector2(s, -s * 0.62),
				])
				draw_colored_polygon(pts, color)
			Kind.VOID:
				var pts := PackedVector2Array([
					c + Vector2(0.0, -s),
					c + Vector2(s * 0.34, 0.0),
					c + Vector2(0.0, s),
					c + Vector2(-s * 0.34, 0.0),
				])
				draw_colored_polygon(pts, color)
