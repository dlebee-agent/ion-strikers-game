class_name GameRegistry
extends RefCounted

var max_lobbies: int = 1
var instances: Dictionary = {}   # game_id → GameInstance


func create(cfg: Dictionary) -> GameInstance:
	if instances.size() >= max_lobbies:
		return null
	var inst := GameInstance.new(cfg)
	instances[inst.game_id] = inst
	return inst


func resolve_join_direct() -> GameInstance:
	if instances.size() == 1:
		return instances.values()[0]
	return null


func remove_instance(game_id: String) -> void:
	instances.erase(game_id)
