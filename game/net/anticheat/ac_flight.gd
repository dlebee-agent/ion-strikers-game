class_name AcFlightCheck
extends RefCounted

## Hovering and clipping. The map says whether there is ground under a body
## and whether the body is inside a wall; the client's own grounded flag is
## not trusted for either.
##
## A body with nothing under it must be falling. After HOVER_S in the air it
## has to be at least MIN_FALL below the highest point it reached, which a
## jump or a drop always satisfies and a hover never does. A slow descent
## slips through, but a slow descent ends on the ground.

const GROUND_PROBE := Movement.STEP_HEIGHT + 0.3
## As wide as the body the solver stands on, so a foot hanging over a ledge
## still finds the ledge.
const GROUND_HALF := Vector3(Movement.PLAYER_RADIUS + 0.05, 0.05, Movement.PLAYER_RADIUS + 0.05)
const HOVER_S := 1.0
const MIN_FALL := 1.0
const STRIKE_GAP_S := 1.0

## A box well inside both the standing and the crouching body, high enough
## that its lower corners clear a walkable ramp under the feet.
const BODY_CENTRE_Y := 0.85
const BODY_HALF := Vector3(0.22, 0.38, 0.22)

const REJECT := "reject"
const FLIGHT := "flight"
const NOCLIP := "noclip"

var _trace := TraceResult.new()
var _air: Dictionary = {}   # body_id → {since, apex, struck_at}


func reset(body_id: int) -> void:
	_air.erase(body_id)


func forget(body_id: int) -> void:
	_air.erase(body_id)


## "" when the position is fine, NOCLIP inside a wall, FLIGHT when a hover
## earns a strike, REJECT while a hover already struck carries on.
func check(body_id: int, pos: Vector3, now: float, world: CollisionWorld) -> String:
	if world == null:
		return ""
	if world.box_overlaps(pos + Vector3(0.0, BODY_CENTRE_Y, 0.0), BODY_HALF):
		return NOCLIP

	var from := pos + Vector3(0.0, 0.2, 0.0)
	world.trace_box(from, from + Vector3(0.0, -(GROUND_PROBE + 0.2), 0.0), GROUND_HALF, _trace)
	if _trace.hit():
		_air.erase(body_id)
		return ""

	var a: Dictionary = _air.get(body_id, {})
	if a.is_empty():
		a = {"since": now, "apex": pos.y, "struck_at": 0.0}
		_air[body_id] = a
	a["apex"] = maxf(float(a["apex"]), pos.y)
	if now - float(a["since"]) < HOVER_S:
		return ""
	if pos.y <= float(a["apex"]) - MIN_FALL:
		return ""
	if now - float(a["struck_at"]) < STRIKE_GAP_S:
		return REJECT
	a["struck_at"] = now
	return FLIGHT
