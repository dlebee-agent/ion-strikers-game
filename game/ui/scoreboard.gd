class_name Scoreboard
extends Control

## Full-match table shown while the scoreboard key is held: a card per team,
## then the stands. Rows are deliberately short so a full twelve-player lobby
## plus spectators fits without scrolling.

const PANEL_W := 940.0
const ROW_H := 26.0
const HEAD_H := 40.0
const COL_K := 38.0
const COL_D := 38.0
const COL_KD := 56.0
const COL_PING := 54.0

const BLUE_A := Color("#3aa3e8")
const BLUE_B := Color("#1b5f9e")
const RED_A := Color("#d8455d")
const RED_B := Color("#95243a")
const CARD_BG := Color(0.031, 0.043, 0.078, 0.92)
const ROW_LINE := Color(0.91, 0.93, 0.97, 0.05)
const YOU_BG := Color(0.31, 0.64, 0.91, 0.10)

var _meta_left: Label
var _meta_right: Label
var _blue_card: TeamCard
var _red_card: TeamCard
var _spec_head: Label
var _spec_rows: VBoxContainer
var _spec_panel: PanelContainer
var _foot_left: Label
var _foot_right: Label


## Children are built here rather than in _ready so callers may push data
## before the board is parented.
func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var col := VBoxContainer.new()
	col.custom_minimum_size.x = PANEL_W
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(col)

	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meta)
	_meta_left = _kick("", MenuLook.MUTE)
	_meta_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_meta_left)
	_meta_right = _kick("", MenuLook.MUTE_3)
	_meta_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(_meta_right)

	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 18)
	teams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(teams)

	_blue_card = TeamCard.new("BLUE", BLUE_A, BLUE_B)
	_blue_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams.add_child(_blue_card)

	_red_card = TeamCard.new("RED", RED_A, RED_B)
	_red_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams.add_child(_red_card)

	_build_spectators(col)

	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	_foot_left = _kick("", MenuLook.MUTE_2)
	_foot_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_foot_left)
	_foot_right = _kick("M SWITCH TEAM  ·  ESC MENU", MenuLook.MUTE_3)
	_foot_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(_foot_right)


func _build_spectators(parent: VBoxContainer) -> void:
	_spec_panel = PanelContainer.new()
	_spec_panel.add_theme_stylebox_override("panel", _card_style(MenuLook.LINE))
	_spec_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_spec_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spec_panel.add_child(box)

	var head := _row_shell(false)
	box.add_child(head)
	var hb: HBoxContainer = head.get_child(0)
	_spec_head = _kick("SPECTATORS 0 / 0", MenuLook.MUTE_2)
	_spec_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_spec_head)
	hb.add_child(_col_head("K", COL_K))
	hb.add_child(_col_head("D", COL_D))
	hb.add_child(_col_head("K/D", COL_KD))
	hb.add_child(_col_head("PING", COL_PING))

	_spec_rows = VBoxContainer.new()
	_spec_rows.add_theme_constant_override("separation", 0)
	_spec_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_spec_rows)


# ── Public API ───────────────────────────────────────────────────────────

func update_data(info: Dictionary, players: Array) -> void:
	var mode: String = str(info.get("mode", "classic"))
	var kill_target := int(info.get("kill_target", 50))
	var win_rounds := int(info.get("win_rounds", 10))
	var map_name: String = str(info.get("map_name", "PARKOUR YARD"))
	var my_id := int(info.get("my_id", 0))
	var max_spec := int(info.get("max_spectators", 0))

	var match_over := bool(info.get("match_over", false))
	var winner := int(info.get("winner", 0))
	if match_over:
		var win_name := "BLUE WINS" if winner == Protocol.TEAM_BLUE else ("RED WINS" if winner == Protocol.TEAM_RED else "MATCH OVER")
		var mode_label := "DEATHMATCH" if mode == "dm" else "CLASSIC"
		_meta_left.text = MenuLook.tracked(mode_label) + "   ·   " + MenuLook.tracked(win_name)
		_meta_right.text = MenuLook.tracked(map_name.to_upper())
	elif mode == "dm":
		_meta_left.text = MenuLook.tracked("DEATHMATCH") + "   ·   " + MenuLook.tracked("FIRST TO %d KILLS" % kill_target)
	else:
		_meta_left.text = MenuLook.tracked("CLASSIC") + "   ·   " + MenuLook.tracked("FIRST TO %d ROUNDS" % win_rounds)
	if not match_over:
		_meta_right.text = MenuLook.tracked(map_name.to_upper()) + "   ·   " + MenuLook.tracked("HOLD TAB")

	var blue: Array[Dictionary] = []
	var red: Array[Dictionary] = []
	var spec: Array[Dictionary] = []
	for p: Dictionary in players:
		match int(p.get("team", 0)):
			Protocol.TEAM_BLUE:
				blue.append(p)
			Protocol.TEAM_RED:
				red.append(p)
			_:
				spec.append(p)

	blue.sort_custom(_by_score)
	red.sort_custom(_by_score)
	spec.sort_custom(_by_score)

	var unit := "ROUNDS" if mode == "classic" else "KILLS"
	_blue_card.fill(int(info.get("score_blue", 0)), unit, blue, my_id)
	_red_card.fill(int(info.get("score_red", 0)), unit, red, my_id)

	_spec_head.text = MenuLook.tracked("SPECTATORS %d / %d" % [spec.size(), max_spec])
	_spec_panel.visible = not spec.is_empty()
	for c in _spec_rows.get_children():
		c.queue_free()
	for p: Dictionary in spec:
		_spec_rows.add_child(_spec_row(p, my_id))

	_fill_footer(players, my_id, match_over)


