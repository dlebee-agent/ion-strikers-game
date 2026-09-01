class_name BspFile
extends RefCounted

# The raw lumps of a GoldSrc BSP (version 30 — Half-Life, Counter-Strike 1.6),
# decoded into flat arrays and nothing more. Meaning is BspImporter's job.
#
# Everything here stays in Quake units and Quake axes. Converting on the way out
# rather than on the way in keeps the texture solve honest: texture axes are
# defined against the unscaled coordinates, so a vertex has to be available in
# the space the .bsp wrote it in.

const VERSION_GOLDSRC := 30

const LUMP_ENTITIES := 0
const LUMP_PLANES := 1
const LUMP_TEXTURES := 2
const LUMP_VERTEXES := 3
const LUMP_NODES := 5
const LUMP_TEXINFO := 6
const LUMP_FACES := 7
const LUMP_LEAVES := 10
const LUMP_EDGES := 12
const LUMP_SURFEDGES := 13
const LUMP_MODELS := 14
const LUMP_COUNT := 15

# Quake's leaf contents. Only the two that stop a player matter here; sky is
# solid to movement even though it draws as a hole.
const CONTENTS_SOLID := -2
const CONTENTS_SKY := -6

# A malformed file is untrusted input, not a crash. Anything implausible is
# recorded and the level is refused rather than half-built.
const MAX_ELEMENTS := 1 << 21

var version := 0
var warnings: Array[String] = []

var entities := ""
# Plane i is planes_n[i] (Quake space, unit) and planes_d[i] (Quake units).
var planes_n: PackedVector3Array = []
var planes_d: PackedFloat32Array = []
var planes_type: PackedInt32Array = []

var vertexes: PackedVector3Array = []
# Edge i is a pair of vertex indices at 2*i and 2*i+1.
var edges: PackedInt32Array = []
var surfedges: PackedInt32Array = []

# Face i occupies FACE_STRIDE ints starting at i * FACE_STRIDE.
const FACE_STRIDE := 5
const FACE_PLANE := 0
const FACE_SIDE := 1
const FACE_FIRSTEDGE := 2
const FACE_NUMEDGES := 3
const FACE_TEXINFO := 4
var faces: PackedInt32Array = []
var face_count := 0

# Texinfo i: s axis, s shift, t axis, t shift, miptex index.
var texinfo_s: PackedVector3Array = []
var texinfo_sd: PackedFloat32Array = []
var texinfo_t: PackedVector3Array = []
var texinfo_td: PackedFloat32Array = []
var texinfo_miptex: PackedInt32Array = []

# Node i: plane index, front child, back child. A negative child is a leaf,
# encoded as -(leaf + 1), which is why zero cannot mean "leaf 0" directly.
const NODE_STRIDE := 3
var nodes: PackedInt32Array = []
var node_count := 0

var leaf_contents: PackedInt32Array = []

# Texture names in miptex order, lowercased, and the images for the ones the
# compiler embedded. A name with no image was left as a WAD reference.
var texture_names: PackedStringArray = []
var textures: WadPack = null

var world_mins := Vector3.ZERO
var world_maxs := Vector3.ZERO
var headnode := 0


func ok() -> bool:
	return version == VERSION_GOLDSRC and face_count > 0 and node_count > 0


