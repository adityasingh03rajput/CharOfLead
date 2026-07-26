extends Node
## AIController.gd — Drives one player slot (Red or Blue) with hard-difficulty AI.
##
## Attach ONE of these to the scene tree (Main.gd adds it after spawning players).
## Set ai_player_id = 1 (Red) or 2 (Blue) and ai_difficulty before _ready().
##
## The AI works in BOTH dimensions:
##   • 3D (State A): Red is the hunter; AI steers toward Blue, strafes, aims & shoots.
##   • 2D (State B): Blue is the armed assassin; AI tracks Red, aims at mouse pos, fires.
##
## Hard difficulty: near-perfect aim with slight intentional spread, minimal reaction delay,
## aggressive flanking, body-hop usage (Blue), grapple usage (Red).

@export var ai_player_id: int = 2          # 1=Red AI, 2=Blue AI
@export var ai_difficulty: int = 2         # 0=Easy, 1=Medium, 2=Hard

# ── State machine ──────────────────────────────────────────────────────────────
enum AIState {
	IDLE,        # waiting / game over
	SEEK,        # moving toward enemy
	STRAFE,      # circling enemy while armed
	EVADE,       # running away (unarmed dimension)
	GRAPPLE,     # P1 using grapple in 2D to escape
	BODY_HOP,    # P2 picking a clone to jump into
}

var _state: int = AIState.IDLE

# ── References (populated in setup()) ─────────────────────────────────────────
var _body_3d: CharacterBody3D   # the AI's 3D body
var _body_2d: CharacterBody2D   # the AI's 2D body
var _enemy_3d: CharacterBody3D  # opponent's 3D body
var _enemy_2d: CharacterBody2D  # opponent's 2D body

# ── Timers and accumulators ────────────────────────────────────────────────────
var _react_timer: float = 0.0    # reaction delay before acting each burst
var _strafe_timer: float = 0.0   # cycles strafe direction
var _strafe_dir: float = 1.0
var _decision_timer: float = 0.0 # re-evaluates state this often
var _grapple_timer: float = 0.0  # 2D grapple debounce
var _body_hop_timer: float = 0.0 # P2 3D body-hop debounce
var _clone_timer: float = 0.0    # P2 3D clone planting debounce
var _tactic_timer: float = 0.0   # small tactical variation timer
var _weapon_commit_timer: float = 0.0 # holds a weapon choice; switching costs 0.3s
var _hurt_timer: float = 0.0     # set when damaged, biases the AI toward cover
var _last_known_health: float = 100.0
var _stuck_2d_timer: float = 0.0 # tracks 2D movement stagnation
var _last_2d_pos: Vector2 = Vector2.ZERO
var _unstick_flank_timer: float = 0.0
var _unstick_flank_dir: float = 1.0

# ── Difficulty tuning tables ───────────────────────────────────────────────────
# Tuned against real weapon stats: the rifle fires every 0.1s for 14 damage, so
# REACT_DELAY is the real rate limiter on AI damage output. Values assume aim
# and movement actually connect — before the input-contract fixes the AI shot
# from the human's camera, so the old near-zero delay/spread was masking a miss.
const REACT_DELAY    := [0.70, 0.34, 0.14]   # seconds before acting
const AIM_SPREAD     := [22.0, 9.0, 3.5]     # degrees of aim randomness
const STRAFE_PERIOD  := [2.0,  1.4, 0.9]     # how often strafe direction flips
const DECISION_RATE  := [0.7,  0.45, 0.22]   # how often AI re-picks a state

# ── Virtual input state (read by hooked player scripts each frame) ─────────────
var _virt_move: Vector2 = Vector2.ZERO
var _virt_fire: bool = false
var _virt_jump: bool = false
var _virt_grapple: bool = false
var _virt_body_hop: int = 0
var _virt_clone_pos = null
var _virt_mouse_world: Vector2 = Vector2.ZERO  # 2D aim target
var _virt_aim_dir_3d: Vector3 = Vector3.FORWARD # 3D aim direction
var _selected_weapon_3d: int = 1               # 0=Pistol, 1=Rifle, 2=Shotgun, 3=Bomb

# ── Strafe orbit state ─────────────────────────────────────────────────────────
var _orbit_angle: float = 0.0
var _ai_cam_yaw: float = 0.0

# ── Lifecycle ──────────────────────────────────────────────────────────────────
var _enabled: bool = false

# ── Custom Pathfinding (Maze is fixed, simple waypoint graph) ─────────────────
var _astar: AStar2D = AStar2D.new()

const MAZE_WALLS = [
	[Vector2(-12.0, -4), Vector2(0.5, -4)], # A (expanded for width)
	[Vector2(0, -4.5), Vector2(0, 4.5)],    # B
	[Vector2(-0.5, 4), Vector2(12.0, 4)]    # C
]

# ── Public API ─────────────────────────────────────────────────────────────────
## Called by Main after spawning players.
func setup(body3d: CharacterBody3D, body2d: CharacterBody2D,
		enemy3d: CharacterBody3D, enemy2d: CharacterBody2D) -> void:
	_body_3d  = body3d
	_body_2d  = body2d
	_enemy_3d = enemy3d
	_enemy_2d = enemy2d
	_strafe_dir  = 1.0 if randf() > 0.5 else -1.0
	_orbit_angle = randf() * TAU
	_enabled  = true
	_state    = AIState.SEEK
	_init_nav()
	if is_instance_valid(_body_2d):
		if _tactical_graph_2d == null:
			var graph_script := load("res://Scripts/TacticalGraph2D.gd") as GDScript
			if graph_script:
				_tactical_graph_2d = graph_script.new()
		if _tactical_graph_2d != null:
			_tactical_graph_2d.call("build_graph", _body_2d.get_world_2d().direct_space_state)
	if is_instance_valid(GameManager) and not GameManager.health_changed.is_connected(_on_health_changed):
		GameManager.health_changed.connect(_on_health_changed)
	if is_instance_valid(GameManager):
		_last_known_health = float(GameManager.get_health(ai_player_id))


