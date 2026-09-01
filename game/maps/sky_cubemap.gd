class_name SkyCubemap
extends RefCounted

# Procedural deep-space cubemap. Every pixel of all six faces is shaded from
# the 3D direction it looks along, so adjacent faces agree on shared edges.

const _SHADER := preload("res://maps/sky_cubemap.gdshader")
const _NEBULA_RES := 176
const _DEFAULT_SIZE := 512
const _DEFAULT_NEBULA: Array[int] = [0x5a2ba8, 0x1240a8, 0xb02a6a, 0xd06a3a]
const _DEFAULT_GALAXY_TINT: Array[int] = [0xffd8b0, 0xbcd4ff, 0xffc0e0]

static var _cache: Dictionary = {}
static var _rng: int = 0


static func make_sky(compiled: Dictionary) -> Sky:
	var cube := cubemap_for(compiled)
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("sky_cube", cube)
	mat.set_shader_parameter("exposure", 1.0)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	return sky


static func cubemap_for(compiled: Dictionary) -> Cubemap:
	var key := str(compiled.get("id", "default"))
	if _cache.has(key):
		return _cache[key]
	var baked := _load_baked(key)
	if baked:
		_cache[key] = baked
		return baked
	var sky: Dictionary = compiled.get("sky", {})
	var raw: Dictionary = sky.get("cubemap", {})
	if not raw.has("seed"):
		raw = raw.duplicate()
		raw["seed"] = _seed_from_id(key)
	var faces := _build_faces(raw)
	var cube := _cubemap_from_faces(faces)
	_cache[key] = cube
	return cube


static func bake_pngs(compiled: Dictionary, stem: String) -> Array[Image]:
	var sky: Dictionary = compiled.get("sky", {})
	var raw: Dictionary = sky.get("cubemap", {})
	if not raw.has("seed"):
		raw = raw.duplicate()
		raw["seed"] = _seed_from_id(str(compiled.get("id", "default")))
	var faces := _build_faces(raw)
	for i in faces.size():
		faces[i].save_png("%s_%d.png" % [stem, i])
	return faces


static func _load_baked(key: String) -> Cubemap:
	var faces: Array[Image] = []
	for i in 6:
		var path := "res://maps/%s/sky_%d.png" % [key, i]
		if not ResourceLoader.exists(path):
			return null
		var res: Resource = ResourceLoader.load(path)
		var img: Image
		if res is Image:
			img = (res as Image).duplicate()
		elif res is Texture2D:
			img = (res as Texture2D).get_image()
		if img == null:
			return null
		if img.is_compressed():
			img.decompress()
		faces.append(img)
	return _cubemap_from_faces(faces)


static func _cubemap_from_faces(faces: Array[Image]) -> Cubemap:
	var cube := Cubemap.new()
	var err := cube.create_from_images(faces)
	if err != OK:
		push_error("SkyCubemap: create_from_images failed (%s)" % err)
	return cube


static func _seed_from_id(key: String) -> int:
	var h := 2166136261
	for i in key.length():
		h = _imul(h ^ key.unicode_at(i), 16777619)
	return _u32(h) % 100000


static func _build_faces(raw: Dictionary) -> Array[Image]:
	var spec := {
		"seed": int(raw.get("seed", 1)),
		"stars": int(raw.get("stars", 3200)),
		"galaxies": int(raw.get("galaxies", 7)),
		"density": float(raw.get("density", 0.5)),
		"scale": float(raw.get("scale", 2.2)),
		"size": int(raw.get("size", _DEFAULT_SIZE)),
		"nebula": raw.get("nebula", _DEFAULT_NEBULA),
		"galaxy_tint": raw.get("galaxyTint", _DEFAULT_GALAXY_TINT),
	}
	var pal: Array[Vector3] = []
	for h in spec["nebula"]:
		pal.append(_hex_rgb(int(h)))
	var tints: Array[Vector3] = []
	for h in spec["galaxy_tint"]:
		tints.append(_hex_rgb(int(h)))
	spec["galaxy_tint"] = tints

	var size: int = spec["size"]
	var faces: Array[Image] = []
	for f in 6:
		var small := _paint_nebula_face(f, _NEBULA_RES, spec, pal)
		small.resize(size, size, Image.INTERPOLATE_BILINEAR)
		faces.append(small)
	_scatter_points(faces, size, spec)
	return faces


static func _hex_rgb(h: int) -> Vector3:
	return Vector3(
		float((h >> 16) & 0xFF),
		float((h >> 8) & 0xFF),
		float(h & 0xFF)
	)


static func _face_dir(f: int, u: float, v: float) -> Vector3:
	var d: Vector3
	match f:
		0:
			d = Vector3(1.0, -v, -u)
		1:
			d = Vector3(-1.0, -v, u)
		2:
			d = Vector3(u, 1.0, v)
		3:
			d = Vector3(u, -1.0, -v)
		4:
			d = Vector3(u, -v, 1.0)
		_:
			d = Vector3(-u, -v, -1.0)
	return d.normalized()


