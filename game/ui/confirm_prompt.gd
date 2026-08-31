extends CanvasLayer

## Full-screen yes/no prompt. Autoload so any scene can call `ConfirmPrompt.ask(...)`.

var _root: Control
var _message: Label
var _yes: Button
var _no: Button
var _on_yes: Callable


func _ready() -> void:
	layer = 80
	visible = false
	_build()


func ask(message: String, on_yes: Callable, yes_text := "YES", no_text := "NO") -> void:
	_message.text = message
	_yes.text = yes_text
	_no.text = no_text
	_on_yes = on_yes
	visible = true
	_no.call_deferred("grab_focus")


func close() -> void:
	_on_yes = Callable()
	visible = false


func is_open() -> bool:
	return visible


func _build() -> void:
	_root = Control.new()
	MenuLook.fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	MenuLook.fill(dim)
	dim.color = Color(0.02, 0.016, 0.039, 0.78)
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	MenuLook.fill(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size.x = 420
	MenuLook.apply_panel(card, 22)
	center.add_child(card)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	card.add_child(cv)

	var kick := MenuLook.kicker("Confirm")
	var kick_m := MarginContainer.new()
	kick_m.add_theme_constant_override("margin_bottom", 10)
	kick_m.add_child(kick)
	cv.add_child(kick_m)

	_message = MenuLook.body("", 16, MenuLook.INK, true)
	_message.custom_minimum_size.x = 360
	cv.add_child(_message)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var row_m := MarginContainer.new()
	row_m.add_theme_constant_override("margin_top", 22)
	row_m.add_child(row)
	cv.add_child(row_m)

	_no = Button.new()
	_no.text = "NO"
	_no.custom_minimum_size.y = 44
	_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_ghost(_no)
	_no.pressed.connect(_cancel)
	row.add_child(_no)

	_yes = Button.new()
	_yes.text = "YES"
	_yes.custom_minimum_size.y = 44
	_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuLook.apply_primary(_yes, true)
	_yes.pressed.connect(_accept)
	row.add_child(_yes)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_cancel()


func _accept() -> void:
	var cb := _on_yes
	close()
	if cb.is_valid():
		cb.call()


func _cancel() -> void:
	close()