func _on_health_changed(pid: int, current: float, _maximum: float) -> void:
	# Taking fire is the cue to break contact and use cover, rather than
	# discovering the damage several polls later.
	if pid != ai_player_id:
		return
	if current < _last_known_health:
		_hurt_timer = 2.5
		_decision_timer = 0.0
	_last_known_health = current


func get_virtual_input_2d() -> Dictionary:
	return {
		"move":        _virt_move,
		"fire":        _virt_fire,
		"jump":        _virt_jump,
		"grapple":     _virt_grapple,
		"mouse_world": _virt_mouse_world,
	}


func get_virtual_input_3d() -> Dictionary:
	return {
		"move":    _virt_move,
		"fire":    _virt_fire,
		"jump":    _virt_jump,
		"weapon":  _selected_weapon_3d,
		"aim_dir": _virt_aim_dir_3d,
		"cam_yaw": _ai_cam_yaw,
		"body_hop": _virt_body_hop,
		"implant_clone": _virt_clone_pos,
	}


func replace_body_3d(new_body: CharacterBody3D) -> void:
	# Called by Player3D after a successful Blue body-hop. Without this, the AI
	# would keep issuing input to the abandoned idle body.
	_body_3d = new_body


func ack_oneshot_3d() -> void:
	# The brain ticks in _process (render rate) but bodies act in
	# _physics_process (fixed 60Hz), so a single command can be read twice on a
	# dropped frame. The consumer acks to guarantee exactly-once.
	_virt_clone_pos = null
	_virt_body_hop = 0


## Freeze every virtual input channel — called whenever the AI or its
## target is dead/respawning so no stale movement bleeds into the next round.
func _zero_virtual_inputs() -> void:
	_virt_move        = Vector2.ZERO
	_virt_fire        = false
	_virt_jump        = false
	_virt_grapple     = false
	_virt_body_hop    = 0
	_virt_clone_pos   = null
	_virt_mouse_world = _virt_mouse_world  # keep aim point stable (cosmetic)


# ── Process ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _enabled:
		return
	if not is_instance_valid(GameManager):
		return

	_react_timer    -= delta
	_strafe_timer   -= delta
	_decision_timer -= delta
	_grapple_timer   = maxf(_grapple_timer - delta, 0.0)
	_body_hop_timer  = maxf(_body_hop_timer - delta, 0.0)
	_clone_timer     = maxf(_clone_timer - delta, 0.0)
	_tactic_timer    = maxf(_tactic_timer - delta, 0.0)
	_weapon_commit_timer = maxf(_weapon_commit_timer - delta, 0.0)
	_hurt_timer      = maxf(_hurt_timer - delta, 0.0)
	_unstick_flank_timer = maxf(_unstick_flank_timer - delta, 0.0)

	# ── 2D Stuck Detection (Unsticking Logic) ─────────────────────────────
	if not GameManager.is_3d_mode and is_instance_valid(_body_2d):
		var pos_2d := _body_2d.global_position
		if pos_2d.distance_to(_last_2d_pos) < 3.0:
			_stuck_2d_timer += delta
		else:
			_stuck_2d_timer = 0.0
		_last_2d_pos = pos_2d

		if _stuck_2d_timer > 0.22:
			_unstick_flank_timer = 0.55
			_unstick_flank_dir = -signf(_virt_move.x) if _virt_move.x != 0.0 else -_strafe_dir
			if _unstick_flank_dir == 0.0: _unstick_flank_dir = 1.0
			_stuck_2d_timer = 0.0

	# Reset virtual inputs every frame so they don't "stick"
	_virt_move  = Vector2.ZERO
	_virt_fire  = false
	_virt_jump  = false
	_virt_grapple = false
	_virt_body_hop = 0
	_virt_clone_pos = null

	if GameManager.is_3d_mode:
		_tick_3d(delta)
	else:
		_tick_2d(delta)


func _init_nav() -> void:
	_astar.clear()
	# Topological graph nodes representing key intersections, shelf edges, and corridor corners
	var nodes := [
		Vector2(-12.0, -8.0), Vector2(-6.0, -8.0), Vector2(0.5, -8.0),   # Top shelf row
		Vector2(-12.0, -4.5), Vector2(-6.0, -4.5), Vector2(1.0, -4.5),   # Mid-upper row (shelf corners)
		Vector2(-1.0, 0.0),   Vector2(1.0, 0.0),                         # Central wall bend
		Vector2(-1.0, 4.5),   Vector2(6.0, 4.5),   Vector2(12.0, 4.5),   # Mid-lower row (lower shelf corners)
		Vector2(-12.0, 8.0),  Vector2(0.0, 8.0),    Vector2(12.0, 8.0)   # Floor row
	]
	for i in nodes.size():
		_astar.add_point(i, nodes[i])
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if _is_path_clear(nodes[i], nodes[j]):
				var weight: float = nodes[i].distance_to(nodes[j])
				_astar.connect_points(i, j, true)

func _is_path_clear(from: Vector2, to: Vector2) -> bool:
	for w in MAZE_WALLS:
		if Geometry2D.segment_intersects_segment(from, to, w[0], w[1]) != null:
			return false
	return true

func _get_nav_dir(self_pos: Vector2, target_pos: Vector2) -> Vector2:
	if _is_path_clear(self_pos, target_pos):
		return (target_pos - self_pos).normalized()
		
	var id_s := 1000
	var id_t := 1001
	_astar.add_point(id_s, self_pos)
	_astar.add_point(id_t, target_pos)
	
	for i in _astar.get_point_ids():
		if i == id_s or i == id_t: continue
		var p_pos := _astar.get_point_position(i)
		if _is_path_clear(self_pos, p_pos):
			_astar.connect_points(id_s, i)
		if _is_path_clear(target_pos, p_pos):
			_astar.connect_points(id_t, i)
			
	var path := _astar.get_point_path(id_s, id_t)
	var dir := (target_pos - self_pos).normalized()
	if path.size() > 1:
		dir = (path[1] - self_pos).normalized()
		
	_astar.remove_point(id_s)
	_astar.remove_point(id_t)
	return dir

