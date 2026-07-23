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

# ── Difficulty tuning tables ───────────────────────────────────────────────────
const REACT_DELAY    := [0.55, 0.28, 0.05]   # seconds before acting
const AIM_SPREAD     := [18.0, 7.0, 1.5]     # degrees of aim randomness
const STRAFE_PERIOD  := [2.0,  1.4, 0.8]     # how often strafe direction flips
const DECISION_RATE  := [0.7,  0.45, 0.2]    # how often AI re-picks a state

# ── Virtual input state (read by hooked player scripts each frame) ─────────────
var _virt_move: Vector2 = Vector2.ZERO
var _virt_fire: bool = false
var _virt_jump: bool = false
var _virt_grapple: bool = false
var _virt_body_hop: int = 0
var _virt_clone_pos = null
var _virt_mouse_world: Vector2 = Vector2.ZERO  # 2D aim target
var _virt_aim_dir_3d: Vector3 = Vector3.FORWARD # 3D aim direction

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
		"aim_dir": _virt_aim_dir_3d,
		"cam_yaw": _ai_cam_yaw,
		"body_hop": _virt_body_hop,
		"implant_clone": _virt_clone_pos,
	}


func replace_body_3d(new_body: CharacterBody3D) -> void:
	# Called by Player3D after a successful Blue body-hop. Without this, the AI
	# would keep issuing input to the abandoned idle body.
	_body_3d = new_body


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
	# Build waypoint graph (scaled to 3D coords, 2D will multiply/divide by 32)
	var nodes := [
		Vector2(-10, -10), Vector2(-10, 0), Vector2(-10, 10),
		Vector2(0, -8), Vector2(0, 8),
		Vector2(10, -10), Vector2(10, 0), Vector2(10, 10),
		Vector2(-4, -8), Vector2(4, 8)
	]
	for i in nodes.size():
		_astar.add_point(i, nodes[i])
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if _is_path_clear(nodes[i], nodes[j]):
				_astar.connect_points(i, j)

func _is_path_clear(from: Vector2, to: Vector2) -> bool:
	for w in MAZE_WALLS:
		if Geometry2D.segment_intersects_segment(from, to, w[0], w[1]) != null:
			return false
	return true

func _get_nav_dir(self_pos: Vector2, target_pos: Vector2) -> Vector2:
	if _is_path_clear(self_pos, target_pos):
		return (target_pos - self_pos).normalized()
		
	var id_s = 100
	var id_t = 101
	_astar.add_point(id_s, self_pos)
	_astar.add_point(id_t, target_pos)
	
	for i in _astar.get_point_ids():
		if i == id_s or i == id_t: continue
		if _is_path_clear(self_pos, _astar.get_point_position(i)):
			_astar.connect_points(id_s, i)
		if _is_path_clear(target_pos, _astar.get_point_position(i)):
			_astar.connect_points(id_t, i)
			
	var path = _astar.get_point_path(id_s, id_t)
	var dir = (target_pos - self_pos).normalized()
	if path.size() > 1:
		dir = (path[1] - self_pos).normalized()
		
	_astar.remove_point(id_s)
	_astar.remove_point(id_t)
	return dir

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

	# ── State selection ───────────────────────────────────────────────────────
	if _decision_timer <= 0.0:
		_decision_timer = DECISION_RATE[ai_difficulty]
		if ai_player_id == 1:
			# Red is hunter in 3D
			_state = AIState.STRAFE if dist < 14.0 and _has_line_of_sight_3d() else AIState.SEEK
		else:
			# Blue is unarmed in 3D: evade, and body-hop when exposed or hurt.
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
	var nav_dir = _get_nav_dir(Vector2(self_pos.x, self_pos.z), Vector2(target_pos.x, target_pos.z))
	
	_virt_move    = nav_dir
	_ai_cam_yaw   = atan2(nav_dir.x, nav_dir.y)

	if ai_player_id == 1 and dist < 22.0 and GameManager.is_armed(1):
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

	if ai_player_id == 1 and GameManager.is_armed(1) and _react_timer <= 0.0 and _has_line_of_sight_3d():
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
	var self_pos = _body_3d.global_position
	var away := -to_enemy
	away.y = 0.0
	if away.length_squared() > 0.01:
		away = away.normalized()
	else:
		away = Vector3.FORWARD
		
	# Compute an evade target away from Red, biased toward the map center when near edges.
	var evade_target = self_pos + away * (7.0 if ai_difficulty == 2 else 5.0)
	var center_pull := Vector3.ZERO - self_pos
	center_pull.y = 0.0
	if absf(self_pos.x) > 9.5 or absf(self_pos.z) > 9.5:
		evade_target += center_pull.normalized() * 4.0
	
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

	var spread: float = deg_to_rad(AIM_SPREAD[ai_difficulty])
	var dir    := (enemy_pos - self_pos).normalized()
	dir = dir.rotated(Vector3.UP,    randf_range(-spread, spread) * 0.5)
	dir = dir.rotated(Vector3.RIGHT, randf_range(-spread, spread) * 0.3)
	dir = dir.normalized()

	_virt_aim_dir_3d = dir   # ← correct var name (was wrong in earlier draft)
	_virt_fire       = true
	_react_timer     = REACT_DELAY[ai_difficulty]


