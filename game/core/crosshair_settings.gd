extends Node

## Size, palette color, opacity, and gap for the match crosshair. The HUD,
## settings preview, and console commands all read from here.

signal changed

const SETTINGS_PATH := "user://settings.cfg"

const COLOR_IDS: PackedStringArray = [
	"cyan", "green", "white", "yellow", "orange", "red", "magenta", "blue",
]
const PALETTE := {
	"cyan": Color(0.6, 1.0, 1.0),
	"green": Color("#35ff9e"),
	"white": Color(1.0, 1.0, 1.0),
	"yellow": Color(1.0, 0.88, 0.2),
	"orange": Color(1.0, 0.55, 0.18),
	"red": Color(1.0, 0.30, 0.36),
	"magenta": Color(1.0, 0.40, 0.82),
	"blue": Color(0.30, 0.55, 1.0),
}

const DEFAULT_SIZE := 8.0
const DEFAULT_THICKNESS := 2.0
const DEFAULT_GAP := 4.0
const DEFAULT_COLOR_ID := "cyan"
const DEFAULT_ALPHA := 0.7

const SIZE_MIN := 1.0
const SIZE_MAX := 40.0
const THICKNESS_MIN := 1.0
const THICKNESS_MAX := 12.0
const GAP_MIN := 0.0
const GAP_MAX := 32.0
const ALPHA_MIN := 0.15
const ALPHA_MAX := 1.0


var size: float = DEFAULT_SIZE
var thickness: float = DEFAULT_THICKNESS
var gap: float = DEFAULT_GAP
var color_id: String = DEFAULT_COLOR_ID
var alpha: float = DEFAULT_ALPHA


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	size = clampf(float(cfg.get_value("crosshair", "size", DEFAULT_SIZE)), SIZE_MIN, SIZE_MAX)
	thickness = clampf(float(cfg.get_value("crosshair", "thickness", DEFAULT_THICKNESS)), THICKNESS_MIN, THICKNESS_MAX)
	gap = clampf(float(cfg.get_value("crosshair", "gap", DEFAULT_GAP)), GAP_MIN, GAP_MAX)
	alpha = clampf(float(cfg.get_value("crosshair", "alpha", DEFAULT_ALPHA)), ALPHA_MIN, ALPHA_MAX)
	color_id = _normalize_color_id(str(cfg.get_value("crosshair", "color_id", "")))
	if color_id.is_empty():
		var stored: Variant = cfg.get_value("crosshair", "color", null)
		if stored is Color:
			var old := stored as Color
			color_id = _nearest_color_id(old)
			if not cfg.has_section_key("crosshair", "alpha"):
				alpha = clampf(old.a, ALPHA_MIN, ALPHA_MAX)
		else:
			color_id = DEFAULT_COLOR_ID


func color() -> Color:
	var rgb: Color = PALETTE.get(color_id, PALETTE[DEFAULT_COLOR_ID])
	rgb.a = alpha
	return rgb


func palette_rgb(id: String = "") -> Color:
	if id.is_empty():
		id = color_id
	return PALETTE.get(_normalize_color_id(id), PALETTE[DEFAULT_COLOR_ID])


func has_color(id: String) -> bool:
	return PALETTE.has(id.to_lower())


func color_names() -> String:
	return "|".join(COLOR_IDS)


func set_size(value: float) -> void:
	size = clampf(value, SIZE_MIN, SIZE_MAX)
	_save()


func set_thickness(value: float) -> void:
	thickness = clampf(value, THICKNESS_MIN, THICKNESS_MAX)
	_save()


func set_gap(value: float) -> void:
	gap = clampf(value, GAP_MIN, GAP_MAX)
	_save()


func set_alpha(value: float) -> void:
	alpha = clampf(value, ALPHA_MIN, ALPHA_MAX)
	_save()


func set_color_id(id: String) -> void:
	var next := _normalize_color_id(id)
	if next.is_empty():
		return
	color_id = next
	_save()


func _normalize_color_id(id: String) -> String:
	var key := id.strip_edges().to_lower()
	if PALETTE.has(key):
		return key
	return ""


func _nearest_color_id(sample: Color) -> String:
	var best := DEFAULT_COLOR_ID
	var best_d := INF
	for id in COLOR_IDS:
		var rgb: Color = PALETTE[id]
		var d := Vector3(sample.r - rgb.r, sample.g - rgb.g, sample.b - rgb.b).length_squared()
		if d < best_d:
			best_d = d
			best = id
	return best


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("crosshair", "size", size)
	cfg.set_value("crosshair", "thickness", thickness)
	cfg.set_value("crosshair", "gap", gap)
	cfg.set_value("crosshair", "color_id", color_id)
	cfg.set_value("crosshair", "alpha", alpha)
	cfg.save(SETTINGS_PATH)
	changed.emit()