const MAZE_WALL_BOXES_2D: Array[Rect2] = [
	Rect2(Vector2(-310.0, -115.0), Vector2(335.0, 30.0)), # Top Shelf Wall Box
	Rect2(Vector2(-15.0, -120.0), Vector2(30.0, 240.0)),  # Central Vertical Wall Box
	Rect2(Vector2(-25.0, 85.0), Vector2(335.0, 30.0))     # Lower Shelf Wall Box
]

func _is_path_clear_2d(from_2d: Vector2, to_2d: Vector2) -> bool:
	for box: Rect2 in MAZE_WALL_BOXES_2D:
		if _segment_intersects_rect(from_2d, to_2d, box):
			return false

	if is_instance_valid(_body_2d):
		var space := _body_2d.get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(from_2d, to_2d)
		query.exclude = [_body_2d.get_rid()]
		if is_instance_valid(_enemy_2d):
			query.exclude.append(_enemy_2d.get_rid())
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return false

	return true

func _segment_intersects_rect(p1: Vector2, p2: Vector2, rect: Rect2) -> bool:
	var r_top: Vector2    = rect.position
	var r_bottom: Vector2 = rect.position + rect.size
	var r_right: Vector2  = Vector2(r_bottom.x, r_top.y)
	var r_left: Vector2   = Vector2(r_top.x, r_bottom.y)

	if Geometry2D.segment_intersects_segment(p1, p2, r_top, r_right) != null: return true
	if Geometry2D.segment_intersects_segment(p1, p2, r_right, r_bottom) != null: return true
	if Geometry2D.segment_intersects_segment(p1, p2, r_bottom, r_left) != null: return true
	if Geometry2D.segment_intersects_segment(p1, p2, r_left, r_top) != null: return true

	return false


var _tactical_graph_2d: RefCounted = null
var _tactical_path_2d: Array[Vector2] = []
var _target_attack_node_id: int = -1
var _replan_timer_2d: float = 0.0
var _last_target_enemy_pos: Vector2 = Vector2.ZERO
var _last_los_state: bool = false
var _path_age_2d: float = 0.0      # seconds since last path was computed
var _active_goal_2d: int = -1      # last GOAP goal chosen
var _current_node_score: float = -999999.0  # score of the incumbent tactical node
var _traversal_executor_2d: RefCounted = null
var _traversal_edges_2d: Array[Dictionary] = []

func _get_nav_dir_2d(self_pos: Vector2, target_pos: Vector2) -> Vector2:
	if _is_path_clear_2d(self_pos, target_pos):
		if is_instance_valid(_body_2d):
			if _body_2d.is_on_wall() or _body_2d.is_on_ceiling():
				_virt_jump = true # Push off wall/ceiling into open air!
		return (target_pos - self_pos).normalized()

	# ── TraversalExecutor2D: Data-driven event-based macro execution ───────
	if not _traversal_edges_2d.is_empty() and _traversal_executor_2d != null:
		var exec_res: Dictionary = _traversal_executor_2d.call("tick", get_process_delta_time(), _body_2d, self_pos)
		if exec_res.get("jump", false):
			_virt_jump = true
		if exec_res.get("grapple", false):
			_virt_grapple = true

		if exec_res.get("completed", false):
			_traversal_edges_2d.pop_front()
			if not _traversal_edges_2d.is_empty():
				_traversal_executor_2d.call("start_edge", _traversal_edges_2d[0], self_pos)

		var move_vec: Vector2 = exec_res.get("move", Vector2.ZERO)
		if move_vec.length_squared() > 0.01:
			var nav_tag := "RED 2D AI NAV" if ai_player_id == 1 else "BLUE 2D AI NAV"
			print("[%s] Traversal Macro | Move: %s | Jump: %s" % [nav_tag, move_vec, _virt_jump])
			return move_vec.normalized()

	# Fallback: Spatial graph pathfinding if traversal edges empty
	if not _tactical_path_2d.is_empty():
		var waypoint: Vector2 = _tactical_path_2d[0]

		# ── Waypoint arrival: axis-separated thresholds ──────────────────────
		var on_wall := is_instance_valid(_body_2d) and _body_2d.is_on_wall()
		var arrived := false
		if on_wall:
			arrived = absf(waypoint.x - self_pos.x) < 30.0 and absf(waypoint.y - self_pos.y) < 55.0
		else:
			arrived = self_pos.distance_to(waypoint) < 40.0

		if arrived:
			_tactical_path_2d.pop_front()
			if not _tactical_path_2d.is_empty():
				waypoint = _tactical_path_2d[0]

		var way_dir := (waypoint - self_pos).normalized()
		if is_instance_valid(_body_2d):
			if _body_2d.is_on_wall():
				var on_corner_ceiling := _body_2d.is_on_ceiling()
				var is_stuck := _stuck_2d_timer > 0.1 or _unstick_flank_timer > 0.0
				var x_offset := absf(waypoint.x - self_pos.x)

				var space := _body_2d.get_world_2d().direct_space_state
				var overhead_blocked := false
				if space and waypoint.y < self_pos.y:
					var ray_q := PhysicsRayQueryParameters2D.create(self_pos, self_pos + Vector2(0, -35.0))
					ray_q.collision_mask = 1
					ray_q.exclude = [_body_2d.get_rid()]
					overhead_blocked = not space.intersect_ray(ray_q).is_empty()

				if x_offset > 16.0 or on_corner_ceiling or overhead_blocked or is_stuck:
					_virt_jump = true
				else:
					way_dir.y = signf(waypoint.y - self_pos.y)
					way_dir.x = 0.0
			elif _body_2d.is_on_ceiling():
				if waypoint.y > self_pos.y + 20.0 or _stuck_2d_timer > 0.1:
					_virt_jump = true
			elif absf(waypoint.x - self_pos.x) < 35.0 and waypoint.y < self_pos.y - 30.0 and _body_2d.is_on_floor():
				_virt_jump = true
		var nav_tag := "RED 2D AI NAV" if ai_player_id == 1 else "BLUE 2D AI NAV"
		print("[%s] Self: %s | Waypoint: %s | WayDir: %s | Jump: %s" % [nav_tag, self_pos, waypoint, way_dir, _virt_jump])
		return way_dir

	var shelf_route_x := _find_best_2d_shelf_route(self_pos, target_pos)
	var route_dir := Vector2(shelf_route_x, 0.0)
	if is_instance_valid(_body_2d) and _body_2d.is_on_wall():
		route_dir = Vector2(-shelf_route_x, -1.0).normalized()
		_virt_jump = true
	return route_dir.normalized()

