class_name Protocol
extends RefCounted

# Minimal message protocol.  V1 uses JSON dictionaries on ENet channels.
# Reliable channel 0: join handshake, init, leave, errors.
# Unreliable channel 1: state updates, snapshots.
# A later binary schema (IMPLEMENTATION_PLAN §15) replaces the encoding
# without changing class or field names.

const CHANNEL_RELIABLE := 0
const CHANNEL_UNRELIABLE := 1
const PROTOCOL_VERSION := 1

# ---- message types ----

enum Msg {
	JOIN_DIRECT,
	JOIN_ERROR,
	INIT,
	STATE,
	SNAP,
	LEAVE,
}

# ---- encode (Dictionary → PackedByteArray) ----

static func encode(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()


static func decode(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


# ---- helpers to build typed messages ----

static func join_direct(callsign: String) -> Dictionary:
	return {"t": Msg.JOIN_DIRECT, "v": PROTOCOL_VERSION, "name": callsign}


static func join_error(reason: String) -> Dictionary:
	return {"t": Msg.JOIN_ERROR, "reason": reason}


static func init_msg(peer_id: int, map_id: String, spawn: Vector3, yaw: float) -> Dictionary:
	return {
		"t": Msg.INIT,
		"id": peer_id,
		"map": map_id,
		"sx": spawn.x, "sy": spawn.y, "sz": spawn.z,
		"yaw": yaw,
	}


static func state_msg(pos: Vector3, yaw: float, pitch: float) -> Dictionary:
	return {
		"t": Msg.STATE,
		"x": pos.x, "y": pos.y, "z": pos.z,
		"yaw": yaw, "pitch": pitch,
	}


static func snap_msg(players: Array[Dictionary]) -> Dictionary:
	return {"t": Msg.SNAP, "players": players}


static func leave_msg() -> Dictionary:
	return {"t": Msg.LEAVE}
