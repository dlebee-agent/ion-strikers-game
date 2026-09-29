extends SceneTree

# Checks the voice feature's two halves: who a frame reaches, and whether a
# frame survives the codec.
#
# The routing half is the point of the feature, so it is driven through a live
# GameInstance rather than by calling VoiceRouter directly: what matters is that
# real lobby state — a dead pawn, a spectator with no team, a human riding a bot
# — resolves the way the rule intends.
# Run: godot --headless --path game --script res://tools/voice_check.gd

const A := 1        # blue
const B := 2        # red
const C := 3        # red, second body
const SPEC := 4     # no team

var failed := 0
var _sent: Array = []   # [peer_id, channel, decoded msg]


func _initialize() -> void:
	_codec()
	_rule_table()
	_dm_routing()
	_arena_routing()
	_arena_spectator()
	_possession()
	_abuse()
	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  ok    %s" % label)
	else:
		print("  FAIL  %s" % label)
		failed += 1


# ── codec ───────────────────────────────────────────────────────────────

func _codec() -> void:
	print("codec")

	# A 300 Hz tone at 8 kHz, which is inside the band speech actually uses.
	var samples := PackedInt32Array()
	for i in range(Protocol.VOICE_FRAME_SAMPLES):
		samples.append(int(sin(float(i) / 8000.0 * TAU * 300.0) * 12000.0))

	var frame := VoiceCodec.encode(samples)
	_ok("frame is the documented size (%d bytes)" % frame.size(),
		frame.size() == VoiceCodec.frame_size(Protocol.VOICE_FRAME_SAMPLES))
	_ok("frame fits the relay ceiling", frame.size() <= Protocol.VOICE_MAX_PAYLOAD)

	var back := VoiceCodec.decode(frame, Protocol.VOICE_FRAME_SAMPLES)
	_ok("decodes to the sample count it was given", back.size() == samples.size())

	# ADPCM is lossy, so this asserts the error stays in the band where the
	# result is recognisable speech rather than demanding it be exact.
	var err := 0.0
	var signal_power := 0.0
	for i in range(samples.size()):
		var d := float(samples[i] - back[i])
		err += d * d
		signal_power += float(samples[i]) * float(samples[i])
	var snr := 10.0 * log(signal_power / maxf(err, 1.0)) / log(10.0)
	_ok("round trip SNR %.1f dB is above 20 dB" % snr, snr > 20.0)

	# Silence must not decode into noise, or an open microphone would hiss.
	var quiet := PackedInt32Array()
	quiet.resize(Protocol.VOICE_FRAME_SAMPLES)
	var quiet_back := VoiceCodec.decode(VoiceCodec.encode(quiet), Protocol.VOICE_FRAME_SAMPLES)
	var peak := 0
	for s in quiet_back:
		peak = maxi(peak, absi(s))
	_ok("silence stays silent (peak %d)" % peak, peak < 64)

	# A truncated frame is what a corrupt or hostile packet looks like.
	var short := frame.slice(0, 10)
	var short_back := VoiceCodec.decode(short, Protocol.VOICE_FRAME_SAMPLES)
	_ok("a truncated frame yields only what it held, no crash",
		short_back.size() == (10 - VoiceCodec.HEADER_BYTES) * 2)
	_ok("an empty frame decodes to nothing",
		VoiceCodec.decode(PackedByteArray(), Protocol.VOICE_FRAME_SAMPLES).is_empty())

	# Wire round trip through the protocol, since the length is read back from
	# an attacker-controlled u16.
	var wire := Protocol.decode(Protocol.encode_voice(frame))
	_ok("VOICE survives the wire", (wire["audio"] as PackedByteArray) == frame)
	var relayed := Protocol.decode(Protocol.encode_voice_data(-7, Protocol.TEAM_RED, 65535, frame, true))
	_ok("VOICE_DATA keeps a negative speaker id", int(relayed["speaker_id"]) == -7)
	_ok("VOICE_DATA keeps seq at the u16 edge", int(relayed["seq"]) == 65535)
	_ok("VOICE_DATA carries the dead flag", bool(relayed["speaker_dead"]))
	_ok("VOICE_DATA keeps the payload", (relayed["audio"] as PackedByteArray) == frame)


