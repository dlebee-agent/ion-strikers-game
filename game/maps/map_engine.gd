class_name MapEngine
extends RefCounted

# GDScript port of laser-arena/public/maps/_engine.js.
# Compiles a map definition (shapes array) into flat { walls, cover } box lists
# that the movement controller and the renderer both consume.

const DEFAULT_ARENA := 21.0
const DEFAULT_T := 0.7
const DEFAULT_CRATE := 1.7
const DEFAULT_CRATE_H := 1.4


static func compile(def: Dictionary) -> Dictionary:
	var arena: float = def.get("arena", DEFAULT_ARENA)
	var walls: Array[Dictionary] = []
	var cover: Array[Dictionary] = []
	for sh: Dictionary in def.get("shapes", []):
		var part := _compile_shape(sh, arena)
		for pair: Array in _mirrors_for(sh.get("mirror", "")):
			var sx: float = pair[0]
			var sz: float = pair[1]
			for b: Dictionary in part["walls"]:
				walls.append(_mirror_box(b, sx, sz))
			for b: Dictionary in part["cover"]:
				cover.append(_mirror_box(b, sx, sz))
	return {
		"id": def.get("id", ""),
		"name": def.get("name", ""),
		"desc": def.get("desc", ""),
		"arena": arena,
		# Optional [half_x, half_z] floor extents for maps that are not
		# square; everything defaults to the square the arena value implies.
		"floor": def.get("floor", []),
		"spawns": def.get("spawns", {}),
		"pads": def.get("pads", []),
		"theme": def.get("theme", {}),
		"sky": def.get("sky", {}),
		"walls": walls,
		"cover": cover,
	}


static func _mirrors_for(m: String) -> Array:
	if m == "x":
		return [[1.0, 1.0], [-1.0, 1.0]]
	if m == "z":
		return [[1.0, 1.0], [1.0, -1.0]]
	if m == "xz":
		return [[1.0, 1.0], [-1.0, -1.0], [-1.0, 1.0], [1.0, -1.0]]
	return [[1.0, 1.0]]


static func _mirror_box(b: Dictionary, sx: float, sz: float) -> Dictionary:
	var out := b.duplicate()
	out["x"] = b["x"] * sx
	out["z"] = b["z"] * sz
	return out


static func _box(x: float, z: float, sx_val: float, sz_val: float, h: float) -> Dictionary:
	return {"x": x, "z": z, "sx": sx_val, "sz": sz_val, "h": h, "y0": 0.0}


static func _abs_h(sh: Dictionary, h: float) -> float:
	return sh.get("on", 0.0) + h


static func _stair_boxes(o: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spacing: float = o.get("spacing", 1.2)
	var depth: float = o.get("depth", 1.7)
	var width: float = o.get("width", 8.0)
	var at: float = o.get("at", 0.0)
	var start: float = o["start"]
	var heights: Array = o["heights"]
	for i in heights.size():
		var entry = heights[i]
		var step_h: float
		var w := width
		var d := depth
		if entry is Dictionary:
			step_h = entry["h"]
			w = entry.get("width", width)
			d = entry.get("depth", depth)
		else:
			step_h = float(entry)
		var along: float = start + i * spacing
		if o.get("axis", "z") == "x":
			out.append(_box(along, at, d, w, step_h))
		else:
			out.append(_box(at, along, w, d, step_h))
	return out


static func _compile_shape(sh: Dictionary, arena: float) -> Dictionary:
	var walls: Array[Dictionary] = []
	var cover: Array[Dictionary] = []
	if sh.has("perimeter"):
		var h: float = sh.get("h", 4.0)
		var t: float = sh.get("t", DEFAULT_T)
		walls.append(_box(0, -arena, arena * 2, t, h))
		walls.append(_box(0, arena, arena * 2, t, h))
		# The side walls stop at the inner face of the end walls rather than
		# running the full span. Overlapping them left four corner squares
		# covered twice at one height, which flickers; the end walls already
		# reach the corners, so nothing opens up.
		walls.append(_box(-arena, 0, t, arena * 2 - t, h))
		walls.append(_box(arena, 0, t, arena * 2 - t, h))
	elif sh.has("wall"):
		var w: Array = sh["wall"]
		walls.append(_box(w[0], w[1], w[2], w[3], _abs_h(sh, sh.get("h", 3.0))))
	elif sh.has("cover"):
		var c: Array = sh["cover"]
		cover.append(_box(c[0], c[1], c[2], c[3], _abs_h(sh, sh["h"])))
	elif sh.has("crate"):
		var c: Array = sh["crate"]
		var s: float = sh.get("s", DEFAULT_CRATE)
		cover.append(_box(c[0], c[1], s, s, _abs_h(sh, sh.get("h", DEFAULT_CRATE_H))))
	elif sh.has("stairs"):
		cover.append_array(_stair_boxes(sh["stairs"]))
	if sh.has("base"):
		var base_y: float = sh["base"]
		for b in walls:
			b["y0"] = base_y
		for b in cover:
			b["y0"] = base_y
	return {"walls": walls, "cover": cover}
