class_name RoundState
extends RefCounted

## Classic mode only. DM skips this entirely.

var round_id: String
var round_num: int
var round_score_blue: int = 0
var round_score_red: int = 0


func _init(p_num: int) -> void:
	round_num = p_num
	round_id = MatchState._gen_id()
