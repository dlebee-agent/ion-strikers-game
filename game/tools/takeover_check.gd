extends SceneTree

# Drives bot possession: who may ride a body, what they inherit with it, and
# who the scoreboard credits afterwards. A kill made while riding has to land
# on the bot's row — the human keeps their own seat. The refusals keep this
# from being a free respawn.
# Run: godot --headless --path game --script res://tools/takeover_check.gd

const DT := 1.0 / 60.0

var failed := 0
var _to_peer: Array[Dictionary] = []
var _broadcasts: Array[Dictionary] = []


func _initialize() -> void:
	_inherits_the_body()
	_first_claim_wins()
	_the_living_may_not_claim()
	_the_stands_may_not_claim()
	_enemy_bots_are_not_offered()
	_a_dead_bot_is_not_a_body()
	_kills_read_as_the_bot()
	_roster_keeps_both_rows()
	_arena_holds_the_body_count()
	_deathmatch_does_not_refill()

	print("")
	print("FAILURES: %d" % failed)
	quit(1 if failed > 0 else 0)


# ── cases ────────────────────────────────────────────────────────────────

## The pawn carries over as it stands: same place, same health, no fresh spawn
## protection. Taking a bot that is one shot from death must not be a heal.
## The bot is not erased — the human is only riding it.
func _inherits_the_body() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)

	var body: ServerPawn = inst.pawns[-1]
	body.hp = 42
	body.position = Vector3(7.0, 3.0, -4.0)
	body.yaw = 123.0
	_kill(inst, 1)

	var took := inst.handle_takeover(1, -1)
	_expect("inherit", took, "the claim was accepted")
	_expect("inherit", inst.pawns.get(-1) == body, "the bot still owns the pawn")
	_expect("inherit", body.alive and body.hp == 42, "alive on the bot's remaining health")
	_expect("inherit", inst.participants.has(-1), "the bot stays on the roster")
	_expect("inherit", inst.participants.has(1), "and so does the player")
	_expect("inherit", inst.participants[1].possessing == -1, "the player is riding it")
	_expect("inherit", inst.participants[-1].possessed_by == 1, "the bot knows who")
	_expect("inherit", inst._control_id(1) == -1, "input routes to the bot")
	var own: ServerPawn = inst.pawns.get(1)
	_expect("inherit", own != null and not own.alive, "the player's own pawn is still dead")

	var spawn := _sent_to(1, Protocol.Msg.RESPAWN)
	_expect("inherit", not spawn.is_empty(), "the rider was told where it stands")
	if not spawn.is_empty():
		_expect("inherit", is_equal_approx(float(spawn["x"]), 7.0)
			and is_equal_approx(float(spawn["yaw"]), 123.0),
			"at the body's own position and facing")
		_expect("inherit", int(spawn["hp"]) == 42, "on the health it inherited")
		_expect("inherit", int(spawn.get("body_id", 0)) == -1, "and which body they ride")
	print("  %-12s hp %d, bot kept, player dead" % ["inherit", body.hp])
	_free(inst)


## Two dead players, one body: the second request finds it already possessed.
func _first_claim_wins() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)
	_kill(inst, 1)
	_kill(inst, 3)

	var first := inst.handle_takeover(1, -1)
	var second := inst.handle_takeover(3, -1)
	_expect("race", first, "the first claim took it")
	_expect("race", not second, "the second was refused")
	_expect("race", inst.participants[-1].possessed_by == 1, "only the first is riding")
	_expect("race", not (inst.pawns[3] as ServerPawn).alive, "the loser is still dead")
	print("  %-12s first=%s second=%s" % ["race", first, second])
	_free(inst)


func _the_living_may_not_claim() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)
	_expect("alive", not inst.handle_takeover(1, -1), "a standing player is refused")
	_expect("alive", inst.participants.has(-1), "the bot keeps its body")
	_expect("alive", inst.participants[-1].possessed_by == 0, "and is not ridden")
	_free(inst)


