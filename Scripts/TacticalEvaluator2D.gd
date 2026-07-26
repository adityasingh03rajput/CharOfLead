class_name TacticalEvaluator2D
extends RefCounted
## TacticalEvaluator2D.gd — Evaluates graph nodes to select the best tactical position.
##
## Three distinct scoring profiles keyed on GOAP goal:
##   ELIMINATE  → maximize LOS + ideal standoff (180–400px), prefer high ground
##   GAIN_LOS   → reach nearest LOS-breaking cover fast; ignore enemy distance
##   EVADE      → maximize distance from enemy, avoid LOS, prefer escape lanes
##
## Hysteresis: caller passes current_node_id + current_score; a new node only
## wins if its score exceeds the incumbent by SWITCH_THRESHOLD.

const SWITCH_THRESHOLD: float = 18.0   # minimum score improvement needed to switch nodes
const WALL_BOXES: Array[Rect2] = [
	Rect2(Vector2(-310.0, -115.0), Vector2(335.0, 30.0)), # Top Shelf Wall Box
	Rect2(Vector2(-15.0, -120.0), Vector2(30.0, 240.0)),  # Central Vertical Wall Box
	Rect2(Vector2(-25.0, 85.0), Vector2(335.0, 30.0))     # Lower Shelf Wall Box
]

## goal_type mirrors GOAPPlanner2D.GoalType values (0=ELIMINATE, 1=GAIN_LOS, 2=FLANK, 3=UNSTICK, 4=TARGET_DEAD)
static func select_best_attack_node(
		graph: RefCounted,
		self_pos: Vector2,
		enemy_pos: Vector2,
		space_state: PhysicsDirectSpaceState2D,
		exclude_self_body: RID = RID(),
		exclude_enemy_body: RID = RID(),
		goal_type: int = 1,
		current_node_id: int = -1,
		current_node_score: float = -999999.0
) -> Dictionary:   # returns { "id": int, "score": float }
	if not graph:
		return {"id": -1, "score": -999999.0}

	var node_ids: Array = graph.call("get_all_node_ids")
	if node_ids.is_empty():
		return {"id": -1, "score": -999999.0}

	var best_node_id: int = current_node_id
	# Incumbent score must be beaten by SWITCH_THRESHOLD to actually switch
	var best_score: float = current_node_score + SWITCH_THRESHOLD if current_node_id != -1 else -999999.0

	for node_id in node_ids:
		# Reachability Filter: must have valid A* path
		var path_res = graph.call("get_path_positions", self_pos, node_id)
		if not (path_res is Array) or path_res.is_empty():
			continue

		var npos: Vector2 = graph.call("get_node_pos", node_id)
		var surf: int     = graph.call("get_node_surface", node_id)
		var score: float  = 0.0

		# Travel distance along path waypoints
		var travel_dist: float = 0.0
		var curr_p: Vector2 = self_pos
		for wp: Vector2 in path_res:
			travel_dist += curr_p.distance_to(wp)
			curr_p = wp

		var has_los := _check_line_of_sight(npos, enemy_pos, space_state, exclude_self_body, exclude_enemy_body)
		var enemy_dist := npos.distance_to(enemy_pos)

		# Occupancy / Anti-Stacking: Don't choose nodes right on top of the enemy
		if enemy_dist < 70.0:
			score -= 150.0

		match goal_type:
			0: # ELIMINATE — want LOS, ideal standoff, height advantage
				if has_los:
					score += 200.0
				else:
					score -= 60.0
				score -= travel_dist * 0.20
				if enemy_dist >= 160.0 and enemy_dist <= 380.0:
					score += 55.0
				elif enemy_dist < 100.0:
					score -= 35.0
				if npos.y < enemy_pos.y - 25.0:
					score += 45.0
				if surf == 0:
					score += 25.0
				elif surf == 1 or surf == 2:
					score += 15.0
				elif surf == 3:
					score -= 15.0

			1, 2: # GAIN_LOS / FLANK — reach first LOS position quickly, ignore distance
				if has_los:
					score += 180.0
				score -= travel_dist * 0.35  # heavy travel penalty: go fast
				if npos.y < enemy_pos.y - 25.0:
					score += 30.0
				if surf == 0:
					score += 20.0
				elif surf == 1 or surf == 2:
					score += 10.0

			3: # UNSTICK — nearest reachable node
				score -= travel_dist * 0.50

			_: # EVADE / TARGET_DEAD — maximize distance, avoid LOS, prefer escape lanes
				# Flee: more distance = better
				var dist_score: float = clampf(enemy_dist / 6.0, 0.0, 90.0)
				score += dist_score
				# Penalize positions where enemy still has LOS on us
				if has_los:
					score -= 80.0
				else:
					score += 40.0  # reward cover
				# Penalize short travel (don't flee to nearest node, flee far)
				score -= clampf((400.0 - travel_dist) * 0.10, 0.0, 30.0)
				# Prefer floor (stability while fleeing)
				if surf == 0:
					score += 15.0
				elif surf == 3:
					score -= 20.0

		if score > best_score:
			best_score = score
			best_node_id = node_id

	# Fallback: if hysteresis kept incumbent and it's still valid, keep it
	# If no incumbent, fall back to nearest enemy node
	if best_node_id == -1:
		best_node_id = graph.call("get_nearest_node_id", enemy_pos)
		best_score = -999999.0

	return {"id": best_node_id, "score": best_score}


static func _check_line_of_sight(
		from_pos: Vector2,
		to_pos: Vector2,
		space_state: PhysicsDirectSpaceState2D,
		exclude_self: RID,
		exclude_enemy: RID
) -> bool:
	# Geometric wall box check
	for box: Rect2 in WALL_BOXES:
		var r_top: Vector2    = box.position
		var r_bottom: Vector2 = box.position + box.size
		var r_right: Vector2  = Vector2(r_bottom.x, r_top.y)
		var r_left: Vector2   = Vector2(r_top.x, r_bottom.y)

		if Geometry2D.segment_intersects_segment(from_pos, to_pos, r_top, r_right) != null: return false
		if Geometry2D.segment_intersects_segment(from_pos, to_pos, r_right, r_bottom) != null: return false
		if Geometry2D.segment_intersects_segment(from_pos, to_pos, r_bottom, r_left) != null: return false
		if Geometry2D.segment_intersects_segment(from_pos, to_pos, r_left, r_top) != null: return false

	if not space_state:
		return true

	# Raycast 1: To center of enemy
	var q1 := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	q1.collision_mask = 1
	q1.exclude = [exclude_self]
	if exclude_enemy.is_valid():
		q1.exclude.append(exclude_enemy)
	var hit1 := space_state.intersect_ray(q1)

	if not hit1.is_empty():
		return false

	# Raycast 2: To head of enemy (slightly offset upward)
	var q2 := PhysicsRayQueryParameters2D.create(from_pos, to_pos + Vector2(0, -25))
	q2.collision_mask = 1
	q2.exclude = [exclude_self]
	if exclude_enemy.is_valid():
		q2.exclude.append(exclude_enemy)
	var hit2 := space_state.intersect_ray(q2)

	return hit2.is_empty()
