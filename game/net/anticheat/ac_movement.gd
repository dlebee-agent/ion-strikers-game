class_name AcMovementCheck
extends RefCounted

## Teleport check on the positions a client reports.
##
## The client owns its movement, so the server cannot know where a body
## should be, only how far one can travel in the time since the last report
## it accepted. Distance is paid out of a budget that refills at MAX_SPEED
## and caps at BUDGET_CAP_S of it: a burst of late packets clears, a jump
## across the map does not.
##
## MAX_SPEED is not running speed. Movement is Quake-style air acceleration
## with no ceiling, and a bunny hop that keeps strafing keeps gaining: the
## solver measured 27 m/s at 25 deg/s of air turn and 61 m/s at 75 deg/s
## over 90 s on an open plane. The budget sits above that, so this catches a
## body that crosses the map in an instant and nothing slower. A speed hack
## under MAX_SPEED looks like a hop and goes through; only running the
## solver on the server from replicated inputs could tell them apart.
##
## A report that cannot be paid for is dropped and the server keeps the last
## accepted position. After RESYNC_S of that the client is accepted where it
## is and the episode counts as one teleport, so a player whose packets were
## lost is not stuck forever and a cheater buys each jump with a strike.

const MAX_SPEED := 65.0
const BUDGET_CAP_S := 0.5
const STEP_SLACK := 0.5
const RISE_SLACK := 1.3
const RESYNC_S := 2.0

const REJECT := "reject"
const TELEPORT := "teleport"

var _records: Dictionary = {}   # body_id → {pos, at, budget, reject_since}


func reset(body_id: int, pos: Vector3, now: float) -> void:
	_records[body_id] = {"pos": pos, "at": now, "budget": 0.0, "reject_since": 0.0}


func forget(body_id: int) -> void:
	_records.erase(body_id)


## "" when the report is accepted, TELEPORT when it is accepted only because
## the client has been out of reach for RESYNC_S, REJECT when it is dropped.
func check(body_id: int, pos: Vector3, now: float) -> String:
	if not _records.has(body_id):
		reset(body_id, pos, now)
		return ""
	var r: Dictionary = _records[body_id]
	var dt := maxf(0.0, now - float(r["at"]))
	var budget := minf(float(r["budget"]) + MAX_SPEED * dt, MAX_SPEED * BUDGET_CAP_S)
	r["budget"] = budget

	var last: Vector3 = r["pos"]
	var flat := Vector2(pos.x - last.x, pos.z - last.z).length()
	var rise := pos.y - last.y
	# Falling is not capped: gravity is. A step is instant, a jump is not.
	var rise_allowed := Movement.JUMP_VEL * RISE_SLACK * dt + Movement.STEP_HEIGHT + STEP_SLACK

	if flat <= budget + STEP_SLACK and rise <= rise_allowed:
		r["budget"] = maxf(0.0, budget - flat)
		r["pos"] = pos
		r["at"] = now
		r["reject_since"] = 0.0
		return ""

	if float(r["reject_since"]) <= 0.0:
		r["reject_since"] = now
	if now - float(r["reject_since"]) < RESYNC_S:
		return REJECT

	r["pos"] = pos
	r["at"] = now
	r["budget"] = 0.0
	r["reject_since"] = 0.0
	return TELEPORT