# ══════════════════════════════════════════════════════════════════════════════
# 3-D BRAIN  (State A — Red is hunter)
# ══════════════════════════════════════════════════════════════════════════════
func _tick_3d(delta: float) -> void:
	if not is_instance_valid(_body_3d) or not is_instance_valid(_enemy_3d):
		return
	if _body_3d.get("_is_dead") or _enemy_3d.get("_is_dead"):
		return

	var self_pos: Vector3  = _body_3d.global_position
	var enemy_pos: Vector3 = _enemy_3d.global_position
	var to_enemy: Vector3  = enemy_pos - self_pos
	var dist: float        = to_enemy.length()

	var is_ai_armed: bool = GameManager.is_armed(ai_player_id) if is_instance_valid(GameManager) else (ai_player_id == 1)

	# ── State selection ───────────────────────────────────────────────────────
	if _decision_timer <= 0.0:
		_decision_timer = DECISION_RATE[ai_difficulty]
		if is_ai_armed:
			_state = AIState.STRAFE if dist < 14.0 and _has_line_of_sight_3d() else AIState.SEEK
		else:
			_state = AIState.BODY_HOP if _should_body_hop_3d(dist) else AIState.EVADE

	# ── Strafe direction cycling ──────────────────────────────────────────────
	if _strafe_timer <= 0.0:
		_strafe_timer = STRAFE_PERIOD[ai_difficulty]
		_strafe_dir   = -_strafe_dir

	match _state:
		AIState.SEEK:   _ai_3d_seek(to_enemy, dist)
		AIState.STRAFE: _ai_3d_strafe(delta, to_enemy, enemy_pos)
		AIState.EVADE:  _ai_3d_evade(to_enemy)
		AIState.BODY_HOP:
			_ai_3d_evade(to_enemy)
			_ai_3d_body_hop()


func _ai_3d_seek(to_enemy: Vector3, dist: float) -> void:
	var self_pos = _body_3d.global_position
	var target_pos = _enemy_3d.global_position

	# Maintain a 3.2m combat standoff distance — stops AI from walking into player's capsule
	if dist < 3.2:
		var away := -to_enemy
		away.y = 0.0
		if away.length_squared() > 0.01:
			away = away.normalized()
		else:
			away = Vector3.FORWARD
		_virt_move = Vector2(away.x, away.z)
		_ai_cam_yaw = atan2(to_enemy.x, to_enemy.z)
		return

	var nav_dir = _get_nav_dir(Vector2(self_pos.x, self_pos.z), Vector2(target_pos.x, target_pos.z))
	
	_virt_move    = nav_dir
	_ai_cam_yaw   = atan2(nav_dir.x, nav_dir.y)

	var is_ai_armed: bool = GameManager.is_armed(ai_player_id) if is_instance_valid(GameManager) else true
	if is_ai_armed and dist < 22.0:
		if _react_timer <= 0.0 and _has_line_of_sight_3d():
			_aim_and_fire_3d()


func _ai_3d_strafe(delta: float, to_enemy: Vector3, enemy_pos: Vector3) -> void:
	var self_pos: Vector3 = _body_3d.global_position

	var desired_dist := randf_range(6.5, 10.0) if ai_difficulty == 2 else randf_range(4.0, 11.0)
	if _health_ratio(ai_player_id) < 0.35:
		desired_dist += 3.0
	_orbit_angle += _strafe_dir * (1.2 if ai_difficulty == 2 else 0.8) * delta

	var orbit_target := enemy_pos + Vector3(
		sin(_orbit_angle) * desired_dist, 0.0, cos(_orbit_angle) * desired_dist)

	var nav_dir = _get_nav_dir(Vector2(self_pos.x, self_pos.z), Vector2(orbit_target.x, orbit_target.z))
	_virt_move = nav_dir

	var aim_flat := to_enemy
	aim_flat.y = 0.0
	if aim_flat.length_squared() > 0.01:
		aim_flat    = aim_flat.normalized()
		_ai_cam_yaw = atan2(aim_flat.x, aim_flat.z)

	var is_ai_armed: bool = GameManager.is_armed(ai_player_id) if is_instance_valid(GameManager) else true
	if is_ai_armed and _react_timer <= 0.0 and _has_line_of_sight_3d():
		_aim_and_fire_3d()

	if randf() < 0.002:
		_virt_jump = true


func _has_line_of_sight_3d() -> bool:
	if not is_instance_valid(_body_3d) or not is_instance_valid(_enemy_3d):
		return false
	var space = _body_3d.get_world_3d().direct_space_state
	var self_pos = _body_3d.global_position + Vector3.UP * 1.2
	var enemy_pos = _enemy_3d.global_position + Vector3.UP * 0.9
	var query = PhysicsRayQueryParameters3D.create(self_pos, enemy_pos)
	query.exclude = [_body_3d.get_rid(), _enemy_3d.get_rid()]
	var hit = space.intersect_ray(query)
	return hit.is_empty()


