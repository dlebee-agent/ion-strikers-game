class_name TraceResult
extends RefCounted

# Outcome of a swept box or ray query against the CollisionWorld. Reused across
# queries so a move that clips four times does not allocate four results.

# Fraction of the requested motion actually travelled, 0..1.
var fraction := 1.0
# Surface normal of whatever stopped the sweep; ZERO when nothing did.
var normal := Vector3.ZERO
# Where the box ended up.
var end_pos := Vector3.ZERO
# The sweep began already inside solid geometry.
var start_solid := false
# The sweep began inside solid and never got out.
var all_solid := false
# Index of the brush that was hit, -1 when none was.
var brush := -1


func reset(start: Vector3, target: Vector3) -> void:
	fraction = 1.0
	normal = Vector3.ZERO
	end_pos = target
	start_solid = false
	all_solid = false
	brush = -1


func hit() -> bool:
	return fraction < 1.0
