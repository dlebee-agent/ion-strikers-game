class_name RoundEndOverlay
extends Control

## Cinematic round-end card: reason line, team-coloured "BLUE/RED WINS",
## then the series score. Covers the HUD for the round-end delay.

const FADE_IN := 0.16
const FADE_OUT := 0.4
const RULE_W := 520.0
const TITLE_SIZE := 78
const SCORE_SIZE := 64

var _dim: ColorRect
var _flare: ColorRect
var _flare_mat: ShaderMaterial
var _header: Label
var _rule_top: ColorRect
var _title: Label
var _rule_bot: ColorRect
var _blue_tag: Label
var _blue_score: Label
var _red_tag: Label
var _red_score: Label
var _tween: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	_build()


func present(winner: int, score_blue: int, score_red: int, round_num: int, match_over: bool,
		reason: int = Protocol.END_ELIMINATION) -> void:
	var blue_win := winner == Protocol.TEAM_BLUE
	var draw := winner == Protocol.TEAM_NONE
	# A draw belongs to neither side, so it wears neither side's colour and
	# leaves both scores muted.
	var accent := MenuLook.MUTE if draw else (MenuLook.CY if blue_win else MenuLook.RD)

	var detail := _detail(winner, reason)
	if match_over and round_num <= 0:
		_header.text = MenuLook.tracked("MATCH OVER")
	elif match_over:
		_header.text = MenuLook.tracked("MATCH OVER · %s" % detail)
	else:
		_header.text = MenuLook.tracked("ROUND %d · %s" % [round_num, detail])

	_title.text = "DRAW" if draw else ("BLUE WINS" if blue_win else "RED WINS")
	_title.add_theme_color_override("font_color", accent)
	_rule_top.color = Color(accent, 0.9)
	_rule_bot.color = Color(accent, 0.9)
	_flare_mat.set_shader_parameter("glow", Color(accent, 0.62))

	_blue_score.text = str(score_blue)
	_red_score.text = str(score_red)
	_blue_score.add_theme_color_override("font_color", accent if blue_win else MenuLook.MUTE)
	_red_score.add_theme_color_override("font_color", accent if not blue_win and not draw else MenuLook.MUTE)
	_blue_tag.add_theme_color_override("font_color", Color(accent, 0.7) if blue_win else MenuLook.MUTE_2)
	_red_tag.add_theme_color_override("font_color", Color(accent, 0.7) if not blue_win and not draw else MenuLook.MUTE_2)

	_show()


# The line above the result, saying how the round was actually decided.
# "TEAM ELIMINATED" was true when that was the only way to end one.
static func _detail(winner: int, reason: int) -> String:
	var loser := "RED" if winner == Protocol.TEAM_BLUE else "BLUE"
	match reason:
		Protocol.END_TIME:
			if winner == Protocol.TEAM_NONE:
				return "TIME UP · LEVEL"
			return "TIME UP · %s AHEAD" % ("BLUE" if winner == Protocol.TEAM_BLUE else "RED")
		Protocol.END_FORFEIT:
			return "%s TEAM LEFT" % loser
		_:
			if winner == Protocol.TEAM_NONE:
				return "BOTH TEAMS DOWN"
			return "%s TEAM ELIMINATED" % loser


func _show() -> void:
	visible = true
	modulate.a = 0.0
	_rule_top.custom_minimum_size.x = 36.0
	_rule_bot.custom_minimum_size.x = 36.0

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_rule_top, "custom_minimum_size:x", RULE_W, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_rule_bot, "custom_minimum_size:x", RULE_W, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var hold := 2.2 if match_over else (MatchState.ROUND_END_DELAY - FADE_OUT)
	_tween.set_parallel(false)
	_tween.tween_interval(maxf(0.4, hold))
	_tween.tween_callback(_fade_out)


func dismiss() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
		_tween = null
	visible = false
	modulate.a = 0.0


func is_showing() -> bool:
	return visible


func _fade_out() -> void:
	if _tween:
		_tween.kill()
	if not is_inside_tree():
		visible = false
		modulate.a = 0.0
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void:
		visible = false
		_tween = null)


func _build() -> void:
	_dim = ColorRect.new()
	MenuLook.fill(_dim)
	_dim.color = Color(0.015, 0.02, 0.04, 0.9)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var scan := MenuLook.shader_rect(MenuLook.SH_SCAN)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scan)

	_flare = ColorRect.new()
	_flare.anchor_left = 0.5
	_flare.anchor_top = 0.5
	_flare.anchor_right = 0.5
	_flare.anchor_bottom = 0.5
	_flare.offset_left = -640.0
	_flare.offset_right = 640.0
	_flare.offset_top = -110.0
	_flare.offset_bottom = 110.0
	_flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flare.color = Color.WHITE
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = preload("res://ui/round_end_flare.gdshader")
	_flare.material = _flare_mat
	add_child(_flare)

	_header = MenuLook.kicker("", Color(0.86, 0.89, 0.94, 0.82), 13)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.anchor_left = 0.0
	_header.anchor_right = 1.0
	_header.anchor_top = 0.17
	_header.anchor_bottom = 0.17
	_header.offset_top = -10.0
	_header.offset_bottom = 16.0
	add_child(_header)

	var title_col := VBoxContainer.new()
	title_col.alignment = BoxContainer.ALIGNMENT_CENTER
	title_col.add_theme_constant_override("separation", 8)
	title_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_col.anchor_left = 0.5
	title_col.anchor_right = 0.5
	title_col.anchor_top = 0.5
	title_col.anchor_bottom = 0.5
	title_col.offset_left = -420.0
	title_col.offset_right = 420.0
	title_col.offset_top = -72.0
	title_col.offset_bottom = 72.0
	add_child(title_col)

	_rule_top = _rule()
	title_col.add_child(_centered(_rule_top))

	_title = MenuLook.heading("BLUE WINS", TITLE_SIZE, MenuLook.CY)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.72))
	title_col.add_child(_title)

	_rule_bot = _rule()
	title_col.add_child(_centered(_rule_bot))

	var score_wrap := CenterContainer.new()
	score_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_wrap.anchor_left = 0.0
	score_wrap.anchor_right = 1.0
	score_wrap.anchor_top = 0.66
	score_wrap.anchor_bottom = 0.66
	score_wrap.offset_top = -8.0
	score_wrap.offset_bottom = 88.0
	add_child(score_wrap)
	score_wrap.add_child(_scores())


func _scores() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var blue := _score_col()
	_blue_tag = blue[0]
	_blue_score = blue[1]
	_blue_tag.text = MenuLook.tracked("BLUE")
	row.add_child(blue[2])

	var tick := ColorRect.new()
	tick.custom_minimum_size = Vector2(1, 56)
	tick.color = Color(0.91, 0.93, 0.97, 0.22)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)

	var red := _score_col()
	_red_tag = red[0]
	_red_score = red[1]
	_red_tag.text = MenuLook.tracked("RED")
	row.add_child(red[2])
	return row


func _score_col() -> Array:
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 2)
	wrap.custom_minimum_size.x = 120
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tag := MenuLook.kicker("", MenuLook.MUTE_2, 11)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(tag)

	var num := MenuLook.heading("0", SCORE_SIZE, MenuLook.INK)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(num)
	return [tag, num, wrap]


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(RULE_W, 2)
	r.color = MenuLook.RD
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c
