class_name GameRegistry
extends RefCounted

# Owns GameInstances keyed by game_id.  For local_dedicated max_lobbies=1.

var max_lobbies: int = 1
var instances: Dictionary = {}   # game_id → GameInstance


func preload_instance(cfg: Dictionary) -> GameInstance:
	if instances.size() >= max_lobbies:
		return null
	var inst := GameInstance.new(cfg)
	instances[inst.game_id] = inst
	return inst


func resolve_join_direct() -> GameInstance:
	if max_lobbies == 1 and instances.size() == 1:
		return instances.values()[0]
	return null


func remove_instance(game_id: String) -> void:
	instances.erase(game_id)
