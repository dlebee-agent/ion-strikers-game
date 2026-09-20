extends Node3D

const LocalPawn = preload("res://core/local_pawn.gd")
const CameraRig = preload("res://core/camera_rig.gd")
const WallhackEsp = preload("res://hacks/wallhack_esp.gd")
const RemotePawn = preload("res://core/remote_pawn.gd")
const TracerBolt = preload("res://core/tracer_bolt.gd")
const ImpactFlash = preload("res://core/impact_flash.gd")
const SpecialBeam = preload("res://core/special_beam.gd")
const SpectatorCam = preload("res://core/spectator_cam.gd")
const AnimDriver = preload("res://core/anim_driver.gd")
const MeteorFx = preload("res://core/meteor_fx.gd")
const CameraShake = preload("res://core/camera_shake.gd")
const RagdollScript = preload("res://core/ragdoll.gd")
const HitboxDebugScript = preload("res://core/hitbox_debug.gd")
const FxWarmScript = preload("res://core/fx_warm.gd")
const SuitSettings = preload("res://core/suit_settings.gd")

var pawn: LocalPawn
var client: GameClient
var _world: CollisionWorld = null
# Reused by every tracer, so a firefight allocates nothing.
var _shot_trace := TraceResult.new()
var _map_id: String = "parkour"
var _mode: String = "arena"
var _my_team: int = 0
var _in_stands := true
var _alive := false
## Bot id we are riding (daemon possession). Scoreboard row stays ours; frags
## land on the bot. `_ridden_id` stays set through the local ragdoll so the
## remote copy of that body does not spawn a second corpse.
var _possessing_id: int = 0
var _ridden_id: int = 0
var _special_armed := false
var _special_spent := false
var _special_progress := 0

var init_data: Dictionary = {}
var game_client: GameClient
var local_callsign: String = "Player"

var _hud: MatchHud
var _team_panel: TeamPanel
var _remotes: Dictionary = {}  # peer_id → RemotePawn
var _snap_time: float = 0.0
# Sample stamps: wall time, kept strictly increasing across a same-frame burst.
var _sample_clock: float = 0.0
var _last_snap_players: Array = []

var _spectator: SpectatorCam
var _arena_size: float = 28.0
var _player_names: Dictionary = {}  # id → name

var _meteor_warn_until: float = 0.0
var _shake := CameraShake.new()

# Stash the death cause from HIT so the ragdoll (triggered on the next snapshot
# for remotes, or immediately for the local player) knows how to kick.
var _last_death: Dictionary = {}  # target_id -> { by, head, cause }
var _local_ragdoll: Ragdoll

## Score bar clock, as the server last reported it: seconds, and which of
## Protocol's CLOCK_ modes to read them as. The server owns it so every
## client reads the same thing and a late joiner sees the real time left in
## the round rather than their own time since loading.
var _clock_s: int = 0
var _clock_mode: int = Protocol.CLOCK_UP
var _win_rounds: int = 10
var _max_spectators: int = 0
var _last_kill_target: int = 50
var _last_score_blue: int = 0
var _last_score_red: int = 0
var _last_round_num: int = 1

## Loaded up front so no clip is fetched off disk mid-fight. The meteor's impact
## borrows "died", which otherwise waits until the first time somebody dies.
const MATCH_WARM_SFX: Array[String] = [
	"died", "hurt", "respawn", "round_start", "first_blood", "headshot",
]

## Smallest gap allowed between two sample timestamps, so a burst that arrives
## inside one millisecond still interpolates instead of teleporting.
const SNAP_TIME_EPSILON := 0.002

const SCOREBOARD_REFRESH := 0.25
var _scoreboard_next_refresh: float = 0.0
var _match_over: bool = false
var _match_winner: int = 0

## Long enough for the round card's full fade-in, hold, and fade-out, so the
## match-over overlay never lands on top of the result it is replacing.
const MATCH_OVER_HANDOFF := 2.9
var _match_over_pending: bool = false
var _outro_active: bool = false

## Mirrors MatchState.ROUND_FREEZE, which the server enforces. This copy only
## keeps the local body still so it does not fight the server's refusal.
var _freeze_until: float = 0.0


func _ready() -> void:
	add_to_group("match_scene")
	if "--wallhack" in OS.get_cmdline_user_args():
		var esp := WallhackEsp.new()
		esp.match_scene = self
		add_child(esp)
	AudioMix.fade_out_keep_place(400.0)

	_map_id = str(init_data.get("map", "parkour"))
	_mode = str(init_data.get("mode", "arena"))
	_win_rounds = int(init_data.get("win_rounds", 10))
	_max_spectators = int(init_data.get("max_spectators", 0))
	client = game_client
	SuitSettings.listen(_apply_suit_preference)
	var my_init_id := int(init_data.get("id", 0))
	if my_init_id != 0:
		_player_names[my_init_id] = local_callsign

	_build_map()
	# Compile the FX shader variants now, while the team panel is up, rather than
	# on the frame the first meteor is drawn.
	FxWarmScript.warm(self)
	Announcer.warm(MATCH_WARM_SFX)
	_spectator = SpectatorCam.new()
	add_child(_spectator)
	_start_spectate_watch()
	_build_hud()
	_build_team_panel()

	var _hitbox_debug := HitboxDebugScript.new()
	add_child(_hitbox_debug)

	if client:
		add_child(client)
		client.snap_received.connect(_on_snap)
		client.connection_failed.connect(_on_connection_failed)
		client.hit_received.connect(_on_hit)
		client.tracer_received.connect(_on_tracer)
		client.round_start_received.connect(_on_round_start)
		client.round_end_received.connect(_on_round_end)
		client.match_over_received.connect(_on_match_over)
		client.respawn_received.connect(_on_respawn)
		client.chat_received.connect(_on_chat)
		client.special_received.connect(_on_special)
		client.announce_received.connect(_on_announce)
		client.meteor_received.connect(_on_meteor)
		client.team_received.connect(_on_team)
		client.team_opts_received.connect(_on_team_opts)
		client.team_denied_received.connect(_on_team_denied)
		client.roster_received.connect(_on_roster)
		client.cheats_changed.connect(_on_cheats_changed)
		client.cheats_denied.connect(_on_cheats_denied)

	if Announcer:
		Announcer.banner_requested.connect(_on_announcer_banner)

	InputSettings.changed.connect(_apply_input_settings)

	if _parse_round_state(str(init_data.get("round_state", "active"))) == Protocol.RS_OVER:
		var winner := Protocol.TEAM_BLUE if _last_score_blue >= _last_score_red else Protocol.TEAM_RED
		if _last_score_blue == _last_score_red:
			winner = 0
		_enter_match_over(winner)
	else:
		_show_team_panel()


