class_name WadPack
extends RefCounted

# Textures loaded from a WAD, the container TrenchBroom's texture browser reads
# and therefore the one a mapper already has their art in.
#
# This is the same miptex data a compiled Quake BSP embeds, which is why taking
# the WAD gets community maps their own textures without taking the BSP and its
# collision hulls, which are baked for Quake's player box rather than ours.
#
# Two variants exist. WAD2 is Quake's and stores 8-bit indices against a palette
# the file does not contain, so one has to be supplied. WAD3 is Half-Life's and
# appends a 256-colour palette to every texture, which makes it self-contained
# and gives each texture its own colours rather than sharing one 256-entry
# compromise across a whole pack. Prefer WAD3 for anything shared.

const MAGIC_WAD2 := "WAD2"
const MAGIC_WAD3 := "WAD3"

# Lump type codes. Quake writes 'D' for a texture, Half-Life writes 'C'.
const TYPE_MIPTEX_QUAKE := 0x44
const TYPE_MIPTEX_HL := 0x43
const TYPE_PALETTE := 0x40

const MAX_DIMENSION := 4096

# Lowercase texture name to Image, RGBA8.
var textures: Dictionary = {}
var warnings: Array[String] = []
# Which variant the file turned out to be, for reporting.
var format := ""


func has_texture(name: String) -> bool:
	return textures.has(name.to_lower())


func get_texture(name: String) -> Image:
	return textures.get(name.to_lower(), null)


func size() -> int:
	return textures.size()


# Reads a WAD. `palette` is 768 bytes of RGB used for WAD2 files, which carry no
# palette of their own; it is ignored for WAD3. Never throws: a malformed lump is
# skipped and recorded, because a community texture pack is untrusted input.
static func load_file(path: String, palette := PackedByteArray()) -> WadPack:
	var pack := WadPack.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		pack.warnings.append("cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return pack

	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC_WAD2 and magic != MAGIC_WAD3:
		pack.warnings.append("%s is not a WAD (magic '%s')" % [path, magic])
		f.close()
		return pack
	pack.format = magic

	var count := f.get_32()
	var dir_offset := f.get_32()
	if count <= 0 or count > 65536:
		pack.warnings.append("implausible lump count %d" % count)
		f.close()
		return pack

	f.seek(dir_offset)
	var entries: Array = []
	for i in count:
		if f.eof_reached():
			pack.warnings.append("directory ends early at lump %d" % i)
			break
		var entry := {
			"offset": f.get_32(),
			"dsize": f.get_32(),
			"size": f.get_32(),
			"type": f.get_8(),
			"compression": f.get_8(),
		}
		f.get_16()  # padding
		entry["name"] = f.get_buffer(16).get_string_from_ascii()
		entries.append(entry)

	# A palette lump inside the file wins over the one passed in.
	var pal := palette
	for e: Dictionary in entries:
		if e["type"] == TYPE_PALETTE and e["size"] >= 768:
			f.seek(e["offset"])
			pal = f.get_buffer(768)
			break

	for e: Dictionary in entries:
		var t: int = e["type"]
		if t != TYPE_MIPTEX_QUAKE and t != TYPE_MIPTEX_HL:
			continue
		if e["compression"] != 0:
			pack.warnings.append("'%s' is compressed, which is not supported" % e["name"])
			continue
		var img := pack._read_miptex(f, e["offset"], magic == MAGIC_WAD3, pal)
		if img != null:
			pack.textures[String(e["name"]).to_lower()] = img

	f.close()
	if pack.textures.is_empty() and pack.warnings.is_empty():
		pack.warnings.append("%s holds no textures" % path)
	return pack


# Reads one miptex record at `base` and files it under `name`. A compiled BSP
# embeds exactly the records a WAD3 holds, palette and all, so the BSP importer
# borrows this decoder rather than growing a second copy of the palette rules.
func add_miptex(f: FileAccess, base: int, name: String) -> bool:
	var img := _read_miptex(f, base, true, PackedByteArray())
	if img == null:
		return false
	textures[name.to_lower()] = img
	if format.is_empty():
		format = MAGIC_WAD3
	return true


func _read_miptex(f: FileAccess, base: int, wad3: bool, palette: PackedByteArray) -> Image:
	f.seek(base)
	var name := f.get_buffer(16).get_string_from_ascii()
	var width := f.get_32()
	var height := f.get_32()
	if width <= 0 or height <= 0 or width > MAX_DIMENSION or height > MAX_DIMENSION:
		warnings.append("'%s' has implausible size %dx%d" % [name, width, height])
		return null

	var mip_offsets: Array[int] = []
	for i in 4:
		mip_offsets.append(f.get_32())

	# Half-Life appends the palette after the smallest mip, which is what makes
	# a WAD3 self-describing.
	var pal := palette
	if wad3:
		var smallest := (width / 8) * (height / 8)
		f.seek(base + mip_offsets[3] + smallest)
		var entries := f.get_16()
		if entries > 0 and entries <= 256:
			pal = f.get_buffer(entries * 3)

	if pal.size() < 768:
		warnings.append(("'%s' needs a 256 colour palette and none was available. " +
			"WAD2 does not carry one, so supply the pack's palette.lmp or ship WAD3.") % name)
		return null

	f.seek(base + mip_offsets[0])
	var pixels := f.get_buffer(width * height)
	if pixels.size() < width * height:
		warnings.append("'%s' is truncated" % name)
		return null

	# A leading brace is Quake's mark for a cutout texture, where the last
	# palette entry means transparent rather than its colour.
	var cutout := name.begins_with("{")

	var rgba := PackedByteArray()
	rgba.resize(width * height * 4)
	for i in width * height:
		var index := pixels[i]
		var o := i * 4
		if cutout and index == 255:
			rgba[o] = 0
			rgba[o + 1] = 0
			rgba[o + 2] = 0
			rgba[o + 3] = 0
			continue
		var p := index * 3
		rgba[o] = pal[p]
		rgba[o + 1] = pal[p + 1]
		rgba[o + 2] = pal[p + 2]
		rgba[o + 3] = 255

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
