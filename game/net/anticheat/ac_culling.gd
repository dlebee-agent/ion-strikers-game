class_name AcVisibilityCull
extends RefCounted

## Corner culling: whether one body can see another through the map, decided
## on the server so a client that cannot see a player is never told where
## that player is.
##
## Rays run from the viewer's eye to points on the target body pushed out
## sideways by how far the two can close on each other before the snapshot
## is on screen. That lookahead is what keeps the culling optimistic: a
## player peeking a corner is in the snapshot before their model clears the
## edge, so nobody pops in late. A body that
## was visible stays in the snapshot for HOLD_S after the last clear ray,
## which covers a missed sample and stops flicker at an edge.
##
## Cost is one ray for a pair in plain view and five for a hidden one, paid
## once per pair rather than once per direction, and no more often than the
## recheck intervals. Bodies within NEAR_ALWAYS are always sent, since a wall
## that thin should not hide the melee coming through it.

const NEAR_ALWAYS := 4.0
const HOLD_S := 0.3
const RECHECK_VISIBLE_S := 0.1
const RECHECK_HIDDEN_S := 1.0 / 15.0
const CHEST_Y := 1.0

var _trace := TraceResult.new()
var _pairs: Dictionary = {}   # "lo:hi" → {visible, checked_at, seen_at}


func forget(id: int) -> void:
	for key: String in _pairs.keys():
		var parts := key.split(":")
		if int(parts[0]) == id or int(parts[1]) == id:
			_pairs.erase(key)


## lead is how far the two bodies can close on each other before the
## snapshot is on screen. One verdict serves both directions of a pair, and
## it is only refreshed at RECHECK_VISIBLE_S or RECHECK_HIDDEN_S, whichever
## the last verdict calls for.
func sees(world: CollisionWorld, viewer: ServerPawn, target: ServerPawn,
		lead: float, now: float) -> bool:
	if world == null:
		return true
	var a := mini(viewer.participant_id, target.participant_id)
	var b := maxi(viewer.participant_id, target.participant_id)
	var key := "%d:%d" % [a, b]
	var e: Dictionary = _pairs.get(key, {})
	if not e.is_empty():
		var wait: float = RECHECK_VISIBLE_S if bool(e["visible"]) else RECHECK_HIDDEN_S
		if now - float(e["checked_at"]) < wait:
			return bool(e["visible"]) or now - float(e["seen_at"]) < HOLD_S

	var clear := viewer.position.distance_to(target.position) <= NEAR_ALWAYS \
		or _clear(world, viewer, target, lead)
	if e.is_empty():
		e = {"visible": clear, "checked_at": now, "seen_at": -INF}
		_pairs[key] = e
	e["visible"] = clear
	e["checked_at"] = now
	if clear:
		e["seen_at"] = now
	return clear or now - float(e["seen_at"]) < HOLD_S


## Five rays at most: chest, head, feet, and the two sides of the body as
## seen from the eye, pushed out by the lead. The sides are what a corner
## peek shows first, so those two carry the lookahead.
func _clear(world: CollisionWorld, viewer: ServerPawn, target: ServerPawn, lead: float) -> bool:
	var eye := viewer.position + Vector3(0.0, Hitbox.eye_height(viewer.crouched), 0.0)
	var t := target.position
	var chest := t + Vector3(0.0, CHEST_Y, 0.0)
	if not _blocked(world, eye, chest):
		return true

	var head_y := Hitbox.CROUCH_HEAD_Y if target.crouched else Hitbox.STAND_HEAD_Y
	var flat := Vector3(t.x - eye.x, 0.0, t.z - eye.z)
	var side := Vector3(-flat.z, 0.0, flat.x).normalized() if flat.length_squared() > 0.001 else Vector3.RIGHT
	var reach := Movement.PLAYER_RADIUS + lead
	for p: Vector3 in [chest + side * reach, chest - side * reach,
			t + Vector3(0.0, head_y, 0.0), t + Vector3(0.0, Hitbox.STAND_FOOT_Y, 0.0)]:
		if not _blocked(world, eye, p):
			return true
	return false


func _blocked(world: CollisionWorld, from: Vector3, to: Vector3) -> bool:
	world.raycast(from, to, _trace, CollisionWorld.MASK_SOLID)
	return _trace.hit()