func _build_map() -> void:
	if MapCatalog.is_community(_map_id):
		_build_community_map()
	else:
		_build_builtin_map()


func _build_builtin_map() -> void:
	var compiled := MapEngine.compile(MapCatalog.builtin_definition(_map_id))
	MapBuilder.build_visual(self, compiled)
	_world = MapBuilder.build_world(compiled)
	_arena_size = float(compiled.get("arena", 28.0))


func _build_community_map() -> void:
	var level := MapCatalog.load_community(_map_id)
	if not level.ok():
		push_error("[client] %s did not import (%s); falling back to parkour" % [
			_map_id, ", ".join(level.warnings)])
		_build_builtin_map()
		return
	for w: String in level.warnings:
		print("[client] %s: %s" % [_map_id, w])

	var mesh := MeshInstance3D.new()
	mesh.mesh = level.mesh
	# Imported geometry is the level's own art, so it lights and shadows like
	# any other world surface.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)

	var ambience := MapCatalog.ambience_for(level)
	MapBuilder.build_ambience(self, ambience)

	_world = level.world
	_arena_size = level.arena


func _start_spectate_watch() -> void:
	_spectator.start_watch(_arena_size)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_hud() -> void:
	_hud = MatchHud.new()
	add_child(_hud)
	_hud.leave_requested.connect(_request_leave)
	_hud.lobby_requested.connect(_exit_to_lobby)
	_hud.team_menu_requested.connect(_show_team_panel)
	_hud.controls_requested.connect(_toggle_controls_card)
	_hud.settings_requested.connect(_toggle_settings)
	_hud.chat_submitted.connect(_on_chat_submit)
	_hud.chat_cancelled.connect(_on_chat_cancel)
	_hud.set_stands_mode(true, Protocol.TEAM_NONE)

	var init_mode := str(init_data.get("mode", "arena"))
	var score_blue := int(init_data.get("score_blue", 0))
	var score_red := int(init_data.get("score_red", 0))
	var round_num := int(init_data.get("round_num", 1))
	var kill_target := int(init_data.get("kill_target", 50))
	var round_state := _parse_round_state(str(init_data.get("round_state", "active")))
	_last_kill_target = kill_target
	_last_score_blue = score_blue
	_last_score_red = score_red
	_last_round_num = round_num
	_hud.update_score(score_blue, score_red, round_num, init_mode, kill_target,
		round_state, _win_rounds, 0, 0, _clock_text())


func _build_team_panel() -> void:
	_team_panel = TeamPanel.new()
	add_child(_team_panel)
	_team_panel.team_selected.connect(_on_team_select)
	_team_panel.closed.connect(_on_team_panel_closed)


func _show_team_panel() -> void:
	if _match_over:
		return
	if _hud.is_settings_open():
		_hud.dismiss_settings()
	if _hud.is_controls_visible():
		_hud.dismiss_controls_card()
	if _team_panel.is_open():
		_team_panel.close()
		return
	if client:
		client.send_team_menu()
	_team_panel.open()


func _on_team_select(team: int) -> void:
	if client:
		client.send_set_team(team)


func _on_team_panel_closed() -> void:
	if _match_over:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not _in_stands:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_hud.show_cursor_controls(false)


func _toggle_controls_card() -> void:
	if _hud.is_controls_visible():
		_close_controls_card()
		return
	if _team_panel.is_open():
		_team_panel.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.present_controls_card()


func _close_controls_card() -> void:
	_hud.dismiss_controls_card()
	_restore_cursor()


func _toggle_settings() -> void:
	if _hud.is_settings_open():
		_hud.dismiss_settings()
		_restore_cursor()
		return
	if _team_panel.is_open():
		_team_panel.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.present_settings()


## Back to mouselook if there is a body to look with (or a spectator cam to steer),
## otherwise leave the cursor out so the stands buttons stay clickable.
func _restore_cursor() -> void:
	if not _in_stands:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_hud.show_cursor_controls(false)
	else:
		_hud.show_cursor_controls(true)


func _apply_input_settings() -> void:
	if pawn and pawn.camera_rig:
		InputSettings.apply_to(pawn.camera_rig)


# ── Team / spawn ─────────────────────────────────────────────────────────

func _on_team(msg: Dictionary) -> void:
	_my_team = int(msg.get("team", 0))
	var is_alive := bool(msg.get("alive", false))

	_team_panel.close()

	if _my_team == Protocol.TEAM_NONE:
		_enter_stands()
		return

	_in_stands = false
	_hud.set_stands_mode(false, _my_team)

	if is_alive:
		_possessing_id = 0
		_ridden_id = 0
		var sx: float = float(msg.get("spawn_x", 0.0))
		var sy: float = float(msg.get("spawn_y", 0.0))
		var sz: float = float(msg.get("spawn_z", 0.0))
		var yaw: float = float(msg.get("yaw", 0.0))
		_spawn_local_pawn(Vector3(sx, sy, sz), yaw)
	else:
		_spectator.start_teammate_follow()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_team_opts(msg: Dictionary) -> void:
	if _match_over:
		return
	_team_panel.update_opts(
		int(msg.get("current_team", 0)),
		int(msg.get("blue_used", 0)), int(msg.get("blue_max", 6)),
		int(msg.get("red_used", 0)), int(msg.get("red_max", 6)),
		int(msg.get("spec_used", 0)), int(msg.get("spec_max", 12)))

	if not _team_panel.is_open():
		_team_panel.open()


