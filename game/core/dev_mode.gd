extends Node

var active: bool = false

func _ready() -> void:
	active = OS.is_debug_build() or OS.has_feature("dev")
	for arg in OS.get_cmdline_args():
		if arg == "--dev":
			active = true
			break
