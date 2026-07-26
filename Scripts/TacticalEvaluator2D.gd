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

static func select_best_attack_node(
		graph: TacticalGraph2D,
		self_pos: Vector2,
		enemy_pos: Vector2,
		space_state: PhysicsDirectSpaceState2D,
		exclude_self_body: RID = RID(),
		exclude_enemy_body: RID = RID()
) -> int:
	var node_ids := graph.get_all_node_ids()
	if node_ids.is_empty():
		return -1

	var best_node_id: int = -1
	var best_score: float = -999999.0

	for node_id in node_ids:
		var npos: Vector2 = graph.get_node_pos(node_id)
		var surf: int = graph.get_node_surface(node_id)
		var score: float = 0.0

		# 1. Line-of-Sight Evaluation (Physics raycast to enemy center & head)
		var has_los := _check_line_of_sight(npos, enemy_pos, space_state, exclude_self_body, exclude_enemy_body)
		if has_los:
			score += 150.0
		else:
			score -= 80.0 # Heavy penalty if node has no sightline to enemy

		# 2. Distance Penalty (Prefer closer nodes to avoid unnecessary long treks)
		var travel_dist := self_pos.distance_to(npos)
		score -= travel_dist * 0.25

		# 3. Target Range Optimization (Ideal combat standoff 180px - 400px)
		var enemy_dist := npos.distance_to(enemy_pos)
		if enemy_dist >= 150.0 and enemy_dist <= 420.0:
			score += 40.0
		elif enemy_dist < 100.0:
			score -= 30.0 # Too close / vulnerable to melee/counter

		# 4. Height Advantage
		if npos.y < enemy_pos.y - 30.0:
			score += 35.0 # Above enemy

		# 5. Surface & Stability Preference (Prefer Floor and Wall over Ceiling)
		if surf == TacticalGraph2D.SurfaceType.FLOOR:
			score += 20.0
		elif surf == TacticalGraph2D.SurfaceType.WALL_LEFT or surf == TacticalGraph2D.SurfaceType.WALL_RIGHT:
			score += 15.0
		elif surf == TacticalGraph2D.SurfaceType.CEILING:
			score -= 10.0

		if score > best_score:
			best_score = score
			best_node_id = node_id

	# Fallback if all nodes scored low
	if best_node_id == -1:
		best_node_id = graph.get_nearest_node_id(enemy_pos)

	return best_node_id


static func _check_line_of_sight(
		from_pos: Vector2,
		to_pos: Vector2,
		space_state: PhysicsDirectSpaceState2D,
		exclude_self: RID,
		exclude_enemy: RID
) -> bool:
	if not space_state:
		return true

	# Raycast 1: To center of enemy
	var q1 := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	q1.exclude = [exclude_self]
	if exclude_enemy.is_valid():
		q1.exclude.append(exclude_enemy)
	var hit1 := space_state.intersect_ray(q1)

	if hit1.is_empty():
		return true

	# Raycast 2: To head of enemy (slightly offset upward)
	var q2 := PhysicsRayQueryParameters2D.create(from_pos, to_pos + Vector2(0, -25))
	q2.exclude = [exclude_self]
	if exclude_enemy.is_valid():
		q2.exclude.append(exclude_enemy)
	var hit2 := space_state.intersect_ray(q2)

	return hit2.is_empty()
