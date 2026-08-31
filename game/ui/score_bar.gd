class_name ScoreBar
extends Control

## Top-of-screen score readout: two slanted team wedges flanking a dark centre
## column. The wedges are drawn rather than styled because StyleBoxFlat cannot
## express a parallelogram or a horizontal gradient.

const BLUE_W := 172.0
const CENTER_W := 180.0
const RED_W := 172.0
const GAP := 3.0
const SLANT := 16.0
const BAR_H := 74.0
const BAR_W := BLUE_W + GAP + CENTER_W + GAP + RED_W

const BLUE_A := Color("#3aa3e8")
const BLUE_B := Color("#1a5691")
const RED_A := Color("#d8455d")
const RED_B := Color("#8c2033")
const CENTER_BG := Color("#05070f")
const EDGE := Color(0.91, 0.93, 0.97, 0.16)

var _blue_score: Label
var _red_score: Label
var _blue_kicker: Label
var _red_kicker: Label
var _blue_alive: Label
var _red_alive: Label
var _round_lbl: Label
var _clock_lbl: Label
var _target_lbl: Label


## Children are built here rather than in _ready so callers may push data
## before the bar is parented.
func _init() -> void:
	custom_minimum_size = Vector2(BAR_W, BAR_H)
	size = Vector2(BAR_W, BAR_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_blue_kicker = _add(_kicker("BLUE", Color(0.85, 0.94, 1.0, 0.75)))
	_blue_alive = _add(_body("0 alive", 13, Color("#eaf4ff")))
	_blue_score = _add(_num("0", 34, Color.WHITE))

	_round_lbl = _add(_kicker("ROUND 1", Color(0.72, 0.79, 0.92, 0.8)))
	_clock_lbl = _add(_num("0:00", 30, MenuLook.CY))
	_target_lbl = _add(_kicker("FIRST TO 10", Color(0.62, 0.70, 0.85, 0.7)))

	_red_score = _add(_num("0", 34, Color.WHITE))
	_red_kicker = _add(_kicker("RED", Color(1.0, 0.88, 0.90, 0.75)))
	_red_alive = _add(_body("0 alive", 13, Color("#ffeaee")))

	_layout()


func _add(l: Label) -> Label:
	add_child(l)
	return l


# ── Public API ───────────────────────────────────────────────────────────

func set_scores(blue: int, red: int) -> void:
	_blue_score.text = str(blue)
	_red_score.text = str(red)


func set_alive(blue_alive: int, red_alive: int, show: bool) -> void:
	_blue_alive.visible = show
	_red_alive.visible = show
	if show:
		_blue_alive.text = "%d alive" % blue_alive
		_red_alive.text = "%d alive" % red_alive


func set_center(top: String, big: String, bottom: String) -> void:
	_round_lbl.text = MenuLook.tracked(top)
	_clock_lbl.text = big
	_target_lbl.text = MenuLook.tracked(bottom)


# ── Geometry ─────────────────────────────────────────────────────────────

func _blue_quad() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, 0), Vector2(BLUE_W, 0),
		Vector2(BLUE_W - SLANT, BAR_H), Vector2(0, BAR_H)])


func _center_quad() -> PackedVector2Array:
	var x := BLUE_W + GAP
	return PackedVector2Array([
		Vector2(x, 0), Vector2(x + CENTER_W, 0),
		Vector2(x + CENTER_W - SLANT, BAR_H), Vector2(x - SLANT, BAR_H)])


func _red_quad() -> PackedVector2Array:
	var x := BLUE_W + GAP + CENTER_W + GAP
	return PackedVector2Array([
		Vector2(x, 0), Vector2(BAR_W, 0),
		Vector2(BAR_W, BAR_H), Vector2(x - SLANT, BAR_H)])


func _draw() -> void:
	_wedge(_blue_quad(), BLUE_A, BLUE_B)
	_wedge(_center_quad(), CENTER_BG, CENTER_BG)
	_wedge(_red_quad(), RED_A, RED_B)


func _wedge(pts: PackedVector2Array, left: Color, right: Color) -> void:
	draw_polygon(pts, PackedColorArray([left, right, right, left]))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, EDGE, 1.0, true)


func _layout() -> void:
	var mid := BAR_H * 0.5

	# Blue wedge: stacked kicker/alive block, then the score hard against the slant.
	var b_score_x := BLUE_W - SLANT - 14.0 - 46.0
	_place(_blue_score, b_score_x, 0, 46, BAR_H, HORIZONTAL_ALIGNMENT_RIGHT)
	var b_text_r := b_score_x - 10.0
	_place(_blue_kicker, 12, mid - 20, b_text_r - 12, 13, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_blue_alive, 12, mid - 5, b_text_r - 12, 18, HORIZONTAL_ALIGNMENT_RIGHT)

	var cx := BLUE_W + GAP - SLANT * 0.5
	_place(_round_lbl, cx, 9, CENTER_W, 12, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_clock_lbl, cx, 21, CENTER_W, 32, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_target_lbl, cx, 52, CENTER_W, 12, HORIZONTAL_ALIGNMENT_CENTER)

	var r_x := BLUE_W + GAP + CENTER_W + GAP
	_place(_red_score, r_x + 8, 0, 46, BAR_H, HORIZONTAL_ALIGNMENT_LEFT)
	var r_text_l := r_x + 8 + 46 + 10
	_place(_red_kicker, r_text_l, mid - 20, BAR_W - r_text_l - 12, 13, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_red_alive, r_text_l, mid - 5, BAR_W - r_text_l - 12, 18, HORIZONTAL_ALIGNMENT_LEFT)


func _place(l: Label, x: float, y: float, w: float, h: float, halign: int) -> void:
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.horizontal_alignment = halign
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# ── Label factories ──────────────────────────────────────────────────────

func _kicker(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = MenuLook.tracked(text)
	l.add_theme_font_override("font", MenuLook.FONT_MONO)
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _body(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuLook.FONT_HEADING)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _num(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MenuLook.FONT_HEADING)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
