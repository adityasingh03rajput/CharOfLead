class_name TacticalGraph2D
extends RefCounted
## TacticalGraph2D.gd — Builds and manages the 2D surface navigation graph for CharOfLead.
##
## Maps every floor, wall, ceiling, shelf ledge, and aerial jump transition into a node.
## Edges are weighted by action cost (walk, climb, drop, vault).

enum SurfaceType { FLOOR, WALL_LEFT, WALL_RIGHT, CEILING, LEDGE, AIR }
enum ActionType { WALK, CLIMB, DROP, JUMP }

class TacGraphNode:
	var id: int = 0
	var position: Vector2 = Vector2.ZERO
	var surface: int = 0
	var normal: Vector2 = Vector2.UP

var _nodes: Dictionary = {} # id -> GraphNode (using class or dictionary representation)
var _astar: AStar2D = AStar2D.new()

# Arena grid dimensions & bounds (State B cross-section)
const ARENA_CENTER := Vector2(0.0, 0.0)
const ARENA_WIDTH  := 700.0
const ARENA_HEIGHT := 500.0

func _init() -> void:
	_astar.clear()


func build_graph(space_state: PhysicsDirectSpaceState2D = null) -> void:
	_nodes.clear()
	_astar.clear()

	# Sample surfaces across key arena features:
	# 1. Top Shelf (Floor Y = -120, X from -320 to 20)
	# 2. Central Vertical Wall (Wall X = 20, Y from -120 to 120)
	# 3. Lower Shelf (Floor Y = 120, X from 20 to 320)
	# 4. Arena Floor (Y = 220, X from -340 to 340)
	# 5. Arena Roof (Y = -220, X from -340 to 340)
	# 6. Outer Left Wall (X = -340, Y from -220 to 220)
	# 7. Outer Right Wall (X = 340, Y from -220 to 220)

	var node_list: Array = []

	# --- Top Shelf ---
	for x in range(-320, 30, 25):
		node_list.append({"pos": Vector2(x, -120.0), "surf": SurfaceType.FLOOR, "norm": Vector2.UP})

	# --- Central Vertical Wall (Left & Right Faces + Top/Bottom Corners) ---
	for y in range(-120, 125, 25):
		node_list.append({"pos": Vector2(-20.0, y), "surf": SurfaceType.WALL_LEFT, "norm": Vector2.RIGHT})
		node_list.append({"pos": Vector2(20.0, y), "surf": SurfaceType.WALL_RIGHT, "norm": Vector2.LEFT})

	# --- Corner Waypoints (Tactical Vault Points around Wall Edges) ---
	node_list.append({"pos": Vector2(-320.0, -140.0), "surf": SurfaceType.FLOOR, "norm": Vector2.UP})
	node_list.append({"pos": Vector2(0.0, -145.0),    "surf": SurfaceType.FLOOR, "norm": Vector2.UP})
	node_list.append({"pos": Vector2(0.0, 140.0),     "surf": SurfaceType.FLOOR, "norm": Vector2.DOWN})
	node_list.append({"pos": Vector2(320.0, 140.0),   "surf": SurfaceType.FLOOR, "norm": Vector2.UP})

	# --- Lower Shelf ---
	for x in range(-25, 330, 25):
		node_list.append({"pos": Vector2(x, 120.0), "surf": SurfaceType.FLOOR, "norm": Vector2.UP})

	# --- Arena Bottom Floor ---
	for x in range(-340, 350, 35):
		node_list.append({"pos": Vector2(x, 220.0), "surf": SurfaceType.FLOOR, "norm": Vector2.UP})

	# --- Arena Ceiling / Roof ---
	for x in range(-340, 350, 35):
		node_list.append({"pos": Vector2(x, -220.0), "surf": SurfaceType.CEILING, "norm": Vector2.DOWN})

	# --- Outer Left Wall ---
	for y in range(-210, 220, 35):
		node_list.append({"pos": Vector2(-340.0, y), "surf": SurfaceType.WALL_LEFT, "norm": Vector2.RIGHT})

	# --- Outer Right Wall ---
	for y in range(-210, 220, 35):
		node_list.append({"pos": Vector2(340.0, y), "surf": SurfaceType.WALL_RIGHT, "norm": Vector2.LEFT})

	# Add nodes to AStar2D graph
	for i in node_list.size():
		var data: Dictionary = node_list[i]
		_nodes[i] = data
		_astar.add_point(i, data["pos"])

	# Build weighted edges between reachable nodes
	for i in _nodes.keys():
		var p1: Vector2 = _nodes[i]["pos"]
		var s1: int = _nodes[i]["surf"]
		for j in _nodes.keys():
			if i >= j: continue
			var p2: Vector2 = _nodes[j]["pos"]
			var s2: int = _nodes[j]["surf"]
			var dist := p1.distance_to(p2)

			if dist > 160.0:
				continue # Nodes too far apart for direct single-step transition

			if _is_segment_clear(p1, p2, space_state):
				var cost_mult := 1.0
				if s1 == SurfaceType.WALL_LEFT or s1 == SurfaceType.WALL_RIGHT or s2 == SurfaceType.WALL_LEFT or s2 == SurfaceType.WALL_RIGHT:
					cost_mult = 1.25 # Climbing cost
				elif s1 == SurfaceType.CEILING or s2 == SurfaceType.CEILING:
					cost_mult = 1.40 # Ceiling traverse cost
				elif p1.y != p2.y and (s1 == SurfaceType.FLOOR or s2 == SurfaceType.FLOOR):
					cost_mult = 1.15 # Jump/Drop transition cost

				_astar.connect_points(i, j, true)
				_astar.set_point_weight_scale(i, cost_mult)