## Someone in the stands has no side, so no bot is theirs to take. Note that
## being dead is not what stops them — a spectator has no pawn at all, so the
## "are you standing up" test passes them straight through. It is having no
## team that does, and it has to: otherwise the stands would be a way around
## the team menu and the capacity and balance limits it applies.
func _the_stands_may_not_claim() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)

	var watcher := Participant.new(4, "P4", false)
	watcher.team = Protocol.TEAM_NONE
	inst.participants[4] = watcher
	_expect("stands", not inst.pawns.has(4), "a spectator starts with no pawn at all")
	_expect("stands", not inst.handle_takeover(4, -1), "and is refused")
	_expect("stands", inst.participants.has(-1), "the bot keeps its body")
	_expect("stands", not inst.pawns.has(4), "the spectator is still not on the field")
	_free(inst)


func _enemy_bots_are_not_offered() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_RED)
	_kill(inst, 1)
	_expect("enemy", not inst.handle_takeover(1, -1), "the other side's bot is refused")
	_expect("enemy", inst.participants[-1].team == Protocol.TEAM_RED, "and stays red")
	_free(inst)


func _a_dead_bot_is_not_a_body() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)
	_kill(inst, 1)
	_kill(inst, -1)
	_expect("corpse", not inst.handle_takeover(1, -1), "a dead bot cannot be taken")
	_free(inst)


## The whole point of possession: the feed and the scoreboard name the bot.
func _kills_read_as_the_bot() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)
	_kill(inst, 1)
	inst.handle_takeover(1, -1)

	_broadcasts = []
	inst._apply_damage(2, inst._control_id(1), 1000, false, Protocol.CAUSE_LASER)
	var hit := _broadcast(Protocol.Msg.HIT)
	_expect("credit", not hit.is_empty(), "the kill went out")
	if not hit.is_empty():
		_expect("credit", str(hit["by_name"]) == "BOT 1",
			"the feed names the bot, not the rider (got %s)" % hit["by_name"])
		_expect("credit", int(hit["by_id"]) == -1, "and credits the bot's id")
	_expect("credit", inst.participants[-1].kills == 1, "the frag lands on the bot's row")
	_expect("credit", inst.participants[1].kills == 0, "the rider's row is unchanged")
	print("  %-12s by_name=%s bot_kills=%d player_kills=%d" % [
		"credit", hit.get("by_name", "?"),
		inst.participants[-1].kills, inst.participants[1].kills])
	_free(inst)


## The score tab reads the roster and the snapshot, so both still list the bot
## and the player in their own seats.
func _roster_keeps_both_rows() -> void:
	var inst := _match("arena", false)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 3, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	_bot(inst, -1, Protocol.TEAM_BLUE)
	_kill(inst, 1)
	inst.handle_takeover(1, -1)

	_broadcasts = []
	inst.tick(DT)
	var roster := _broadcast(Protocol.Msg.ROSTER)
	_expect("roster", not roster.is_empty(), "the roster was pushed")
	var names: Array[String] = []
	var saw_bot := false
	for e: Dictionary in roster.get("entries", []):
		names.append(str(e["name"]))
		if int(e["id"]) == 1:
			_expect("roster", not bool(e["is_bot"]), "the claimant is listed as human")
		if int(e["id"]) == -1:
			saw_bot = true
			_expect("roster", bool(e["is_bot"]), "the bot is still a bot")
	_expect("roster", names.has("P1"), "the player is on it")
	_expect("roster", saw_bot and names.has("BOT 1"), "the bot is still on it")

	var snap := Protocol.decode(inst.build_snap())
	var ids: Array[int] = []
	var bot_alive := false
	var player_alive := false
	for p: Dictionary in snap.get("players", []):
		ids.append(int(p["id"]))
		if int(p["id"]) == -1:
			bot_alive = (int(p["flags"]) & Protocol.PFLG_ALIVE) != 0
			_expect("roster", (int(p["flags"]) & Protocol.PFLG_BOT) != 0,
				"the body still flags as a bot")
		if int(p["id"]) == 1:
			player_alive = (int(p["flags"]) & Protocol.PFLG_ALIVE) != 0
	_expect("roster", bot_alive, "the bot is on the field")
	_expect("roster", not player_alive, "the player is still dead on their row")
	_expect("roster", ids.has(-1), "the bot id is in the snap")
	print("  %-12s roster %s" % ["roster", ", ".join(names)])
	_free(inst)


## Possession must not add a body. The bot was already on the side, and it
## stays there — no refill, no disappearance.
func _arena_holds_the_body_count() -> void:
	var inst := _match("arena", true)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	inst._manage_bots()
	var before := _side(inst, Protocol.TEAM_BLUE)
	var bot_id := _a_bot_on(inst, Protocol.TEAM_BLUE)
	_kill(inst, 1)
	_expect("arena", inst.handle_takeover(1, bot_id), "the claim was accepted")

	for _i in 30:
		inst.tick(DT)
	var after := _side(inst, Protocol.TEAM_BLUE)
	_expect("arena", after == before,
		"the side is the same size (%d then %d)" % [before, after])
	print("  %-12s blue %d then %d" % ["arena", before, after])
	_free(inst)


## Deathmatch used to spawn a replacement because the bot was erased. It is
## still there, so the side must not grow.
func _deathmatch_does_not_refill() -> void:
	var inst := _match("dm", true)
	_join(inst, 1, Protocol.TEAM_BLUE)
	_join(inst, 2, Protocol.TEAM_RED)
	inst._manage_bots()
	var before := _side(inst, Protocol.TEAM_BLUE)
	var bot_id := _a_bot_on(inst, Protocol.TEAM_BLUE)
	_kill(inst, 1)
	_expect("dm", inst.handle_takeover(1, bot_id), "the claim was accepted")
	inst._manage_bots()
	var after := _side(inst, Protocol.TEAM_BLUE)
	_expect("dm", after == before, "the side is the same size (%d then %d)" % [before, after])
	print("  %-12s blue %d then %d" % ["dm", before, after])
	_free(inst)


# ── harness ──────────────────────────────────────────────────────────────

func _match(mode: String, bots: bool) -> GameInstance:
	var inst := GameInstance.new({
		"map_id": "skydeck", "mode": mode, "bots": bots,
		"kills": 999, "rounds": 99,
	})
	root.add_child(inst)
	inst.setup_map()
	inst.match_state.round_state = Protocol.RS_ACTIVE
	_to_peer = []
	_broadcasts = []
	inst.event_to_peer.connect(_on_to_peer)
	inst.event_broadcast.connect(_on_broadcast)
	return inst


func _join(inst: GameInstance, pid: int, team: int) -> void:
	var p := Participant.new(pid, "P%d" % pid, false)
	p.team = team
	inst.participants[pid] = p
	inst._spawn_pawn(pid)


func _bot(inst: GameInstance, pid: int, team: int) -> void:
	var b := Participant.new(pid, "BOT %d" % -pid, true)
	b.team = team
	inst.participants[pid] = b
	inst.bot_director.init_ai(b)
	inst._spawn_pawn(pid)


func _kill(inst: GameInstance, pid: int) -> void:
	inst._apply_damage(pid, 0, 1000, false, Protocol.CAUSE_VOID)


func _side(inst: GameInstance, team: int) -> int:
	var n := 0
	for p: Participant in inst.participants.values():
		if p.team == team:
			n += 1
	return n


func _a_bot_on(inst: GameInstance, team: int) -> int:
	for pid: int in inst.participants:
		var p: Participant = inst.participants[pid]
		if p.is_bot and p.team == team:
			return pid
	return 0


func _free(inst: GameInstance) -> void:
	inst.event_to_peer.disconnect(_on_to_peer)
	inst.event_broadcast.disconnect(_on_broadcast)
	inst.queue_free()


func _on_to_peer(peer_id: int, _channel: int, data: PackedByteArray) -> void:
	var msg := Protocol.decode(data)
	msg["peer"] = peer_id
	_to_peer.append(msg)


func _on_broadcast(_channel: int, data: PackedByteArray, _exclude_id: int) -> void:
	_broadcasts.append(Protocol.decode(data))


func _sent_to(peer_id: int, type: int) -> Dictionary:
	for m: Dictionary in _to_peer:
		if int(m.get("peer", 0)) == peer_id and int(m.get("t", -1)) == type:
			return m
	return {}


func _broadcast(type: int) -> Dictionary:
	for m: Dictionary in _broadcasts:
		if int(m.get("t", -1)) == type:
			return m
	return {}


func _expect(label: String, cond: bool, what: String) -> void:
	if cond:
		return
	print("    FAIL: %s — %s" % [label, what])
	failed += 1
