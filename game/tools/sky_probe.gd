extends SceneTree

# Rebake parkour sky faces: godot --headless --path game --script res://tools/sky_probe.gd

const SkyCubemapScript = preload("res://maps/sky_cubemap.gd")
const Parkour = preload("res://maps/parkour.gd")
const EngineScript = preload("res://maps/map_engine.gd")


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var compiled := EngineScript.compile(Parkour.definition())
	SkyCubemapScript.bake_pngs(compiled, "res://maps/sky_parkour")
	print("baked in ", Time.get_ticks_msec() - t0, " ms")
	quit()
