extends SceneTree

# Throwaway: runs what match.gd does when it builds a map, and times it.
# Run: godot --headless --path game --script res://tools/client_build_check.gd

# A build slower than this stalls the connect handshake past its timeout.
const BUDGET_MS := 2000

var failed := 0


func _initialize() -> void:
	var host := Node3D.new()
	root.add_child(host)

	for map_id in ["parkour", "skydeck", "community/arena1"]:
		print("== ", map_id)
		var t0 := Time.get_ticks_msec()
		if MapCatalog.is_community(map_id):
			var level := MapCatalog.load_community(map_id)
			print("   import        %6d ms" % (Time.get_ticks_msec() - t0))
			var t1 := Time.get_ticks_msec()
			var mi := MeshInstance3D.new()
			mi.mesh = level.mesh
			host.add_child(mi)
			print("   mesh instance %6d ms" % (Time.get_ticks_msec() - t1))
			var t2 := Time.get_ticks_msec()
			MapBuilder.build_ambience(host, MapCatalog.ambience_for(level))
			print("   ambience      %6d ms" % (Time.get_ticks_msec() - t2))
		else:
			var compiled := MapEngine.compile(MapCatalog.builtin_definition(map_id))
			var t1 := Time.get_ticks_msec()
			MapBuilder.build_visual(host, compiled)
			print("   build_visual  %6d ms" % (Time.get_ticks_msec() - t1))
		var total := Time.get_ticks_msec() - t0
		print("   TOTAL         %6d ms" % total)
		# The client builds the map while the server is already counting it as
		# joined, so a slow build is not slow, it is a disconnect.
		if total > BUDGET_MS:
			failed += 1
			print("   FAIL: over the %d ms budget" % BUDGET_MS)
		for c in host.get_children():
			c.queue_free()

	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)
