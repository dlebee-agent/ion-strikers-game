extends Node

const SETTINGS_PATH := "user://settings.cfg"
const MENU_BASE := 0.45
const MENU_PATH := "res://assets/audio/menu_music.mp3"
const MATCH_OVER_PATH := "res://assets/audio/matchover_music.mp3"

var master_pct: int = 80
var sfx_pct: int = 90
var music_pct: int = 45

var _player: AudioStreamPlayer
var _fade: float = 1.0
var _tween: Tween
var _match_over_playing: bool = false

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load()
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.stream = _load_menu_stream()
	_player.volume_db = linear_to_db(MENU_BASE)
	add_child(_player)
	apply()

func play_menu() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	_fade = 1.0
	_apply_player_volume()
	if _match_over_playing:
		# Victory track keeps looping into the lobby until a new match starts.
		if _player.stream_paused:
			_player.stream_paused = false
		elif not _player.playing:
			_player.play()
		return
	if _player.stream == null or _player.stream.resource_path != MENU_PATH:
		_player.stream = _load_menu_stream()
	if _player.stream == null:
		return
	if _player.stream_paused:
		_player.stream_paused = false
	elif not _player.playing:
		_player.play()


func play_match_over() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	_fade = 1.0
	_match_over_playing = true
	var stream := _load_stream(MATCH_OVER_PATH)
	if stream == null:
		return
	if _player.stream != stream:
		_player.stream = stream
	_apply_player_volume()
	if _player.stream_paused:
		_player.stream_paused = false
	if not _player.playing:
		_player.play()

func fade_out_menu(ms: float = 600.0) -> void:
	fade_out_keep_place(ms)

func fade_out_keep_place(ms: float = 600.0) -> void:
	if _player == null or not _player.playing:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_fade, _fade, 0.0, ms / 1000.0)
	_tween.finished.connect(func() -> void:
		_player.stream_paused = true
		_fade = 1.0
		_match_over_playing = false
		_apply_player_volume()
		_tween = null)

func apply() -> void:
	_set_bus_linear("Master", master_pct / 100.0)
	_set_bus_linear("SFX", sfx_pct / 100.0)
	_set_bus_linear("Music", music_pct / 100.0)
	_apply_player_volume()

func set_master(pct: int) -> void:
	master_pct = clampi(pct, 0, 100)
	apply()
	_save()

func set_sfx(pct: int) -> void:
	sfx_pct = clampi(pct, 0, 100)
	apply()
	_save()

func set_music(pct: int) -> void:
	music_pct = clampi(pct, 0, 100)
	apply()
	_save()

func _set_fade(v: float) -> void:
	_fade = v
	_apply_player_volume()

func _apply_player_volume() -> void:
	if _player == null:
		return
	var lin := MENU_BASE * _fade
	_player.volume_db = linear_to_db(lin) if lin > 0.0001 else -80.0

func _load_menu_stream() -> AudioStream:
	return _load_stream(MENU_PATH)


func _load_stream(path: String) -> AudioStream:
	var s: Resource = load(path)
	if s is AudioStream:
		var stream := s as AudioStream
		if stream.has_method("set_loop"):
			stream.call("set_loop", true)
		return stream
	if ClassDB.class_exists("AudioStreamMP3"):
		var mp3: AudioStream = AudioStreamMP3.load_from_file(path)
		if mp3:
			mp3.set("loop", true)
			return mp3
	return null

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if linear <= 0.0001:
		AudioServer.set_bus_mute(idx, true)
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_pct = _read_pct(cfg, "master", 80)
	sfx_pct = _read_pct(cfg, "sfx", 90)
	music_pct = _read_pct(cfg, "music", 45)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "master", master_pct)
	cfg.set_value("audio", "sfx", sfx_pct)
	cfg.set_value("audio", "music", music_pct)
	cfg.save(SETTINGS_PATH)

func _read_pct(cfg: ConfigFile, key: String, fallback: int) -> int:
	if not cfg.has_section_key("audio", key):
		return fallback
	var v: Variant = cfg.get_value("audio", key, fallback)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		var f := float(v)
		if f <= 1.0:
			return clampi(int(round(f * 100.0)), 0, 100)
		return clampi(int(round(f)), 0, 100)
	return fallback
