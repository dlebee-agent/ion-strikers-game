extends SceneTree

# Renders a built-in map from a few fixed viewpoints and saves them as PNGs,
# for checking how the map reads: is a player visible against the ground,
# do the edge lines show, is the body the right slate. It goes through
# MapBuilder.build_visual, so lights, fog and the baked sky are the real
# ones; players are stood in for by capsules in TeamTint's body colours,
# which is what a pawn's largest surface is drawn with.
#
# Needs a window, since headless has no renderer:
#   godot --path game --script res://tools/look_shot.gd --resolution 1600x900 -- <map_id> <out_dir>

const EYE := 1.6

var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id := args[0] if args.size() > 0 else "skydeck"
	var out_dir := args[1] if args.size() > 1 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	_world = Node3D.new()
	root.add_child(_world)
	var compiled := MapEngine.compile(MapCatalog.builtin_definition(map_id))
	MapBuilder.build_visual(_world, compiled)

	_cam = Camera3D.new()
	_cam.fov = 80.0
	_world.add_child(_cam)
	_cam.current = true

	_shoot(map_id, out_dir)


func _shoot(map_id: String, out_dir: String) -> void:
	# One stand-in per team in every shot, placed where a player would be
	# and at the ranges a fight happens at.
	var shots := [
		{
			"name": "deck_across",
			"eye": Vector3(0.0, 3.2 + EYE, -25.0), "look": Vector3(0.0, 2.0, 5.0),
			"blue": Vector3(4.0, 3.2, -19.0), "red": Vector3(0.0, 1.6, -5.0),
		},
		{
			"name": "gate_ramp",
			"eye": Vector3(10.5, EYE, 0.5), "look": Vector3(10.5, 3.0, -14.0),
			"blue": Vector3(10.5, 1.8, -8.5), "red": Vector3(10.5, 3.2, -17.0),
		},
		{
			"name": "catwalk_ring",
			"eye": Vector3(16.6, 7.0 + EYE, -6.0), "look": Vector3(0.0, 7.0, 0.0),
			"blue": Vector3(11.0, 7.0, 0.0), "red": Vector3(5.8, 7.0, 0.0),
		},
	]

	var standins: Array[Node3D] = []
	for shot: Dictionary in shots:
		for n in standins:
			n.queue_free()
		standins.clear()
		standins.append(_standin(shot["blue"], TeamTint.BODY_BLUE))
		standins.append(_standin(shot["red"], TeamTint.BODY_RED))

		# look_at needs the node in the tree and its first frame behind it;
		# this form does not, and the first shot was aimed at nothing without it.
		_cam.look_at_from_position(shot["eye"], shot["look"], Vector3.UP)

		# Let the frame settle: added nodes, sky, and shadow maps all need a
		# draw or two before the image is what a player would see.
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%s_%s.png" % [out_dir, map_id, shot["name"]]
		var err := img.save_png(path)
		print("%s %s" % ["saved" if err == OK else "FAILED to save", path])

	quit()


func _standin(feet: Vector3, body: Color) -> Node3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.75
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body
	mat.roughness = 0.6
	cap.material = mat
	mi.mesh = cap
	mi.position = feet + Vector3(0.0, cap.height * 0.5, 0.0)
	_world.add_child(mi)
	return mi
