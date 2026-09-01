extends SceneTree

# Audits bot movement against the world they are actually standing in.
# Run: godot --headless --path game --script res://tools/bot_collision_check.gd
#
# Two failures are worth catching and neither shows up in a smoke test, because
# a bot that misbehaves mid-tick is back in clear space by the time the tick
# ends:
#
#   climbing  feet rising while nothing is under the bot — walking up the
#             outside of a staircase through open air.
#   clipping  the path between two ticks crossing solid geometry — running
#             through a wall and coming out the far side.

const TICK := 1.0 / 60.0
const SECONDS := 60
const MAPS := ["parkour", "community/arena1", "community/fy_snow"]

# Both are movement bugs, not tuning: the budget is zero.
const MAX_CLIMBS := 0
const MAX_CLIPS := 0

## How far the body has to be inside a surface before it counts as having gone
## through it rather than touched it. A swept solver resolves contact to within
## a small tolerance and a slide rides flush along a wall, so a few centimetres
## on a 0.8 m body is contact, not a breach. Anything approaching the body's own
## radius is a real hole.
const BREACH := 0.05

var failed := 0


func _initialize() -> void:
	# The sim rolls dice for roam goals, idling and strafing. Pin them so a run
	# is comparable with the last one.
	seed(20260901)
	for map_id in MAPS:
		_audit(map_id)
	print("\nFAILURES: ", failed)
	quit(1 if failed > 0 else 0)


func _audit(map_id: String) -> void:
	var inst := GameInstance.new({
		"map_id": map_id, "mode": "arena", "bots": true, "rounds": 99,
		"max_players": 12, "bots_shoot": true, "bot_skill": "expert",
	})
	root.add_child(inst)
	inst.setup_map()
	inst.admit_spectator(1, "Auditor")
	inst.handle_set_team(1, Protocol.TEAM_BLUE)
	inst._kill_pawn(1, Protocol.CAUSE_VOID, 0, true)

	var world: CollisionWorld = inst.world
	var tr := TraceResult.new()
	# The body as the sweep sees it, and a narrow pad for "is anything under me".
	var body := Vector3(BotNav.BODY_RADIUS, BotNav.BODY_HEIGHT * 0.5, BotNav.BODY_RADIUS)
	var pin := Vector3(0.06, 0.02, 0.06)

	var last: Dictionary = {}
	var climbs := 0
	var clips := 0
	var worst_climb := 0.0
	var worst_clip := 0.0
	var steps := 0
	var walked := 0.0
	var embedded := 0
	var deepest := 0.0
	var grazes := 0

	for i in 60 * SECONDS:
		inst.tick(TICK)
		for pid: int in inst.pawns:
			var p: ServerPawn = inst.pawns[pid]
			if not p.alive or not inst.participants[pid].is_bot:
				continue
			if not last.has(pid):
				last[pid] = p.position
				continue
			var prev: Vector3 = last[pid]
			last[pid] = p.position
			var step := prev.distance_to(p.position)
			# Skip respawn teleports.
			if step <= 0.0001 or step >= 1.0:
				continue
			steps += 1
			walked += step
			# Finishing a tick inside geometry is the upstream fault: the next
			# tick has to dig out, and digging out is a move with no sweep.
			var centre := p.position + Vector3(0.0, body.y, 0.0)
			if world.box_overlaps(centre, body):
				# Overlap within contact tolerance is a body resting on a surface,
				# not one inside it.
				var depth := world.depenetrate(centre, body).length()
				if depth > 0.01:
					embedded += 1
					deepest = maxf(deepest, depth)

			var rise: float = p.position.y - prev.y

			# Climbing on nothing: the bot rose, and at the new spot its body
			# rests on nothing walkable. Sweeping the BODY down asks the same
			# question the bot's own support does, so a bot legitimately
			# perched on a ledge edge is supported and not counted.
			if rise > 0.02:
				# Free the body first, exactly as Movement does before it moves.
				# An axis-aligned box on a slope is always in epsilon contact,
				# and a sweep that starts in contact reports nothing useful.
				var top := p.position + Vector3(0.0, body.y, 0.0)
				top += world.depenetrate(top, body)
				world.trace_box(top, top - Vector3(0.0, 0.12, 0.0), body, tr)
				var held := tr.hit() and not tr.start_solid \
					and tr.normal.y >= BotNav.MIN_WALK_NORMAL
				if not held:
					climbs += 1
					if climbs <= 5:
						world.trace_box(top, Vector3(top.x, world.bounds.position.y - 1.0, top.z), body, tr)
						print("      climb %5.2f->%5.2f  at (%5.1f, %5.1f)  floor %.2f below  grounded=%s"
							% [prev.y, p.position.y, p.position.x, p.position.z,
								p.position.y - (tr.end_pos.y - body.y), p.grounded])
					world.trace_box(top,
						Vector3(top.x, world.bounds.position.y - 1.0, top.z), body, tr)
					var floor_y := (tr.end_pos.y - body.y) if tr.hit() else world.bounds.position.y
					worst_climb = maxf(worst_climb, p.position.y - floor_y)

			# Clipping. A body that changed height went up and then over (or over
			# and then down), not along the diagonal: that is how Movement steps,
			# and the straight chord cuts the corner of every stair tread it
			# climbed. Trace the path that was actually taken, and separate a
			# graze from a breach by depth — a slide riding a convex corner still
			# touches it.
			var from := prev + Vector3(0.0, body.y, 0.0)
			var to := p.position + Vector3(0.0, body.y, 0.0)
			var legs: Array = []
			if rise > 0.02:
				legs = [[from, Vector3(from.x, to.y, from.z)], [Vector3(from.x, to.y, from.z), to]]
			elif rise < -0.02:
				legs = [[from, Vector3(to.x, from.y, to.z)], [Vector3(to.x, from.y, to.z), to]]
			else:
				legs = [[from, to]]
			var through := 0.0
			var touched := false
			for leg: Array in legs:
				var a: Vector3 = leg[0]
				var b: Vector3 = leg[1]
				world.trace_box(a, b, body, tr)
				if not tr.hit() or tr.start_solid:
					continue
				touched = true
				for k in range(1, 12):
					var mid: Vector3 = a.lerp(b, float(k) / 12.0)
					if world.box_overlaps(mid, body):
						through = maxf(through, world.depenetrate(mid, body).length())
			if through > BREACH:
				clips += 1
				worst_clip = maxf(worst_clip, through)
			elif touched:
				grazes += 1

	print("== %s   brushes=%d  steps=%d  walked=%.0f m" % [
		map_id, world.brush_count(), steps, walked])
	print("   climbed onto nothing : %-4d worst %.2f m" % [climbs, worst_climb])
	print("   passed through solid : %-4d worst %.2f m" % [clips, worst_clip])
	print("   corner grazes (ok)   : %-4d" % grazes)
	print("   ended tick embedded  : %-4d deepest %.2f m (%.1f%%)"
		% [embedded, deepest, 100.0 * embedded / maxi(1, steps)])
	if climbs > MAX_CLIMBS:
		print("   FAIL: bots climb on nothing")
		failed += 1
	if clips > MAX_CLIPS:
		print("   FAIL: bots pass through geometry")
		failed += 1
	if walked < 100.0:
		print("   FAIL: bots barely moved (%.0f m); they may be stuck" % walked)
		failed += 1
	inst.queue_free()
