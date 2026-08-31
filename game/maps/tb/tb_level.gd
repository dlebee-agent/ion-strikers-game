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
# Half the level's larger horizontal extent, which is what the systems built
# around a square arena expect.
var arena := 0.0
var bounds := AABB()
# Everything that went wrong but did not stop the import.
var warnings: Array[String] = []


func spawn_count() -> int:
	var n := 0
	for team: String in spawns:
		n += (spawns[team] as Array).size()
	return n


func ok() -> bool:
	return world != null and world.brush_count() > 0 and spawn_count() > 0
