extends SceneTree

# Rebake built-in sky faces: godot --headless --path game --script res://tools/sky_probe.gd

const SkyCubemapScript = preload("res://maps/sky_cubemap.gd")
const CatalogScript = preload("res://maps/map_catalog.gd")
const EngineScript = preload("res://maps/map_engine.gd")

const BUILTIN_IDS := ["parkour", "grid_arena"]


func _initialize() -> void:
	for map_id: String in BUILTIN_IDS:
		var t0 := Time.get_ticks_msec()
		DirAccess.make_dir_recursive_absolute("res://maps/%s" % map_id)
		var compiled := EngineScript.compile(CatalogScript.builtin_definition(map_id))
		SkyCubemapScript.bake_pngs(compiled, "res://maps/%s/sky" % map_id)
		print(map_id, " baked in ", Time.get_ticks_msec() - t0, " ms")
	quit()
