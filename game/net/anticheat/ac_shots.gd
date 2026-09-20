class_name AcShotCheck
extends RefCounted

## What the server can hold a shot to. Aim itself is the client's and stays
## that way; the rest is not:
##
## - Rate: a token bucket at the weapon's fire delay with a burst of two, so
##   two shots squeezed together by jitter both land and a third does not.
## - Origin: the shot must leave the eye of the body the server knows. A
##   client runs ahead of the server by its latency, so an origin within
##   ORIGIN_TOLERANCE is kept and anything further is moved to the eye.
## - Rewind: the client asks for lag compensation; it gets at most half its
##   own ping plus interpolation and a little slack, never a stranger's past.
## - View: a shot far off the direction the client itself last reported is
##   a strike. Lost state packets and real flicks both happen, so this only
##   ever counts, and only past AIM_VIEW_MAX.

const FIRE_GAP_S := Movement.FIRE_DELAY_MS / 1000.0
const BURST := 2.0
const ORIGIN_TOLERANCE := 1.5
const LAG_SLACK_MS := 140.0
const AIM_VIEW_MAX := deg_to_rad(100.0)

var _buckets: Dictionary = {}   # peer_id → {tokens, at}


func forget(peer_id: int) -> void:
	_buckets.erase(peer_id)


## Returns {"allow", "origin", "lag_ms", "strikes"}: whether the shot goes
## through, the origin and rewind it goes through with, and the kinds of
## strike it earned.
func check_shot(peer_id: int, pawn: ServerPawn, origin: Vector3, dir: Vector3,
		lag_ms: int, ping_ms: int, now: float, max_rewind_ms: float) -> Dictionary:
	var out := {"allow": true, "origin": origin, "lag_ms": lag_ms, "strikes": []}

	var b: Dictionary = _buckets.get(peer_id, {"tokens": BURST, "at": now})
	b["tokens"] = minf(BURST, float(b["tokens"]) + maxf(0.0, now - float(b["at"])) / FIRE_GAP_S)
	b["at"] = now
	_buckets[peer_id] = b
	if float(b["tokens"]) < 1.0:
		out["allow"] = false
		out["strikes"].append("fire_rate")
		return out
	b["tokens"] = float(b["tokens"]) - 1.0

	var eye := pawn.position + Vector3(0.0, Hitbox.eye_height(pawn.crouched), 0.0)
	if origin.distance_to(eye) > ORIGIN_TOLERANCE:
		out["origin"] = eye
		out["strikes"].append("shot_origin")

	var lag_cap := minf(max_rewind_ms, float(ping_ms) * 0.5 + LAG_SLACK_MS)
	out["lag_ms"] = int(clampf(float(lag_ms), 0.0, lag_cap))

	if dir.length_squared() > 0.0 and aim_dir(pawn.yaw, pawn.pitch).angle_to(dir.normalized()) > AIM_VIEW_MAX:
		out["strikes"].append("aim_view")
	return out


static func aim_dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	var ry := deg_to_rad(yaw_deg)
	var rp := deg_to_rad(pitch_deg)
	return Vector3(-sin(ry) * cos(rp), -sin(rp), -cos(ry) * cos(rp))
