extends Node

## Mouse look preferences. Every camera rig reads them from here, so a change
## made mid-match reaches the live rig without a restart.

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 1.0
const SENSITIVITY_MIN := 0.1
const SENSITIVITY_MAX := 5.0
# A sensitivity of 1.0 has to feel like the rig's original hard-coded 0.15.
const CAMERA_SCALE := 0.15
# The settings slider steps in whole numbers, so it carries a scaled value.
const SLIDER_SCALE := 20.0

var sensitivity: float = DEFAULT_SENSITIVITY
var invert_y: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	invert_y = bool(cfg.get_value("input", "invert_y", false))
	var stored := float(cfg.get_value("input", "sensitivity", DEFAULT_SENSITIVITY))
	# Older builds wrote the rig's raw multiplier (0.15) into this same key.
	if stored <= 0.2:
		stored = DEFAULT_SENSITIVITY
	sensitivity = clampf(stored, SENSITIVITY_MIN, SENSITIVITY_MAX)


func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	_save()


func set_invert_y(value: bool) -> void:
	invert_y = value
	_save()


func slider_value() -> float:
	return sensitivity * SLIDER_SCALE


func set_from_slider(value: float) -> void:
	set_sensitivity(value / SLIDER_SCALE)


func apply_to(rig: CameraRig) -> void:
	if rig == null:
		return
	rig.sensitivity = sensitivity * CAMERA_SCALE
	rig.invert_y = invert_y


func _save() -> void:
	var cfg := ConfigFile.new()
	# AudioMix owns other sections of this file, so read before writing ours.
	cfg.load(SETTINGS_PATH)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.save(SETTINGS_PATH)
	changed.emit()