static func _paint_nebula_face(f: int, n: int, spec: Dictionary, pal: Array[Vector3]) -> Image:
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var s: float = spec["scale"]
	var seed: int = spec["seed"]
	var dens: float = spec["density"]
	var pal_last := pal.size() - 1
	for y in n:
		var vv := (2.0 * (float(y) + 0.5)) / float(n) - 1.0
		for x in n:
			var uu := (2.0 * (float(x) + 0.5)) / float(n) - 1.0
			var d := _face_dir(f, uu, vv)
			var base := _fbm3(d.x * s, d.y * s, d.z * s, seed, 5)
			var fil := _fbm3(
				d.x * s * 3.4 + 17.0,
				d.y * s * 3.4 - 9.0,
				d.z * s * 3.4 + 5.0,
				seed + 777, 4
			)
			var t := (base - (1.0 - dens)) * 3.2
			if t < 0.0:
				t = 0.0
			t = pow(t, 1.35)
			var fl := pow(fil if fil > 0.0 else 0.0, 2.2) * 1.7
			var amt: float = t * (0.85 + fl)
			if amt > 2.1:
				amt = 2.1
			var mix_n := _fbm3(
				d.x * 1.1 - 31.0,
				d.y * 1.1 + 13.0,
				d.z * 1.1 + 41.0,
				seed + 313, 3
			)
			var fi := mix_n * float(pal_last)
			var i0 := mini(pal_last, int(floor(fi)))
			var i1 := mini(pal_last, i0 + 1)
			var w := fi - float(i0)
			var a: Vector3 = pal[i0]
			var b: Vector3 = pal[i1]
			var rgb: Vector3 = a + (b - a) * w
			var o := (y * n + x) * 4
			data[o] = clampi(int(6.0 + rgb.x * amt), 0, 255)
			data[o + 1] = clampi(int(7.0 + rgb.y * amt), 0, 255)
			data[o + 2] = clampi(int(14.0 + rgb.z * amt), 0, 255)
			data[o + 3] = 255
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)


static func _scatter_points(faces: Array[Image], size: int, spec: Dictionary) -> void:
	_rng = _u32(int(spec["seed"]))
	var tints: Array = spec["galaxy_tint"]
	for _i in int(spec["galaxies"]):
		var z := _rnd() * 2.0 - 1.0
		var th := _rnd() * TAU
		var r := sqrt(1.0 - z * z)
		var dx := r * cos(th)
		var dy := z
		var dz := r * sin(th)
		var rad := (0.010 + _rnd() * 0.018) * float(size)
		var tint: Vector3 = tints[int(_rnd() * tints.size())]
		var ang := _rnd() * PI
		var squash := 0.30 + _rnd() * 0.45
		_draw_on_faces(faces, size, dx, dy, dz, func(img: Image, px: float, py: float) -> void:
			_stamp_galaxy(img, px, py, rad, tint, ang, squash)
		)
	for _i in int(spec["stars"]):
		var z := _rnd() * 2.0 - 1.0
		var th := _rnd() * TAU
		var r := sqrt(1.0 - z * z)
		var dx := r * cos(th)
		var dy := z
		var dz := r * sin(th)
		var roll := _rnd()
		var bright := roll > 0.985
		var rad := (0.0016 + _rnd() * 0.0022) * float(size) if bright \
			else (0.0006 + _rnd() * 0.0009) * float(size)
		var alpha := 1.0 if bright else 0.28 + _rnd() * 0.62
		var tw := _rnd()
		var col := Vector3(255, 214, 170) if tw > 0.86 \
			else (Vector3(186, 214, 255) if tw < 0.14 else Vector3(255, 255, 255))
		_draw_on_faces(faces, size, dx, dy, dz, func(img: Image, px: float, py: float) -> void:
			if bright:
				_stamp_disc(img, px, py, rad * 3.0, col, 0.30)
			_stamp_disc(img, px, py, rad, col, alpha)
		)


static func _draw_on_faces(faces: Array[Image], size: int, dx: float, dy: float, dz: float, draw: Callable) -> void:
	for f in 6:
		var a: float
		var b: float
		var c: float
		match f:
			0:
				c = dx
				a = -dz
				b = -dy
			1:
				c = -dx
				a = dz
				b = -dy
			2:
				c = dy
				a = dx
				b = dz
			3:
				c = -dy
				a = dx
				b = -dz
			4:
				c = dz
				a = dx
				b = -dy
			_:
				c = -dz
				a = -dx
				b = -dy
		if c <= 0.0001:
			continue
		var u := a / c
		var v := b / c
		if u < -1.06 or u > 1.06 or v < -1.06 or v > 1.06:
			continue
		draw.call(faces[f], ((u + 1.0) * 0.5) * float(size), ((v + 1.0) * 0.5) * float(size))


