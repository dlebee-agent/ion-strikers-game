extends Node

signal bindings_changed

const BIND_DEFAULTS: Dictionary = {
	"forward": ["W", "Up"],
	"back": ["S", "Down"],
	"left": ["A", ""],
	"right": ["D", ""],
	"jump": ["Space", ""],
	"crouch": ["C", "Ctrl"],
	"walk": ["Shift", ""],
	"special": ["F", ""],
	"scoreboard": ["Tab", "L"],
	"controls": ["F1", ""],
	"team_menu": ["M", ""],
	"fullscreen": ["F11", ""],
	"chat_all": ["Y", "Enter"],
	"chat_team": ["U", ""],
}

const BIND_GROUPS: Array = [
	["Movement", ["forward", "back", "left", "right", "jump", "crouch", "walk"]],
	["Combat", ["special"]],
	["Communication", ["chat_all", "chat_team"]],
	["Interface", ["team_menu", "scoreboard", "controls", "fullscreen"]],
]

const BIND_LABELS: Dictionary = {
	"forward": "Forward",
	"back": "Back",
	"left": "Strafe left",
	"right": "Strafe right",
	"jump": "Jump",
	"crouch": "Duck / crouch",
	"walk": "Walk (slow)",
	"special": "Special attack (hold)",
	"scoreboard": "Scoreboard (hold)",
	"controls": "Controls card",
	"team_menu": "Team menu",
	"fullscreen": "Fullscreen",
	"chat_all": "Global message",
	"chat_team": "Team chat",
}

const BIND_FIXED: Array = [
	["Fire laser", "Mouse1"],
	["Melee", "Mouse2"],
]

var bindings: Dictionary = {}
var _save_path: String = "user://bindings.cfg"

func _ready() -> void:
	_load_defaults()
	_load_saved()
	_apply_to_input_map()

func _load_defaults() -> void:
	for action_name: String in BIND_DEFAULTS:
		bindings[action_name] = BIND_DEFAULTS[action_name].duplicate()

func _load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		return
	for action_name: String in bindings:
		if cfg.has_section_key("binds", action_name + "_primary"):
			bindings[action_name][0] = cfg.get_value("binds", action_name + "_primary", "")
		if cfg.has_section_key("binds", action_name + "_alt"):
			bindings[action_name][1] = cfg.get_value("binds", action_name + "_alt", "")

func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for action_name: String in bindings:
		cfg.set_value("binds", action_name + "_primary", bindings[action_name][0])
		cfg.set_value("binds", action_name + "_alt", bindings[action_name][1])
	cfg.save(_save_path)

func reset_to_defaults() -> void:
	_load_defaults()
	save_bindings()
	_apply_to_input_map()
	bindings_changed.emit()

func set_bind(action_name: String, slot: int, key_name: String) -> void:
	if action_name in bindings and slot >= 0 and slot <= 1:
		bindings[action_name][slot] = key_name
		save_bindings()
		_apply_to_input_map()
		bindings_changed.emit()

func _apply_to_input_map() -> void:
	for action_name: String in bindings:
		var im_action: String = "game_" + action_name
		if InputMap.has_action(im_action):
			InputMap.erase_action(im_action)
		InputMap.add_action(im_action)
		for i in 2:
			var key_name: String = bindings[action_name][i]
			if key_name.is_empty():
				continue
			var ev := _key_name_to_event(key_name)
			if ev:
				InputMap.action_add_event(im_action, ev)

func _key_name_to_event(key_name: String) -> InputEvent:
	var mapping := {
		"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D,
		"E": KEY_E, "F": KEY_F, "G": KEY_G, "H": KEY_H,
		"I": KEY_I, "J": KEY_J, "K": KEY_K, "L": KEY_L,
		"M": KEY_M, "N": KEY_N, "O": KEY_O, "P": KEY_P,
		"Q": KEY_Q, "R": KEY_R, "T": KEY_T, "U": KEY_U,
		"V": KEY_V, "X": KEY_X, "Y": KEY_Y, "Z": KEY_Z,
		"Space": KEY_SPACE, "Shift": KEY_SHIFT, "Ctrl": KEY_CTRL,
		"Tab": KEY_TAB, "Enter": KEY_ENTER, "Escape": KEY_ESCAPE,
		"Up": KEY_UP, "Down": KEY_DOWN, "Left": KEY_LEFT, "Right": KEY_RIGHT,
		"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4,
		"F5": KEY_F5, "F6": KEY_F6, "F7": KEY_F7, "F8": KEY_F8,
		"F9": KEY_F9, "F10": KEY_F10, "F11": KEY_F11, "F12": KEY_F12,
		"C": KEY_C, "1": KEY_1, "2": KEY_2, "3": KEY_3,
	}
	if key_name in mapping:
		var ev := InputEventKey.new()
		ev.physical_keycode = mapping[key_name]
		return ev
	return null

func get_display_name(key_name: String) -> String:
	if key_name.is_empty():
		return "—"
	return key_name

func is_action_pressed(action_name: String) -> bool:
	return Input.is_action_pressed("game_" + action_name)

func is_action_just_pressed(action_name: String) -> bool:
	return Input.is_action_just_pressed("game_" + action_name)

func is_action_just_released(action_name: String) -> bool:
	return Input.is_action_just_released("game_" + action_name)
