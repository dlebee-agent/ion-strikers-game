extends SceneTree

# Guards every built-in map against z-fighting: two surfaces at one height
# covering the same ground render the same pixels twice and flicker between
# them as the camera moves. Checks the solids and the glow trim laid over
# each one, mirroring what MapBuilder draws.
# Run: godot --headless --path game --script res://tools/map_overlap_check.gd

# Trims are inset by these margins, matching MapBuilder._trim_span.
const WALL_INSET := 0.06
const COVER_INSET := 0.05
# Below this a shared edge is contact, not overlap.
const EPS := 0.004

var failed := 0


func _initialize() -> void:
	for map_id: String in MapCatalog.BUILTIN_IDS:
		_check_map(map_id)
	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


func _check_map(map_id: String) -> void:
	var compiled := MapEngine.compile(MapCatalog.builtin_definition(map_id))
	var faces: Array = []
	for b: Dictionary in compiled["walls"]:
		faces.append(_face(b, 0.0, 0.0, "wall"))
		faces.append(_face(b, 0.06, WALL_INSET, "wall-trim"))
	for b: Dictionary in compiled["cover"]:
		faces.append(_face(b, 0.0, 0.0, "cover"))
		faces.append(_face(b, 0.04, COVER_INSET, "cover-trim"))

	var hits := 0
	for i in faces.size():
		for j in range(i + 1, faces.size()):
			var a: Dictionary = faces[i]
			var d: Dictionary = faces[j]
			if absf(a["y"] - d["y"]) > EPS:
				continue
			var ox := _overlap(a["x"], a["sx"], d["x"], d["sx"])
			var oz := _overlap(a["z"], a["sz"], d["z"], d["sz"])
			if ox <= EPS or oz <= EPS:
				continue
			hits += 1
			print("  %s y=%.2f overlap %.2fx%.2f  %s(%.1f,%.1f) vs %s(%.1f,%.1f)" % [
				map_id, a["y"], ox, oz,
				a["kind"], a["x"], a["z"], d["kind"], d["x"], d["z"]])
	print("  %-12s %d surfaces, %d coplanar overlaps" % [map_id, faces.size(), hits])
	failed += hits


func _face(b: Dictionary, lift: float, inset: float, kind: String) -> Dictionary:
	var sx: float = b["sx"]
	var sz: float = b["sz"]
	return {
		"y": float(b["h"]) + lift,
		"x": float(b["x"]), "z": float(b["z"]),
		"sx": maxf(sx - inset, sx * 0.5) if inset > 0.0 else sx,
		"sz": maxf(sz - inset, sz * 0.5) if inset > 0.0 else sz,
		"kind": kind,
	}


static func _overlap(ca: float, sa: float, cb: float, sb: float) -> float:
	return minf(ca + sa * 0.5, cb + sb * 0.5) - maxf(ca - sa * 0.5, cb - sb * 0.5)
