class_name ServerPawn
extends RefCounted

## One life. Destroyed on death or round reset, new one allocated on spawn.

const HISTORY_MS := 1000.0
const MAX_HISTORY := 64

var participant_id: int
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var hp: int = 100
var alive: bool = true
## Whether the pawn is standing on something. Reported by the owning client
## for players, set from the walk step for bots. The animation on every other
## client reads this rather than guessing from vertical speed.
var grounded := true
var crouched: bool = false
var protected_until: float = 0.0
var respawn_at: float = 0.0

var _history: Array[Dictionary] = []


func record_history(now: float) -> void:
	_history.append({"t": now, "x": position.x, "y": position.y, "z": position.z, "cr": crouched})
	while _history.size() > 2 and now - _history[0]["t"] > HISTORY_MS:
		_history.pop_front()


func rewind_to(at: float) -> Dictionary:
	if _history.is_empty():
		return {"x": position.x, "y": position.y, "z": position.z, "cr": crouched}
	if at >= _history[-1]["t"]:
		return _history[-1].duplicate()
	if at <= _history[0]["t"]:
		return _history[0].duplicate()
	for i in range(_history.size() - 1):
		var a: Dictionary = _history[i]
		var b: Dictionary = _history[i + 1]
		if at >= a["t"] and at <= b["t"]:
			var span: float = b["t"] - a["t"]
			if span < 0.001:
				return a.duplicate()
			var f: float = (at - a["t"]) / span
			return {
				"x": lerpf(a["x"], b["x"], f),
				"y": lerpf(a["y"], b["y"], f),
				"z": lerpf(a["z"], b["z"], f),
				"cr": b["cr"],
			}
	return _history[-1].duplicate()
