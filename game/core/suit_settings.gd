class_name SuitSettings
extends RefCounted

## The suit finish this client paints. Cosmetic only: every pawn this machine
## draws uses it, so it is a preference rather than something the host locks.
## A class_name rather than an autoload, so the editor can resolve it when it
## reloads a single script.

const SETTINGS_PATH := "user://settings.cfg"

static var _style: String = SuitStyle.DEFAULT
static var _loaded := false
static var _listeners: Array[Callable] = []

static var style: String:
	get:
		_ensure()
		return _style


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_style = SuitStyle.normalize(str(cfg.get_value("suit", "style", SuitStyle.DEFAULT)))


static func listen(cb: Callable) -> void:
	_ensure()
	if not _listeners.has(cb):
		_listeners.append(cb)


static func set_style(value: String) -> void:
	_ensure()
	var next := SuitStyle.normalize(value)
	if next == _style:
		return
	_style = next
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("suit", "style", _style)
	cfg.save(SETTINGS_PATH)
	for cb in _listeners:
		if cb.is_valid():
			cb.call()