const WALL_BOXES: Array[Rect2] = [
	Rect2(Vector2(-310.0, -115.0), Vector2(335.0, 30.0)), # Top Shelf Wall Box
	Rect2(Vector2(-15.0, -120.0), Vector2(30.0, 240.0)),  # Central Vertical Wall Box
	Rect2(Vector2(-25.0, 85.0), Vector2(335.0, 30.0))     # Lower Shelf Wall Box
]

func _is_segment_clear(p1: Vector2, p2: Vector2, space_state: PhysicsDirectSpaceState2D) -> bool:
	for box: Rect2 in WALL_BOXES:
		var r_top: Vector2    = box.position
		var r_bottom: Vector2 = box.position + box.size
		var r_right: Vector2  = Vector2(r_bottom.x, r_top.y)
		var r_left: Vector2   = Vector2(r_top.x, r_bottom.y)

		if Geometry2D.segment_intersects_segment(p1, p2, r_top, r_right) != null: return false
		if Geometry2D.segment_intersects_segment(p1, p2, r_right, r_bottom) != null: return false
		if Geometry2D.segment_intersects_segment(p1, p2, r_bottom, r_left) != null: return false
		if Geometry2D.segment_intersects_segment(p1, p2, r_left, r_top) != null: return false

	if not space_state:
		return true

	var query := PhysicsRayQueryParameters2D.create(p1, p2)
	query.collision_mask = 1
	var hit := space_state.intersect_ray(query)
	return hit.is_empty()


func get_nearest_node_id(pos: Vector2) -> int:
	if _astar.get_point_count() == 0:
		return -1
	return _astar.get_closest_point(pos)


func get_node_pos(node_id: int) -> Vector2:
	if _nodes.has(node_id):
		return _nodes[node_id]["pos"]
	return Vector2.ZERO


func get_node_surface(node_id: int) -> int:
	if _nodes.has(node_id):
		return _nodes[node_id]["surf"]
	return SurfaceType.FLOOR


func get_path_positions(start_pos: Vector2, target_node_id: int) -> Array[Vector2]:
	var start_id := get_nearest_node_id(start_pos)
	if start_id == -1 or target_node_id == -1:
		return []

	var point_path := _astar.get_point_path(start_id, target_node_id)
	var result: Array[Vector2] = []
	for p in point_path:
		result.append(p)
	return result


## String-pulling path smoothing: removes redundant intermediate waypoints
## if a direct line-of-sight segment exists between non-adjacent nodes.
func get_smoothed_path_positions(start_pos: Vector2, target_node_id: int, space_state: PhysicsDirectSpaceState2D = null) -> Array[Vector2]:
	var raw_path := get_path_positions(start_pos, target_node_id)
	if raw_path.size() <= 2:
		return raw_path

	var smoothed: Array[Vector2] = [raw_path[0]]
	var curr := 0
	while curr < raw_path.size() - 1:
		var furthest := curr + 1
		for check in range(raw_path.size() - 1, curr + 1, -1):
			if _is_segment_clear(raw_path[curr], raw_path[check], space_state):
				furthest = check
				break
		smoothed.append(raw_path[furthest])
		curr = furthest

	return smoothed


func get_all_node_ids() -> Array:
	return _nodes.keys()


## Converts a smoothed path into a sequence of structured Traversal Edge Dictionaries
## for TraversalExecutor2D.
func get_traversal_edges(start_pos: Vector2, target_node_id: int, space_state: PhysicsDirectSpaceState2D = null) -> Array[Dictionary]:
	var smoothed_positions := get_smoothed_path_positions(start_pos, target_node_id, space_state)
	if smoothed_positions.size() < 2:
		return []

	var edges: Array[Dictionary] = []
	for i in range(smoothed_positions.size() - 1):
		var p1 := smoothed_positions[i]
		var p2 := smoothed_positions[i + 1]

		var id1 := get_nearest_node_id(p1)
		var id2 := get_nearest_node_id(p2)
		var s1 := get_node_surface(id1)
		var s2 := get_node_surface(id2)

		var dx := p2.x - p1.x
		var dy := p2.y - p1.y

		var type: int = TraversalExecutor2D.TraversalType.WALK
		var dir: int  = TraversalExecutor2D.Direction.NONE

		if dx < -5.0:
			dir = TraversalExecutor2D.Direction.LEFT
		elif dx > 5.0:
			dir = TraversalExecutor2D.Direction.RIGHT
		elif dy < -5.0:
			dir = TraversalExecutor2D.Direction.UP
		elif dy > 5.0:
			dir = TraversalExecutor2D.Direction.DOWN

		if s1 == SurfaceType.WALL_LEFT or s1 == SurfaceType.WALL_RIGHT:
			if absf(dx) > 16.0 or dy < -30.0:
				type = TraversalExecutor2D.TraversalType.CORNER_LEAP
			elif absf(dx) > 80.0:
				type = TraversalExecutor2D.TraversalType.WALL_JUMP
			else:
				type = TraversalExecutor2D.TraversalType.CLIMB
		elif s1 == SurfaceType.CEILING:
			if dy > 20.0:
				type = TraversalExecutor2D.TraversalType.DROP
			else:
				type = TraversalExecutor2D.TraversalType.CEILING_SLIDE
		elif s1 == SurfaceType.FLOOR and (s2 == SurfaceType.WALL_LEFT or s2 == SurfaceType.WALL_RIGHT) and dy < -30.0:
			type = TraversalExecutor2D.TraversalType.CORNER_LEAP
		else:
			type = TraversalExecutor2D.TraversalType.WALK

		edges.append({
			"pos_from": p1,
			"pos_to": p2,
			"type": type,
			"dir": dir,
			"timeout": 1.2
		})

	return edges
