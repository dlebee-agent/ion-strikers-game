extends Node

signal screen_changed(screen_name: String)

var current_screen: String = ""
var _screens: Dictionary = {}
var _floating_layers: Dictionary = {}

func register_screen(screen_name: String, node: Control) -> void:
	_screens[screen_name] = node
	node.visible = false
	node.tree_exiting.connect(_forget_screen.bind(screen_name), CONNECT_ONE_SHOT)

func register_floating_layer(layer_name: String, node: Control, visible_on: Array) -> void:
	_floating_layers[layer_name] = {"node": node, "visible_on": visible_on}
	node.visible = false
	node.tree_exiting.connect(_forget_layer.bind(layer_name), CONNECT_ONE_SHOT)

# This autoload outlives the scene that registered with it, so a scene change
# leaves it pointing at freed Controls. current_screen is the one that bites:
# registration hides every screen, so a leftover name makes show() decide it has
# nothing to do and the rebuilt menu comes up blank.
func _forget_screen(screen_name: String) -> void:
	_screens.erase(screen_name)
	if current_screen == screen_name:
		current_screen = ""

func _forget_layer(layer_name: String) -> void:
	_floating_layers.erase(layer_name)

func show(screen_name: String) -> void:
	if screen_name == current_screen:
		return
	for sname in _screens:
		_screens[sname].visible = (sname == screen_name)
	for lname in _floating_layers:
		var layer_data: Dictionary = _floating_layers[lname]
		layer_data["node"].visible = screen_name in layer_data["visible_on"]
	current_screen = screen_name
	screen_changed.emit(screen_name)

func hide_all() -> void:
	for sname in _screens:
		_screens[sname].visible = false
	for lname in _floating_layers:
		_floating_layers[lname]["node"].visible = false
	current_screen = ""
