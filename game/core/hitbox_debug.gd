extends Node3D

var active: bool = false:
	set(v):
		active = v
		_clear_meshes()


var _meshes: Array[MeshInstance3D] = []
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("hitbox_debug")
	_body_mat = _make_material(Color(0.3, 0.9, 1.0, 0.25))
	_head_mat = _make_material(Color(1.0, 0.65, 0.3, 0.3))


func _process(_dt: float) -> void:
	_clear_meshes()
	if not active:
		return

	var match_node := _find_match()
	if match_node == null:
		return

	var remotes: Dictionary = match_node.get("_remotes")
	if remotes == null:
		remotes = {}
	for pid: int in remotes:
		var rp = remotes[pid]
		if not rp.alive:
			continue
		var pos := Vector3(rp._last_eye_x, rp._last_eye_y, rp._last_eye_z)
		_draw_hitbox(pos, rp._last_eye_crouched)


func _draw_hitbox(pos: Vector3, crouched: bool) -> void:
	var foot_y: float
	var chest_y: float
	var body_r: float
	var head_y: float
	var head_r: float

	if crouched:
		foot_y = Hitbox.CROUCH_FOOT_Y
		chest_y = Hitbox.CROUCH_CHEST_Y
		body_r = Hitbox.CROUCH_RADIUS
		head_y = Hitbox.CROUCH_HEAD_Y
		head_r = Hitbox.CROUCH_HEAD_R
	else:
		foot_y = Hitbox.STAND_FOOT_Y
		chest_y = Hitbox.STAND_CHEST_Y
		body_r = Hitbox.STAND_RADIUS
		head_y = Hitbox.STAND_HEAD_Y
		head_r = Hitbox.STAND_HEAD_R

	var capsule_height := (chest_y - foot_y) + body_r * 2.0
	var capsule_center_y := (foot_y + chest_y) * 0.5

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = body_r
	body_mesh.height = capsule_height
	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body_mesh
	body_inst.material_override = _body_mat
	body_inst.position = Vector3(pos.x, pos.y + capsule_center_y, pos.z)
	add_child(body_inst)
	_meshes.append(body_inst)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = head_r
	head_mesh.height = head_r * 2.0
	var head_inst := MeshInstance3D.new()
	head_inst.mesh = head_mesh
	head_inst.material_override = _head_mat
	head_inst.position = Vector3(pos.x, pos.y + head_y, pos.z)
	add_child(head_inst)
	_meshes.append(head_inst)


func _clear_meshes() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.queue_free()
	_meshes.clear()


func _find_match() -> Node:
	var nodes := get_tree().get_nodes_in_group("match_scene")
	if not nodes.is_empty():
		return nodes[0]
	return get_parent()


static func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
