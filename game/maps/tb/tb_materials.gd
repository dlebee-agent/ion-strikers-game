class_name TbMaterials
extends RefCounted

# Turns a face's texture name into something to draw with.
#
# Resolution order, by name:
#   ion/...   the engine's own surfaces, so a mapper can build against the game
#             without shipping any art at all
#   anything  looked up in the map's WAD, rendered as authored
#   a miss    a loud checker, so the mapper sees the mistake rather than
#             shipping a silently untextured level
#
# Quake tooling has a few names that mean "no surface here" rather than a
# texture, and those faces are skipped entirely instead of being drawn.

# Faces wearing these are structural markers, not geometry anyone should see.
const SKIP_TEXTURES := ["__tb_empty", "skip", "trigger", "clip", "nodraw", "caulk", "hint"]

# WAD art is low resolution by design, so it is filtered nearest to stay crisp
# rather than smeared into mush.
const NOMINAL_SIZE := Vector2(64, 64)

var _wad: WadPack = null
var _cache: Dictionary = {}
var _missing: Dictionary = {}
# Names that resolved to nothing, for reporting back to the mapper.
var warnings: Array[String] = []


func _init(wad: WadPack = null) -> void:
	_wad = wad


# True when the face carries a marker rather than a surface.
static func is_skipped(texture: String) -> bool:
	return SKIP_TEXTURES.has(texture.to_lower())


# True when resolve() would hand back a real surface rather than the checker.
func known(texture: String) -> bool:
	var key := texture.to_lower()
	return key.begins_with("ion/") or (_wad != null and _wad.has_texture(key))


# Returns {"material": StandardMaterial3D, "size": Vector2}. The size is the
# texture's pixel dimensions, which UV generation needs to normalise into 0..1.
func resolve(texture: String) -> Dictionary:
	var key := texture.to_lower()
	if _cache.has(key):
		return _cache[key]

	var entry: Dictionary
	if key.begins_with("ion/"):
		entry = {"material": _builtin(key.substr(4)), "size": NOMINAL_SIZE}
	elif _wad != null and _wad.has_texture(key):
		entry = _from_wad(key)
	else:
		if not _missing.has(key):
			_missing[key] = true
			warnings.append("no texture named '%s'" % texture)
		entry = {"material": _checker(), "size": NOMINAL_SIZE}

	_cache[key] = entry
	return entry


func _from_wad(key: String) -> Dictionary:
	var img := _wad.get_texture(key)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 0.9
	mat.metallic = 0.0
	# A leading brace is Quake's cutout mark, and those textures carry real
	# transparency that has to be honoured or fences render as solid blocks.
	if key.begins_with("{"):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return {"material": mat, "size": Vector2(img.get_width(), img.get_height())}


# The engine's own surfaces. Flat shaded to match how the built-in maps are
# drawn, so an ion/ face sits in an imported level the way it would in a
# hand-built one.
func _builtin(name: String) -> StandardMaterial3D:
	match name:
		"floor":
			return _flat(Color(0.10, 0.11, 0.17), 0.85)
		"wall":
			return _flat(Color(0.16, 0.17, 0.24), 0.75)
		"cover":
			return _flat(Color(0.22, 0.24, 0.32), 0.7)
		"hazard":
			return _flat(Color(0.35, 0.12, 0.10), 0.6)
		"accent":
			var mat := _flat(Color(0.20, 0.85, 0.95), 0.4)
			mat.emission_enabled = true
			mat.emission = Color(0.20, 0.85, 0.95)
			mat.emission_energy_multiplier = 1.4
			return mat
		_:
			warnings.append("no built-in surface called 'ion/%s'" % name)
			return _checker()


func _flat(albedo: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = 0.0
	return mat


func _checker() -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var on := ((x / 4) + (y / 4)) % 2 == 0
			img.set_pixel(x, y, Color(1, 0, 1) if on else Color(0.1, 0.1, 0.1))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat
