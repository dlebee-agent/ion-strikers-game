class_name Hitbox
extends RefCounted

const STAND_FOOT_Y := 0.30
const STAND_CHEST_Y := 1.35
const STAND_RADIUS := 0.26
const STAND_HEAD_Y := 1.60
const STAND_HEAD_R := 0.19

const CROUCH_FOOT_Y := 0.24
const CROUCH_CHEST_Y := 0.90
const CROUCH_RADIUS := 0.28
const CROUCH_HEAD_Y := 1.12
const CROUCH_HEAD_R := 0.19

const EYE_STAND := 1.6
const EYE_CROUCH := 0.9

const AIM_STAND := 1.15
const AIM_CROUCH := 0.70

const DMG_BODY := 34
const DMG_HEAD := 100

# Arena walls are 3.4m. Stairs and jump pads top out at 2.4m. A special punches
# through anything shorter than this; only the floor and the outer walls stop it.
const SPECIAL_PUNCH_HEIGHT := 3.0


static func special_blocks(box: AABB) -> bool:
	# Floor slab sits under y=0. Looking down still detonates on the ground.
	if box.end.y <= 0.05:
		return true
	return box.size.y >= SPECIAL_PUNCH_HEIGHT


static func eye_height(crouched: bool) -> float:
	return EYE_CROUCH if crouched else EYE_STAND


static func aim_height(crouched: bool) -> float:
	return AIM_CROUCH if crouched else AIM_STAND


static func ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var m := origin - center
	var b := m.dot(dir)
	var c := m.dot(m) - radius * radius
	if c <= 0.0:
		return 0.0
	if b > 0.0:
		return INF
	var disc := b * b - c
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	return INF if t < 0.0 else t


static func ray_capsule_y(origin: Vector3, dir: Vector3,
		center_x: float, y0: float, y1: float, center_z: float,
		radius: float) -> float:
	var mx := origin.x - center_x
	var mz := origin.z - center_z

	if mx * mx + mz * mz <= radius * radius and origin.y >= y0 and origin.y <= y1:
		return 0.0

	var best := INF

	var a := dir.x * dir.x + dir.z * dir.z
	if a > 1e-12:
		var b := mx * dir.x + mz * dir.z
		var c := mx * mx + mz * mz - radius * radius
		var disc := b * b - a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / a
			if t1 >= 0.0 and t1 < best:
				var y := origin.y + dir.y * t1
				if y >= y0 and y <= y1:
					best = t1
			var t2 := (-b + sq) / a
			if t2 >= 0.0 and t2 < best:
				var y := origin.y + dir.y * t2
				if y >= y0 and y <= y1:
					best = t2

	var cap_a := ray_sphere(origin, dir, Vector3(center_x, y0, center_z), radius)
	if cap_a < best:
		best = cap_a
	var cap_b := ray_sphere(origin, dir, Vector3(center_x, y1, center_z), radius)
	if cap_b < best:
		best = cap_b

	return best


static func ray_vs_player(origin: Vector3, dir: Vector3,
		player_pos: Vector3, crouched: bool, max_dist: float) -> Dictionary:
	var head_y: float
	var head_r: float
	var foot_y: float
	var chest_y: float
	var body_r: float

	if crouched:
		head_y = CROUCH_HEAD_Y
		head_r = CROUCH_HEAD_R
		foot_y = CROUCH_FOOT_Y
		chest_y = CROUCH_CHEST_Y
		body_r = CROUCH_RADIUS
	else:
		head_y = STAND_HEAD_Y
		head_r = STAND_HEAD_R
		foot_y = STAND_FOOT_Y
		chest_y = STAND_CHEST_Y
		body_r = STAND_RADIUS

	var head_center := Vector3(player_pos.x, player_pos.y + head_y, player_pos.z)
	var head_t := ray_sphere(origin, dir, head_center, head_r)
	if head_t < max_dist:
		return {"hit": true, "head": true, "dist": head_t}

	var body_t := ray_capsule_y(origin, dir,
			player_pos.x, player_pos.y + foot_y, player_pos.y + chest_y,
			player_pos.z, body_r)
	if body_t < max_dist:
		return {"hit": true, "head": false, "dist": body_t}

	return {"hit": false, "head": false, "dist": max_dist}