func _on_team_denied(msg: Dictionary) -> void:
	_team_panel.show_denied(str(msg.get("reason", "Denied.")))


func _enter_stands() -> void:
	_in_stands = true
	_alive = false
	_possessing_id = 0
	_ridden_id = 0
	if _local_ragdoll:
		_local_ragdoll.end()
		_local_ragdoll = null
	_hud.set_stands_mode(true, Protocol.TEAM_NONE)

	if pawn:
		pawn.queue_free()
		pawn = null

	_start_spectate_watch()
	_hud.hide_spectator_panel()


func _spawn_local_pawn(spawn_pos: Vector3, yaw: float, hp: int = 100) -> void:
	if _local_ragdoll:
		_local_ragdoll.end()
		_local_ragdoll = null
	if pawn:
		pawn.queue_free()

	_spectator.stop()
	_hud.hide_spectator_panel()
	# Death-follow hides the crosshair whenever it is not in first person, and
	# a respawn does not otherwise go through _on_team to restore it.
	_hud.set_stands_mode(false, _my_team)

	pawn = LocalPawn.new()
	pawn.suit_style = _suit_style()
	add_child(pawn)
	pawn.setup(_world)
	pawn.movement.position = spawn_pos
	pawn.movement.yaw = yaw

	var team_str := "blue" if _my_team == Protocol.TEAM_BLUE else "red"
	pawn.set_team(team_str)
	pawn.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	InputSettings.apply_to(pawn.camera_rig)
	pawn.set_mannequin_visible(false)
	pawn.set_fp_arms_visible(true)

	_alive = true
	_special_spent = false
	pawn.weapon.special_armed = _special_armed
	_hud.update_hp(hp)
	_sync_special_hud()

	pawn.weapon.fired.connect(_on_local_fire)
	pawn.weapon.melee_hit.connect(_on_local_melee)
	pawn.weapon.special_started.connect(_on_local_special_start)
	pawn.weapon.special_fired.connect(_on_local_special_fire)

	# The new Camera3D is current the moment it enters the tree, but its
	# transform is only written by process_input, which does not run until the
	# next physics tick — and spawns arrive from the client poll AFTER this
	# node's _physics_process. Place it now, or the first rendered frame of
	# every spawn and respawn shows the camera's identity transform.
	pawn.camera_rig.update_camera()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _suit_style() -> String:
	return SuitSettings.style


func _apply_suit_preference() -> void:
	var style := _suit_style()
	if pawn:
		pawn.suit_style = style
		pawn.set_team(pawn.team_color)
	for pid: int in _remotes:
		var rp: RemotePawn = _remotes[pid]
		if is_instance_valid(rp):
			rp.apply_suit(style)


# ── Physics + input ──────────────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	var blocked := _team_panel.is_open() or ConfirmPrompt.is_open() or _hud.is_chat_open() \
		or _hud.is_settings_open() or GameConsole.is_open()
	var now := Time.get_ticks_msec() / 1000.0
	var frozen := _outro_active or now < _freeze_until

	if pawn and _alive and not _in_stands and not _match_over:
		# A blocked or frozen pawn still falls, slides to a stop, and keeps its
		# camera pointed where the player left it. Only input reading stops.
		if blocked or frozen:
			pawn.process_idle(dt)
		else:
			pawn.process_input(dt)
		if client:
			client.send_state(pawn.movement.position, pawn.movement.yaw,
				pawn.movement.pitch, pawn.movement.is_crouching,
				pawn.movement.on_ground)
		_sync_special_hud()

	_snap_time = Time.get_ticks_msec() / 1000.0
	for pid: int in _remotes:
		var rp: RemotePawn = _remotes[pid]
		rp.interpolate(_snap_time)
		rp.tick_ragdoll(dt, _world)

	if _local_ragdoll:
		_local_ragdoll.update(dt, _world, _world.void_y() if _world != null else -INF)
		if _local_ragdoll.dead:
			if pawn:
				pawn.set_mannequin_visible(false)
			_local_ragdoll.end()
			_local_ragdoll = null

	if not _match_over and _spectator:
		if _outro_active:
			# Ride the winning side out instead of freezing wherever the last
			# shot left the camera.
			_spectator.update_death_follow(dt, _remotes, _match_winner)
		elif not blocked:
			if _in_stands:
				_spectator.update_watch(dt, _remotes)
				_update_spectator_panel()
			elif not _alive:
				_spectator.update_death_follow(dt, _remotes, _my_team)
				_update_spectator_panel()

	if _meteor_warn_until > 0.0 and _snap_time > _meteor_warn_until:
		_hud.show_meteor_warning(false)
		_meteor_warn_until = 0.0

	var cam := get_viewport().get_camera_3d()
	if cam:
		_shake.apply(cam, dt)


func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if ConfirmPrompt.is_open() or _team_panel.is_open() or _hud.is_chat_open() \
			or _hud.is_settings_open() or _match_over or _outro_active \
			or GameConsole.is_open():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if pawn and pawn.camera_rig and _alive:
			pawn.camera_rig.handle_mouse_motion(motion.relative)
		elif _spectator and (_in_stands or not _alive):
			_spectator.handle_mouse_motion(motion.relative)


