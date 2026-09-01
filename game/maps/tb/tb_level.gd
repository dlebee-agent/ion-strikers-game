class_name TbLevel
extends RefCounted

# An imported .map, in the shape the rest of the game consumes.

var id := ""
var name := ""
# Brush geometry for movement, hitscan and everything else that asks the world
# a question.
var world: CollisionWorld = null
# One ArrayMesh for the whole level, grouped into a surface per texture.
var mesh: ArrayMesh = null
# Per-brush bounding boxes. Bot navigation still reads AABBs, and a bounding box
# is a safe over-approximation for it: it can make a bot think a ramp's airspace
# is blocked, which costs a path, not a bug.
var colliders: Array[AABB] = []
# Team name to an array of {"position": Vector3, "yaw": float}.
var spawns: Dictionary = {}
var pads: Array = []
# Which baked sky set to use, from worldspawn's `sky` key. Baked only: the
# procedural generator takes the better part of a minute for one cubemap, which
# is fine as an offline bake and fatal in the middle of a connect.
var sky_id := "parkour"

# Half the level's larger horizontal extent, which is what the systems built
# around a square arena expect.
var arena := 0.0
var bounds := AABB()
# Everything that went wrong but did not stop the import.
var warnings: Array[String] = []


## How far below a spawn point the floor is allowed to be before the point is
## left where the mapper put it. Quake-family editors place a spawn at the
## player's centre, a good metre and a half up; anything much further is a
## point over a pit, which snapping would hide.
const SPAWN_REACH := 4.0


## Drops every spawn point onto the floor under it, so a body arrives standing
## rather than falling in from wherever the editor's origin sat.
func ground_spawns() -> void:
	if world == null:
		return
	var half := Vector3(Movement.PLAYER_RADIUS, Movement.STAND_HEIGHT * 0.5, Movement.PLAYER_RADIUS)
	var lift := Vector3(0.0, half.y, 0.0)
	var probe := TraceResult.new()
	for team: String in spawns:
		for entry: Dictionary in spawns[team]:
			var at: Vector3 = entry["position"]
			world.trace_box(at + lift, at + lift - Vector3(0.0, SPAWN_REACH, 0.0), half, probe)
			if probe.start_solid:
				warnings.append("%s spawn at %s is inside the walls" % [team, at])
			elif not probe.hit():
				warnings.append("%s spawn at %s has no floor within %.0fm" % [team, at, SPAWN_REACH])
			else:
				entry["position"] = Vector3(at.x, probe.end_pos.y - half.y, at.z)


func spawn_count() -> int:
	var n := 0
	for team: String in spawns:
		n += (spawns[team] as Array).size()
	return n


func ok() -> bool:
	return world != null and world.brush_count() > 0 and spawn_count() > 0
