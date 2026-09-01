class_name FxWarm
extends Node

## Godot compiles a material's shader variant the first time it is drawn, and in
## a match that first draw is a meteor falling on someone. FxUtil.emissive makes
## exactly two variants — opaque unshaded, and additive alpha with depth writes
## off — and MeteorFx's head is the ONLY full-opacity effect in the game, so the
## opaque variant has never been compiled by the time the rock arrives.
##
## Draw one of each into a 4x4 offscreen viewport during map load instead. Its
## own World3D keeps the warm-up meshes out of the match's world, so nothing
## reaches the player's screen.

const FxUtil = preload("res://core/fx_util.gd")

const WARM_FRAMES := 4

var _frames := 0


static func warm(parent: Node) -> void:
	parent.add_child(FxWarm.new())


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(4, 4)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 10.0
	cam.position = Vector3(0.0, 0.0, 2.0)
	cam.current = true
	vp.add_child(cam)

	var opaque := FxUtil.sphere(FxUtil.emissive(Color.WHITE, 1.0))
	opaque.position = Vector3(-0.4, 0.0, 0.0)
	vp.add_child(opaque)

	var additive := FxUtil.cylinder(FxUtil.emissive(Color.WHITE, 0.5))
	additive.position = Vector3(0.4, 0.0, 0.0)
	vp.add_child(additive)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames >= WARM_FRAMES:
		queue_free()
