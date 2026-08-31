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
	"fire": ["Mouse1", ""],
	"melee": ["Mouse2", ""],
	"special": ["F", ""],
	"scoreboard": ["Tab", "L"],
	"controls": ["H", ""],
	"team_menu": ["M", ""],
	"chat_all": ["Y", "Enter"],
	"chat_team": ["U", ""],
	"spec_swap": ["V", ""],
}

const BIND_GROUPS: Array = [
	["Movement", ["forward", "back", "left", "right", "jump", "crouch", "walk"]],
	["Combat", ["fire", "melee", "special"]],
	["Communication", ["chat_all", "chat_team"]],
	["Interface", ["team_menu", "scoreboard", "controls", "spec_swap"]],
]

const BIND_LABELS: Dictionary = {
	"forward": "Forward",
	"back": "Back",
	"left": "Strafe left",
	"right": "Strafe right",
	"jump": "Jump",
	"crouch": "Duck / crouch",
	"walk": "Walk (slow)",
	"fire": "Fire laser",
	"melee": "Melee",
	"special": "Special attack (hold)",
	"scoreboard": "Scoreboard (hold)",
	"controls": "Controls card",
	"team_menu": "Team menu",
	"chat_all": "Global message",
	"chat_team": "Team chat",
	"spec_swap": "Toggle spectate mode",
}

const MOUSE_BUTTON_NAMES: Dictionary = {
	MOUSE_BUTTON_LEFT: "Mouse1",
	MOUSE_BUTTON_RIGHT: "Mouse2",
	MOUSE_BUTTON_MIDDLE: "Mouse3",
	MOUSE_BUTTON_XBUTTON1: "Mouse4",
	MOUSE_BUTTON_XBUTTON2: "Mouse5",
	MOUSE_BUTTON_WHEEL_UP: "WheelUp",
	MOUSE_BUTTON_WHEEL_DOWN: "WheelDown",
}

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
	# Old defaults were F1, then H+F1. On Mac F1 is brightness-down, so anyone
	# still on those defaults picks up H; a custom bind is left alone.
	var ctrl: Array = bindings["controls"]
	if (ctrl[0] == "F1" and (ctrl[1] as String).is_empty()) or (ctrl[0] == "H" and ctrl[1] == "F1"):
		bindings["controls"] = BIND_DEFAULTS["controls"].duplicate()
		save_bindings()

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
	if action_name not in bindings or slot < 0 or slot > 1:
		return
	if not key_name.is_empty():
		for other: String in bindings:
			for i in 2:
				if bindings[other][i] == key_name:
					bindings[other][i] = ""
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
	for button_index: int in MOUSE_BUTTON_NAMES:
		if MOUSE_BUTTON_NAMES[button_index] == key_name:
			var mouse_ev := InputEventMouseButton.new()
			mouse_ev.button_index = button_index
			return mouse_ev
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

func event_to_bind_name(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		var button_index: int = (event as InputEventMouseButton).button_index
		if button_index in MOUSE_BUTTON_NAMES:
			return MOUSE_BUTTON_NAMES[button_index]
		return ""
	if event is InputEventKey:
		var mapping := {
			KEY_W: "W", KEY_A: "A", KEY_S: "S", KEY_D: "D",
			KEY_E: "E", KEY_F: "F", KEY_G: "G", KEY_H: "H",
			KEY_I: "I", KEY_J: "J", KEY_K: "K", KEY_L: "L",
			KEY_M: "M", KEY_N: "N", KEY_O: "O", KEY_P: "P",
			KEY_Q: "Q", KEY_R: "R", KEY_T: "T", KEY_U: "U",
			KEY_V: "V", KEY_X: "X", KEY_Y: "Y", KEY_Z: "Z",
			KEY_SPACE: "Space", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl",
			KEY_TAB: "Tab", KEY_ENTER: "Enter",
			KEY_UP: "Up", KEY_DOWN: "Down", KEY_LEFT: "Left", KEY_RIGHT: "Right",
			KEY_F1: "F1", KEY_F2: "F2", KEY_F3: "F3", KEY_F4: "F4",
			KEY_F5: "F5", KEY_F6: "F6", KEY_F7: "F7", KEY_F8: "F8",
			KEY_F9: "F9", KEY_F10: "F10", KEY_F11: "F11", KEY_F12: "F12",
			KEY_C: "C", KEY_1: "1", KEY_2: "2", KEY_3: "3",
		}
		var keycode: int = (event as InputEventKey).physical_keycode
		if keycode in mapping:
			return mapping[keycode]
	return ""

func get_display_name(key_name: String) -> String:
	if key_name.is_empty():
		return "—"
	return key_name

func primary(action_name: String) -> String:
	if action_name not in bindings:
		return ""
	for k in bindings[action_name]:
		if not (k as String).is_empty():
			return k
	return ""

func fmt(action_name: String) -> String:
	if action_name not in bindings:
		return "—"
	var parts: PackedStringArray = []
	for k in bindings[action_name]:
		if not (k as String).is_empty():
			parts.append(get_display_name(k).to_upper())
	return " / ".join(parts) if parts.size() > 0 else "—"

func is_action_pressed(action_name: String) -> bool:
	return Input.is_action_pressed("game_" + action_name)

func is_action_just_pressed(action_name: String) -> bool:
	return Input.is_action_just_pressed("game_" + action_name)

func is_action_just_released(action_name: String) -> bool:
	return Input.is_action_just_released("game_" + action_name)
