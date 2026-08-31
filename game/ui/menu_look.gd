class_name MenuLook
extends Object

const CY := Color("#4ee2f5")
const RD := Color("#f43f5e")
const RD_SOFT := Color("#ff6b83")
const INK := Color("#e9edf6")
const INK_2 := Color("#c6cee2")
const MUTE := Color("#9aa6c2")
const MUTE_2 := Color("#6d7d9c")
const MUTE_3 := Color("#55637f")
const LINE := Color(0.914, 0.929, 0.965, 0.1)
const LINE_SOFT := Color(0.914, 0.929, 0.965, 0.06)
const PANEL := Color(0.047, 0.043, 0.086, 0.8)
const PANEL_2 := Color("#0b0a16")
const FIELD_BG := Color("#0a0913")
const CARD_BG := Color("#0a1220")
const CARD_BG_RED := Color("#1a0a12")
const GHOST_BG := Color(0.043, 0.039, 0.086, 0.7)
const PRIMARY_INK := Color("#04121a")
const RED_INK := Color("#1a0209")
const YES := Color("#35ff9e")

const FONT_HEADING: FontFile = preload("res://assets/fonts/ChakraPetch-Bold.ttf")
const FONT_HEADING_SB: FontFile = preload("res://assets/fonts/ChakraPetch-SemiBold.ttf")
const FONT_MONO: FontFile = preload("res://assets/fonts/IBMPlexMono-Medium.ttf")
const FONT_MONO_REG: FontFile = preload("res://assets/fonts/IBMPlexMono-Regular.ttf")
const FONT_MONO_SB: FontFile = preload("res://assets/fonts/IBMPlexMono-SemiBold.ttf")

const SH_BG: Shader = preload("res://ui/menu_bg.gdshader")
const SH_SCAN: Shader = preload("res://ui/scanlines.gdshader")
const SH_FADE: Shader = preload("res://ui/floor_fade.gdshader")
const SH_WASH: Shader = preload("res://ui/card_wash.gdshader")
const SH_GLOW: Shader = preload("res://ui/stage_glow.gdshader")

static var _grabber: ImageTexture


static func fill(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = Control.GROW_DIRECTION_BOTH


static func shader_rect(shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	fill(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	r.material = mat
	r.color = Color.WHITE
	return r


static func box(bg: Color, border: Color, radius := 4, border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	return s


## Labels have no letter-spacing property, so wide-tracked small caps are faked
## by interleaving spaces between glyphs.
static func tracked(text: String) -> String:
	var out := ""
	for i in text.length():
		if i > 0:
			out += " "
		out += text[i]
	return out


static func kicker(text: String, color: Color = MUTE_2, size := 10) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", FONT_MONO)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func heading(text: String, size := 40, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_HEADING)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func body(text: String, size := 14, color: Color = INK, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_HEADING_SB)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func mono(text: String, size := 11, color: Color = MUTE_3) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_MONO)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func style_button(btn: Button, normal: StyleBox, hover: StyleBox, font_color: Color, font: Font = FONT_HEADING, size := 14) -> void:
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("disabled", normal)
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", size)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_color_override("font_focus_color", font_color)
	btn.add_theme_color_override("font_disabled_color", Color(font_color, 0.35))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func ghost_style(hover_border: Color = Color(CY, 0.45)) -> Array:
	return [box(GHOST_BG, LINE, 4), box(GHOST_BG, hover_border, 4)]


static func apply_ghost(btn: Button, size := 11) -> void:
	var styles: Array = ghost_style()
	style_button(btn, styles[0], styles[1], INK_2, FONT_MONO, size)


static func apply_primary(btn: Button, red := false) -> void:
	var bg := RD if red else CY
	var ink := RED_INK if red else PRIMARY_INK
	var n := box(bg, bg, 4, 0)
	var h := box(bg.lightened(0.08), bg.lightened(0.08), 4, 0)
	style_button(btn, n, h, ink, FONT_HEADING, 14)


static func apply_field(le: LineEdit) -> void:
	le.add_theme_font_override("font", FONT_HEADING_SB)
	le.add_theme_font_size_override("font_size", 15)
	le.add_theme_color_override("font_color", INK)
	le.add_theme_color_override("font_placeholder_color", MUTE_3)
	le.add_theme_color_override("caret_color", CY)
	le.add_theme_stylebox_override("normal", box(FIELD_BG, LINE, 4))
	le.add_theme_stylebox_override("focus", box(FIELD_BG, CY, 4))
	le.add_theme_stylebox_override("read_only", box(FIELD_BG, LINE, 4))


static func apply_dropdown(ob: OptionButton) -> void:
	ob.add_theme_font_override("font", FONT_HEADING_SB)
	ob.add_theme_font_size_override("font_size", 15)
	ob.add_theme_color_override("font_color", INK)
	ob.add_theme_color_override("font_hover_color", INK)
	ob.add_theme_color_override("font_pressed_color", INK)
	ob.add_theme_color_override("font_focus_color", INK)
	ob.add_theme_color_override("font_disabled_color", MUTE_3)
	ob.add_theme_stylebox_override("normal", box(FIELD_BG, LINE, 4))
	ob.add_theme_stylebox_override("hover", box(FIELD_BG, Color(CY, 0.45), 4))
	ob.add_theme_stylebox_override("pressed", box(FIELD_BG, CY, 4))
	ob.add_theme_stylebox_override("focus", box(FIELD_BG, CY, 4))
	ob.add_theme_stylebox_override("disabled", box(FIELD_BG, LINE, 4))
	var popup := ob.get_popup()
	popup.add_theme_font_override("font", FONT_HEADING_SB)
	popup.add_theme_font_size_override("font_size", 14)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", INK)
	popup.add_theme_color_override("font_disabled_color", MUTE_3)
	popup.add_theme_stylebox_override("panel", box(PANEL_2, LINE, 4))
	popup.add_theme_stylebox_override("hover", box(Color(CY, 0.16), CY, 3))
	ob.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ob.flat = false
	ob.fit_to_longest_item = true


static func apply_panel(panel: PanelContainer, pad := 18) -> void:
	var s := box(PANEL, LINE, 6)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	panel.add_theme_stylebox_override("panel", s)


static func apply_card(btn: Button, red := false, hovered := false) -> void:
	var bg := CARD_BG_RED if red else CARD_BG
	var border := Color(RD, 0.3) if red else Color(CY, 0.3)
	var glow := Color(RD, 0.2) if red else Color(CY, 0.22)
	if hovered:
		border = RD if red else CY
	var s := box(bg, border, 4)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 24
	s.content_margin_bottom = 20
	if hovered:
		s.shadow_color = glow
		s.shadow_size = 18
	style_button(btn, s, s, INK, FONT_HEADING, 26)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))


static func apply_opt(btn: Button, active: bool, kind: String = "opt") -> void:
	var border := CY if active else LINE
	var bg := CARD_BG if active and kind != "yn" else GHOST_BG
	if kind == "yn":
		if active and btn.get_meta("yes", false):
			border = YES
			bg = Color(0.208, 1.0, 0.62, 0.12)
		elif active:
			border = RD
			bg = Color(RD, 0.12)
		else:
			bg = GHOST_BG
	elif active:
		bg = CARD_BG
	var s := box(bg, border, 4)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 13
	s.content_margin_bottom = 13
	if kind == "num":
		s.content_margin_top = 10
		s.content_margin_bottom = 10
	style_button(btn, s, box(bg, Color(CY, 0.45) if not active else border, 4), INK, FONT_HEADING, 15)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
	if kind == "yn":
		var col := MUTE_2
		if active and btn.get_meta("yes", false):
			col = Color("#9dffcf")
		elif active:
			col = Color("#ffb3c0")
		elif not active:
			col = MUTE_2
		btn.add_theme_color_override("font_color", col)
		btn.add_theme_color_override("font_hover_color", INK)
		btn.add_theme_color_override("font_pressed_color", col)
		btn.add_theme_font_override("font", FONT_MONO)
		btn.add_theme_font_size_override("font_size", 13)


static func apply_tile(btn: Button) -> void:
	var n := box(GHOST_BG, LINE, 4)
	var h := box(GHOST_BG, Color(CY, 0.45), 4)
	n.content_margin_left = 16
	n.content_margin_right = 16
	n.content_margin_top = 14
	n.content_margin_bottom = 14
	h.content_margin_left = 16
	h.content_margin_right = 16
	h.content_margin_top = 14
	h.content_margin_bottom = 14
	style_button(btn, n, h, INK, FONT_HEADING, 16)
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))


