extends SceneTree

# Throwaway harness for the importer, on a map small enough to reason about.
# Run: godot --headless --path game --script res://tools/tb_import_check.gd

const TMP := "res://maps/community/_import_check.map"

# A floor slab, one wall, and spawns for both sides. Face winding follows the
# verified box template: for x0..x1, y0..y1, z0..z1 the six lines are +X, -X,
# +Y, -Y, +Z, -Z in that order.
const SOURCE := """
// Game: IonStrikers
// Format: Valve
{
"mapversion" "220"
"classname" "worldspawn"
"message" "Import Check"
"wad" "C:\\\\somewhere\\\\else\\\\arena1.wad"
{
( 512 512 -16 ) ( 512 -512 -16 ) ( 512 -512 0 ) arena_floor [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -512 -512 -16 ) ( -512 512 -16 ) ( -512 512 0 ) arena_floor [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( -512 512 -16 ) ( 512 512 -16 ) ( 512 512 0 ) arena_floor [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 512 -512 -16 ) ( -512 -512 -16 ) ( -512 -512 0 ) arena_floor [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 512 -512 0 ) ( -512 -512 0 ) ( -512 512 0 ) arena_floor [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( -512 -512 -16 ) ( 512 -512 -16 ) ( 512 512 -16 ) __TB_empty [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
}
{
( 288 256 0 ) ( 288 -256 0 ) ( 288 -256 128 ) ion/wall [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 256 -256 0 ) ( 256 256 0 ) ( 256 256 128 ) ion/wall [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 256 256 0 ) ( 288 256 0 ) ( 288 256 128 ) ion/wall [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 288 -256 0 ) ( 256 -256 0 ) ( 256 -256 128 ) ion/wall [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 1 1
( 288 -256 128 ) ( 256 -256 128 ) ( 256 256 128 ) ion/accent [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
( 256 -256 0 ) ( 288 -256 0 ) ( 288 256 0 ) __TB_empty [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 1 1
}
}
{
"classname" "info_player_team1"
"origin" "0 -400 40"
"angle" "90"
}
{
"classname" "info_player_team2"
"origin" "0 400 40"
"angle" "270"
}
{
"classname" "info_player_start"
"origin" "0 0 40"
"angle" "0"
}
"""

var _fails := 0


func _ok(label: String, got, want, tol := 0.001) -> void:
	var pass_: bool
	if got is float and want is float:
		pass_ = absf(got - want) <= tol
	elif got is Vector3 and want is Vector3:
		pass_ = (got - want).length() <= tol
	else:
		pass_ = got == want
	if not pass_:
		_fails += 1
	print("  %-50s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


func _initialize() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(SOURCE)
	f.close()

	var u := TbMap.UNIT_SCALE
	var level := TbImporter.import_file(TMP)

	print("-- import --")
	_ok("level is playable", level.ok(), true)
	_ok("name from worldspawn message", level.name, "Import Check")
	_ok("two brushes", level.world.brush_count(), 2)
	_ok("two collider bounds", level.colliders.size(), 2)
	if not level.warnings.is_empty():
		print("    warnings: ", level.warnings)
	_ok("no warnings", level.warnings.size(), 0)

	print("-- the WAD is found beside the map, not where it was authored --")
	# worldspawn names a Windows path from another machine, so only the filename
	# can be used, resolved against the map's own directory.
	var surfaces: Array[String] = []
	for i in level.mesh.get_surface_count():
		surfaces.append(level.mesh.surface_get_name(i))
	surfaces.sort()
	_ok("a surface per drawn texture", surfaces, ["arena_floor", "ion/accent", "ion/wall"] as Array[String])

	print("-- spawns --")
	_ok("four spawn points", level.spawn_count(), 2)
	var blue: Array = level.spawns["blue"]
	var red: Array = level.spawns["red"]
	_ok("one per team", [blue.size(), red.size()], [1, 1])
	# Quake (0,-400,40) is Godot (0, 40u, 400u).
	_ok("blue spawn converted", blue[0]["position"], Vector3(0, 40, 400) * u)
	_ok("red spawn converted", red[0]["position"], Vector3(0, 40, -400) * u)
	# Quake's angle counts from +X, the game's yaw from -Z, a quarter turn apart.
	_ok("blue faces down the map", blue[0]["yaw"], 0.0)
	_ok("red faces back up it", red[0]["yaw"], 180.0)

	print("-- extents --")
	_ok("arena is half the wider span", level.arena, 512.0 * u, 0.01)
	_ok("bounds span the floor", level.bounds.size.x, 1024.0 * u, 0.01)

	print("-- the world is solid --")
	var res := TraceResult.new()
	var half := Vector3(0.4, 0.895, 0.4)
	# Drop onto the floor, whose top is z=0 in map space and y=0 in Godot.
	level.world.trace_box(Vector3(0, 5, 0), Vector3(0, -1, 0), half, res)
	_ok("a drop lands on the floor", res.end_pos.y - half.y, 0.0, 0.01)
	_ok("landing normal points up", res.normal, Vector3(0, 1, 0))
	# The wall sits at map x 256..288, so a sweep across it must stop.
	level.world.trace_box(Vector3(0, 1, 0), Vector3(10, 1, 0), half, res)
	_ok("the wall stops a sweep", res.hit(), true)
	_ok("stopped before the wall face", res.end_pos.x < 256.0 * u, true)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