# ── the rule, in isolation ──────────────────────────────────────────────

func _rule_table() -> void:
	print("rule")
	_ok("dm: live hears live", VoiceRouter.can_hear(true, true, "dm"))
	_ok("dm: live hears dead", VoiceRouter.can_hear(false, true, "dm"))
	_ok("dm: dead hears live", VoiceRouter.can_hear(true, false, "dm"))
	_ok("dm: dead hears dead", VoiceRouter.can_hear(false, false, "dm"))
	_ok("arena: live hears live", VoiceRouter.can_hear(true, true, "arena"))
	_ok("arena: live does NOT hear dead", not VoiceRouter.can_hear(false, true, "arena"))
	_ok("arena: dead hears live", VoiceRouter.can_hear(true, false, "arena"))
	_ok("arena: dead hears dead", VoiceRouter.can_hear(false, false, "arena"))


# ── routing through a live instance ─────────────────────────────────────

func _instance(mode: String) -> GameInstance:
	var inst := GameInstance.new({
		"map_id": "parkour", "mode": mode, "bots": false, "kills": 999, "rounds": 999,
	})
	root.add_child(inst)
	inst.setup_map()
	inst.match_state.round_state = Protocol.RS_ACTIVE
	inst.match_state.freeze_until = 0.0
	_sent.clear()
	inst.event_to_peer.connect(func(pid: int, ch: int, data: PackedByteArray) -> void:
		_sent.append([pid, ch, Protocol.decode(data)]))
	return inst


func _seat(inst: GameInstance, id: int, team: int, alive: bool, is_bot := false) -> void:
	var p := Participant.new(id, "p%d" % id, is_bot)
	p.team = team
	inst.participants[id] = p
	if team == Protocol.TEAM_NONE:
		return
	var pawn := ServerPawn.new()
	pawn.participant_id = id
	pawn.alive = alive
	pawn.position = Vector3(float(id), 1.0, 0.0)
	inst.pawns[id] = pawn


func _frame() -> PackedByteArray:
	var samples := PackedInt32Array()
	for i in range(Protocol.VOICE_FRAME_SAMPLES):
		samples.append((i % 40) * 300 - 6000)
	return VoiceCodec.encode(samples)


## Who received audio, from the per-peer sends the instance emitted.
func _heard_by() -> Array:
	var out: Array = []
	for entry in _sent:
		if int(entry[2]["t"]) == Protocol.Msg.VOICE_DATA:
			out.append(int(entry[0]))
	out.sort()
	return out


func _dm_routing() -> void:
	print("deathmatch routing")
	var inst := _instance("dm")
	_seat(inst, A, Protocol.TEAM_BLUE, true)
	_seat(inst, B, Protocol.TEAM_RED, false)    # dead
	_seat(inst, C, Protocol.TEAM_RED, true)

	inst.handle_voice(B, _frame())              # a dead player speaks
	_ok("a dead speaker reaches everyone alive and dead", _heard_by() == [A, C])
	_ok("the speaker never hears themselves", not _heard_by().has(B))

	_sent.clear()
	inst.handle_voice(A, _frame())
	_ok("a live speaker reaches everyone", _heard_by() == [B, C])

	var ch := int(_sent[0][1])
	_ok("voice uses the bulk channel", ch == Protocol.CH_BULK)
	inst.free()


func _arena_routing() -> void:
	print("arena routing")
	var inst := _instance("arena")
	_seat(inst, A, Protocol.TEAM_BLUE, true)    # alive
	_seat(inst, B, Protocol.TEAM_RED, false)    # dead
	_seat(inst, C, Protocol.TEAM_RED, true)     # alive

	inst.handle_voice(B, _frame())
	_ok("a dead speaker reaches nobody alive", _heard_by().is_empty())

	_sent.clear()
	_seat(inst, SPEC, Protocol.TEAM_NONE, false)
	inst.handle_voice(B, _frame())
	_ok("a dead speaker does reach another dead listener", _heard_by() == [SPEC])

	_sent.clear()
	inst.handle_voice(A, _frame())
	_ok("a live speaker reaches the living and the dead",
		_heard_by() == [B, C, SPEC])
	var dead_flags: Array = []
	for entry in _sent:
		dead_flags.append(bool(entry[2]["speaker_dead"]))
	_ok("a live speaker is not flagged dead", not dead_flags.has(true))

	_sent.clear()
	inst.handle_voice(B, _frame())
	for entry in _sent:
		_ok("a dead speaker is flagged dead", bool(entry[2]["speaker_dead"]))
	inst.free()