func _ai_3d_evade(to_enemy: Vector3) -> void:
	var self_pos: Vector3 = _body_3d.global_position
	var away := -to_enemy
	away.y = 0.0
	if away.length_squared() > 0.01:
		away = away.normalized()
	else:
		away = Vector3.FORWARD
		
	# Compute an evade target away from Red, biased toward the map center when near edges.
	var evade_target: Vector3 = self_pos + away * (8.5 if ai_difficulty == 2 else 6.0)
	var center_pull: Vector3 = Vector3.ZERO - self_pos
	center_pull.y = 0.0
	if absf(self_pos.x) > 9.5 or absf(self_pos.z) > 9.5:
		evade_target += center_pull.normalized() * 5.0

	# ── Survival Skills: Seek cover behind maze walls when low HP or under fire ──
	if _health_ratio(ai_player_id) < 0.45 or _hurt_timer > 0.0:
		var cover_pos := _find_best_cover_3d(self_pos)
		if cover_pos != Vector3.ZERO:
			evade_target = cover_pos
	
	# Mix in some perpendicular movement (dodging)
	var perp := Vector3(-away.z, 0.0, away.x)
	var dodge := sin(Time.get_ticks_msec() * 0.004 + _orbit_angle)
	evade_target += perp * dodge * (4.5 if ai_difficulty == 2 else 3.0)
	
	var nav_dir = _get_nav_dir(Vector2(self_pos.x, self_pos.z), Vector2(evade_target.x, evade_target.z))
	_virt_move = nav_dir
	_ai_cam_yaw = atan2(nav_dir.x, nav_dir.y)

	if ai_player_id == 2 and not GameManager.is_armed(2):
		_maybe_plant_clone_3d(evade_target)

	if abs(dodge) > 0.75 and randf() < (0.08 if ai_difficulty == 2 else 0.04):
		_virt_jump = true


func _find_best_cover_3d(self_pos: Vector3) -> Vector3:
	var nodes := [
		Vector3(-10, 0.9, -10), Vector3(-10, 0.9, 10),
		Vector3(10, 0.9, -10), Vector3(10, 0.9, 10),
		Vector3(-4, 0.9, -8), Vector3(4, 0.9, 8)
	]
	var best_pos := Vector3.ZERO
	var best_dist := INF
	if not is_instance_valid(_enemy_3d):
		return best_pos

	var space := _body_3d.get_world_3d().direct_space_state
	var enemy_head := _enemy_3d.global_position + Vector3.UP * 1.2

	for n in nodes:
		var query := PhysicsRayQueryParameters3D.create(enemy_head, n)
		query.exclude = [_enemy_3d.get_rid(), _body_3d.get_rid()]
		var hit := space.intersect_ray(query)
		# If ray intersects a wall, node 'n' is behind cover!
		if not hit.is_empty():
			var d := self_pos.distance_to(n)
			if d < best_dist:
				best_dist = d
				best_pos = n
	return best_pos


func _maybe_plant_clone_3d(preferred_pos: Vector3) -> void:
	if _clone_timer > 0.0 or _valid_blue_clones().size() >= 5:
		return
	var pos := preferred_pos
	pos.x = clampf(pos.x, -11.0, 11.0)
	pos.z = clampf(pos.z, -11.0, 11.0)
	pos.y = 0.9
	# Do not stack clones too tightly. They are escape anchors, not decorations.
	for c in _valid_blue_clones():
		if c.global_position.distance_to(pos) < 3.0:
			return
	_virt_clone_pos = pos
	_clone_timer = 5.0 if ai_difficulty == 2 else 8.0


func _should_body_hop_3d(dist: float) -> bool:
	if ai_player_id != 2 or GameManager.is_armed(2) or _body_hop_timer > 0.0:
		return false
	var clones: Array = _valid_blue_clones()
	if clones.is_empty():
		return false
	var hidden := not _has_line_of_sight_3d()
	var low_health := _health_ratio(2) < 0.45
	return hidden and (dist < 18.0 or low_health)


func _ai_3d_body_hop() -> void:
	var best_clone = null
	var best_score := -INF
	for c in _valid_blue_clones():
		var cpos: Vector3 = c.global_position
		var red_dist := cpos.distance_to(_enemy_3d.global_position)
		var self_gain := cpos.distance_to(_body_3d.global_position)
		var score := red_dist + self_gain * 0.35
		if _is_clone_hidden_from_enemy(c):
			score += 10.0
		if score > best_score:
			best_score = score
			best_clone = c
	if best_clone != null:
		_virt_body_hop = int(best_clone.get("clone_number"))
		_body_hop_timer = 4.0


func _valid_blue_clones() -> Array:
	var clones: Array = []
	for c in get_tree().get_nodes_in_group("p2_body_3d"):
		if c == _body_3d:
			continue
		if not is_instance_valid(c):
			continue
		if bool(c.get("is_idle_clone")) and int(c.get("clone_number")) > 0:
			clones.append(c)
	return clones


func _is_clone_hidden_from_enemy(clone: Node3D) -> bool:
	if not is_instance_valid(clone) or not is_instance_valid(_enemy_3d):
		return false
	var space := clone.get_world_3d().direct_space_state
	var from := _enemy_3d.global_position + Vector3.UP * 1.2
	var to := clone.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_enemy_3d.get_rid(), clone.get_rid()]
	var hit := space.intersect_ray(query)
	return not hit.is_empty()


func _health_ratio(player_id: int) -> float:
	if not is_instance_valid(GameManager):
		return 1.0
	var max_health: float = maxf(float(GameManager.max_health), 1.0)
	return clampf(float(GameManager.get_health(player_id)) / max_health, 0.0, 1.0)


