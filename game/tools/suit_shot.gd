extends SceneTree

# Renders the mannequin in both suit styles for both teams and saves PNGs,
# for checking how the painted suit reads: do the seams sit where they
# should, does the visor land on the face, do the eyes and core light up,
# does the design survive an animated pose. The stock mannequin goes through
# TeamTint.apply_body exactly as a pawn does.
#
# Needs a window, since headless has no renderer:
#   godot --path game --script res://tools/suit_shot.gd --resolution 1600x900 -- <out_dir>

var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://suit_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	_world = Node3D.new()
	root.add_child(_world)
	_build_stage()

	_cam = Camera3D.new()
	_cam.fov = 32.0
	_world.add_child(_cam)
	_cam.current = true

	_shoot(out_dir)


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#04121a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#1f3a5a")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#06151f")
	fm.roughness = 0.4
	fm.metallic = 0.3
	plane.material = fm
	floor.mesh = plane
	_world.add_child(floor)

	var key := DirectionalLight3D.new()
	key.light_color = Color("#fff1dc")
	key.light_energy = 1.8
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-55, 30, 0)
	_world.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#bfd8ff")
	fill.light_energy = 0.5
	fill.rotation_degrees = Vector3(-25, -140, 0)
	_world.add_child(fill)

	for side in [[-1.0, Color("#3a90ff")], [1.0, Color("#ff3b48")]]:
		var rim := OmniLight3D.new()
		rim.light_color = side[1]
		rim.light_energy = 2.0
		rim.omni_range = 8.0
		rim.position = Vector3(side[0] * 3.0, 3.0, -2.5)
		_world.add_child(rim)


func _shoot(out_dir: String) -> void:
	var scene := load("res://assets/characters/mannequin.glb")
	var views := [
		{"name": "front", "eye": Vector3(0.0, 1.35, 4.4), "look": Vector3(0.0, 0.95, 0.0)},
		{"name": "back", "eye": Vector3(-1.8, 1.6, -3.8), "look": Vector3(0.0, 0.95, 0.0)},
		{"name": "face", "eye": Vector3(-0.35, 1.72, 1.3), "look": Vector3(-0.45, 1.66, 0.0)},
		{"name": "gun", "eye": Vector3(-1.75, 1.44, 1.45), "look": Vector3(-0.5, 1.26, 0.15)},
	]
	for style in SuitStyle.STYLES:
		var bodies: Array[Node3D] = []
		for slot in [["blue", -0.55], ["red", 0.55]]:
			var m: Node3D = scene.instantiate()
			m.scale = Vector3(0.98, 0.98, 0.98)
			m.position = Vector3(slot[1], 0.0, 0.0)
			_world.add_child(m)
			# The importer consumes a clip's "_Loop" suffix, so the aim pose the
			# pawns idle in is plain "Pistol_Idle" here.
			var player := _find_animation_player(m)
			if player and player.has_animation("Pistol_Idle"):
				player.play("Pistol_Idle")
				player.seek(0.6, true)
			# The gun rides the hand bone as it does on a pawn, so its black and
			# its lit accents are checked against every suit finish.
			var gun := _attach_gun(m)
			TeamTint.apply_body(m, slot[0], style)
			if gun:
				TeamTint.apply_gun(gun, slot[0])
			bodies.append(m)

		for view: Dictionary in views:
			_cam.look_at_from_position(view["eye"], view["look"], Vector3.UP)
			for i in 4:
				await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			var path := "%s/suit_%s_%s.png" % [out_dir, style, view["name"]]
			var err := img.save_png(path)
			print("%s %s" % ["saved" if err == OK else "FAILED to save", path])

		for b in bodies:
			b.queue_free()
		await process_frame

	quit()


## Seats the pistol in the right hand, using the pawns' own placement constants
## so the shots frame it exactly where a player sees it.
func _attach_gun(model: Node3D) -> Node3D:
	var skel := _find_skeleton(model)
	if skel == null:
		return null
	var bone_name := ""
	for candidate: String in LocalPawn.HAND_BONE_NAMES:
		if skel.find_bone(candidate) != -1:
			bone_name = candidate
			break
	if bone_name.is_empty():
		return null
	var gun_scene := load(LocalPawn.GUN_MODEL_PATH)
	if gun_scene == null:
		return null

	var attach := BoneAttachment3D.new()
	attach.bone_name = bone_name
	skel.add_child(attach)
	var seat := Node3D.new()
	seat.rotation_order = EULER_ORDER_ZYX
	seat.position = LocalPawn.GUN_HAND_POS
	seat.rotation_degrees = LocalPawn.GUN_HAND_ROT
	attach.add_child(seat)

	var gun: Node3D = gun_scene.instantiate()
	gun.rotation_degrees = Vector3(0.0, LocalPawn.GUN_MODEL_YAW, 0.0)
	gun.scale = Vector3.ONE * LocalPawn.GUN_HAND_SCALE
	seat.add_child(gun)
	return gun


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
