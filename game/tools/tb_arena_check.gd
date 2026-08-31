extends SceneTree

# Throwaway: imports the community arena and reports what came through.
# Run: godot --headless --path game --script res://tools/tb_arena_check.gd

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var level := MapCatalog.load_community("community/arena1")
	var ms := Time.get_ticks_msec() - t0

	print("name:      ", level.name)
	print("import:    %d ms" % ms)
	print("brushes:   ", level.world.brush_count() if level.world else 0)
	print("bounds:    ", level.bounds)
	print("arena:     %.1f m" % level.arena)
	print("spawns:    %d  (blue %d, red %d)" % [level.spawn_count(),
		(level.spawns.get("blue", []) as Array).size(),
		(level.spawns.get("red", []) as Array).size()])
	print("pads:      ", level.pads.size())
	if level.mesh:
		print("surfaces:  ", level.mesh.get_surface_count())
		var verts := 0
		for i in level.mesh.get_surface_count():
			verts += level.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()
		print("triangles: ", verts / 3)
		for i in level.mesh.get_surface_count():
			print("    %s" % level.mesh.surface_get_name(i))
	print("playable:  ", level.ok())
	if level.warnings.is_empty():
		print("warnings:  none")
	else:
		print("warnings:")
		for w: String in level.warnings:
			print("    ", w)

	# How much of the level is actually walkable, and does it have real slopes?
	if level.world:
		var res := TraceResult.new()
		var half := Vector3(0.4, 0.895, 0.4)
		var landed := 0
		var sloped := 0
		var probes := 0
		var step := 1.0
		var x := level.bounds.position.x + step
		while x < level.bounds.end.x:
			var z := level.bounds.position.z + step
			while z < level.bounds.end.z:
				probes += 1
				var top := level.bounds.end.y + 1.0
				level.world.trace_box(Vector3(x, top, z), Vector3(x, level.bounds.position.y - 1.0, z), half, res)
				if res.hit():
					landed += 1
					if res.normal.y > 0.5 and res.normal.y < 0.999:
						sloped += 1
				z += step
			x += step
		print("")
		print("probes:    %d, landed on something: %d, landed on a slope: %d" % [probes, landed, sloped])
	quit()