# ══════════════════════════════════════════════════════════════════════════════
# 2-D BRAIN  (State B — Blue is hunter/assassin)
# ══════════════════════════════════════════════════════════════════════════════
func _tick_2d(_delta: float) -> void:
	if not is_instance_valid(_body_2d) or not is_instance_valid(_enemy_2d):
		return
	if _body_2d.get("_is_dead") or _enemy_2d.get("_is_dead"):
		return

	var self_pos: Vector2  = _body_2d.global_position
	var enemy_pos: Vector2 = _enemy_2d.global_position
	var to_enemy: Vector2  = enemy_pos - self_pos
	var dist: float        = to_enemy.length()

	# ── State selection ───────────────────────────────────────────────────────
	if _decision_timer <= 0.0:
		_decision_timer = DECISION_RATE[ai_difficulty]
		if ai_player_id == 2:
			# Blue assassin: close distance when blocked/far, kite at pistol range.
			_state = AIState.STRAFE if dist < 560.0 and _has_line_of_sight_2d() else AIState.SEEK
		else:
			# Red unarmed in 2D — evade
			if (dist < 420.0 or _health_ratio(1) < 0.5) and _grapple_timer <= 0.0:
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
	_virt_move = _smart_2d_move_toward(to_enemy)
	_virt_mouse_world = _predict_enemy_2d(enemy_pos)
	if ai_player_id == 2 and GameManager.is_armed(2) and _react_timer <= 0.0 and _has_line_of_sight_2d():
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

	_virt_mouse_world = _predict_enemy_2d(enemy_pos)

	if randf() < (0.004 if ai_difficulty == 2 else 0.002):
		_virt_jump = true

	if ai_player_id == 2 and GameManager.is_armed(2) and _react_timer <= 0.0 and _has_line_of_sight_2d():
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
	var x_dir := -sign(to_enemy.x)
	if x_dir == 0.0:
		x_dir = _strafe_dir
	_virt_move = Vector2(x_dir, -1.0).normalized()


func _smart_2d_move_toward(to_enemy: Vector2) -> Vector2:
	var move := Vector2.ZERO
	move.x = sign(to_enemy.x) if abs(to_enemy.x) > 35.0 else 0.0
	move.y = sign(to_enemy.y) if abs(to_enemy.y) > 90.0 else 0.0
	if move == Vector2.ZERO:
		move.x = _strafe_dir
	return move.normalized()


func _has_line_of_sight_2d() -> bool:
	if not is_instance_valid(_body_2d) or not is_instance_valid(_enemy_2d):
		return false
	var space := _body_2d.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_body_2d.global_position, _enemy_2d.global_position)
	query.exclude = [_body_2d.get_rid(), _enemy_2d.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _predict_enemy_2d(enemy_pos: Vector2) -> Vector2:
	if not is_instance_valid(_enemy_2d):
		return enemy_pos
	var lead_time: float = REACT_DELAY[ai_difficulty] * 0.5
	var predicted: Vector2 = enemy_pos + _enemy_2d.velocity * lead_time
	var spread: float = AIM_SPREAD[ai_difficulty]
	predicted += Vector2(
		randf_range(-spread * 3.0, spread * 3.0),
		randf_range(-spread * 2.0, spread * 2.0))
	return predicted
