class_name BotSkill
extends RefCounted

## Difficulty presets shared by BotDirector and the lobby-creation UI.
## Each level is a dictionary of tuning knobs; BotDirector.init_ai merges
## them into every bot's ai state so the brain reads them at runtime.

const LEVELS: Array[String] = ["easy", "medium", "hard", "expert"]
const DEFAULT_LEVEL := "medium"

static var _presets: Dictionary = {
	"easy": {
		"aim_err": 0.20,
		"aim_gate": 0.30,
		"reaction": 0.85,
		"fire_gap": 0.55,
		"burst": 2,
		"burst_pause": 1.4,
		"turn": 0.06,
		"fov": 100.0,
		"sight": 22.0,
		"speed": 0.72,
		"idle_chance": 0.50,
		"idle_time_lo": 1.2,
		"idle_time_hi": 3.0,
		"duck_chance": 0.10,
		"cover_chance": 0.15,
		"special_delay": 2.5,
	},
	"medium": {
		"aim_err": 0.12,
		"aim_gate": 0.20,
		"reaction": 0.55,
		"fire_gap": 0.34,
		"burst": 3,
		"burst_pause": 0.9,
		"turn": 0.11,
		"fov": 130.0,
		"sight": 30.0,
		"speed": 0.85,
		"idle_chance": 0.30,
		"idle_time_lo": 0.8,
		"idle_time_hi": 2.0,
		"duck_chance": 0.25,
		"cover_chance": 0.40,
		"special_delay": 1.2,
	},
	"hard": {
		"aim_err": 0.06,
		"aim_gate": 0.14,
		"reaction": 0.34,
		"fire_gap": 0.22,
		"burst": 4,
		"burst_pause": 0.5,
		"turn": 0.20,
		"fov": 160.0,
		"sight": 42.0,
		"speed": 0.95,
		"idle_chance": 0.15,
		"idle_time_lo": 0.5,
		"idle_time_hi": 1.2,
		"duck_chance": 0.40,
		"cover_chance": 0.60,
		"special_delay": 0.5,
	},
	"expert": {
		"aim_err": 0.03,
		"aim_gate": 0.11,
		"reaction": 0.18,
		"fire_gap": 0.15,
		"burst": 6,
		"burst_pause": 0.25,
		"turn": 0.30,
		"fov": 360.0,
		"sight": 200.0,
		"speed": 1.0,
		"idle_chance": 0.05,
		"idle_time_lo": 0.3,
		"idle_time_hi": 0.8,
		"duck_chance": 0.45,
		"cover_chance": 0.75,
		"special_delay": 0.0,
	},
}


static func preset(level: String) -> Dictionary:
	return _presets.get(normalize(level), _presets[DEFAULT_LEVEL])


static func normalize(level: String) -> String:
	var lower := level.to_lower()
	if lower in _presets:
		return lower
	return DEFAULT_LEVEL


static func index_of(level: String) -> int:
	var n := normalize(level)
	for i in LEVELS.size():
		if LEVELS[i] == n:
			return i
	return 1


static func from_index(idx: int) -> String:
	if idx >= 0 and idx < LEVELS.size():
		return LEVELS[idx]
	return DEFAULT_LEVEL


static func label_for(level: String) -> String:
	return normalize(level).capitalize()
