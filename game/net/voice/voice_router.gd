class_name VoiceRouter
extends RefCounted

## Who hears whom, following Counter-Strike.
##
##   deathmatch  everyone hears everyone, always
##   arena       a dead listener hears everyone
##               a live listener hears only live speakers
##
## The asymmetry is the whole point. A dead player hearing the living is not
## ghosting — they already watch the round from the spectator camera. Ghosting
## is a dead player *telling* the living what they can see, so the rule that
## matters is the one on the live listener's side: they are never given a dead
## speaker's audio. Blocking is therefore decided per listener, not per
## speaker, and one frame from one speaker reaches some listeners and not
## others in the same tick.
##
## Arena rounds end with one side wiped out, so by the last seconds of a round
## most of the lobby is dead and talking freely. That is exactly the window in
## which ghosting would decide matches, and exactly what this prevents.
##
## Liveness is read through possession, the same way combat reads it: a dead
## human riding a bot is judged on the body they drive. They are in the round,
## looking through a live pawn's eyes, so they speak and are heard as that
## pawn. Treating them as dead would mute a player who is still playing.
##
## Spectators in the stands carry no team and never hold a live body, so in
## arena they are dead for this purpose: they hear everything and no live
## player hears them. In deathmatch the mode rule wins and they are audible,
## which is what the mode asks for. Deathmatch has no round to protect and a
## five second respawn, so there is no information worth withholding.

const MODE_DM := "dm"


## The listeners a speaker's frame should be relayed to.
##
## liveness maps participant id to whether that participant is alive for voice
## purposes; callers build it once per frame rather than per listener. Bots are
## expected to be absent from listeners entirely, since nothing plays audio for
## them, but they are filtered here too so a caller cannot leak frames into a
## send loop by forgetting.
static func listeners_for(
		speaker_id: int, mode: String,
		listeners: Array, liveness: Dictionary, bots: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var speaker_alive := bool(liveness.get(speaker_id, false))
	for listener_id: int in listeners:
		if listener_id == speaker_id:
			continue
		if bool(bots.get(listener_id, false)):
			continue
		if can_hear(speaker_alive, bool(liveness.get(listener_id, false)), mode):
			out.append(listener_id)
	return out


## The rule itself, with no lobby state around it.
##
## Reads as: deathmatch never blocks; otherwise the only blocked pairing is a
## dead speaker reaching a live listener.
static func can_hear(speaker_alive: bool, listener_alive: bool, mode: String) -> bool:
	if mode == MODE_DM:
		return true
	if not listener_alive:
		return true
	return speaker_alive
