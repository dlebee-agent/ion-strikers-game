class_name AntiCheat
extends RefCounted

## Server-side anti-cheat. One instance per GameInstance, which calls in at
## four points and does what comes back:
##
##   update_state  → check_state   accept or drop a reported position
##   handle_shot   → check_shot    drop, or fix origin and rewind
##   build_snap    → sees          leave a hidden enemy out of a snapshot
##   _spawn_pawn / remove          on_spawn / on_leave
##
## Every check is its own class in this directory; this file only wires them
## and turns repeat offenders into kick_requested through the ledger. Nothing
## here touches the client, the protocol, or any state but its own.

signal kick_requested(peer_id: int, reason: String)
signal strike(peer_id: int, kind: String, count: int)

var enabled := true
## Movement and flight enforcement pause while server cheats are on; an
## admin flying around the map is the point of that mode.
var enforce_movement := true
var world: CollisionWorld = null

var movement := AcMovementCheck.new()
var flight := AcFlightCheck.new()
var shots := AcShotCheck.new()
var culling := AcVisibilityCull.new()
var ledger := AcViolations.new()

## Seconds a snapshot has to look ahead before any ping is added: the
## client's interpolation delay, one snapshot interval, and the longest a
## hidden pair waits to be looked at again.
const LEAD_BASE_S := 0.08 + 1.0 / 30.0 + AcVisibilityCull.RECHECK_HIDDEN_S
## Two bodies closing on each other cover ground faster than one running;
## less than twice, since a peek is a sidestep, not a sprint.
const LEAD_SPEED := Movement.RUN_SPEED * 1.5


func configure(p_world: CollisionWorld) -> void:
	world = p_world


func on_spawn(body_id: int, pos: Vector3, now: float) -> void:
	movement.reset(body_id, pos, now)
	flight.reset(body_id)


func on_leave(id: int) -> void:
	movement.forget(id)
	flight.forget(id)
	shots.forget(id)
	culling.forget(id)
	ledger.clear(id)


## True when the reported position may be applied to the pawn.
func check_state(peer_id: int, pawn: ServerPawn, pos: Vector3, now: float) -> bool:
	if not enabled or not enforce_movement:
		return true
	var body_id := pawn.participant_id
	var m := movement.check(body_id, pos, now)
	if m == AcMovementCheck.REJECT:
		return false
	var f := flight.check(body_id, pos, now, world)
	if f == AcFlightCheck.REJECT:
		return false
	if f != "":
		_strike(peer_id, f, now)
		return false
	if m == AcMovementCheck.TELEPORT:
		_strike(peer_id, m, now)
	return true


## Returns {"allow", "origin", "lag_ms"}: the shot as the server will run it.
func check_shot(peer_id: int, pawn: ServerPawn, origin: Vector3, dir: Vector3,
		lag_ms: int, ping_ms: int, now: float, max_rewind_ms: float) -> Dictionary:
	if not enabled:
		return {"allow": true, "origin": origin, "lag_ms": int(clampf(float(lag_ms), 0.0, max_rewind_ms))}
	var v := shots.check_shot(peer_id, pawn, origin, dir, lag_ms, ping_ms, now, max_rewind_ms)
	for kind: String in v["strikes"]:
		_strike(peer_id, kind, now)
	return v


## Whether a snapshot for the viewer should carry where the target is.
func sees(viewer: ServerPawn, viewer_ping_ms: int, target: ServerPawn, target_ping_ms: int,
		now: float) -> bool:
	if not enabled or world == null:
		return true
	var lead := LEAD_SPEED * (LEAD_BASE_S + float(viewer_ping_ms + target_ping_ms) * 0.0005)
	return culling.sees(world, viewer, target, lead, now)


func _strike(peer_id: int, kind: String, now: float) -> void:
	var n := ledger.add(peer_id, kind, now)
	strike.emit(peer_id, kind, n)
	if ledger.over_limit(peer_id, kind, now):
		ledger.clear(peer_id)
		kick_requested.emit(peer_id, kind)
