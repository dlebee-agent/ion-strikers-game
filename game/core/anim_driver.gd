class_name AnimDriver
extends Node3D

const Movement = preload("res://core/movement.gd")

# Used by both the designer and future match — no separate viewer anim code.

# There is deliberately no SHOOT state: the laser has no third-person recoil, so
# firing never takes the body out of its locomotion pose. The kick lives on the
# first-person arms only (see LocalPawn).
enum State { IDLE, WALK, RUN, CROUCH_IDLE, CROUCH_WALK, JUMP, MELEE,
	SPELL_CHARGE, SPELL_CHANNEL, SPELL_FIRE, DEATH, DANCE }

# Clip names as Godot's glTF importer exposes them: a trailing "_Loop" is
# consumed to set the loop mode, so the clip itself is the bare name.
#
# Every locomotion state plays a "_GunReady" clip: the source movement from the
# waist down mixed with the pistol-idle pose from the waist up, so a player who is
# running, crouching or mid-air still reads as armed and aimed. Those clips are
# baked at import by tools/gun_ready_import.gd, which is also where the mix is
# explained. IDLE needs no mix — Pistol_Idle *is* the aim pose.
const ANIM_MAP := {
	State.IDLE: "Pistol_Idle",
	State.WALK: "Walk_GunReady",
	State.RUN: "Sprint_GunReady",
	State.CROUCH_IDLE: "Crouch_Idle_GunReady",
	State.CROUCH_WALK: "Crouch_Fwd_GunReady",
	State.JUMP: "Jump_GunReady",
	State.MELEE: "Punch_Jab",
	State.SPELL_CHARGE: "Spell_Simple_Enter",
	State.SPELL_CHANNEL: "Spell_Simple_Idle",
	State.SPELL_FIRE: "Spell_Simple_Shoot",
	State.DEATH: "Death01",
	State.DANCE: "Dance",
}

const GUN_READY_SUFFIX := "_GunReady"

const LOOPING_STATES := [State.IDLE, State.WALK, State.RUN, State.CROUCH_IDLE,
	State.CROUCH_WALK, State.JUMP, State.SPELL_CHANNEL, State.DANCE]

# The raise hands over to the looping channel just before it ends, so the two
# clips overlap instead of showing a seam.
const SPELL_HANDOFF_LEAD := 0.12

# Locomotion cross-fades, because a stride that snaps between clips reads as a
# glitch. A punch or a discharge has to land, so it fades in far quicker.
const BLEND_LOOP := 0.18
const BLEND_ONE_SHOT := 0.08

var current_state: State = State.IDLE
var _anim_player: AnimationPlayer
var _mannequin: Node3D
var _available_clips: PackedStringArray = []

# A pose that locomotion must not steal back. The channel is not cancellable, so
# the body must not look like it can be; the discharge and the punch hold for as
# long as their clips run.
var _channeling := false
var _hold_until_ms := 0
# Bumped to abandon a scheduled hand-off, standing in for clearTimeout().
var _spell_gen := 0
var _warned_missing_bake := false

func setup(mannequin: Node3D) -> void:
	_mannequin = mannequin
	_anim_player = _find_animation_player(mannequin)
	if _anim_player:
		_available_clips = _anim_player.get_animation_list()

func get_clip_list() -> PackedStringArray:
	return _available_clips

func play_clip(clip_name: String) -> void:
	_release_holds()
	if _anim_player and _anim_player.has_animation(clip_name):
		_anim_player.play(clip_name)

func update_from_movement(movement: Movement) -> void:
	# Death keeps the body on the floor and the victory dance runs to the end of
	# the round; neither hands back to locomotion.
	if current_state == State.DEATH or current_state == State.DANCE:
		return
	if _channeling or Time.get_ticks_msec() < _hold_until_ms:
		return
	var new_state := _resolve_state(movement)
	if new_state != current_state:
		_apply_state(new_state)

func set_state(state: State) -> void:
	if state != current_state:
		_apply_state(state)

# ---- one-shot moves ----

func trigger_melee() -> void:
	_release_holds()
	_apply_state(State.MELEE)
	_hold_until_ms = Time.get_ticks_msec() + int(_clip_length(State.MELEE) * 1000.0)

func start_spell_charge() -> void:
	_release_holds()
	_channeling = true
	var gen := _spell_gen
	_apply_state(State.SPELL_CHARGE)

	var delay := maxf(SPELL_HANDOFF_LEAD, _clip_length(State.SPELL_CHARGE) - SPELL_HANDOFF_LEAD)
	await get_tree().create_timer(delay).timeout
	if gen != _spell_gen or not _channeling or not is_instance_valid(_anim_player):
		return
	_apply_state(State.SPELL_CHANNEL)

func fire_spell() -> void:
	_release_holds()
	_apply_state(State.SPELL_FIRE)
	_hold_until_ms = Time.get_ticks_msec() + int(_clip_length(State.SPELL_FIRE) * 1000.0)

# Abandon the channel without a discharge (you died mid-wind-up).
func end_spell() -> void:
	_release_holds()

func _release_holds() -> void:
	_spell_gen += 1
	_channeling = false
	_hold_until_ms = 0

func _clip_length(state: State) -> float:
	if not is_instance_valid(_anim_player):
		return 0.0
	var clip_name := _clip_for(state)
	return _anim_player.get_animation(clip_name).length if not clip_name.is_empty() else 0.0

# The baked mix, or the source clip it was baked from if the import step has not
# run. Falling back leaves the arms swinging free, which is the wrong look rather
# than a missing one — say so once, then let the body keep moving.
func _clip_for(state: State) -> String:
	var clip_name: String = ANIM_MAP.get(state, "")
	if _anim_player.has_animation(clip_name):
		return clip_name
	if not clip_name.ends_with(GUN_READY_SUFFIX):
		return ""
	if not _warned_missing_bake:
		_warned_missing_bake = true
		push_warning("No gun-ready clips on this rig; reimport mannequin.glb.")
	var raw := clip_name.trim_suffix(GUN_READY_SUFFIX)
	return raw if _anim_player.has_animation(raw) else ""

func _resolve_state(movement: Movement) -> State:
	if not movement.on_ground:
		return State.JUMP

	var speed := Vector2(movement.velocity.x, movement.velocity.z).length()
	if movement.is_crouching:
		return State.CROUCH_WALK if speed > 0.5 else State.CROUCH_IDLE

	if speed > Movement.RUN_SPEED * 0.7:
		return State.RUN
	elif speed > 0.5:
		return State.WALK
	return State.IDLE

func _apply_state(state: State) -> void:
	current_state = state
	if not is_instance_valid(_anim_player):
		return
	var clip_name := _clip_for(state)
	if clip_name.is_empty():
		return
	var looping := state in LOOPING_STATES
	_anim_player.play(clip_name, BLEND_LOOP if looping else BLEND_ONE_SHOT)
	if not looping:
		# Restart from the top even when this clip is already the current one, so a
		# retriggered punch reads as a second punch rather than as nothing.
		_anim_player.seek(0.0, true)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