func _arena_spectator() -> void:
	print("arena spectator cannot ghost")
	var inst := _instance("arena")
	_seat(inst, A, Protocol.TEAM_BLUE, true)
	_seat(inst, C, Protocol.TEAM_RED, true)
	_seat(inst, SPEC, Protocol.TEAM_NONE, false)

	inst.handle_voice(SPEC, _frame())
	_ok("a spectator reaches no live player", _heard_by().is_empty())

	_sent.clear()
	inst.handle_voice(A, _frame())
	_ok("but the spectator still hears the match", _heard_by().has(SPEC))
	inst.free()


func _possession() -> void:
	print("possession counts as alive")
	var inst := _instance("arena")
	_seat(inst, A, Protocol.TEAM_BLUE, true)
	_seat(inst, B, Protocol.TEAM_RED, false)        # dead human
	_seat(inst, -1, Protocol.TEAM_RED, true, true)  # a live bot

	# B is dead but drives the bot, so B is in the round and audible to A.
	(inst.participants[B] as Participant).possessing = -1
	(inst.participants[-1] as Participant).possessed_by = B

	inst.handle_voice(B, _frame())
	_ok("a human riding a live bot is heard by the living", _heard_by().has(A))
	var flagged_dead := false
	for entry in _sent:
		if bool(entry[2]["speaker_dead"]):
			flagged_dead = true
	_ok("and is not flagged dead", not flagged_dead)
	_ok("the bot is never sent audio", not _heard_by().has(-1))

	# Release the bot and the same human goes back to being dead.
	_sent.clear()
	(inst.participants[B] as Participant).possessing = 0
	(inst.participants[-1] as Participant).possessed_by = 0
	inst.handle_voice(B, _frame())
	_ok("releasing the bot mutes them to the living again", not _heard_by().has(A))
	inst.free()


func _abuse() -> void:
	print("abuse and malformed input")
	var inst := _instance("dm")
	_seat(inst, A, Protocol.TEAM_BLUE, true)
	_seat(inst, C, Protocol.TEAM_RED, true)

	inst.handle_voice(A, PackedByteArray())
	_ok("an empty frame is dropped", _heard_by().is_empty())

	_sent.clear()
	var huge := PackedByteArray()
	huge.resize(Protocol.VOICE_MAX_PAYLOAD + 1)
	inst.handle_voice(A, huge)
	_ok("an oversized frame is refused rather than relayed", _heard_by().is_empty())

	_sent.clear()
	inst.handle_voice(999, _frame())
	_ok("a stranger who never joined is ignored", _heard_by().is_empty())

	# The rate limit: an honest client sends 50 a second.
	_sent.clear()
	var accepted := 0
	for i in range(GameInstance.VOICE_RATE_MAX * 3):
		_sent.clear()
		inst.handle_voice(A, _frame())
		if not _heard_by().is_empty():
			accepted += 1
	_ok("flooding is capped at the window limit (%d accepted)" % accepted,
		accepted == GameInstance.VOICE_RATE_MAX)

	# The speaker id on the wire is the session's, never one the client chose.
	_sent.clear()
	inst.handle_voice(C, _frame())
	var claimed := int(_sent[0][2]["speaker_id"])
	_ok("the relayed speaker id is the sender's own", claimed == C)

	# seq has to advance per speaker so a receiver can drop stale frames.
	_sent.clear()
	var seqs: Array = []
	for i in range(3):
		_sent.clear()
		inst.handle_voice(C, _frame())
		if not _sent.is_empty():
			seqs.append(int(_sent[0][2]["seq"]))
	_ok("seq advances per frame (%s)" % str(seqs),
		seqs.size() == 3 and seqs[1] == seqs[0] + 1 and seqs[2] == seqs[1] + 1)

	_ok("a wrapped seq still reads as newer",
		VoicePlayback._seq_is_newer(2, 65534))
	_ok("an older seq is rejected", not VoicePlayback._seq_is_newer(65534, 2))
	inst.free()
