class_name TbParser
extends RefCounted

# Reads the Quake .map text format into a TbMap.
#
# Written from the format rather than ported from TrenchBroom, which is GPLv3;
# nothing here derives from their source.
#
# Two texture layouts exist in the wild and community maps will contain both.
# The older Quake one is `name offX offY rot scaleX scaleY` and leaves the engine
# to derive UV axes from the face normal. Valve 220, which TrenchBroom writes by
# default, is `name [ ux uy uz offX ] [ vx vy vz offY ] rot scaleX scaleY` and
# states the axes outright, which is what lets it hold alignment across a face
# that the older format shears. Which one a face uses is read off the bracket
# rather than off worldspawn's mapversion key, because the key is not always
# there and the bracket always is.

const _WS := " \t\r\n"
const _PUNCT := "{}()[]"

var _text := ""
var _pos := 0
var _len := 0
var _line := 1
var _map: TbMap


# Parses .map source. Never throws: anything malformed is skipped and recorded in
# the returned map's `warnings`, because community maps are untrusted input and
# one bad face should not cost the whole level.
func parse(text: String) -> TbMap:
	_text = text
	_pos = 0
	_len = text.length()
	_line = 1
	_map = TbMap.new()

	while true:
		var t := _next()
		if t == "":
			break
		if t == "{":
			var e := _parse_entity()
			if e != null:
				_map.entities.append(e)
		else:
			_warn("expected '{' at top level, found '%s'" % t)

	return _map


func parse_file(path: String) -> TbMap:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var m := TbMap.new()
		m.warnings.append("cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return m
	var text := f.get_as_text()
	f.close()
	return parse(text)


func _warn(msg: String) -> void:
	if _map.warnings.size() < 64:
		_map.warnings.append("line %d: %s" % [_line, msg])


# ── Tokenizer ────────────────────────────────────────────────────────────────

func _skip_trivia() -> void:
	while _pos < _len:
		var c := _text[_pos]
		if c == "\n":
			_line += 1
			_pos += 1
		elif _WS.contains(c):
			_pos += 1
		elif c == "/" and _pos + 1 < _len and _text[_pos + 1] == "/":
			while _pos < _len and _text[_pos] != "\n":
				_pos += 1
		else:
			return


# Next token, or "" at end of input. Punctuation is always its own token, quoted
# strings come back without their quotes, and everything else is a bare word
# ending at whitespace or punctuation.
func _next() -> String:
	_skip_trivia()
	if _pos >= _len:
		return ""

	var c := _text[_pos]
	if _PUNCT.contains(c):
		_pos += 1
		return c

	if c == '"':
		_pos += 1
		var start := _pos
		while _pos < _len and _text[_pos] != '"':
			if _text[_pos] == "\n":
				_line += 1
			_pos += 1
		var s := _text.substr(start, _pos - start)
		if _pos < _len:
			_pos += 1
		return s

	var word_start := _pos
	while _pos < _len:
		var w := _text[_pos]
		if _WS.contains(w) or _PUNCT.contains(w):
			break
		_pos += 1
	return _text.substr(word_start, _pos - word_start)


# Looks at the next token without consuming it.
func _peek() -> String:
	var save_pos := _pos
	var save_line := _line
	var t := _next()
	_pos = save_pos
	_line = save_line
	return t


func _expect(want: String) -> bool:
	var t := _next()
	if t != want:
		_warn("expected '%s', found '%s'" % [want, t])
		return false
	return true


func _number() -> float:
	var t := _next()
	return t.to_float()


# ── Grammar ──────────────────────────────────────────────────────────────────

func _parse_entity() -> TbMap.Entity:
	var e := TbMap.Entity.new()
	while true:
		var t := _next()
		if t == "":
			_warn("unexpected end of file inside an entity")
			break
		if t == "}":
			break
		if t == "{":
			var b := _parse_brush()
			if b != null:
				e.brushes.append(b)
			continue
		# Anything else is a key, and its value is the token after it.
		var value := _next()
		e.properties[t] = value
	return e


func _parse_brush() -> TbMap.Brush:
	var b := TbMap.Brush.new()
	while true:
		var t := _peek()
		if t == "":
			_warn("unexpected end of file inside a brush")
			break
		if t == "}":
			_next()
			break
		var f := _parse_face()
		if f == null:
			# Resynchronise on the next line so one bad face costs one face.
			_skip_line()
			continue
		b.faces.append(f)

	if b.faces.size() < 4:
		# Fewer than four planes cannot bound a volume.
		_warn("brush has only %d usable faces, skipped" % b.faces.size())
		return null
	return b


func _skip_line() -> void:
	while _pos < _len and _text[_pos] != "\n":
		_pos += 1


func _point() -> Vector3:
	if not _expect("("):
		return Vector3.ZERO
	var x := _number()
	var y := _number()
	var z := _number()
	_expect(")")
	return TbMap.to_godot(Vector3(x, y, z))


func _parse_face() -> TbMap.Face:
	var f := TbMap.Face.new()
	f.p0 = _point()
	f.p1 = _point()
	f.p2 = _point()

	f.texture = _next()
	if f.texture == "" or _PUNCT.contains(f.texture):
		_warn("face has no texture name")
		return null

	if _peek() == "[":
		f.valve = true
		_next()
		var ux := _number()
		var uy := _number()
		var uz := _number()
		f.u_offset = _number()
		_expect("]")
		if not _expect("["):
			return null
		var vx := _number()
		var vy := _number()
		var vz := _number()
		f.v_offset = _number()
		_expect("]")
		f.u_axis = TbMap.dir_to_godot(Vector3(ux, uy, uz))
		f.v_axis = TbMap.dir_to_godot(Vector3(vx, vy, vz))
	else:
		f.u_offset = _number()
		f.v_offset = _number()

	f.rotation = _number()
	f.u_scale = _number()
	f.v_scale = _number()

	# Quake 2 and later append contents, surface flags and a light value. They
	# mean nothing here, so consume any trailing numbers to reach the next face.
	while true:
		var t := _peek()
		if t == "" or _PUNCT.contains(t) or not t.is_valid_float():
			break
		_next()

	if f.degenerate():
		_warn("face '%s' has collinear points, skipped" % f.texture)
		return null
	if f.u_scale == 0.0:
		f.u_scale = 1.0
	if f.v_scale == 0.0:
		f.v_scale = 1.0
	return f
