class_name PlatformsMap
extends RefCounted

# Reverse-engineered from the grid-arena reference model (grid-arena.obj),
# which is where the map got its working name before it became Platforms.
# The model is a 60x40 deck with the teams split along its long axis; the
# game keeps blue on -z and red on +z, so the model is rotated 90 degrees
# here: model (x, z) -> game (z, x). Wedge ramps in the model become stairs
# because the engine only solves boxes, and every stair keeps its climb at
# or under 0.3m per metre: BotNav samples heights on a 1m grid and refuses
# any cell-to-cell rise past STEP_LIP, so a steeper pitch would read as a
# cliff and cut the ramp out of every bot route.
#
# Call PlatformsMap.definition() -> Dictionary, then MapEngine.compile().


static func definition() -> Dictionary:
	return {
		"id": "platforms",
		"name": "Platforms",
		"desc": "Three tiers: spawn garages under twin base decks, catwalks along the walls, and a ring floating over the core.",
		"arena": 30.0,
		# The deck is 60 long but only 40 wide; the floor and grid stop at the
		# side walls instead of filling the square the arena value implies.
		"floor": [20.6, 30.0],
		"shapes": [
			# ---- perimeter ----
			# Long side walls run the full 60m; the model's end walls only
			# spanned the base deck, they are widened here so the corners
			# behind the bases are sealed instead of dropping into the void.
			{"wall": [20.3, 0.0, 0.6, 61.2], "h": 5.0, "mirror": "x"},
			{"wall": [0.0, 29.7, 40.0, 0.6], "h": 5.4, "mirror": "z"},
			# Corner beacon pylons, poking above the walls.
			{"cover": [19.0, -28.5, 0.8, 0.8], "h": 9.0, "mirror": "xz"},

			# ---- base decks (blue -z, mirrored to red +z) ----
			# Elevated deck with a 2.5m spawn garage underneath.
			{"cover": [0.0, -22.0, 26.0, 16.0], "h": 0.7, "on": 2.5, "base": 2.5, "mirror": "z"},
			# Garage front wall with two 4m gate openings.
			{"wall": [0.0, -14.0, 8.0, 0.7], "h": 2.5, "mirror": "z"},
			{"wall": [10.5, -14.0, 5.0, 0.7], "h": 2.5, "mirror": "xz"},
			# Pillars holding the deck up inside the garage.
			{"cover": [4.0, -20.0, 1.2, 1.2], "h": 2.5, "mirror": "xz"},
			{"cover": [11.5, -20.0, 1.2, 1.2], "h": 2.5, "mirror": "xz"},
			# The model's thin deck-front rails are left out on purpose: a rail
			# thinner than a nav cell never lands on a cell column, so bots
			# cannot see it and walk into it forever. The deck edge is instead
			# a clean drop bots refuse on their own (past MAX_DROP they never
			# link the cells) and players can hop down for a flank.

			# Floor-to-deck ramps flanking the gates.
			{
				"stairs": {
					"axis": "z", "at": 10.5, "start": -3.5, "spacing": -1.0,
					"width": 4.4, "depth": 1.0,
					"heights": [0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0, 3.2],
				},
				"mirror": "xz",
			},

			# Deck-to-catwalk upramps along the back of each deck. Longer than
			# the model's wedge so the pitch stays bot-walkable.
			{
				"stairs": {
					"axis": "x", "at": -18.5, "start": -1.6, "spacing": -1.0,
					"width": 3.8, "depth": 1.0,
					"heights": [
						3.5, 3.8, 4.1, 4.4, 4.7, 5.0, 5.3,
						5.6, 5.9, 6.2, 6.5, 6.8, 7.0,
					],
				},
				"base": 3.2,
				"mirror": "xz",
			},

			# Deck furniture: consoles and spawn pod plates.
			{"cover": [8.0, -27.0, 2.4, 1.6], "h": 1.1, "on": 3.2, "base": 3.2, "mirror": "xz"},
			{"cover": [0.0, -24.5, 1.8, 1.8], "h": 0.25, "on": 3.2, "base": 3.2, "mirror": "z"},
			{"cover": [11.0, -24.5, 1.8, 1.8], "h": 0.25, "on": 3.2, "base": 3.2, "mirror": "xz"},

			# ---- high route: catwalks, bridges, sky ring ----
			# Nothing up here shares a top plane with anything it touches: two
			# surfaces at one height render the same pixels twice and flicker
			# between them. Pieces that meet do so edge to edge, on numbers
			# that line up exactly (ring 8.0, catwalk 14.1).
			# Side catwalks running wall to wall on pillars.
			{"cover": [16.6, 0.0, 5.0, 44.0], "h": 0.4, "on": 6.6, "base": 6.6, "mirror": "x"},
			{"cover": [18.95, 0.0, 0.16, 44.0], "h": 1.15, "on": 7.0, "base": 7.0, "mirror": "x"},
			{"cover": [16.6, 4.0, 1.1, 1.1], "h": 6.6, "mirror": "xz"},
			{"cover": [16.6, 12.0, 1.1, 1.1], "h": 6.6, "mirror": "xz"},
			{"cover": [16.6, 20.0, 1.1, 1.1], "h": 6.6, "mirror": "xz"},
			# Bridges from each catwalk to the sky ring, butted to both.
			{"cover": [11.05, 0.0, 6.1, 3.2], "h": 0.35, "on": 6.65, "base": 6.65, "mirror": "x"},
			# Sky ring around the core orb: four bars enclosing an open middle
			# the orb rises through. The model's octagon was eight overlapping
			# slabs, which is the one shape this engine cannot draw cleanly.
			{"cover": [5.8, 0.0, 4.4, 16.0], "h": 0.35, "on": 6.65, "base": 6.65, "mirror": "x"},
			{"cover": [0.0, 5.8, 7.2, 4.4], "h": 0.35, "on": 6.65, "base": 6.65, "mirror": "z"},

			# ---- core ----
			{"cover": [0.0, 0.0, 16.0, 16.0], "h": 1.6},
			# Ramps up the core platform on all four sides.
			{
				"stairs": {
					"axis": "z", "at": 0.0, "start": -12.5, "spacing": 1.0,
					"width": 4.5, "depth": 1.0,
					"heights": [0.3, 0.6, 0.9, 1.2, 1.5],
				},
				"mirror": "z",
			},
			{
				"stairs": {
					"axis": "x", "at": 0.0, "start": -12.5, "spacing": 1.0,
					"width": 4.5, "depth": 1.0,
					"heights": [0.3, 0.6, 0.9, 1.2, 1.5],
				},
				"mirror": "x",
			},
			# Pylon on the platform, orb floating above its collar.
			{"wall": [0.0, 0.0, 2.2, 2.2], "h": 5.2, "on": 1.66, "base": 1.66},
			{"cover": [0.0, 0.0, 3.0, 3.0], "h": 3.0, "on": 6.9, "base": 6.9},

			# ---- mid-field cover ----
			{"cover": [5.5, -11.0, 3.0, 2.6], "h": 1.4, "mirror": "xz"},
			{"cover": [15.5, -7.0, 4.0, 2.4], "h": 1.2, "mirror": "xz"},
			# Crates inside the garages.
			{"cover": [13.0, -17.5, 2.4, 3.4], "h": 1.8, "mirror": "xz"},
			{"cover": [0.0, -25.0, 5.0, 2.2], "h": 2.2, "mirror": "z"},
			# Flush pad plates at the gate mouth and under each catwalk end.
			{"cover": [0.0, -13.5, 2.6, 2.6], "h": 0.15, "mirror": "z"},
			{"cover": [16.6, -20.0, 2.6, 2.6], "h": 0.15, "mirror": "xz"},
		],
		# Spawns sit on the deck at the model's spawn pods. The deck is the
		# nav layer for those columns (BotNav keeps one surface per cell,
		# topmost wins), so spawning up here is what lets bots route out.
		"spawns": {
			"blue": [
				[0.0, -24.5, 3.45], [-11.0, -24.5, 3.45], [11.0, -24.5, 3.45],
				[-5.5, -25.5, 3.2], [5.5, -25.5, 3.2],
			],
			"red": [
				[0.0, 24.5, 3.45], [-11.0, 24.5, 3.45], [11.0, 24.5, 3.45],
				[-5.5, 25.5, 3.2], [5.5, 25.5, 3.2],
			],
		},
		"pads": [
			{"x": 0.0, "z": -24.5, "y": 3.2, "team": "blue"},
			{"x": 0.0, "z": 24.5, "y": 3.2, "team": "red"},
		],
		"theme": {
			"floor": 0x2a3240,
			"grid": 0x38424c,
			"wall": 0x6f7d8a,
			"cover": 0x8aa0b4,
			"fog": 0x1e262e,
		},
		"sky": {
			"cubemap": {
				"seed": 77,
				"stars": 3400,
				"galaxies": 7,
				"density": 0.5,
				"nebula": [0x1a4ac8, 0x22b8c8, 0xc82a50, 0x6a2ba8],
			},
		},
	}