func _aim_and_fire_3d() -> void:
	if not is_instance_valid(_enemy_3d):
		return
	var self_pos  := _body_3d.global_position + Vector3.UP * 1.2
	var enemy_pos := _enemy_3d.global_position + Vector3.UP * 0.9

	var dist := self_pos.distance_to(enemy_pos)

	# Dynamic Weapon Selection. Rifle is the DPS king at every range (140 vs 80
	# pistol / 75 shotgun), and every switch costs 0.3s of dead time — so commit
	# to a choice instead of re-picking each shot. Shotgun only inside knife
	# range, where its 60-damage burst lands before the rifle can ramp.
	# C4 is never selected: the AI cannot detonate it (KEY_G is human-only) and
	# its own blast does ~33 damage back at 5m.
	if _weapon_commit_timer <= 0.0:
		var want_weapon := 2 if dist < 5.0 else 1
		if want_weapon != _selected_weapon_3d:
			_selected_weapon_3d = want_weapon
			_weapon_commit_timer = 2.0

	# Weapons are hitscan, so aim at where the enemy is now — leading the target
	# would place every shot ahead of them.
	var spread: float = deg_to_rad(AIM_SPREAD[ai_difficulty])
	var dir    := (enemy_pos - self_pos).normalized()
	dir = dir.rotated(Vector3.UP,    randf_range(-spread, spread) * 0.4)
	dir = dir.rotated(Vector3.RIGHT, randf_range(-spread, spread) * 0.25)
	dir = dir.normalized()

	_virt_aim_dir_3d = dir
	_virt_fire       = true
	_react_timer     = REACT_DELAY[ai_difficulty]


# ══════════════════════════════════════════════════════════════════════════════
# 2-D BRAIN  (State B — Blue is hunter/assassin)
# ══════════════════════════════════════════════════════════════════════════════
func _tick_2d(delta: float) -> void:
	if not is_instance_valid(_body_2d) or not is_instance_valid(_enemy_2d):
		_zero_virtual_inputs()
		return
	if _body_2d.get("_is_dead"):
		# AI itself is dead — stop all inputs and clear navigation state.
		_zero_virtual_inputs()
		_tactical_path_2d.clear()
		return
	if _enemy_2d.get("_is_dead"):
		# Target is dead / respawning — freeze in place, clear path, wait.
		_zero_virtual_inputs()
		_tactical_path_2d.clear()
		_replan_timer_2d = 1.5  # wait 1.5s before re-evaluating after kill
		_last_los_state = false
		return

	if _tactical_graph_2d == null:
		var graph_script := load("res://Scripts/TacticalGraph2D.gd") as GDScript
		if graph_script:
			_tactical_graph_2d = graph_script.new()
			_tactical_graph_2d.build_graph(_body_2d.get_world_2d().direct_space_state)

	_replan_timer_2d -= delta
	_path_age_2d += delta
	var self_pos: Vector2  = _body_2d.global_position
	var enemy_pos: Vector2 = _enemy_2d.global_position
	var to_enemy: Vector2  = enemy_pos - self_pos
	var dist: float        = to_enemy.length()

	var space := _body_2d.get_world_2d().direct_space_state
	var has_los := _has_line_of_sight_2d()

	# Build GOAP Belief State
	var beliefs := {
		"has_los": has_los,
		"is_on_wall": _body_2d.is_on_wall(),
		"is_on_ceiling": _body_2d.is_on_ceiling(),
		"is_on_floor": _body_2d.is_on_floor(),
		"stuck": _stuck_2d_timer > 0.25,
		"target_dist": dist,
		"health_ratio": _health_ratio(ai_player_id),
		"target_dead": _enemy_2d.get("_is_dead") == true
	}

	# Replan if: path empty, enemy moved >90px, or LOS flipped — but give path at
	# least 0.60s of life so Age grows and we don't spam the evaluator.
	var should_replan := _tactical_path_2d.is_empty() \
		or (_replan_timer_2d <= 0.0 \
			and (enemy_pos.distance_to(_last_target_enemy_pos) > 90.0 \
				or has_los != _last_los_state))
	if should_replan:
		_replan_timer_2d = 0.60   # 600ms commitment window (was 250ms)
		_last_target_enemy_pos = enemy_pos
		_last_los_state = has_los
		_active_goal_2d = GOAPPlanner2D.evaluate_best_goal(beliefs)

		# Goal-aware node selection with hysteresis
		var eval_result: Dictionary = TacticalEvaluator2D.select_best_attack_node(
			_tactical_graph_2d, self_pos, enemy_pos, space,
			_body_2d.get_rid(), _enemy_2d.get_rid(),
			_active_goal_2d,
			_target_attack_node_id,
			_current_node_score
		)
		var new_node_id: int = eval_result.get("id", -1)
		var new_score: float = eval_result.get("score", -999999.0)

		if _traversal_executor_2d == null:
			var exec_script := load("res://Scripts/TraversalExecutor2D.gd") as GDScript
			if exec_script:
				_traversal_executor_2d = exec_script.new()

		# Only change the tactical node (and recompute path) when the evaluator
		# actually selected a DIFFERENT node after beating the hysteresis threshold.
		if new_node_id != _target_attack_node_id and new_node_id != -1 and _tactical_graph_2d != null:
			_target_attack_node_id = new_node_id
			_current_node_score    = new_score
			_path_age_2d = 0.0    # path genuinely changed — reset age
			var path_res = _tactical_graph_2d.call("get_smoothed_path_positions", self_pos, _target_attack_node_id, space)
			if path_res is Array and not path_res.is_empty():
				_tactical_path_2d = path_res

			var edges_res = _tactical_graph_2d.call("get_traversal_edges", self_pos, _target_attack_node_id, space)
			if edges_res is Array and not edges_res.is_empty():
				_traversal_edges_2d = edges_res
				if _traversal_executor_2d != null:
					_traversal_executor_2d.call("start_edge", _traversal_edges_2d[0], self_pos)

			if (_tactical_path_2d.size() <= 1) and not has_los:
				var enemy_node: int = _tactical_graph_2d.call("get_nearest_node_id", enemy_pos)
				if enemy_node != -1 and enemy_node != _target_attack_node_id:
					var enemy_path = _tactical_graph_2d.call("get_smoothed_path_positions", self_pos, enemy_node, space)
					if enemy_path is Array and not enemy_path.is_empty():
						_tactical_path_2d = enemy_path
			# Log only when node actually changed
			var ai_tag_ev := "RED 2D AI" if ai_player_id == 1 else "BLUE 2D AI"
			var goal_names_ev: Array[String] = ["ELIMINATE", "GAIN_LOS", "FLANK", "UNSTICK", "TARGET_DEAD"]
			var goal_str_ev: String = goal_names_ev[_active_goal_2d] if _active_goal_2d >= 0 and _active_goal_2d < goal_names_ev.size() else "?"
			var state_names_ev: Array[String] = ["SEEK", "STRAFE", "EVADE", "BODY_HOP", "GRAPPLE"]
			var state_str_ev: String = state_names_ev[_state] if _state >= 0 and _state < state_names_ev.size() else "?"
			var dist_to_wp_ev: float = 0.0
			if not _tactical_path_2d.is_empty():
				dist_to_wp_ev = self_pos.distance_to(_tactical_path_2d[0])
			print("[%s] ► Goal:%s | State:%s | Node:%d(score:%.0f) | Path:%d | LOS:%s | DWP:%.0f | DE:%.0f | Age:%.2fs" % [
				ai_tag_ev, goal_str_ev, state_str_ev, _target_attack_node_id, _current_node_score,
				_tactical_path_2d.size(), has_los, dist_to_wp_ev, dist, _path_age_2d
			])
		else:
			# Same node kept — still log periodically so user sees Age growing
			if int(_path_age_2d * 10.0) % 10 == 0 and _path_age_2d > 0.05:
				var ai_tag_ev := "RED 2D AI" if ai_player_id == 1 else "BLUE 2D AI"
				var goal_names_ev: Array[String] = ["ELIMINATE", "GAIN_LOS", "FLANK", "UNSTICK", "TARGET_DEAD"]
				var goal_str_ev: String = goal_names_ev[_active_goal_2d] if _active_goal_2d >= 0 and _active_goal_2d < goal_names_ev.size() else "?"
				var dist_to_wp_ev: float = 0.0
				if not _tactical_path_2d.is_empty():
					dist_to_wp_ev = self_pos.distance_to(_tactical_path_2d[0])
				print("[%s] — Goal:%s | Node:%d(held) | Path:%d | LOS:%s | DWP:%.0f | DE:%.0f | Age:%.2fs" % [
					ai_tag_ev, goal_str_ev, _target_attack_node_id,
					_tactical_path_2d.size(), has_los, dist_to_wp_ev, dist, _path_age_2d
				])



	var is_ai_armed: bool = GameManager.is_armed(ai_player_id) if is_instance_valid(GameManager) else (ai_player_id == 2)

	# ── State selection ───────────────────────────────────────────────────────
	# IMMEDIATE override: if GOAP says attack and we have LOS, snap to STRAFE
	# NOW without waiting for _decision_timer — this is the bug fix for Goal:0
	# + still navigating instead of strafing.
	if is_ai_armed and _active_goal_2d == GOAPPlanner2D.GoalType.ELIMINATE_TARGET and has_los:
		_state = AIState.STRAFE
		_tactical_path_2d.clear() # Drop nav path — switch to combat movement
	elif _decision_timer <= 0.0:
		_decision_timer = DECISION_RATE[ai_difficulty]
		if is_ai_armed:
			_state = AIState.STRAFE if dist < 560.0 and _has_line_of_sight_2d() else AIState.SEEK
		else:
			if (dist < 420.0 or _health_ratio(ai_player_id) < 0.5) and _grapple_timer <= 0.0 and ai_player_id == 1:
				_state = AIState.GRAPPLE
			else:
				_state = AIState.EVADE

	if _strafe_timer <= 0.0:
		_strafe_timer = STRAFE_PERIOD[ai_difficulty]
		_strafe_dir   = -_strafe_dir

	match _state:
		AIState.SEEK:
			_ai_2d_seek(to_enemy, enemy_pos)
		AIState.STRAFE:
			_ai_2d_strafe(to_enemy, dist, enemy_pos)
		AIState.EVADE:
			_ai_2d_evade(to_enemy)
		AIState.GRAPPLE:
			_ai_2d_grapple_escape(to_enemy)



