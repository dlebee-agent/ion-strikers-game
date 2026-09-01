class_name MatchOverOverlay
extends Control

## Post-match screen: dim, winner line, and a lobby exit. The in-match
## scoreboard is pinned on top by MatchHud; chat stays a sibling so Y/U
## still work.

signal lobby_requested

const BTN_W := 280.0
const BTN_H := 48.0

var _dim: ColorRect
var _kicker: Label
var _title: Label
var _score_line: Label
var _lobby_btn: Button
var _hint: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func present(winner: int, score_blue: int, score_red: int, mode: String) -> void:
	var blue_win := winner == Protocol.TEAM_BLUE
	var accent := MenuLook.CY if blue_win else MenuLook.RD
	var mode_label := "DEATHMATCH" if mode == "dm" else "ARENA"
	var unit := "kills" if mode == "dm" else "rounds"

	_kicker.text = MenuLook.tracked("%s · MATCH OVER" % mode_label)
	_title.text = "BLUE WINS" if blue_win else "RED WINS"
	_title.add_theme_color_override("font_color", accent)
	_score_line.text = "%d  —  %d  %s" % [score_blue, score_red, unit]

	visible = true


func dismiss() -> void:
	visible = false


func is_showing() -> bool:
	return visible


func _build() -> void:
	_dim = ColorRect.new()
	MenuLook.fill(_dim)
	_dim.color = Color(0.02, 0.03, 0.06, 0.88)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var scan := MenuLook.shader_rect(MenuLook.SH_SCAN)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scan)

	_kicker = MenuLook.kicker("", Color(0.86, 0.89, 0.94, 0.72), 12)
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kicker.anchor_left = 0.0
	_kicker.anchor_right = 1.0
	_kicker.anchor_top = 0.04
	_kicker.anchor_bottom = 0.04
	_kicker.offset_top = 0.0
	_kicker.offset_bottom = 18.0
	add_child(_kicker)

	_title = MenuLook.heading("BLUE WINS", 42, MenuLook.CY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.7))
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.anchor_top = 0.055
	_title.anchor_bottom = 0.055
	_title.offset_top = 14.0
	_title.offset_bottom = 58.0
	add_child(_title)

	_score_line = MenuLook.body("", 16, MenuLook.MUTE)
	_score_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_line.anchor_left = 0.0
	_score_line.anchor_right = 1.0
	_score_line.anchor_top = 0.055
	_score_line.anchor_bottom = 0.055
	_score_line.offset_top = 58.0
	_score_line.offset_bottom = 80.0
	add_child(_score_line)

	_lobby_btn = Button.new()
	_lobby_btn.text = "EXIT TO LOBBY"
	_lobby_btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	_lobby_btn.anchor_left = 0.5
	_lobby_btn.anchor_right = 0.5
	_lobby_btn.anchor_top = 1.0
	_lobby_btn.anchor_bottom = 1.0
	_lobby_btn.offset_left = -BTN_W * 0.5
	_lobby_btn.offset_right = BTN_W * 0.5
	_lobby_btn.offset_top = -92.0
	_lobby_btn.offset_bottom = -44.0
	_lobby_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_lobby_btn(_lobby_btn)
	_lobby_btn.pressed.connect(func() -> void: lobby_requested.emit())
	add_child(_lobby_btn)

	_hint = MenuLook.mono("", 11, MenuLook.MUTE_3)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -38.0
	_hint.offset_bottom = -18.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_refresh_hint()

	if InputBinds:
		InputBinds.bindings_changed.connect(_refresh_hint)


func _refresh_hint() -> void:
	if not _hint:
		return
	if not InputBinds:
		_hint.text = MenuLook.tracked("Y CHAT  ·  U TEAM CHAT")
		return
	_hint.text = MenuLook.tracked("%s CHAT  ·  %s TEAM CHAT" % [
		InputBinds.primary("chat_all").to_upper(),
		InputBinds.primary("chat_team").to_upper(),
	])


func _apply_lobby_btn(btn: Button) -> void:
	var bg := MenuLook.YES
	var ink := Color("#04160d")
	var n := MenuLook.box(bg, bg, 4, 0)
	var h := MenuLook.box(bg.lightened(0.08), bg.lightened(0.08), 4, 0)
	MenuLook.style_button(btn, n, h, ink, MenuLook.FONT_HEADING, 16)
