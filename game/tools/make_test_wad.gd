extends SceneTree

# Generates the test texture pack for the community arena and round-trips it
# back through WadPack to prove the loader reads what a real pack contains.
# Run: godot --headless --path game --script res://tools/make_test_wad.gd
#
# WAD3 rather than WAD2 on purpose: it appends a palette to every texture, so
# the file is self-describing and each texture gets its own 256 colours instead
# of sharing one compromise across the pack.

const OUT := "res://maps/community/arena1.wad"
const SIZE := 64

var _fails := 0


func _ok(label: String, got, want) -> void:
	var pass_: bool = got == want
	if not pass_:
		_fails += 1
	print("  %-42s %s   got=%s want=%s" % [label, "ok " if pass_ else "FAIL", got, want])


# A palette whose first `ramp` entries run from `dark` to `light`, with a few
# named accents after them. Indices are drawn directly, so nothing is quantised.
func _palette(dark: Color, light: Color, accents: Array[Color]) -> PackedByteArray:
	var pal := PackedByteArray()
	pal.resize(768)
	for i in 240:
		var c := dark.lerp(light, float(i) / 239.0)
		pal[i * 3] = int(c.r * 255.0)
		pal[i * 3 + 1] = int(c.g * 255.0)
		pal[i * 3 + 2] = int(c.b * 255.0)
	for j in accents.size():
		var idx := 240 + j
		if idx > 255:
			break
		var a: Color = accents[j]
		pal[idx * 3] = int(a.r * 255.0)
		pal[idx * 3 + 1] = int(a.g * 255.0)
		pal[idx * 3 + 2] = int(a.b * 255.0)
	return pal


# Index buffer for a tiled floor: a noisy field with grid lines every 16.
func _floor_pixels() -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var v := 60 + ((x * 7 + y * 13) % 24)
			if x % 16 == 0 or y % 16 == 0:
				v = 150
			if x % 32 == 0 and y % 32 == 0:
				v = 240  # accent
			px[y * SIZE + x] = v
	return px


# Vertical panels with a bright seam.
func _wall_pixels() -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var v := 90 + ((y * 5) % 18)
			if x % 21 == 0:
				v = 30
			if y < 3 or y > SIZE - 4:
				v = 170
			px[y * SIZE + x] = v
	return px


# Diagonal hazard stripes.
func _trim_pixels() -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			px[y * SIZE + x] = 241 if ((x + y) / 8) % 2 == 0 else 40
	return px


# Nearest-neighbour halving, which is what a miptex chain is.
func _downsample(src: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize((w / 2) * (h / 2))
	for y in h / 2:
		for x in w / 2:
			out[y * (w / 2) + x] = src[(y * 2) * w + (x * 2)]
	return out


func _write_miptex(f: FileAccess, name: String, pixels: PackedByteArray,
		palette: PackedByteArray) -> void:
	var name_bytes := PackedByteArray()
	name_bytes.resize(16)
	var raw := name.to_ascii_buffer()
	for i in mini(raw.size(), 15):
		name_bytes[i] = raw[i]

	var m1 := _downsample(pixels, SIZE, SIZE)
	var m2 := _downsample(m1, SIZE / 2, SIZE / 2)
	var m3 := _downsample(m2, SIZE / 4, SIZE / 4)

	# Offsets are relative to the start of this lump. The header is the 16 byte
	# name, two dimensions and four offsets: 40 bytes.
	var o0 := 40
	var o1 := o0 + pixels.size()
	var o2 := o1 + m1.size()
	var o3 := o2 + m2.size()

	f.store_buffer(name_bytes)
	f.store_32(SIZE)
	f.store_32(SIZE)
	f.store_32(o0)
	f.store_32(o1)
	f.store_32(o2)
	f.store_32(o3)
	f.store_buffer(pixels)
	f.store_buffer(m1)
	f.store_buffer(m2)
	f.store_buffer(m3)
	f.store_16(256)
	f.store_buffer(palette)
	f.store_16(0)  # trailing pad, as real packs carry


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://maps/community"))

	var packs := [
		{
			"name": "arena_floor",
			"pixels": _floor_pixels(),
			"palette": _palette(Color(0.05, 0.06, 0.10), Color(0.42, 0.47, 0.58),
				[Color(0.20, 0.85, 0.95)] as Array[Color]),
		},
		{
			"name": "arena_wall",
			"pixels": _wall_pixels(),
			"palette": _palette(Color(0.08, 0.08, 0.09), Color(0.55, 0.55, 0.60),
				[Color(0.90, 0.90, 0.95)] as Array[Color]),
		},
		{
			"name": "arena_trim",
			"pixels": _trim_pixels(),
			"palette": _palette(Color(0.06, 0.05, 0.03), Color(0.35, 0.30, 0.20),
				[Color(0.98, 0.65, 0.10)] as Array[Color]),
		},
	]

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("cannot write ", OUT)
		quit(1)
		return

	f.store_buffer("WAD3".to_ascii_buffer())
	f.store_32(packs.size())
	f.store_32(0)  # directory offset, patched below

	var dir_entries: Array = []
	for p: Dictionary in packs:
		var start := f.get_position()
		_write_miptex(f, p["name"], p["pixels"], p["palette"])
		dir_entries.append({"offset": start, "size": f.get_position() - start, "name": p["name"]})

	var dir_offset := f.get_position()
	for e: Dictionary in dir_entries:
		f.store_32(e["offset"])
		f.store_32(e["size"])
		f.store_32(e["size"])
		f.store_8(0x43)  # miptex
		f.store_8(0)     # uncompressed
		f.store_16(0)
		var nb := PackedByteArray()
		nb.resize(16)
		var raw := String(e["name"]).to_ascii_buffer()
		for i in mini(raw.size(), 15):
			nb[i] = raw[i]
		f.store_buffer(nb)

	f.seek(8)
	f.store_32(dir_offset)
	f.close()

	print("wrote %s (%d textures)" % [OUT, packs.size()])
	print("")
	print("-- reading it back --")
	var pack := WadPack.load_file(OUT)
	_ok("no warnings", pack.warnings, [] as Array[String])
	_ok("format", pack.format, "WAD3")
	_ok("texture count", pack.size(), 3)
	for name in ["arena_floor", "arena_wall", "arena_trim"]:
		_ok("has %s" % name, pack.has_texture(name), true)
	var img := pack.get_texture("arena_floor")
	_ok("floor is 64x64", img.get_size(), Vector2i(SIZE, SIZE))
	_ok("floor is opaque RGBA", img.get_format(), Image.FORMAT_RGBA8)
	# (0,0) draws the accent index, which is the cyan the palette puts at 240.
	var c := img.get_pixel(0, 0)
	_ok("accent colour survived the palette", Vector3(c.r, c.g, c.b).round(),
		Vector3(0.0, 1.0, 1.0))
	_ok("lookup is case insensitive", pack.has_texture("ARENA_WALL"), true)

	print("")
	print("FAILURES: %d" % _fails)
	quit(1 if _fails > 0 else 0)