static func load_file(path: String) -> BspFile:
	var bsp := BspFile.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		bsp.warnings.append("cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return bsp

	bsp.version = f.get_32()
	if bsp.version != VERSION_GOLDSRC:
		bsp.warnings.append(
			"%s is BSP version %d; only %d (GoldSrc) is supported"
			% [path, bsp.version, VERSION_GOLDSRC])
		f.close()
		return bsp

	var size := f.get_length()
	var offsets: Array[int] = []
	var lengths: Array[int] = []
	for i in LUMP_COUNT:
		var off := f.get_32()
		var len_ := f.get_32()
		if off < 0 or len_ < 0 or off + len_ > size:
			bsp.warnings.append("lump %d runs past the end of the file" % i)
			f.close()
			return bsp
		offsets.append(off)
		lengths.append(len_)

	bsp._read_entities(f, offsets[LUMP_ENTITIES], lengths[LUMP_ENTITIES])
	bsp._read_planes(f, offsets[LUMP_PLANES], lengths[LUMP_PLANES])
	bsp._read_vertexes(f, offsets[LUMP_VERTEXES], lengths[LUMP_VERTEXES])
	bsp._read_edges(f, offsets[LUMP_EDGES], lengths[LUMP_EDGES])
	bsp._read_surfedges(f, offsets[LUMP_SURFEDGES], lengths[LUMP_SURFEDGES])
	bsp._read_texinfo(f, offsets[LUMP_TEXINFO], lengths[LUMP_TEXINFO])
	bsp._read_faces(f, offsets[LUMP_FACES], lengths[LUMP_FACES])
	bsp._read_nodes(f, offsets[LUMP_NODES], lengths[LUMP_NODES])
	bsp._read_leaves(f, offsets[LUMP_LEAVES], lengths[LUMP_LEAVES])
	bsp._read_textures(f, offsets[LUMP_TEXTURES], lengths[LUMP_TEXTURES])
	bsp._read_model0(f, offsets[LUMP_MODELS], lengths[LUMP_MODELS])

	f.close()
	return bsp


func _too_many(what: String, n: int) -> bool:
	if n < 0 or n > MAX_ELEMENTS:
		warnings.append("implausible %s count %d" % [what, n])
		return true
	return false


func _read_entities(f: FileAccess, off: int, len_: int) -> void:
	f.seek(off)
	entities = f.get_buffer(len_).get_string_from_ascii()


func _read_planes(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 20
	if _too_many("plane", n):
		return
	f.seek(off)
	planes_n.resize(n)
	planes_d.resize(n)
	planes_type.resize(n)
	for i in n:
		planes_n[i] = Vector3(f.get_float(), f.get_float(), f.get_float())
		planes_d[i] = f.get_float()
		planes_type[i] = f.get_32()


func _read_vertexes(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 12
	if _too_many("vertex", n):
		return
	f.seek(off)
	vertexes.resize(n)
	for i in n:
		vertexes[i] = Vector3(f.get_float(), f.get_float(), f.get_float())


func _read_edges(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 4
	if _too_many("edge", n):
		return
	f.seek(off)
	edges.resize(n * 2)
	for i in n:
		edges[i * 2] = f.get_16()
		edges[i * 2 + 1] = f.get_16()


func _read_surfedges(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 4
	if _too_many("surfedge", n):
		return
	f.seek(off)
	surfedges.resize(n)
	for i in n:
		surfedges[i] = f.get_32()


func _read_texinfo(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 40
	if _too_many("texinfo", n):
		return
	f.seek(off)
	texinfo_s.resize(n)
	texinfo_sd.resize(n)
	texinfo_t.resize(n)
	texinfo_td.resize(n)
	texinfo_miptex.resize(n)
	for i in n:
		texinfo_s[i] = Vector3(f.get_float(), f.get_float(), f.get_float())
		texinfo_sd[i] = f.get_float()
		texinfo_t[i] = Vector3(f.get_float(), f.get_float(), f.get_float())
		texinfo_td[i] = f.get_float()
		texinfo_miptex[i] = f.get_32()
		f.get_32()  # flags


func _read_faces(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 20
	if _too_many("face", n):
		return
	f.seek(off)
	faces.resize(n * FACE_STRIDE)
	for i in n:
		var b := i * FACE_STRIDE
		faces[b + FACE_PLANE] = f.get_16()
		faces[b + FACE_SIDE] = f.get_16()
		faces[b + FACE_FIRSTEDGE] = f.get_32()
		faces[b + FACE_NUMEDGES] = f.get_16()
		faces[b + FACE_TEXINFO] = f.get_16()
		f.get_32()  # four light styles
		f.get_32()  # lightmap offset
	face_count = n


func _read_nodes(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 24
	if _too_many("node", n):
		return
	f.seek(off)
	nodes.resize(n * NODE_STRIDE)
	for i in n:
		var b := i * NODE_STRIDE
		nodes[b] = f.get_32()
		# Children are signed: a negative value is -(leaf + 1).
		nodes[b + 1] = _s16(f.get_16())
		nodes[b + 2] = _s16(f.get_16())
		for _k in 6:
			f.get_16()  # int16 mins/maxs, unused: the descent carries its own box
		f.get_16()  # first face
		f.get_16()  # face count
	node_count = n


func _read_leaves(f: FileAccess, off: int, len_: int) -> void:
	var n := len_ / 28
	if _too_many("leaf", n):
		return
	f.seek(off)
	leaf_contents.resize(n)
	for i in n:
		leaf_contents[i] = f.get_32()
		f.get_32()  # vis offset
		for _k in 6:
			f.get_16()
		f.get_16()
		f.get_16()
		f.get_32()  # four ambient levels


func _read_textures(f: FileAccess, off: int, len_: int) -> void:
	if len_ < 4:
		return
	f.seek(off)
	var n := f.get_32()
	if _too_many("miptex", n):
		return
	var dir: Array[int] = []
	for i in n:
		dir.append(f.get_32())

	textures = WadPack.new()
	texture_names.resize(n)
	for i in n:
		var rel: int = dir[i]
		# A negative offset is the compiler saying it left this one in a WAD.
		if rel < 0 or rel + 40 > len_:
			texture_names[i] = ""
			continue
		var base := off + rel
		f.seek(base)
		var name := f.get_buffer(16).get_string_from_ascii()
		texture_names[i] = name.to_lower()
		# Zero for the first mip means the same thing: name only, pixels elsewhere.
		f.seek(base + 24)
		if f.get_32() == 0:
			continue
		if not textures.add_miptex(f, base, name):
			warnings.append("texture '%s' would not decode" % name)
	warnings.append_array(textures.warnings)


func _read_model0(f: FileAccess, off: int, len_: int) -> void:
	if len_ < 64:
		warnings.append("no world model")
		return
	f.seek(off)
	world_mins = Vector3(f.get_float(), f.get_float(), f.get_float())
	world_maxs = Vector3(f.get_float(), f.get_float(), f.get_float())
	f.get_float(); f.get_float(); f.get_float()  # origin
	headnode = f.get_32()


static func _s16(v: int) -> int:
	return v - 65536 if v >= 32768 else v