func _unhandled_input(event: InputEvent) -> void:
	# change_scene from a leave/exit can leave this node receiving input while
	# already out of the tree; get_viewport() is then null.
	if not is_inside_tree():
		return

	if ConfirmPrompt.is_open():
		return

	if GameConsole.is_open():
		return

	# A bind waiting for a key eats its own input, so anything reaching here
	# while settings are up is meant for the page itself.
	if _hud.is_settings_open():
		if event.is_action_pressed("ui_cancel") or InputBinds.is_action_just_pressed("controls"):
			_toggle_settings()
			_mark_input_handled()
		return

	if _hud.is_chat_open():
		if event.is_action_pressed("ui_cancel"):
			_hud.close_chat()
			_mark_input_handled()
		return

	if _team_panel.is_open():
		# Keys (1/2/3, M, ESC) are owned by TeamPanel._input.
		_mark_input_handled()
		return

	if _hud.is_controls_visible():
		if event.is_action_pressed("ui_cancel") or InputBinds.is_action_just_pressed("controls"):
			_close_controls_card()
			_mark_input_handled()
		return

	if _match_over:
		if event.is_action_pressed("ui_cancel"):
			# Mark handled before leaving — change_scene frees this node.
			_mark_input_handled()
			_exit_to_lobby()
			return
		if InputBinds.is_action_just_pressed("chat_all"):
			_hud.open_chat(false)
		if InputBinds.is_action_just_pressed("chat_team"):
			_hud.open_chat(true)
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_hud.show_cursor_controls(false)
				return
			if _in_stands and _spectator \
					and _spectator.view_mode == SpectatorCam.ViewMode.FPV:
				_spectator.cycle_target(1, _remotes, -1)
				return
			if not _in_stands and not _alive and _spectator:
				_spectator.leave_death_for_teammate(1, _remotes, _my_team)
				return

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_hud.show_cursor_controls(true)
		else:
			_request_leave()

	if InputBinds.is_action_just_pressed("team_menu"):
		_show_team_panel()

	if InputBinds.is_action_just_pressed("controls"):
		_toggle_controls_card()

	if InputBinds.is_action_just_pressed("scoreboard"):
		_update_scoreboard()
		_hud.set_scoreboard_visible(true)
	if InputBinds.is_action_just_released("scoreboard"):
		_hud.set_scoreboard_visible(false)

	if InputBinds.is_action_just_pressed("chat_all"):
		_hud.open_chat(false)
	if InputBinds.is_action_just_pressed("chat_team"):
		_hud.open_chat(true)

	if _spectator:
		if _in_stands:
			if InputBinds.is_action_just_pressed("spec_swap"):
				_spectator.toggle_view_mode()
			if _spectator.view_mode == SpectatorCam.ViewMode.FPV:
				if event.is_action_pressed("ui_right"):
					_spectator.cycle_target(1, _remotes, -1)
				elif event.is_action_pressed("ui_left"):
					_spectator.cycle_target(-1, _remotes, -1)
		elif not _alive:
			if InputBinds.is_action_just_pressed("action"):
				_try_takeover()
			if event.is_action_pressed("ui_right") \
					or InputBinds.is_action_just_pressed("right"):
				_spectator.leave_death_for_teammate(1, _remotes, _my_team)
			elif event.is_action_pressed("ui_left") \
					or InputBinds.is_action_just_pressed("left"):
				_spectator.leave_death_for_teammate(-1, _remotes, _my_team)


## Ask to possess the bot the death camera is riding. The bot stays on the
## board; we just drive it. Two riders cannot share a body — the first request
## that lands keeps it, the second is refused in silence.
func _try_takeover() -> void:
	if _match_over or _outro_active or client == null:
		return
	var tid := _spectator.target_id()
	if tid == 0 or not _remotes.has(tid):
		return
	var rp: RemotePawn = _remotes[tid]
	if not is_instance_valid(rp) or not rp.is_bot or not rp.alive or rp.team != _my_team:
		return
	client.send_takeover(tid)


func _is_my_combat(pid: int) -> bool:
	var my_id := client.my_id if client else 0
	return pid != 0 and (pid == my_id or pid == _possessing_id)


func _should_hide_ridden(pid: int) -> bool:
	if pid == 0:
		return false
	if pid == _possessing_id:
		return true
	return pid == _ridden_id and (_alive or _local_ragdoll != null)


# ── Combat events from local weapons ────────────────────────────────────

func _on_local_fire() -> void:
	if _match_over or not client or not pawn:
		return
	var origin := pawn.camera_rig.get_aim_origin()
	var dir := pawn.camera_rig.get_aim_direction()
	client.send_shot(origin, dir)


func _on_local_melee() -> void:
	if _match_over:
		return
	if client:
		client.send_melee()


func _on_local_special_start() -> void:
	if _match_over:
		return
	if client:
		client.send_special_start()


func _on_local_special_fire() -> void:
	_special_armed = false
	_special_spent = true
	_special_progress = 0
	if pawn:
		pawn.weapon.special_armed = false
	_sync_special_hud()
	if client:
		client.send_special_fire()


# ── Server events ────────────────────────────────────────────────────────