func _ai_2d_seek(to_enemy: Vector2, enemy_pos: Vector2) -> void:
	if not is_instance_valid(_body_2d):
		return

	var self_pos := _body_2d.global_position
	var nav_dir := _get_nav_dir_2d(self_pos, enemy_pos)

	_virt_move = _apply_surface_frame_2d(nav_dir, to_enemy)
	_virt_mouse_world = _predict_enemy_2d(enemy_pos)

	var is_ai_armed: bool = GameManager.is_armed(ai_player_id) if is_instance_valid(GameManager) else true
	if is_ai_armed and _react_timer <= 0.0 and _has_line_of_sight_2d():
		_virt_fire   = true
		_react_timer = REACT_DELAY[ai_difficulty]


func _ai_2d_strafe(to_enemy: Vector2, dist: float, enemy_pos: Vector2) -> void:
	var ideal_dist := 330.0 if ai_difficulty == 2 else 260.0
	if _health_ratio(ai_player_id) < 0.35:
		ideal_dist += 130.0
	var dist_err   := dist - ideal_dist
	_virt_move.x   = _strafe_dir

	if dist_err > 120.0:
		_virt_move.x = sign(to_enemy.x)
	elif dist_err < -100.0:
		_virt_move.x = -sign(to_enemy.x)
	_virt_move.y = sign(to_enemy.y) if abs(to_enemy.y) > 140.0 else 0.0
	if _virt_move.length_squared() > 1.0:
		_virt_move = _virt_move.normalized()
	_virt_move = _apply_surface_frame_2d(_virt_move, to_enemy)

	_virt_mouse_world = _predict_enemy_2d(enemy_pos)

	if randf() < (0.004 if ai_difficulty == 2 else 0.002):
		_virt_jump = true

	var is_ai_armed: bool = GameManager.is_armed(ai_player_id) if is_instance_valid(GameManager) else true
	if is_ai_armed and _react_timer <= 0.0 and _has_line_of_sight_2d():
		_virt_fire   = true
		_react_timer = REACT_DELAY[ai_difficulty]


