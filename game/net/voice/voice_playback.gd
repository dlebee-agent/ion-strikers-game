class_name VoicePlayback
extends Node

## Received frames to speakers, one independent stream per speaker.
##
## Each speaker gets their own AudioStreamPlayer fed by an AudioStreamGenerator,
## because mixing several speakers into one generator would need a mixer here
## and the audio engine already is one. Players are created on first frame and
## kept afterwards: a generator allocates its own ring buffer, and churning
## those every time someone stops talking is a hitch mid-match.
##
## Frames are upsampled from 8 kHz to the mixer rate on the way in, since
## AudioStreamGenerator plays at whatever rate it is given and resampling by
## hand costs less than running the whole bus at 8 kHz.

signal speaker_started(speaker_id: int)
signal speaker_stopped(speaker_id: int)

const BUS_NAME := "Voice"
## A generator holds this much audio. Long enough to ride out normal jitter at
## 20 ms a frame, short enough that the delay it adds is not itself noticeable.
const BUFFER_S := 0.3
## No frame for this long and the speaker is treated as having stopped, which
## is what clears their indicator. Push-to-talk sends nothing on release, so
## there is no end-of-speech packet to wait for.
const SILENCE_TIMEOUT_S := 0.25

var _streams: Dictionary = {}     # speaker_id → { player, playback, last_seq, last_at, speaking }
var _mix_rate: float = 44100.0
var _bus_idx: int = -1

## Output level, 0 to 1, independent of SFX so voice can be turned down
## without turning the game down.
var volume: float = 1.0:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		_apply_volume()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mix_rate = AudioServer.get_mix_rate()
	_ensure_bus()


static func is_supported() -> bool:
	return ClassDB.class_exists("AudioStreamGenerator")


## Queues one decoded frame for a speaker.
##
## seq is the speaker's own frame counter. Voice rides an unreliable channel,
## so a frame can arrive behind one already played; that one is dropped rather
## than played out of order, which would be an audible click for audio the
## listener has effectively already heard.
func push_frame(speaker_id: int, seq: int, audio: PackedByteArray) -> void:
	if audio.is_empty() or not is_supported():
		return

	var stream := _stream_for(speaker_id)
	if stream.is_empty():
		return

	if not _seq_is_newer(seq, int(stream["last_seq"])):
		return
	stream["last_seq"] = seq
	stream["last_at"] = Time.get_ticks_msec() / 1000.0

	if not bool(stream["speaking"]):
		stream["speaking"] = true
		speaker_started.emit(speaker_id)

	var samples := VoiceCodec.decode(audio, Protocol.VOICE_FRAME_SAMPLES)
	if samples.is_empty():
		return

	var playback: AudioStreamGeneratorPlayback = stream["playback"]
	if playback == null:
		return

	var ratio := _mix_rate / float(Protocol.VOICE_SAMPLE_RATE)
	var out_count := int(float(samples.size()) * ratio)
	if playback.get_frames_available() < out_count:
		# The buffer is behind, which means frames arrived faster than they
		# played. Dropping this one lets it catch up; holding it would grow a
		# delay that never recovers.
		return

	# Linear interpolation between neighbouring samples rather than repeating
	# each one. Sample-and-hold at this ratio puts a buzz on every vowel.
	for i in range(out_count):
		var src := float(i) / ratio
		var i0 := int(src)
		var i1: int = mini(i0 + 1, samples.size() - 1)
		var f := src - float(i0)
		var value: float = lerpf(float(samples[i0]), float(samples[i1]), f) / 32768.0
		playback.push_frame(Vector2(value, value))


## True while a speaker's audio is still arriving, for the HUD indicator.
func is_speaking(speaker_id: int) -> bool:
	if not _streams.has(speaker_id):
		return false
	return bool(_streams[speaker_id]["speaking"])


func speaking_ids() -> Array[int]:
	var out: Array[int] = []
	for sid: int in _streams:
		if bool(_streams[sid]["speaking"]):
			out.append(sid)
	return out


## Drops a speaker entirely, on leave or on match teardown.
func forget(speaker_id: int) -> void:
	if not _streams.has(speaker_id):
		return
	var stream: Dictionary = _streams[speaker_id]
	var player: AudioStreamPlayer = stream["player"]
	if is_instance_valid(player):
		player.stop()
		player.queue_free()
	if bool(stream["speaking"]):
		speaker_stopped.emit(speaker_id)
	_streams.erase(speaker_id)


func clear() -> void:
	for sid: int in _streams.keys():
		forget(sid)


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for sid: int in _streams:
		var stream: Dictionary = _streams[sid]
		if bool(stream["speaking"]) and now - float(stream["last_at"]) > SILENCE_TIMEOUT_S:
			stream["speaking"] = false
			speaker_stopped.emit(sid)


func _stream_for(speaker_id: int) -> Dictionary:
	if _streams.has(speaker_id):
		return _streams[speaker_id]

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _mix_rate
	generator.buffer_length = BUFFER_S

	var player := AudioStreamPlayer.new()
	player.stream = generator
	player.bus = BUS_NAME if _bus_idx >= 0 else "Master"
	add_child(player)
	player.play()

	var playback := player.get_stream_playback()
	if playback == null:
		player.queue_free()
		return {}

	var stream := {
		"player": player,
		"playback": playback as AudioStreamGeneratorPlayback,
		# Starts at zero and the sender's first frame is 1, so the first frame
		# is always newer and nothing is dropped on join.
		"last_seq": 0,
		"last_at": Time.get_ticks_msec() / 1000.0,
		"speaking": false,
	}
	_streams[speaker_id] = stream
	_apply_volume()
	return stream


## Compares two u16 counters allowing for wraparound. A plain `>` would stall
## a stream for 65535 frames once the counter rolled over mid-sentence.
static func _seq_is_newer(candidate: int, current: int) -> bool:
	if candidate == current:
		return false
	return ((candidate - current) & 0xFFFF) < 0x8000


func _ensure_bus() -> void:
	if not is_supported():
		return
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx < 0:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_send(_bus_idx, "Master")
	_apply_volume()


func _apply_volume() -> void:
	if _bus_idx < 0:
		return
	if volume <= 0.0001:
		AudioServer.set_bus_mute(_bus_idx, true)
		AudioServer.set_bus_volume_db(_bus_idx, -80.0)
	else:
		AudioServer.set_bus_mute(_bus_idx, false)
		AudioServer.set_bus_volume_db(_bus_idx, linear_to_db(volume))