func set_post_match(on: bool) -> void:
	# Lift the table so the lobby button at the bottom of the overlay has room.
	offset_top = 72.0 if on else 0.0
	offset_bottom = -108.0 if on else 0.0


func _fill_footer(players: Array, my_id: int, match_over: bool = false) -> void:
	_foot_right.text = "" if match_over else MenuLook.tracked("M SWITCH TEAM  ·  ESC MENU")
	for p: Dictionary in players:
		if int(p.get("id", 0)) != my_id:
			continue
		var k := int(p.get("kills", 0))
		var d := int(p.get("deaths", 0))
		_foot_left.text = MenuLook.tracked("YOU: %s" % str(p.get("name", "")).to_upper()) \
			+ "   ·   " + MenuLook.tracked("%d KILLS" % k) \
			+ "   ·   " + MenuLook.tracked("%d DEATHS" % d)
		return
	_foot_left.text = ""


static func _by_score(a: Dictionary, b: Dictionary) -> bool:
	var ka := int(a.get("kills", 0))
	var kb := int(b.get("kills", 0))
	if ka != kb:
		return ka > kb
	return int(a.get("deaths", 0)) < int(b.get("deaths", 0))


# ── Row construction ─────────────────────────────────────────────────────

func _spec_row(p: Dictionary, my_id: int) -> Control:
	var is_you := int(p.get("id", 0)) == my_id
	var shell := _row_shell(is_you)
	var hb: HBoxContainer = shell.get_child(0)

	hb.add_child(_tick(MenuLook.MUTE_3))
	var nm := _name_label(str(p.get("name", "")), is_you)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(nm)

	var k := int(p.get("kills", 0))
	var d := int(p.get("deaths", 0))
	var ratio := float(k) if d == 0 else float(k) / float(d)
	hb.add_child(_stat(str(k), COL_K, MenuLook.INK))
	hb.add_child(_stat(str(d), COL_D, MenuLook.INK))
	hb.add_child(_stat("%.2f" % ratio, COL_KD, MenuLook.CY if ratio >= 1.0 else MenuLook.MUTE))
	hb.add_child(_stat("%dms" % int(p.get("ping", 0)), COL_PING, MenuLook.MUTE_3, 11))
	return shell