func _ai_2d_evade(to_enemy: Vector2) -> void:
	var away := -to_enemy
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT
	_virt_move = away.normalized()
	# Prefer climbing up/onto walls in 2D to break the assassin's direct shot.
	if to_enemy.length() < 360.0:
		_virt_move.y = -1.0
		_virt_move = _virt_move.normalized()
	var dodge := sin(Time.get_ticks_msec() * 0.004)
	if abs(dodge) > 0.6:
		_virt_jump = true
	# Climb away from the enemy when wall-mounted; move.x would be discarded.
	if _is_wall_mounted_2d():
		_virt_move.y = -signf(to_enemy.y) if absf(to_enemy.y) > 40.0 else -1.0
	_virt_mouse_world = _body_2d.global_position + to_enemy.normalized() * 200.0


func _ai_2d_grapple_escape(to_enemy: Vector2) -> void:
	_ai_2d_evade(to_enemy)
	if ai_player_id != 1 or GameManager.is_armed(1):
		return
	# Red is the 2D victim. Grapple is a two-press action: first opens the reticle,
	# second fires it. Read the player's grapple state so the AI can respond correctly.
	var grapple_state: int = int(_body_2d.get("_grapple_state")) if is_instance_valid(_body_2d) else 0
	if (grapple_state == 0 or grapple_state == 1) and _grapple_timer <= 0.0:
		_virt_grapple = true
		_grapple_timer = 1.4
	# Bias reticle steering upward and away from the assassin so escapes choose walls/ceiling.
	var x_dir: float = -signf(to_enemy.x)
	if x_dir == 0.0:
		x_dir = _strafe_dir
	_virt_move = Vector2(x_dir, -1.0).normalized()


func _smart_2d_move_toward(to_enemy: Vector2) -> Vector2:
	if is_instance_valid(_body_2d) and is_instance_valid(_enemy_2d) and not _has_line_of_sight_2d():
		var astar_dir := _get_nav_dir_2d(_body_2d.global_position, _enemy_2d.global_position)
		if astar_dir.length_squared() > 0.01:
			return _apply_surface_frame_2d(astar_dir, to_enemy)

	var move := Vector2.ZERO
	move.x = signf(to_enemy.x)
	if move.x == 0.0:
		move.x = 1.0
	move.y = signf(to_enemy.y) if absf(to_enemy.y) > 40.0 else 0.0

	if is_instance_valid(_body_2d):
		if _body_2d.is_on_wall():
			move.x = -signf(to_enemy.x)
			if move.x == 0.0: move.x = -1.0
			move.y = -1.0
			_virt_jump = true
		elif _body_2d.is_on_ceiling() and absf(to_enemy.y) > 40.0:
			_virt_jump = true # Drop off ceiling!

	return _apply_surface_frame_2d(move.normalized(), to_enemy)


func _is_wall_mounted_2d() -> bool:
	# MoveState: 0=FLOOR 1=WALL_LEFT 2=WALL_RIGHT 3=CEILING 4=AIR 5=GRAPPLE
	if not is_instance_valid(_body_2d):
		return false
	var st: int = int(_body_2d.get("_current_state"))
	return st == 1 or st == 2


func _apply_surface_frame_2d(move: Vector2, to_enemy: Vector2) -> Vector2:
	# On a wall the body ignores move.x entirely (it is overwritten by the
	# wall-stick velocity), so horizontal intent has to become vertical climb.
	if _is_wall_mounted_2d():
		if absf(move.y) > 0.05:
			return move
		var climb: float = signf(to_enemy.y)
		if climb == 0.0:
			climb = -1.0
		return Vector2(move.x, climb)
	return move


func _has_line_of_sight_2d() -> bool:
	if not is_instance_valid(_body_2d) or not is_instance_valid(_enemy_2d):
		return false
	return _is_path_clear_2d(_body_2d.global_position, _enemy_2d.global_position)


func _predict_enemy_2d(enemy_pos: Vector2) -> Vector2:
	if not is_instance_valid(_enemy_2d):
		return enemy_pos
	# 2D fire is a hitscan raycast, so there is no travel time to lead.
	var spread: float = AIM_SPREAD[ai_difficulty]
	return enemy_pos + Vector2(
		randf_range(-spread * 3.0, spread * 3.0),
		randf_range(-spread * 2.0, spread * 2.0))


func _find_best_2d_shelf_route(self_pos: Vector2, enemy_pos: Vector2) -> float:
	if not is_instance_valid(_body_2d):
		return -1.0 if enemy_pos.x < self_pos.x else 1.0

	var space := _body_2d.get_world_2d().direct_space_state
	var left_drop_x: float = -9999.0
	var right_drop_x: float = 9999.0

	# Scan left for drop edge (downward raycast missing floor)
	for step in range(20, 500, 25):
		var test_pos := self_pos + Vector2(-step, 5.0)
		var ray_end  := self_pos + Vector2(-step, 50.0)
		var q := PhysicsRayQueryParameters2D.create(test_pos, ray_end)
		q.exclude = [_body_2d.get_rid()]
		if space.intersect_ray(q).is_empty():
			left_drop_x = self_pos.x - step
			break

	# Scan right for drop edge
	for step in range(20, 500, 25):
		var test_pos := self_pos + Vector2(step, 5.0)
		var ray_end  := self_pos + Vector2(step, 50.0)
		var q := PhysicsRayQueryParameters2D.create(test_pos, ray_end)
		q.exclude = [_body_2d.get_rid()]
		if space.intersect_ray(q).is_empty():
			right_drop_x = self_pos.x + step
			break

	var dist_left  := absf(self_pos.x - left_drop_x)  + absf(left_drop_x - enemy_pos.x)  if left_drop_x > -9000.0 else 99999.0
	var dist_right := absf(self_pos.x - right_drop_x) + absf(right_drop_x - enemy_pos.x) if right_drop_x < 9000.0  else 99999.0

	if dist_left < dist_right:
		return -1.0 # Route Left!
	elif dist_right < dist_left:
		return 1.0  # Route Right!
	else:
		return -1.0 if enemy_pos.x < self_pos.x else 1.0
