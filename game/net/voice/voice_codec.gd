class_name VoiceCodec
extends RefCounted

## IMA ADPCM at 8 kHz mono: four bits per sample, so a 20 ms frame of 160
## samples packs into 80 bytes.
##
## Godot exposes no Opus encoder to GDScript, and raw 16-bit PCM at this rate
## would be 128 kbit/s per speaker. ADPCM is the best ratio available without
## a native extension: 32 kbit/s, telephone-band, and about 4.3 KB/s on the
## wire once the header is counted. It is also stateless across frames here,
## which matters more than the extra byte or two it costs — voice rides an
## unreliable channel, so a decoder that carried predictor state between
## frames would stay wrong for the rest of the transmission after one drop.
## Each frame instead opens with the predictor it was encoded against.
##
## Wire layout, 84 bytes for a full frame:
##   predictor : i16   the first sample, seeding the decoder
##   index     : u8    step table position, 0-88
##   reserved  : u8    zero, keeps the payload 2-byte aligned
##   nibbles   : 80 bytes, two samples each, low nibble first

const STEP_TABLE: Array[int] = [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
	19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
	130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
	337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
	876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
	2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
	5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
	15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
]

const INDEX_TABLE: Array[int] = [
	-1, -1, -1, -1, 2, 4, 6, 8,
	-1, -1, -1, -1, 2, 4, 6, 8,
]

const MAX_INDEX := 88
const SAMPLE_MIN := -32768
const SAMPLE_MAX := 32767
const HEADER_BYTES := 4


## Packs signed 16-bit samples into one frame. Any sample count is accepted;
## an odd one pads with a zero nibble, which the decoder discards because it
## trusts the declared sample count rather than the byte length.
static func encode(samples: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	if samples.is_empty():
		return out

	var predictor: int = clampi(samples[0], SAMPLE_MIN, SAMPLE_MAX)
	var index := _seed_index(samples)

	out.resize(HEADER_BYTES)
	out.encode_s16(0, predictor)
	out[2] = index
	out[3] = 0

	var pending := 0
	var have_pending := false
	for i in range(samples.size()):
		var step: int = STEP_TABLE[index]
		var diff: int = clampi(samples[i], SAMPLE_MIN, SAMPLE_MAX) - predictor

		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		# Greedy three-bit magnitude: each bit is worth half the one above it.
		var magnitude := step
		if diff >= magnitude:
			code |= 4
			diff -= magnitude
		magnitude >>= 1
		if diff >= magnitude:
			code |= 2
			diff -= magnitude
		magnitude >>= 1
		if diff >= magnitude:
			code |= 1

		predictor = _step(predictor, index, code)
		index = clampi(index + INDEX_TABLE[code], 0, MAX_INDEX)

		if have_pending:
			out.append(pending | (code << 4))
			have_pending = false
		else:
			pending = code
			have_pending = true

	if have_pending:
		out.append(pending)
	return out


## Unpacks a frame back to signed 16-bit samples. sample_count is what the
## caller expects; a short or corrupt frame returns what it could read rather
## than inventing silence past the end.
static func decode(frame: PackedByteArray, sample_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if frame.size() < HEADER_BYTES or sample_count <= 0:
		return out

	var predictor := frame.decode_s16(0)
	var index: int = clampi(frame[2], 0, MAX_INDEX)

	var available := (frame.size() - HEADER_BYTES) * 2
	var count: int = mini(sample_count, available)
	out.resize(count)

	for i in range(count):
		var byte: int = frame[HEADER_BYTES + (i >> 1)]
		var code: int = (byte & 0x0F) if (i & 1) == 0 else ((byte >> 4) & 0x0F)
		predictor = _step(predictor, index, code)
		index = clampi(index + INDEX_TABLE[code], 0, MAX_INDEX)
		out[i] = predictor

	return out


## Bytes a frame of this many samples occupies, header included.
static func frame_size(sample_count: int) -> int:
	return HEADER_BYTES + (sample_count + 1) / 2


## Advances the predictor by one code. Shared so encode and decode cannot
## drift apart, which is the usual way a hand-written ADPCM ends up noisy.
static func _step(predictor: int, index: int, code: int) -> int:
	var step: int = STEP_TABLE[index]
	var delta: int = step >> 3
	if (code & 4) != 0:
		delta += step
	if (code & 2) != 0:
		delta += step >> 1
	if (code & 1) != 0:
		delta += step >> 2
	if (code & 8) != 0:
		predictor -= delta
	else:
		predictor += delta
	return clampi(predictor, SAMPLE_MIN, SAMPLE_MAX)


## Picks a starting step from how much the frame actually moves. Opening at
## index 0 makes every frame begin with a quiet, clipped ramp, because the
## step has to climb eight codes before it can track speech; starting near
## the frame's own mean delta removes that.
static func _seed_index(samples: PackedInt32Array) -> int:
	if samples.size() < 2:
		return 0
	var total := 0
	for i in range(1, samples.size()):
		total += absi(samples[i] - samples[i - 1])
	var mean: int = total / (samples.size() - 1)
	for i in range(MAX_INDEX + 1):
		if STEP_TABLE[i] >= mean:
			return i
	return MAX_INDEX
