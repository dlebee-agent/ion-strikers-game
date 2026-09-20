class_name AcViolations
extends RefCounted

## Ledger of what each peer has been caught doing. One bad packet is a
## rejected packet; a pattern of them inside WINDOW_S is a kick. The
## thresholds are per kind, so a check that can misfire on a bad connection
## needs many strikes and one that cannot needs few.

const WINDOW_S := 60.0

## Strikes within the window before a kick. A kind missing here is logged
## and acted on per packet but never kicks on its own.
const KICK_AFTER := {
	"teleport": 8,
	"flight": 5,
	"noclip": 5,
	"fire_rate": 30,
	"shot_origin": 30,
	"aim_view": 20,
}

var _entries: Dictionary = {}   # peer_id → Array of [kind, at]


## Records a strike and returns how many of that kind are inside the window.
func add(peer_id: int, kind: String, now: float) -> int:
	var list: Array = _entries.get(peer_id, [])
	list.append([kind, now])
	_entries[peer_id] = list
	return count(peer_id, kind, now)


func count(peer_id: int, kind: String, now: float) -> int:
	if not _entries.has(peer_id):
		return 0
	var list: Array = _entries[peer_id]
	while not list.is_empty() and now - float(list[0][1]) > WINDOW_S:
		list.pop_front()
	var n := 0
	for entry: Array in list:
		if entry[0] == kind:
			n += 1
	return n


func over_limit(peer_id: int, kind: String, now: float) -> bool:
	if not KICK_AFTER.has(kind):
		return false
	return count(peer_id, kind, now) >= int(KICK_AFTER[kind])


func clear(peer_id: int) -> void:
	_entries.erase(peer_id)
