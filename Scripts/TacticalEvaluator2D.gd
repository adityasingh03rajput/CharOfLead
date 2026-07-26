class_name TacticalEvaluator2D
extends RefCounted
## TacticalEvaluator2D.gd — Evaluates graph nodes to select the highest-scoring tactical firing position.
##
## Scoring criteria:
##   +150.0 : Clear line of sight to enemy center and head
##   + 50.0 : Height advantage over enemy
##   + 40.0 : Firing angle alignment (horizontal or clear downward angle)
##   -  1.2 * dist : Path travel distance penalty from AI's current position
##   - 30.0 : High risk / floating / ceiling positions unless necessary

const WALL_BOXES: Array[Rect2] = [
	Rect2(Vector2(-310.0, -115.0), Vector2(335.0, 30.0)), # Top Shelf Wall Box
	Rect2(Vector2(-15.0, -120.0), Vector2(30.0, 240.0)),  # Central Vertical Wall Box
	Rect2(Vector2(-25.0, 85.0), Vector2(335.0, 30.0))     # Lower Shelf Wall Box
]

static func select_best_attack_node(
		graph: RefCounted,
		self_pos: Vector2,
		enemy_pos: Vector2,
		space_state: PhysicsDirectSpaceState2D,
		exclude_self_body: RID = RID(),
		exclude_enemy_body: RID = RID()
) -> int:
	if not graph:
		return -1

	var node_ids: Array = graph.call("get_all_node_ids")
	if node_ids.is_empty():
		return -1

	var best_node_id: int = -1
	var best_score: float = -999999.0

	for node_id in node_ids:
		# 0. Reachability Filter: Must have valid A* path from self_pos to candidate node
		var path_res = graph.call("get_path_positions", self_pos, node_id)
		if not (path_res is Array) or path_res.is_empty():
			continue # Skip unreachable / disconnected nodes

		var npos: Vector2 = graph.call("get_node_pos", node_id)
		var surf: int = graph.call("get_node_surface", node_id)
		var score: float = 0.0

		# Calculate total path travel distance along waypoints
		var travel_dist: float = 0.0
		var curr_p: Vector2 = self_pos
		for wp: Vector2 in path_res:
			travel_dist += curr_p.distance_to(wp)
			curr_p = wp

		# 1. Line-of-Sight Evaluation to Enemy
		var has_los := _check_line_of_sight(npos, enemy_pos, space_state, exclude_self_body, exclude_enemy_body)
		if has_los:
			score += 200.0 # High priority for positions with unblocked line of sight
		else:
			score -= 60.0

		# 2. Path Travel Penalty (Prefer shorter, direct travel routes)
		score -= travel_dist * 0.20

		# 3. Target Range Standoff (Ideal combat standoff 180px - 400px)
		var enemy_dist := npos.distance_to(enemy_pos)
		if enemy_dist >= 160.0 and enemy_dist <= 380.0:
			score += 50.0
		elif enemy_dist < 100.0:
			score -= 30.0 # Avoid getting trapped in point-blank melee range

		# 4. Height Advantage (High ground bonus)
		if npos.y < enemy_pos.y - 25.0:
			score += 45.0

		# 5. Surface & Stability Preference (Floor > Wall > Ceiling)
		if surf == 0: # FLOOR
			score += 25.0
		elif surf == 1 or surf == 2: # WALL
			score += 15.0
		elif surf == 3: # CEILING
			score -= 15.0

		if score > best_score:
			best_score = score
			best_node_id = node_id

	# Fallback if no candidate was reachable
	if best_node_id == -1:
		best_node_id = graph.call("get_nearest_node_id", enemy_pos)

	return best_node_id


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