func _on_snap(snap: Dictionary) -> void:
	# Two snapshots drained in one frame land on the same millisecond, and a
	# zero-length span makes the interpolator snap straight to the newer sample
	# instead of easing into it. Stamp samples on a clock that cannot repeat.
	_sample_clock = maxf(Time.get_ticks_msec() / 1000.0, _sample_clock + SNAP_TIME_EPSILON)
	var players: Array = snap.get("players", [])
	_last_snap_players = players

	var score_blue := int(snap.get("score_blue", 0))
	var score_red := int(snap.get("score_red", 0))
	var round_num := int(snap.get("round_num", 1))
	var round_state := int(snap.get("round_state", 0))
	var mode_int := int(snap.get("mode", 0))
	var snap_mode := "dm" if mode_int == Protocol.MODE_DM else "arena"
	var snap_kill_target := int(snap.get("kill_target", 50))
	_win_rounds = int(snap.get("win_rounds", _win_rounds))
	_clock_s = int(snap.get("clock_s", _clock_s))
	_clock_mode = int(snap.get("clock_mode", _clock_mode))
	_mode = snap_mode
	_last_kill_target = snap_kill_target
	if _match_over:
		score_blue = maxi(score_blue, _last_score_blue)
		score_red = maxi(score_red, _last_score_red)
	var scores_changed := score_blue != _last_score_blue or score_red != _last_score_red
	_last_score_blue = score_blue
	_last_score_red = score_red
	_last_round_num = round_num

	var blue_alive := 0
	var red_alive := 0
	for p: Dictionary in players:
		if (int(p.get("flags", 0)) & Protocol.PFLG_ALIVE) == 0:
			continue
		match int(p.get("team", 0)):
			Protocol.TEAM_BLUE:
				blue_alive += 1
			Protocol.TEAM_RED:
				red_alive += 1

	_hud.update_score(score_blue, score_red, round_num, snap_mode, snap_kill_target,
		round_state, _win_rounds, blue_alive, red_alive, _clock_text())

	# The server flips round_state to RS_OVER in the same tick it sends
	# ROUND_END, so without this guard the next snapshot would slam the overlay
	# up before the round card had a chance to play.
	if round_state == Protocol.RS_OVER and not _match_over_pending \
			and (not _match_over or scores_changed):
		var winner := Protocol.TEAM_BLUE if score_blue >= score_red else Protocol.TEAM_RED
		if score_blue == score_red:
			winner = 0
		_enter_match_over(winner)

	# Rows are rebuilt wholesale, so refresh well below snapshot rate while held.
	if _hud.is_scoreboard_visible() and _snap_time >= _scoreboard_next_refresh:
		_scoreboard_next_refresh = _snap_time + SCOREBOARD_REFRESH
		_update_scoreboard()

	var seen_ids: Dictionary = {}
	var my_id := client.my_id if client else 0

	for p: Dictionary in players:
		var pid: int = int(p.get("id", 0))
		seen_ids[pid] = true

		var pflags := int(p.get("flags", 0))
		var p_alive := (pflags & Protocol.PFLG_ALIVE) != 0
		var p_crouched := (pflags & Protocol.PFLG_CROUCHED) != 0
		var p_protected := (pflags & Protocol.PFLG_PROTECTED) != 0
		var p_bot := (pflags & Protocol.PFLG_BOT) != 0
		var p_special_armed := (pflags & Protocol.PFLG_SPECIAL_ARMED) != 0
		var p_special_charging := (pflags & Protocol.PFLG_SPECIAL_CHARGING) != 0
		var p_grounded := (pflags & Protocol.PFLG_GROUNDED) != 0

		p["alive"] = p_alive
		p["crouched"] = p_crouched
		p["protected"] = p_protected
		p["bot"] = p_bot
		p["special_armed"] = p_special_armed
		p["special_charging"] = p_special_charging
		p["grounded"] = p_grounded

		if pid == my_id:
			if _possessing_id == 0:
				if p_special_armed and _special_spent:
					p_special_armed = false
				elif not p_special_armed:
					_special_spent = false
				_special_armed = p_special_armed
				_special_progress = int(p.get("special_progress", _special_progress))
				if pawn and not pawn.weapon.is_special_charging():
					pawn.weapon.special_armed = p_special_armed
				if not _in_stands:
					_hud.update_hp(int(p.get("hp", 100)))
					_sync_special_hud()
			continue

		if _should_hide_ridden(pid):
			if _possessing_id == pid:
				if p_special_armed and _special_spent:
					p_special_armed = false
				elif not p_special_armed:
					_special_spent = false
				_special_armed = p_special_armed
				_special_progress = int(p.get("special_progress", _special_progress))
				if pawn and not pawn.weapon.is_special_charging():
					pawn.weapon.special_armed = p_special_armed
				if not _in_stands:
					_hud.update_hp(int(p.get("hp", 100)))
					_sync_special_hud()
			if _remotes.has(pid):
				_remotes[pid].visible = false
				_remotes[pid].set_body_visible(false)
			continue

		if _remotes.has(pid):
			var rp: RemotePawn = _remotes[pid]
			rp.visible = true
			var p_team := int(p.get("team", 0))
			if p_team != rp.team:
				rp.set_team_value(p_team)
			rp.is_bot = p_bot
			var was_alive := rp.alive
			rp.push_snapshot(p, _sample_clock)
			# The alive flag only updates during interpolate(), but the
			# ragdoll must be seeded the moment the death snapshot arrives
			# so the body is still in the pose it died in.
			if was_alive and not p_alive and not rp.ragdoll:
				_start_remote_ragdoll(rp, pid)
		else:
			var p_team := int(p.get("team", 0))
			if p_team == Protocol.TEAM_NONE:
				continue
			var rp := RemotePawn.new()
			rp.suit_style = _suit_style()
			add_child(rp)
			var rp_name: String = _player_names.get(pid, "Player %d" % pid)
			rp.setup(pid, rp_name, p_team)
			rp.is_bot = p_bot
			# Joining mid-round means their death already happened off screen.
			rp.adopt_initial_alive(p_alive)
			rp.push_snapshot(p, _sample_clock)
			_remotes[pid] = rp

	var to_remove: Array[int] = []
	for pid: int in _remotes:
		if not seen_ids.has(pid):
			to_remove.append(pid)
	for pid: int in to_remove:
		if _remotes.has(pid):
			_remotes[pid].queue_free()
			_remotes.erase(pid)


func _on_hit(msg: Dictionary) -> void:
	var target_id := int(msg.get("target_id", 0))
	var by_id := int(msg.get("by_id", 0))
	var killed := bool(msg.get("killed", false))
	var head := bool(msg.get("head", false))
	var cause := int(msg.get("cause", 0))
	var by_name := str(msg.get("by_name", ""))
	var target_name := str(msg.get("target_name", ""))
	if not by_name.is_empty():
		_player_names[by_id] = by_name
	if not target_name.is_empty():
		_player_names[target_id] = target_name

	if killed:
		_hud.show_kill(
			by_name, target_name, cause, head,
			int(msg.get("by_team", 0)), int(msg.get("target_team", 0)),
			_is_my_combat(by_id) or _is_my_combat(target_id))
		_last_death[target_id] = { "by": by_id, "head": head, "cause": cause }
	if _is_my_combat(target_id):
		_hud.update_hp(int(msg.get("hp", 0)))
		if killed:
			if target_id == _possessing_id:
				_possessing_id = 0
			_alive = false
			_special_armed = false
			_special_spent = false
			_special_progress = 0
			if pawn:
				pawn.cancel_special()
				pawn.weapon.special_armed = false
				pawn.set_fp_arms_visible(false)
				pawn.set_mannequin_visible(true)

				var kick_dir := _death_kick_dir(by_id, pawn.movement.position,
					pawn.movement.yaw)
				var kick_cause := _death_cause_str(cause, head)
				var kick_vel := pawn.movement.velocity
				_local_ragdoll = _try_local_ragdoll(kick_dir, kick_cause, kick_vel)
				if not _local_ragdoll:
					if pawn.anim_driver:
						pawn.anim_driver.set_state(AnimDriver.State.DEATH)

				var body_pos := pawn.movement.position
				var eye_pos := pawn.movement.get_eye_position()
				if _spectator:
					if _local_ragdoll:
						pawn.set_mannequin_visible(false)
						_spectator._death_mannequin = pawn.get_mannequin()
					_spectator.start_death_ragdoll(body_pos, eye_pos,
						_local_ragdoll, _world,
						_killer_world_pos(by_id))
			_sync_special_hud()
			if Announcer:
				Announcer.player_died()
		else:
			if Announcer:
				Announcer.player_hurt()


