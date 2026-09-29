class_name VoiceCapture
extends Node

## Microphone to encoded frames.
##
## Godot captures the microphone through an audio bus: an AudioStreamPlayer
## fed by AudioStreamMicrophone, routed to a bus carrying AudioEffectCapture,
## which buffers what arrived. There is no way to open the device directly, so
## the bus is built here rather than being left in default_bus_layout.tres —
## that keeps a player who never talks from paying for a mic bus at all, and
## keeps the recording path out of the mixer the rest of the game shares.
##
## The bus is muted. Without that, a capture bus routed to Master is a loop:
## the microphone plays out of the speakers, the speakers feed the microphone.

signal frame_ready(audio: PackedByteArray)

const BUS_NAME := "VoiceCapture"

## Mic input runs at the mixer's rate, usually 44100 or 48000. Frames go out at
## 8 kHz, so samples are decimated by whatever ratio that works out to.
var _mix_rate: float = 44100.0

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _bus_idx: int = -1

var _open := false
var _pending: PackedInt32Array = PackedInt32Array()
## Fractional read position into the captured buffer, so decimation does not
## drift a sample every frame at rates that are not clean multiples of 8 kHz.
var _phase: float = 0.0

## Gain applied before quantising. Mic levels vary enormously between devices
## and ADPCM has no headroom to spare, so this is worth exposing.
var gain: float = 1.0

## Frames whose peak sits under this are dropped instead of sent, which stops
## an open microphone spending bandwidth on room noise. Push-to-talk callers
## can set it to 0 to send everything while the key is down.
var squelch: float = 0.006


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## True once the microphone is actually running. Returns false when permission
## is refused or no input device exists, so callers can fall back to text chat
## and say so rather than appearing to transmit into nothing.
func start() -> bool:
	if _open:
		return true
	if not _ensure_bus():
		return false

	_mix_rate = AudioServer.get_mix_rate()
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	add_child(_player)
	_player.play()

	if _capture == null:
		_teardown()
		return false

	_pending = PackedInt32Array()
	_phase = 0.0
	_open = true
	set_process(true)
	return true


func stop() -> void:
	if not _open:
		return
	set_process(false)
	_teardown()
	_open = false
	_pending = PackedInt32Array()
	_phase = 0.0


func is_open() -> bool:
	return _open


## Whether this build can record at all. Checked before offering voice in the
## settings screen, so the option is absent rather than present and broken.
static func is_supported() -> bool:
	return ClassDB.class_exists("AudioStreamMicrophone") \
		and ClassDB.class_exists("AudioEffectCapture")


func _process(_dt: float) -> void:
	if not _open or _capture == null:
		return

	var available := _capture.get_frames_available()
	if available <= 0:
		return

	# Stereo in, mono out: the two channels are averaged rather than one being
	# picked, because some drivers deliver a mono microphone on the left
	# channel only and others duplicate it across both.
	var buffer := _capture.get_buffer(available)
	var ratio := _mix_rate / float(Protocol.VOICE_SAMPLE_RATE)
	var i := _phase
	while i < float(buffer.size()):
		var src: Vector2 = buffer[int(i)]
		var mono: float = clampf((src.x + src.y) * 0.5 * gain, -1.0, 1.0)
		_pending.append(int(round(mono * 32767.0)))
		i += ratio
	_phase = i - float(buffer.size())

	while _pending.size() >= Protocol.VOICE_FRAME_SAMPLES:
		var frame := _pending.slice(0, Protocol.VOICE_FRAME_SAMPLES)
		_pending = _pending.slice(Protocol.VOICE_FRAME_SAMPLES)
		if _loud_enough(frame):
			frame_ready.emit(VoiceCodec.encode(frame))


func _loud_enough(frame: PackedInt32Array) -> bool:
	if squelch <= 0.0:
		return true
	var threshold := int(squelch * 32767.0)
	for sample in frame:
		if absi(sample) >= threshold:
			return true
	return false


func _ensure_bus() -> bool:
	if not is_supported():
		return false

	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx < 0:
		AudioServer.add_bus()
		_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_send(_bus_idx, "Master")
	# Muted so the microphone never reaches the speakers and feeds back. The
	# capture effect still sees every frame; mute applies to the bus output.
	AudioServer.set_bus_mute(_bus_idx, true)

	for i in range(AudioServer.get_bus_effect_count(_bus_idx)):
		var existing := AudioServer.get_bus_effect(_bus_idx, i)
		if existing is AudioEffectCapture:
			_capture = existing as AudioEffectCapture
			return true

	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus_idx, _capture)
	return true


## Leaves the bus in place. Rebuilding it on every push-to-talk press would
## reallocate the mixer graph mid-match; a muted, idle bus costs nothing.
func _teardown() -> void:
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	if _capture != null:
		_capture.clear_buffer()