static func apply_bind_key(btn: Button, empty := false, listening := false, fixed := false) -> void:
	var border := CY if listening else LINE
	var col := MUTE_3 if empty else INK
	if listening:
		col = CY
	var s := box(FIELD_BG, border, 3)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	style_button(btn, s, box(FIELD_BG, Color(CY, 0.45), 3), col, FONT_MONO, 11)
	btn.disabled = fixed
	if fixed:
		btn.modulate.a = 0.55
		btn.mouse_default_cursor_shape = Control.CURSOR_ARROW


static func grabber() -> Texture2D:
	if _grabber:
		return _grabber
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			if d <= 5.4:
				img.set_pixel(x, y, CY)
			elif d <= 6.6:
				img.set_pixel(x, y, Color(CY.r, CY.g, CY.b, 1.0 - (d - 5.4)))
	_grabber = ImageTexture.create_from_image(img)
	return _grabber


static func apply_slider(sl: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.08)
	track.set_corner_radius_all(2)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.set_content_margin_all(0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = CY
	fill.set_corner_radius_all(2)
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_icon_override("grabber", grabber())
	sl.add_theme_icon_override("grabber_highlight", grabber())
	sl.add_theme_icon_override("grabber_disabled", grabber())
	sl.custom_minimum_size.y = 18


static func page_margins(page: MarginContainer) -> void:
	page.add_theme_constant_override("margin_left", 26)
	page.add_theme_constant_override("margin_right", 26)
	page.add_theme_constant_override("margin_top", 118)
	page.add_theme_constant_override("margin_bottom", 62)


static func wash_rect(red := false) -> ColorRect:
	var r := ColorRect.new()
	fill(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SH_WASH
	mat.set_shader_parameter("wash", Color(RD, 0.18) if red else Color(CY, 0.18))
	r.material = mat
	return r


static func glow_rect(red := false) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mat := ShaderMaterial.new()
	mat.shader = SH_GLOW
	mat.set_shader_parameter("glow", Color(RD, 0.28) if red else Color(CY, 0.28))
	r.material = mat
	r.color = Color.WHITE
	return r


static func transparent_panel() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()