func _on_tracer(msg: Dictionary) -> void:
	var by_id := int(msg.get("by_id", 0))
	if _is_my_combat(by_id):
		return

	var origin := Vector3(float(msg.get("origin_x", 0.0)), float(msg.get("origin_y", 0.0)), float(msg.get("origin_z", 0.0)))
	var dir := Vector3(float(msg.get("dir_x", 0.0)), float(msg.get("dir_y", 0.0)), float(msg.get("dir_z", 0.0)))
	var team_val := int(msg.get("team", 1))
	var team_str := "blue" if team_val == Protocol.TEAM_BLUE else "red"

	var hit_dist := 200.0
	if _world != null:
		hit_dist = _world.ray_distance(origin, dir.normalized(), hit_dist, _shot_trace)

	TracerBolt.spawn(self, origin, dir.normalized(), hit_dist, team_str)


func _on_round_start(msg: Dictionary) -> void:
	_hud.hide_round_end()
	_hud.show_banner("ROUND %d" % int(msg.get("round_num", 1)), MatchHud.WHITE,
		"GET READY")
	# The respawn for this round already arrived, so the pawn exists and this
	# only has to hold it still.
	_freeze_until = Time.get_ticks_msec() / 1000.0 + MatchState.ROUND_FREEZE
	if Announcer:
		Announcer.round_start()


func _on_round_end(msg: Dictionary) -> void:
	var winner := int(msg.get("winner", 0))
	var match_over := bool(msg.get("match_over", false))
	var match_point := bool(msg.get("match_point", false))
	var score_blue := int(msg.get("score_blue", _last_score_blue))
	var score_red := int(msg.get("score_red", _last_score_red))
	var round_num := int(msg.get("round_num", _last_round_num))
	_last_score_blue = score_blue
	_last_score_red = score_red
	_last_round_num = round_num
	var reason := int(msg.get("reason", Protocol.END_ELIMINATION))
	_hud.show_round_end(winner, score_blue, score_red, round_num, match_over, reason)
	if match_over:
		_queue_match_over(winner)
	if Announcer:
		Announcer.round_end(winner, match_over, match_point)


func _on_match_over(msg: Dictionary) -> void:
	var winner := int(msg.get("winner", 0))
	if msg.has("score_blue"):
		_last_score_blue = int(msg.get("score_blue", _last_score_blue))
	if msg.has("score_red"):
		_last_score_red = int(msg.get("score_red", _last_score_red))
	_apply_match_over_stats(msg.get("stats", []))
	# ROUND_END normally lands first and has already put the card up; this
	# message is the one carrying the stats. Only raise the card here when the
	# match ended some other way (a forfeit, or joining into a decided match).
	if not _hud.is_round_end_visible() and not _match_over_pending:
		_hud.show_round_end(winner, _last_score_blue, _last_score_red, 0, true)
		if Announcer:
			Announcer.match_over(winner)
	_queue_match_over(winner)


func _on_respawn(msg: Dictionary) -> void:
	if _match_over:
		return
	var pid := int(msg.get("id", 0))
	var my_id := client.my_id if client else 0
	if pid == my_id:
		var body_id := int(msg.get("body_id", pid))
		if body_id != 0 and body_id != my_id:
			_possessing_id = body_id
			_ridden_id = body_id
		else:
			_possessing_id = 0
			_ridden_id = 0
		var sx := float(msg.get("x", 0.0))
		var sy := float(msg.get("y", 0.0))
		var sz := float(msg.get("z", 0.0))
		var yaw := float(msg.get("yaw", 0.0))
		_spawn_local_pawn(Vector3(sx, sy, sz), yaw, int(msg.get("hp", 100)))
		# A round-start redeploy gets the round fanfare instead of the respawn sting.
		if Announcer and not bool(msg.get("round_start", false)):
			Announcer.player_respawn()


func _on_chat(msg: Dictionary) -> void:
	_hud.add_chat_message(
		str(msg.get("name", "")),
		str(msg.get("text", "")),
		int(msg.get("team", 0)),
		bool(msg.get("team_only", false)),
		bool(msg.get("sys", false)))


func _on_chat_submit(text: String, team_only: bool) -> void:
	if client:
		client.send_chat(text, team_only)
	if not _match_over and not _in_stands:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_chat_cancel() -> void:
	if not _match_over and not _in_stands:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_special(msg: Dictionary) -> void:
	var by_id := int(msg.get("by_id", 0))
	var phase := int(msg.get("phase", 0))

	if phase == Protocol.SP_READY and _is_my_combat(by_id) and not _special_spent:
		_special_armed = true
		_special_progress = 0
		if pawn:
			pawn.weapon.special_armed = true
		if not _in_stands:
			_sync_special_hud()
			_hud.show_banner("SPECIAL READY", MatchHud.CYAN,
				"HOLD %s TO CHARGE" % _special_key_label())
		return

	if not _is_my_combat(by_id) and _remotes.has(by_id):
		var rp: RemotePawn = _remotes[by_id]
		if phase == Protocol.SP_CHARGE:
			rp.begin_special()
		elif phase == Protocol.SP_FIRE:
			rp.fire_special()
		elif phase == Protocol.SP_END:
			rp.end_special()

	if phase == Protocol.SP_FIRE and not _is_my_combat(by_id):
		var from := Vector3(float(msg.get("from_x", 0.0)), float(msg.get("from_y", 0.0)), float(msg.get("from_z", 0.0)))
		var hit := Vector3(float(msg.get("hit_x", 0.0)), float(msg.get("hit_y", 0.0)), float(msg.get("hit_z", 0.0)))
		var team_val := int(msg.get("team", 1))
		var team_str := "blue" if team_val == Protocol.TEAM_BLUE else "red"
		var radius := float(msg.get("blast_radius", SpecialBeam.DEFAULT_RADIUS))
		SpecialBeam.spawn(self, from, hit, team_str, radius, false)


