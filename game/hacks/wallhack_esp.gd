extends Control

## Wallhack overlay: draws a box, name, health and distance over every
## enemy the client knows about, through walls, plus a line from the
## bottom of the screen to each. Everything it draws comes from the
## snapshots the server already sends, so it also shows what corner
## culling withholds: an enemy the server has hidden sits at HIDDEN_Y and
## is counted rather than drawn.
##
## Enabled with `-- --wallhack`; see match.gd.

const HIDDEN_BELOW := -500.0
const BODY_HALF := 0.4
const BODY_HEIGHT := 1.8
const COLOR_BLUE := Color(0.35, 0.8, 1.0)
const COLOR_RED := Color(1.0, 0.4, 0.4)
const COLOR_TEXT := Color(1.0, 1.0, 1.0)

var match_scene: Node = null
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if match_scene == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var my_team: int = match_scene.get("_my_team")
	var remotes: Dictionary = match_scene.get("_remotes")
	var snap: Array = match_scene.get("_last_snap_players")
	var hp_by_id: Dictionary = {}
	for p in snap:
		if typeof(p) == TYPE_DICTIONARY:
			hp_by_id[int(p.get("id", 0))] = int(p.get("hp", 0))

	var known := 0
	var hidden := 0
	var anchor := Vector2(size.x * 0.5, size.y)

	for pid: int in remotes:
		var rp: Node3D = remotes[pid]
		if not rp.get("alive") or int(rp.get("team")) == my_team or int(rp.get("team")) == Protocol.TEAM_NONE:
			continue
		var pos := _body_position(rp)
		if pos.y < HIDDEN_BELOW:
			hidden += 1
			continue
		known += 1

		var rect := _screen_box(camera, pos)
		if rect == Rect2():
			continue
		var color := COLOR_BLUE if int(rp.get("team")) == Protocol.TEAM_BLUE else COLOR_RED
		draw_rect(rect, color, false, 2.0)
		draw_line(anchor, Vector2(rect.get_center().x, rect.end.y), color, 1.0)
		var label := "%s  %d hp  %.0f m" % [str(rp.get("display_name")), hp_by_id.get(pid, 0),
			camera.global_position.distance_to(pos)]
		draw_string(_font, Vector2(rect.position.x, rect.position.y - 6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TEXT)

	draw_string(_font, Vector2(16.0, 120.0), "WALLHACK  enemies drawn %d   hidden by server %d" % [known, hidden],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT)


## A remote pawn's root never moves; the interpolated body is its mannequin.
func _body_position(rp: Node3D) -> Vector3:
	var body: Node3D = rp.get("_mannequin")
	return body.global_position if body != null else rp.global_position


## Screen rectangle around the body's box, or an empty Rect2 when it is
## behind the camera.
func _screen_box(camera: Camera3D, foot: Vector3) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for dx: float in [-BODY_HALF, BODY_HALF]:
		for dz: float in [-BODY_HALF, BODY_HALF]:
			for dy: float in [0.0, BODY_HEIGHT]:
				var corner := foot + Vector3(dx, dy, dz)
				if camera.is_position_behind(corner):
					return Rect2()
				var s := camera.unproject_position(corner)
				lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
				hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
	return Rect2(lo, hi - lo)
