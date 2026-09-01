extends SceneTree

# Sanity harness for the grid arena map: nav coverage, spawn routing, and the
# surfaces its routes depend on (garage, deck, ramps, core, catwalk, sky ring).
# Run: godot --headless --path game --script res://tools/skydeck_check.gd

var failed := 0


func _initialize() -> void:
	var compiled := MapEngine.compile(MapCatalog.builtin_definition("skydeck"))
	var cols := MapBuilder.build_world(compiled)
	var arena: float = compiled["arena"]

	var nav := BotNav.new()
	var seeds: Array[Vector3] = [
		Vector3(0, 3.45, -24.5), Vector3(0, 3.45, 24.5), Vector3(10.5, 0, 0),
	]
	var t0 := Time.get_ticks_msec()
	nav.build(cols, arena, seeds)
	print("nav build ms: ", Time.get_ticks_msec() - t0, "  open cells: ", nav.open_points.size())
	_check(nav.open_points.size() > 500, "nav flood-fill covers the arena")

	# Every tier a route crosses, probed from above. The garage is probed under
	# its own ceiling; from the sky the deck rightly wins that column.
	_surface(nav, "garage floor", 0.0, -27.5, 2.0, 0.0)
	_surface(nav, "base deck", 0.0, -22.0, 12.0, 3.2)
	# Probed at tread centres: a coordinate on the seam between two treads
	# reads whichever the sweep catches first and tells you nothing.
	_surface(nav, "gate ramp mid", 10.5, -8.5, 12.0, 1.8)
	_surface(nav, "upramp mid", -7.6, -18.5, 12.0, 5.3)
	_surface(nav, "core lane", -3.0, 0.0, 12.0, 1.6)
	_surface(nav, "catwalk", 16.6, 0.0, 12.0, 7.0)
	_surface(nav, "sky bridge", 11.6, 0.0, 12.0, 7.0)
	_surface(nav, "sky ring", 0.0, 5.8, 12.0, 7.0)

	print("-- line of sight --")
	_check(nav.blocked(Vector3(0, 1.6, -27.5), Vector3(0, 1.15, 27.5)),
		"garage cannot see the other garage")
	_check(nav.blocked(Vector3(0, 4.8, -22.0), Vector3(0, 4.8, 22.0)),
		"deck cannot see the other deck through the core pylon")
	_check(not nav.blocked(Vector3(16.6, 8.6, -10.0), Vector3(16.6, 8.6, 10.0)),
		"catwalk has a clear lane along itself")

	print("-- routing --")
	_route(nav, "blue spawn -> red spawn", Vector3(0, 3.45, -24.5), Vector3(0, 3.45, 24.5))
	_route(nav, "blue spawn -> catwalk mid", Vector3(0, 3.45, -24.5), Vector3(16.6, 7.0, 0.0))
	_route(nav, "blue spawn -> mid ground", Vector3(0, 3.45, -24.5), Vector3(10.5, 0.0, 0.0))

	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


func _route(nav: BotNav, label: String, from: Vector3, to: Vector3) -> void:
	var t0 := Time.get_ticks_msec()
	var path := nav.find_path(from, to)
	print("  %-26s %d waypoints in %dms" % [label + ":", path.size(), Time.get_ticks_msec() - t0])
	if path.size() < 2:
		failed += 1


func _surface(nav: BotNav, label: String, x: float, z: float, ceiling: float, want: float) -> void:
	var y := nav.surface_at(x, z, ceiling)
	var ok := absf(y - want) < 0.3
	print("  %-14s y=%6.2f (want %.2f) %s" % [label, y, want, "ok" if ok else "FAIL"])
	if not ok:
		failed += 1


func _check(cond: bool, label: String) -> void:
	print("  %s: %s" % [label, "ok" if cond else "FAIL"])
	if not cond:
		failed += 1
