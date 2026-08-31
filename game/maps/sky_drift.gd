class_name SkyDrift
extends Node

# Baked cubemap, so rotating the sky is the cheap way to give it life.
const DEG_PER_SEC := 0.42

var environment: Environment
var _deg := 0.0


func _process(dt: float) -> void:
	if environment == null:
		return
	_deg += DEG_PER_SEC * dt
	environment.sky_rotation = Vector3(
		deg_to_rad(_deg * 0.32),
		deg_to_rad(_deg),
		deg_to_rad(_deg * 0.11)
	)
