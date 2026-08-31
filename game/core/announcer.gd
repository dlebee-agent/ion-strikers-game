extends Node

signal banner_requested(text: String, color: Color, sub_text: String)

const AUDIO_PATH := "res://assets/audio/"
const DEBOUNCE_MS := 600

const SPREE_LADDER: Dictionary[int, String] = {
	3: "triple", 5: "multi", 6: "rampage", 7: "spree", 8: "dominating",
	9: "impressive", 10: "unstoppable", 11: "outstanding", 12: "mega", 13: "ultra",
	14: "eagleeye", 15: "ownage", 16: "comboking", 17: "maniac", 18: "ludicrous",
	19: "bullseye", 20: "excellent", 21: "pancake", 22: "headhunter", 23: "unreal",
	24: "assassin", 25: "wickedsick", 26: "massacre", 27: "killingmachine",
	28: "monster", 29: "holyshit", 30: "godlike",
}

const ANNOUNCE_TEXT: Dictionary = {
	"round_start": "Round start",
	"match_point": "Match point",
	"blue_wins": "Blue wins",
	"red_wins": "Red wins",
	"first_blood": "First blood",
	"headshot": "Headshot",
	"triple": "Triple kill",
	"multi": "Multi kill",
	"rampage": "Rampage",
	"spree": "Killing spree",
	"dominating": "Dominating",
	"impressive": "Impressive",
	"unstoppable": "Unstoppable",
	"outstanding": "Outstanding",
	"mega": "Mega kill",
	"ultra": "Ultra kill",
	"eagleeye": "Eagle eye",
	"ownage": "Ownage",
	"comboking": "Combo king",
	"maniac": "Maniac",
	"ludicrous": "Ludicrous kill",
	"bullseye": "Bullseye",
	"excellent": "Excellent",
	"pancake": "Pancake",
	"headhunter": "Head hunter",
	"unreal": "Unreal",
	"assassin": "Assassin",
	"wickedsick": "Wicked sick",
	"massacre": "Massacre",
	"killingmachine": "Killing machine",
	"monster": "Monster kill",
	"holyshit": "Holy cow",
	"godlike": "Godlike",
}

const COLOR_BLUE := Color(0.2, 0.6, 1.0)
const COLOR_RED := Color(1.0, 0.25, 0.25)
const COLOR_GOLD := Color(1.0, 0.85, 0.2)
const COLOR_WHITE := Color.WHITE

var _cache: Dictionary = {}
var _last_played: Dictionary = {}
var _announcer_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer


func _ready() -> void:
	_announcer_player = AudioStreamPlayer.new()
	_announcer_player.bus = "SFX"
	add_child(_announcer_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)


func handle_announce(msg: Dictionary) -> void:
	if msg.get("match_point", false):
		play_clip("match_point")
		show_banner("MATCH POINT", COLOR_GOLD)
		return

	if msg.get("first_blood", false):
		play_clip("first_blood")
		var who: String = msg.get("by_name", "")
		show_banner("FIRST BLOOD", COLOR_RED, who)
		return

	var who: String = msg.get("by_name", "")
	# A streak-ladder clip wins over a simultaneous headshot.
	var clip := _spree_clip(int(msg.get("spree", 0)))
	if not clip.is_empty():
		play_clip(clip)
		show_banner(ANNOUNCE_TEXT.get(clip, clip).to_upper(), COLOR_GOLD, who)
		return

	if msg.get("head", false):
		play_clip("headshot")
		show_banner("HEADSHOT", COLOR_WHITE, who)


func play_clip(key: String) -> void:
	var now := Time.get_ticks_msec()
	if _last_played.has(key) and (now - _last_played[key]) < DEBOUNCE_MS:
		return
	var stream := _load_audio(key)
	if stream == null:
		return
	_last_played[key] = now
	_announcer_player.stream = stream
	_announcer_player.play()


func play_sfx(key: String, volume_db: float = 0.0) -> void:
	var stream := _load_audio(key)
	if stream == null:
		return
	_sfx_player.stream = stream
	_sfx_player.volume_db = volume_db
	_sfx_player.play()


func show_banner(text: String, color: Color, sub: String = "") -> void:
	banner_requested.emit(text, color, sub)


func round_start() -> void:
	play_clip("round_start")
	show_banner("ROUND START", COLOR_WHITE)


func round_end(winner_team: int, match_over: bool, match_point: bool) -> void:
	play_clip("round_end_sting")
	if match_over:
		var delay_timer := get_tree().create_timer(1.2)
		delay_timer.timeout.connect(func() -> void:
			if winner_team == Protocol.TEAM_BLUE:
				play_clip("blue_wins")
			else:
				play_clip("red_wins"))
	elif match_point:
		var delay_timer := get_tree().create_timer(1.4)
		delay_timer.timeout.connect(func() -> void: play_clip("match_point"))


func match_over(winner_team: int) -> void:
	if winner_team == Protocol.TEAM_BLUE:
		play_clip("blue_wins")
		show_banner("BLUE WINS", COLOR_BLUE)
	else:
		play_clip("red_wins")
		show_banner("RED WINS", COLOR_RED)


func player_hurt() -> void:
	play_sfx("hurt")


func player_died() -> void:
	play_sfx("died")


func player_respawn() -> void:
	play_sfx("respawn")


func _spree_clip(spree: int) -> String:
	if spree <= 0:
		return ""
	return SPREE_LADDER.get(mini(spree, 30), "")


func _load_audio(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]

	for ext: String in ["wav", "mp3", "ogg"]:
		var path: String = AUDIO_PATH + key + "." + ext
		if ResourceLoader.exists(path):
			var res: Resource = load(path)
			if res is AudioStream:
				_cache[key] = res
				return res
		if not FileAccess.file_exists(path):
			continue
		var abs_path := ProjectSettings.globalize_path(path)
		var stream: AudioStream = null
		match ext:
			"wav":
				stream = AudioStreamWAV.load_from_file(abs_path)
			"mp3":
				stream = AudioStreamMP3.load_from_file(abs_path)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(abs_path)
		if stream:
			_cache[key] = stream
			return stream

	_cache[key] = null
	return null