static func _stamp_galaxy(img: Image, cx: float, cy: float, rad: float, tint: Vector3, ang: float, squash: float) -> void:
	var pad := rad + 1.0
	var x0 := maxi(0, int(floor(cx - pad)))
	var y0 := maxi(0, int(floor(cy - pad)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + pad)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + pad)))
	var ca := cos(-ang)
	var sa := sin(-ang)
	var inv_sq := 1.0 / squash
	var r_inv := 1.0 / rad
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var lx := float(x) + 0.5 - cx
			var ly := float(y) + 0.5 - cy
			var rx := lx * ca - ly * sa
			var ry := (lx * sa + ly * ca) * inv_sq
			var t := sqrt(rx * rx + ry * ry) * r_inv
			if t >= 1.0:
				continue
			var a: float
			if t < 0.18:
				a = lerpf(0.95, 0.75, t / 0.18)
				_blend(img, x, y, Vector3(255, 255, 255), a)
			elif t < 0.55:
				a = lerpf(0.75, 0.22, (t - 0.18) / 0.37)
				_blend(img, x, y, tint, a)
			else:
				a = lerpf(0.22, 0.0, (t - 0.55) / 0.45)
				_blend(img, x, y, tint, a)


static func _stamp_disc(img: Image, cx: float, cy: float, rad: float, col: Vector3, alpha: float) -> void:
	var r := maxf(rad, 0.55)
	var x0 := maxi(0, int(floor(cx - r - 1.0)))
	var y0 := maxi(0, int(floor(cy - r - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + r + 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + r + 1.0)))
	var r_inv := 1.0 / r
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var t := sqrt(dx * dx + dy * dy) * r_inv
			if t >= 1.0:
				continue
			_blend(img, x, y, col, alpha * (1.0 - t) * (1.0 - t))


static func _blend(img: Image, x: int, y: int, col: Vector3, a: float) -> void:
	if a <= 0.0:
		return
	var dst := img.get_pixel(x, y)
	var ia := 1.0 - a
	img.set_pixel(x, y, Color(
		(col.x / 255.0) * a + dst.r * ia,
		(col.y / 255.0) * a + dst.g * ia,
		(col.z / 255.0) * a + dst.b * ia,
		1.0
	))


static func _rnd() -> float:
	_rng = _u32(_rng * 1664525 + 1013904223)
	return float(_rng) / 4294967296.0


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _hash3i(x: int, y: int, z: int, seed: int) -> float:
	var h := x * 374761393 + y * 668265263 + z * 2147483647 + seed * 974711
	h = _to_i32(h)
	h = _imul(h ^ _usr(h, 13), 1274126177)
	return float(_u32(h ^ _usr(h, 16))) / 4294967296.0


static func _noise3(x: float, y: float, z: float, seed: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var zi := floori(z)
	var xf := _smooth(x - float(xi))
	var yf := _smooth(y - float(yi))
	var zf := _smooth(z - float(zi))
	var c00 := _hash3i(xi, yi, zi, seed)
	var c10 := _hash3i(xi + 1, yi, zi, seed)
	var c01 := _hash3i(xi, yi + 1, zi, seed)
	var c11 := _hash3i(xi + 1, yi + 1, zi, seed)
	var c02 := _hash3i(xi, yi, zi + 1, seed)
	var c12 := _hash3i(xi + 1, yi, zi + 1, seed)
	var c03 := _hash3i(xi, yi + 1, zi + 1, seed)
	var c13 := _hash3i(xi + 1, yi + 1, zi + 1, seed)
	var x00 := c00 + (c10 - c00) * xf
	var x10 := c01 + (c11 - c01) * xf
	var x01 := c02 + (c12 - c02) * xf
	var x11 := c03 + (c13 - c03) * xf
	var y0 := x00 + (x10 - x00) * yf
	var y1 := x01 + (x11 - x01) * yf
	return y0 + (y1 - y0) * zf


static func _fbm3(x: float, y: float, z: float, seed: int, oct: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var f := 1.0
	var norm := 0.0
	for i in oct:
		sum += _noise3(x * f, y * f, z * f, seed + i * 131) * amp
		norm += amp
		amp *= 0.5
		f *= 2.03
	return sum / norm


static func _u32(n: int) -> int:
	return n & 0xFFFFFFFF


static func _usr(n: int, bits: int) -> int:
	return _u32(n) >> bits


static func _to_i32(n: int) -> int:
	n = n & 0xFFFFFFFF
	if n >= 0x80000000:
		return n - 0x100000000
	return n


static func _imul(a: int, b: int) -> int:
	return _to_i32(_u32(a) * _u32(b))
