extends Node

## Voice chat preferences, shared by the match scene and the settings screen.
##
## Autoload, like InputSettings and AudioMix, so a change made mid-match reaches
## the live capture and playback without a reconnect.

signal changed

const SETTINGS_PATH := "user://settings.cfg"

## Off by default. A game that opens a microphone the first time someone joins a
## server, without being asked, is a game people uninstall — and on macOS the
## first capture attempt raises a system permission prompt, which should follow
## a deliberate choice rather than ambush a player mid-match.
const DEFAULT_ENABLED := false
const DEFAULT_OUTPUT_PCT := 100
const DEFAULT_MIC_GAIN_PCT := 100
## Open-mic threshold as a percentage of full scale. Low enough for normal
## speech, high enough that a fan or a mechanical keyboard does not transmit.
const DEFAULT_SQUELCH_PCT := 2

enum Mode { PUSH_TO_TALK = 0, OPEN_MIC = 1 }

var enabled: bool = DEFAULT_ENABLED
var mode: int = Mode.PUSH_TO_TALK
var output_pct: int = DEFAULT_OUTPUT_PCT
var mic_gain_pct: int = DEFAULT_MIC_GAIN_PCT
var squelch_pct: int = DEFAULT_SQUELCH_PCT


func _ready() -> void:
	load_settings()


## False when the engine build cannot record or play generated audio, which is
## checked before the settings screen offers any of this.
func is_supported() -> bool:
	return VoiceCapture.is_supported() and VoicePlayback.is_supported()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	enabled = bool(cfg.get_value("voice", "enabled", DEFAULT_ENABLED))
	mode = int(cfg.get_value("voice", "mode", Mode.PUSH_TO_TALK))
	if mode != Mode.OPEN_MIC:
		mode = Mode.PUSH_TO_TALK
	output_pct = _read_pct(cfg, "output", DEFAULT_OUTPUT_PCT)
	mic_gain_pct = _read_pct(cfg, "mic_gain", DEFAULT_MIC_GAIN_PCT)
	squelch_pct = _read_pct(cfg, "squelch", DEFAULT_SQUELCH_PCT)


func set_enabled(value: bool) -> void:
	enabled = value
	_save()


func set_mode(value: int) -> void:
	mode = Mode.OPEN_MIC if value == Mode.OPEN_MIC else Mode.PUSH_TO_TALK
	_save()


func set_output_pct(value: int) -> void:
	output_pct = clampi(value, 0, 100)
	_save()


func set_mic_gain_pct(value: int) -> void:
	mic_gain_pct = clampi(value, 0, 200)
	_save()


func set_squelch_pct(value: int) -> void:
	squelch_pct = clampi(value, 0, 20)
	_save()


func output_linear() -> float:
	return output_pct / 100.0


func mic_gain() -> float:
	return mic_gain_pct / 100.0


## Push-to-talk sends everything while the key is held, so the gate is off in
## that mode: a player who chose to press the key has already said they mean to
## transmit, and squelching them clips the first word.
func squelch() -> float:
	if mode == Mode.PUSH_TO_TALK:
		return 0.0
	return squelch_pct / 100.0


func is_push_to_talk() -> bool:
	return mode == Mode.PUSH_TO_TALK


func _save() -> void:
	var cfg := ConfigFile.new()
	# AudioMix and InputSettings own other sections of this file, so read
	# before writing ours.
	cfg.load(SETTINGS_PATH)
	cfg.set_value("voice", "enabled", enabled)
	cfg.set_value("voice", "mode", mode)
	cfg.set_value("voice", "output", output_pct)
	cfg.set_value("voice", "mic_gain", mic_gain_pct)
	cfg.set_value("voice", "squelch", squelch_pct)
	cfg.save(SETTINGS_PATH)
	changed.emit()


func _read_pct(cfg: ConfigFile, key: String, fallback: int) -> int:
	if not cfg.has_section_key("voice", key):
		return fallback
	var v: Variant = cfg.get_value("voice", key, fallback)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return clampi(int(round(float(v))), 0, 200)
	return fallback