static func _row_shell(highlight: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = YOU_BG if highlight else Color(0, 0, 0, 0)
	s.border_color = ROW_LINE
	s.border_width_bottom = 1
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", s)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	hb.custom_minimum_size.y = ROW_H - 8
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	return pc


static func _tick(color: Color) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size.x = 3
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(3, 14)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(r)
	return wrap


const NAME_MAX_CHARS := 16

## Sized to its text so the BOT/YOU tag can sit right after the name. Long
## names are trimmed here rather than via clip_text, which would zero out the
## label's minimum width and collapse it inside an HBoxContainer.
static func _name_label(text: String, is_you: bool) -> Label:
	var shown := text
	if shown.length() > NAME_MAX_CHARS:
		shown = shown.substr(0, NAME_MAX_CHARS - 1) + "…"
	var l := Label.new()
	l.text = shown
	l.add_theme_font_override("font", MenuLook.FONT_HEADING)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", MenuLook.CY if is_you else MenuLook.INK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _stat(text: String, w: float, color: Color, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuLook.FONT_MONO)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _col_head(text: String, w: float) -> Label:
	var l := _kick(text, MenuLook.MUTE_3)
	l.custom_minimum_size.x = w
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _kick(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = MenuLook.tracked(text)
	l.add_theme_font_override("font", MenuLook.FONT_MONO)
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _card_style(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CARD_BG
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.set_content_margin_all(0)
	return s


# =========================================================================


class TeamCard:
	extends PanelContainer

	var _score: Label
	var _unit: Label
	var _rows: VBoxContainer
	var _accent: Color

	func _init(team_name: String, col_a: Color, col_b: Color) -> void:
		_accent = col_a
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", Scoreboard._card_style(Color(col_a, 0.45)))

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)

		box.add_child(_build_header(team_name, col_a, col_b))
		box.add_child(_build_col_head())

		_rows = VBoxContainer.new()
		_rows.add_theme_constant_override("separation", 0)
		_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(_rows)

	func _build_header(team_name: String, col_a: Color, col_b: Color) -> PanelContainer:
		var head := PanelContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.custom_minimum_size.y = Scoreboard.HEAD_H
		head.add_theme_stylebox_override("panel", _gradient_style(col_a, col_b))

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(hb)

		var title := Label.new()
		title.text = team_name
		title.add_theme_font_override("font", MenuLook.FONT_HEADING)
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color.WHITE)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(title)

		_score = Label.new()
		_score.text = "0"
		_score.add_theme_font_override("font", MenuLook.FONT_HEADING)
		_score.add_theme_font_size_override("font_size", 21)
		_score.add_theme_color_override("font_color", Color.WHITE)
		_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_score)

		_unit = Label.new()
		_unit.text = MenuLook.tracked("ROUNDS")
		_unit.add_theme_font_override("font", MenuLook.FONT_MONO)
		_unit.add_theme_font_size_override("font_size", 9)
		_unit.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		_unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_unit)
		return head

	## StyleBoxFlat is flat-only, so the header wash comes from a 1-D gradient
	## texture stretched across the box.
	static func _gradient_style(col_a: Color, col_b: Color) -> StyleBoxTexture:
		var grad := Gradient.new()
		grad.set_color(0, col_a)
		grad.set_color(1, col_b)
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 256
		tex.height = 4
		tex.fill_from = Vector2(0, 0)
		tex.fill_to = Vector2(1, 0)
		var s := StyleBoxTexture.new()
		s.texture = tex
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		return s

	func _build_col_head() -> PanelContainer:
		var pc := PanelContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0.25)
		s.border_color = Scoreboard.ROW_LINE
		s.border_width_bottom = 1
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 5
		s.content_margin_bottom = 5
		pc.add_theme_stylebox_override("panel", s)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 7)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(hb)

		var player := _mini("PLAYER")
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(player)
		hb.add_child(_mini_col("K", Scoreboard.COL_K))
		hb.add_child(_mini_col("D", Scoreboard.COL_D))
		hb.add_child(_mini_col("PING", Scoreboard.COL_PING))
		return pc

	func _mini(text: String) -> Label:
		var l := Label.new()
		l.text = MenuLook.tracked(text)
		l.add_theme_font_override("font", MenuLook.FONT_MONO)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", MenuLook.MUTE_3)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l

	func _mini_col(text: String, w: float) -> Label:
		var l := _mini(text)
		l.custom_minimum_size.x = w
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		return l

	func fill(score: int, unit: String, players: Array[Dictionary], my_id: int) -> void:
		_score.text = str(score)
		_unit.text = MenuLook.tracked(unit)
		for c in _rows.get_children():
			c.queue_free()

		for p: Dictionary in players:
			var is_you := int(p.get("id", 0)) == my_id
			var alive := bool(p.get("alive", true))
			var shell := Scoreboard._row_shell(is_you)
			var hb: HBoxContainer = shell.get_child(0)

			hb.add_child(Scoreboard._tick(_accent if alive else MenuLook.MUTE_3))
			hb.add_child(Scoreboard._name_label(str(p.get("name", "")), is_you))

			if is_you:
				hb.add_child(Scoreboard._kick("YOU", MenuLook.MUTE_2))
			elif bool(p.get("bot", false)):
				hb.add_child(Scoreboard._kick("BOT", MenuLook.MUTE_3))

			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(spacer)

			hb.add_child(Scoreboard._stat(str(int(p.get("kills", 0))), Scoreboard.COL_K, MenuLook.INK))
			hb.add_child(Scoreboard._stat(str(int(p.get("deaths", 0))), Scoreboard.COL_D, MenuLook.INK))
			hb.add_child(Scoreboard._stat("%dms" % int(p.get("ping", 0)), Scoreboard.COL_PING, MenuLook.MUTE_3, 11))

			# Eliminated players stay listed but recede, matching the round HUD.
			if not alive:
				shell.modulate.a = 0.45
			_rows.add_child(shell)