func _on_announce(msg: Dictionary) -> void:
	if _is_my_combat(int(msg.get("by_id", 0))) and msg.has("special_progress"):
		_special_progress = int(msg.get("special_progress", _special_progress))
		_sync_special_hud()
	if Announcer:
		Announcer.handle_announce(msg)


func _on_announcer_banner(text: String, color: Color, sub: String) -> void:
	if _match_over or _hud.is_round_end_visible():
		return
	_hud.show_banner(text, color, sub)


func _on_meteor(msg: Dictionary) -> void:
	if _match_over:
		return
	var x := float(msg.get("x", 0.0))
	var y := float(msg.get("y", 0.0))
	var z := float(msg.get("z", 0.0))
	var lead_ms := int(msg.get("lead_ms", 2600))
	var radius := float(msg.get("radius", 5.0))

	var fx := MeteorFx.spawn(self, Vector3(x, y, z), lead_ms, radius)
	fx.impacted.connect(_on_meteor_impact)

	_meteor_warn_until = _snap_time + float(lead_ms) / 1000.0
	_hud.show_meteor_warning(true)


func _on_meteor_impact(pos: Vector3, _radius: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var dist := Vector2(cam_pos.x - pos.x, cam_pos.z - pos.z).length()
	_shake.add_at_distance(dist)
	var k := maxf(0.0, 1.0 - dist / CameraShake.RANGE)
	var vol := minf(1.0, 0.25 + k * 0.85)
	if Announcer:
		Announcer.play_sfx("died", linear_to_db(vol))


func _on_roster(msg: Dictionary) -> void:
	for e: Dictionary in msg.get("entries", []):
		_player_names[int(e.get("id", 0))] = str(e.get("name", ""))
	if _hud.is_scoreboard_visible():
		_update_scoreboard()


func _on_cheats_changed(enabled: bool) -> void:
	GameConsole.on_cheats_changed(enabled)


func _on_cheats_denied() -> void:
	GameConsole.log_line("rejected", GameConsole.COLOR_ERR)


func _clock_text() -> String:
	return "%d:%02d" % [_clock_s / 60, _clock_s % 60]


func _sync_special_hud() -> void:
	if not _hud or _in_stands:
		return
	if pawn and _alive:
		_hud.set_special(
			pawn.weapon.special_armed,
			pawn.weapon.is_special_charging(),
			pawn.weapon.get_special_charge_fraction(),
			pawn.weapon.is_special_releasable(),
			_special_progress)
	else:
		_hud.set_special(_special_armed, false, 0.0, false, _special_progress)


func _special_key_label() -> String:
	if not InputBinds or not InputBinds.bindings.has("special"):
		return "F"
	var slots: Array = InputBinds.bindings["special"]
	var key := str(slots[0]) if slots.size() > 0 else ""
	if key.is_empty() and slots.size() > 1:
		key = str(slots[1])
	return key if not key.is_empty() else "F"


func _apply_match_over_stats(stats: Array) -> void:
	if stats.is_empty():
		return
	var by_id: Dictionary = {}
	var blue_kills := 0
	var red_kills := 0
	for s in stats:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = s
		var pid := int(entry.get("id", 0))
		by_id[pid] = entry
		var name := str(entry.get("name", ""))
		if pid != 0 and not name.is_empty():
			_player_names[pid] = name
		match int(entry.get("team", 0)):
			Protocol.TEAM_BLUE:
				blue_kills += int(entry.get("kills", 0))
			Protocol.TEAM_RED:
				red_kills += int(entry.get("kills", 0))
	if _mode == "dm":
		_last_score_blue = maxi(_last_score_blue, blue_kills)
		_last_score_red = maxi(_last_score_red, red_kills)
	for p in _last_snap_players:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var pid := int(p.get("id", 0))
		if not by_id.has(pid):
			continue
		var s: Dictionary = by_id[pid]
		p["kills"] = int(s.get("kills", 0))
		p["deaths"] = int(s.get("deaths", 0))


func _update_scoreboard() -> void:
	var enriched: Array[Dictionary] = []
	for p: Dictionary in _last_snap_players:
		var pid := int(p.get("id", 0))
		var entry := p.duplicate()
		entry["name"] = _player_names.get(pid, "Player %d" % pid)
		var pflags := int(p.get("flags", 0))
		entry["alive"] = (pflags & Protocol.PFLG_ALIVE) != 0
		entry["bot"] = (pflags & Protocol.PFLG_BOT) != 0
		enriched.append(entry)

	var info := {
		"mode": _mode,
		"kill_target": _last_kill_target,
		"win_rounds": _win_rounds,
		"map_name": _map_display_name(),
		"my_id": client.my_id if client else 0,
		"max_spectators": _max_spectators,
		"score_blue": _last_score_blue,
		"score_red": _last_score_red,
		"match_over": _match_over,
		"winner": _match_winner,
	}
	_hud.update_scoreboard(info, enriched)


func _map_display_name() -> String:
	match _map_id:
		"parkour":
			return "Parkour Yard"
		"skydeck":
			return "Skydeck"
		_:
			return _map_id.capitalize()


func _on_connection_failed(reason: String) -> void:
	push_warning("Connection failed: " + reason)
	_on_leave()


func _request_leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_cursor_controls(true)
	ConfirmPrompt.ask("Leave this lobby?", _on_leave)


func _exit_to_lobby() -> void:
	_on_leave()


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


# The round card and the match-over overlay used to be raised in the same frame,
# so the result you needed to read was covered before it had finished drawing.
# Play the card, hold the camera on the winning side, then hand off.
func _queue_match_over(winner: int) -> void:
	if _match_over or _match_over_pending:
		return
	_match_over_pending = true
	_match_winner = winner
	_begin_match_outro()

	await get_tree().create_timer(MATCH_OVER_HANDOFF).timeout
	if not is_inside_tree() or _match_over:
		return
	_match_over_pending = false
	_enter_match_over(winner)


func _begin_match_outro() -> void:
	_outro_active = true
	if pawn:
		pawn.cancel_special()
		pawn.weapon.special_armed = false
		if _alive:
			# The outro can fall back to an arena orbit, and an orbit that finds
			# a headless pair of viewmodel arms is worse than no orbit at all.
			pawn.set_fp_arms_visible(false)
			pawn.set_mannequin_visible(true)
	if _spectator:
		# TEAMMATE follow against the winning team: it flies to a living winner,
		# or drops to the arena orbit when the local player is the last one up.
		_spectator.start_teammate_follow()
	_hud.hide_spectator_panel()


func _enter_match_over(winner: int) -> void:
	_match_over_pending = false
	_outro_active = false
	_freeze_until = 0.0
	_match_winner = winner
	if _match_over:
		_hud.present_match_over(winner, _last_score_blue, _last_score_red, _mode)
		_update_scoreboard()
		return
	_match_over = true
	_alive = false
	if _local_ragdoll:
		_local_ragdoll.end()
		_local_ragdoll = null
	if _spectator:
		_spectator.stop()
	if _hud:
		_hud.hide_spectator_panel()
	if pawn:
		pawn.cancel_special()
		pawn.weapon.special_armed = false
	if _team_panel.is_open():
		_team_panel.close()
	if _hud.is_settings_open():
		_hud.dismiss_settings()
	if _hud.is_controls_visible():
		_hud.dismiss_controls_card()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.present_match_over(winner, _last_score_blue, _last_score_red, _mode)
	_update_scoreboard()
	if AudioMix:
		AudioMix.play_match_over()


func _on_leave() -> void:
	ConfirmPrompt.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if client:
		client.disconnect_from_server()
	var launcher = get_meta("_local_dedicated") if has_meta("_local_dedicated") else null
	if launcher:
		launcher.stop()
	get_tree().change_scene_to_file("res://scenes/menu/menu_shell.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		var launcher = get_meta("_local_dedicated") if has_meta("_local_dedicated") else null
		if launcher:
			launcher.stop()


func _parse_round_state(s: String) -> int:
	if s == "ended":
		return Protocol.RS_ENDED
	if s == "over":
		return Protocol.RS_OVER
	return Protocol.RS_ACTIVE


func _update_spectator_panel() -> void:
	if not _spectator or not _hud:
		return
	var info := _spectator.get_panel_info(_remotes, _my_team)
	_hud.show_spectator_panel(
		str(info["who"]), str(info["sub"]), Color(info["color"]))
	_hud.set_spectate_crosshair(_spectator.is_fpv_active())


# ── Ragdoll helpers ──────────────────────────────────────────────────────

func _death_cause_str(cause: int, head_shot: bool) -> String:
	if cause == Protocol.CAUSE_METEOR:
		return "meteor"
	if cause == Protocol.CAUSE_SPECIAL:
		return "special"
	if cause == Protocol.CAUSE_MELEE:
		return "melee"
	if head_shot:
		return "head"
	return "laser"


func _death_kick_dir(killer_id: int, victim_pos: Vector3, victim_yaw: float) -> Vector3:
	var src: Variant = _killer_world_pos(killer_id)
	if src != null:
		var dx := victim_pos.x - (src as Vector3).x
		var dz := victim_pos.z - (src as Vector3).z
		var l := sqrt(dx * dx + dz * dz)
		if l > 0.01:
			return Vector3(dx / l, 0.0, dz / l)
	return Vector3(-sin(deg_to_rad(victim_yaw)), 0.0, -cos(deg_to_rad(victim_yaw)))


func _killer_world_pos(killer_id: int) -> Variant:
	if killer_id == 0:
		return null
	var my_id := client.my_id if client else 0
	if killer_id == my_id and pawn:
		return pawn.movement.position
	if _remotes.has(killer_id):
		var rp: RemotePawn = _remotes[killer_id]
		return Vector3(rp._last_eye_x, rp._last_eye_y, rp._last_eye_z)
	return null


func _try_local_ragdoll(dir: Vector3, cause: String, vel: Vector3) -> Ragdoll:
	if not pawn:
		return null
	var skel := pawn._tp_skeleton
	if not skel:
		return null
	var anim_pl: AnimationPlayer = null
	if pawn.anim_driver and pawn.anim_driver._anim_player:
		anim_pl = pawn.anim_driver._anim_player
	var rag := RagdollScript.try_build(skel, anim_pl)
	if not rag:
		return null
	rag.kick(dir, cause, vel)
	return rag


func _start_remote_ragdoll(rp: RemotePawn, pid: int) -> void:
	var info: Dictionary = _last_death.get(pid, {})
	_last_death.erase(pid)

	var victim_pos := Vector3(rp._last_eye_x, rp._last_eye_y, rp._last_eye_z)
	var victim_yaw := rp._last_eye_yaw

	var cause_int: int = int(info.get("cause", Protocol.CAUSE_LASER))
	var head_shot: bool = bool(info.get("head", false))
	var killer_id: int = int(info.get("by", 0))

	var kick_dir := _death_kick_dir(killer_id, victim_pos, victim_yaw)
	var kick_cause := _death_cause_str(cause_int, head_shot)
	var kick_vel := rp.get_last_velocity()
	rp.start_ragdoll(kick_dir, kick_cause, kick_vel)


func _ray_aabb(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var tmin := -1e20
	var tmax := 1e20
	for i in 3:
		if absf(dir[i]) < 1e-8:
			if origin[i] < box.position[i] or origin[i] > box.end[i]:
				return -1.0
		else:
			var t1 := (box.position[i] - origin[i]) / dir[i]
			var t2 := (box.end[i] - origin[i]) / dir[i]
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin if tmin > 0.0 else -1.0
