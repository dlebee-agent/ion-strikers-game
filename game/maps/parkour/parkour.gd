class_name ParkourMap
extends RefCounted

# Data ported from laser-arena/public/maps/parkour.data.js.
# Call ParkourMap.definition() → Dictionary, then MapEngine.compile() on it.


static func definition() -> Dictionary:
	return {
		"id": "parkour",
		"name": "Parkour Yard",
		"desc": "Mirrored stairs & jump blocks. Movement + jump test bed.",
		"arena": 28.0,
		"shapes": [
			{"perimeter": true, "h": 3.4},

			# Spawn-to-spawn cover: standing eye is 1.60m, head top 1.79m.
			# A 2.4m landing sits on the look line (~1.66m at the far tread
			# edge), so neither pad can see the other team's heads. 0.3m
			# rises stay walkable (STEP_LIP 0.35). Starts at z=-18 so the
			# extra treads still finish before mid; pad-edge apron is ~0.35m.
			{
				"stairs": {
					"axis": "z", "at": 0.0, "start": -18.0, "spacing": 1.2,
					"width": 10.0, "depth": 1.7,
					"heights": [
						0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1,
						{"h": 2.4, "width": 10.4, "depth": 2.6},
						2.1, 1.8, 1.5, 1.2, 0.9, 0.6, 0.3,
					],
				},
				"mirror": "z",
			},

			# Rising islands, left side
			{"cover": [-14.0, -14.0, 2.0, 2.0], "h": 0.9, "mirror": "z"},
			{"cover": [-14.0, -10.8, 2.0, 2.0], "h": 1.6, "mirror": "z"},
			{"cover": [-14.0, -7.6, 2.0, 2.0], "h": 2.4, "mirror": "z"},
			{"cover": [-14.0, -4.4, 2.0, 2.0], "h": 1.6, "mirror": "z"},
			# Pillar hops (smaller tops, more precise), right side
			{"cover": [14.0, -14.0, 1.4, 1.4], "h": 0.9, "mirror": "z"},
			{"cover": [14.0, -10.8, 1.4, 1.4], "h": 1.6, "mirror": "z"},
			{"cover": [14.0, -7.6, 1.4, 1.4], "h": 2.2, "mirror": "z"},
			{"cover": [14.0, -4.4, 1.4, 1.4], "h": 1.6, "mirror": "z"},
		],
		"spawns": {
			"blue": [[-1.6, -23], [1.6, -23], [0, -22.2], [-3, -23], [3, -23]],
			"red": [[-1.6, 23], [1.6, 23], [0, 22.2], [-3, 23], [3, 23]],
		},
		"pads": [
			{"x": 0.0, "z": -23.0, "team": "blue"},
			{"x": 0.0, "z": 23.0, "team": "red"},
		],
		"theme": {
			"floor": 0x4a5560,
			"grid": 0x38424c,
			"wall": 0x6f7d8a,
			"cover": 0x8aa0b4,
			"fog": 0x1e262e,
		},
		"sky": {
			"cubemap": {
				"seed": 41,
				"stars": 3600,
				"galaxies": 8,
				"density": 0.52,
				"nebula": [0x5a2ba8, 0x1240a8, 0xb02a6a, 0xd06a3a],
			},
		},
	}
