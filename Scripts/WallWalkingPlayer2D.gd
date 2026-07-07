extends CharacterBody2D
## WallWalkingPlayer2D.gd — a fighter in State B (2D Wall-Walk cross-section).
## Fully upgraded to use a procedural 2D Stickman!

@export var player_id: int = 2
@export var is_assassin: bool = false
@export var speed: float = 220.0
@export var gravity: float = 980.0
@export var jump_force: float = 520.0
@export var rotation_speed: float = 10.0
@export var probe_length: float = 60.0
@export var climb_speed_mult: float = 0.75

@export_group("Weapon")
@export var damage: float = 22.0
@export var fire_cooldown: float = 0.5
@export var weapon_range: float = 1200.0

var surface_normal: Vector2 = Vector2.UP
var _cd: float = 0.0
var _gun: Line2D
var _was_on_floor := true
var _recoil_vel := Vector2.ZERO

var _is_dead := false
var _has_won := false
var _is_shooting := false

# Realistic Movement States
enum MoveState { FLOOR, WALL_LEFT, WALL_RIGHT, CEILING, AIR }
var _current_state := MoveState.AIR

# Pose IDs
const POSE_IDLE     := 1
const POSE_CROUCH   := 2
const POSE_WALK     := 3
const POSE_RUN      := 4
const POSE_COMBAT   := 5
const POSE_VICTORY  := 6
const POSE_JUMP       := 7
const POSE_DEATH      := 8
const POSE_CLIMB      := 9
const POSE_MONKEY_BAR := 10

# Shadow-warrior silhouette parts: a near-black core with a glowing team-coloured rim.
var _visuals: Node2D
var _skeleton: Node2D
var _head_glow: Polygon2D
var _head_core: Polygon2D
var _eye: Polygon2D
var _limb_glow: Dictionary = {}     # name -> Line2D (wide, team colour, low alpha = rim)
var _limb_core: Dictionary = {}     # name -> Line2D (near-black silhouette)

var _team_color: Color = Color.WHITE
const CORE_COLOR := Color(0.02, 0.02, 0.05)
const LIMB_NAMES := ["leg_l", "leg_r", "arm_l", "arm_r", "body"]
const LIMB_WIDTHS := {"body": 7.0, "arm_l": 4.0, "arm_r": 4.0, "leg_l": 5.0, "leg_r": 5.0}

var _ghost_t: float = 0.0

var _anim_time: float = 0.0
var _current_points: Dictionary = {}
var _target_points: Dictionary = {}
var _pt_names = ["head", "neck", "hip", "elbow_l", "hand_l", "elbow_r", "hand_r", "knee_l", "foot_l", "knee_r", "foot_r"]
var _facing_right: bool = true

@onready var _act_left: String = "p%d_left" % player_id
@onready var _act_right: String = "p%d_right" % player_id
@onready var _act_up: String = "p%d_up" % player_id
@onready var _act_down: String = "p%d_down" % player_id
@onready var _act_jump: String = "p%d_jump" % player_id
@onready var _act_fire: String = "p%d_fire" % player_id


func _ready() -> void:
	up_direction = Vector2.UP
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	add_to_group("p%d_body_2d" % player_id)
	
	# Cleanup default placeholders
	for child in get_children():
		if child is ColorRect:
			child.queue_free()

	_visuals = Node2D.new()
	add_child(_visuals)

	_setup_stickman()

	if GameManager:
		GameManager.player_died.connect(_on_player_died)
		GameManager.game_over.connect(_on_game_over)


func _setup_stickman() -> void:
	_skeleton = Node2D.new()
	_skeleton.position = Vector2(0, 30) # Pivot at feet
	_visuals.add_child(_skeleton)

	_team_color = Color(0.85, 0.15, 0.15) if player_id == 1 else Color(0.2, 0.5, 1.0)
	var glow_col := _team_color
	glow_col.a = 0.5

	# 1) Glow layer (added first = drawn behind): wide, team-coloured, translucent.
	#    It peeks out past the black core to read as a rim/aura — the Shadow-Fight look.
	for n in LIMB_NAMES:
		_limb_glow[n] = _make_line(glow_col, LIMB_WIDTHS[n] + 8.0)

	_head_glow = Polygon2D.new()
	_head_glow.color = glow_col
	_head_glow.polygon = _generate_circle(10.0, 20)
	_skeleton.add_child(_head_glow)

	# 2) Core layer (added after = drawn in front): the solid near-black silhouette.
	for n in LIMB_NAMES:
		_limb_core[n] = _make_line(CORE_COLOR, LIMB_WIDTHS[n])

	_head_core = Polygon2D.new()
	_head_core.color = CORE_COLOR
	_head_core.polygon = _generate_circle(6.5, 20)
	_skeleton.add_child(_head_core)

	# Faint team-coloured eye so facing still reads on the shadow.
	_eye = Polygon2D.new()
	_eye.color = Color(_team_color.r, _team_color.g, _team_color.b, 0.9)
	_eye.polygon = _generate_circle(1.8, 8)
	_eye.position = Vector2(3, -2)
	_head_core.add_child(_eye)

	# Gun — bright so the weapon pops against the shadow body.
	_gun = _make_line(Color(1.0, 0.7, 0.1), 4.0)
	_gun.points = [Vector2.ZERO, Vector2(20, 0)]

	for n in _pt_names:
		_current_points[n] = Vector2.ZERO
		_target_points[n] = Vector2.ZERO


func _make_line(col: Color, w: float) -> Line2D:
	var l = Line2D.new()
	l.default_color = col
	l.width = w
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	_skeleton.add_child(l)
	return l


static var _circle_cache: Dictionary = {}

func _generate_circle(radius: float, segments: int) -> PackedVector2Array:
	var key = "%f_%d" % [radius, segments]
	if _circle_cache.has(key):
		return _circle_cache[key]
	var pts := PackedVector2Array()
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	_circle_cache[key] = pts
	return pts


func _on_player_died(dead_id: int) -> void:
	if dead_id == player_id:
		_is_dead = true


func _on_game_over(winner_id: int) -> void:
	if winner_id == player_id:
		_has_won = true


func _physics_process(delta: float) -> void:
	if _cd > 0.0:
		_cd -= delta

	# --- Squash & Stretch ---
	if _skeleton:
		_skeleton.scale = _skeleton.scale.lerp(Vector2.ONE, 12.0 * delta)

	if not _was_on_floor and is_on_floor() and not _is_dead:
		if _skeleton:
			_skeleton.scale = Vector2(1.4, 0.6)
	
	_was_on_floor = is_on_floor()

	if _is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 1200 * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		_animate_stickman(delta, 0.0, false, false)
		return

	var input_x = Input.get_axis(_act_left, _act_right)
	var input_y = Input.get_axis(_act_up, _act_down)
	var is_running := Input.is_key_pressed(KEY_SHIFT) if player_id == 1 else Input.is_key_pressed(KEY_CTRL)
	var is_crouching := Input.is_action_pressed(_act_down)
	
	var current_speed: float = speed * (1.5 if is_running else 1.0)
	if is_crouching:
		current_speed = speed * 0.5
		
	_determine_state()
	
	# Apply state-based velocity & visual rotation
	var target_rotation: float = 0.0
	var move_intensity: float = 0.0

	if _current_state == MoveState.FLOOR:
		velocity.x = input_x * current_speed
		velocity.y += gravity * delta
		target_rotation = 0.0
		move_intensity = input_x
		
		if Input.is_action_just_pressed(_act_jump) and not _is_dead:
			velocity.y = -jump_force
			if _skeleton: _skeleton.scale = Vector2(0.6, 1.4)

	elif _current_state == MoveState.WALL_LEFT or _current_state == MoveState.WALL_RIGHT:
		# Climbing Up/Down
		velocity.y = input_y * current_speed * climb_speed_mult
		
		# Stick to wall by pushing slightly into it
		var wall_dir = -1.0 if _current_state == MoveState.WALL_LEFT else 1.0
		velocity.x = wall_dir * 50.0 
		
		target_rotation = PI / 2.0 if _current_state == MoveState.WALL_LEFT else -PI / 2.0
		move_intensity = input_y
		
		# Jump off the wall
		if Input.is_action_just_pressed(_act_jump) and not _is_dead:
			velocity.y = -jump_force * 0.8
			velocity.x = -wall_dir * jump_force * 0.6
			_current_state = MoveState.AIR
			if _skeleton: _skeleton.scale = Vector2(0.6, 1.4)

	elif _current_state == MoveState.CEILING:
		# Monkey-bar Left/Right
		velocity.x = input_x * current_speed * climb_speed_mult
		velocity.y = -50.0 # Stick to ceiling
		target_rotation = PI
		move_intensity = input_x
		
		# Drop down
		if input_y > 0.5 or Input.is_action_just_pressed(_act_jump):
			velocity.y = 100.0
			_current_state = MoveState.AIR

	elif _current_state == MoveState.AIR:
		# Aerial control and global gravity
		velocity.x = move_toward(velocity.x, input_x * current_speed, 1200 * delta)
		velocity.y += gravity * delta
		target_rotation = 0.0

	_recoil_vel = _recoil_vel.lerp(Vector2.ZERO, 3.0 * delta)
	velocity += _recoil_vel

	# Align the whole silhouette to the current surface (floor / wall / ceiling),
	# so the fighter visibly stands on walls and hangs from ceilings.
	if _visuals:
		_visuals.rotation = lerp_angle(_visuals.rotation, target_rotation, rotation_speed * delta)

	move_and_slide()
	
	_update_facing(move_intensity)
	_animate_stickman(delta, move_intensity, is_running, is_crouching)

	# --- Shadow after-image trail when moving fast (Shadow-Fight signature) ---
	_ghost_t -= delta
	var speed_ratio: float = velocity.length() / (speed * 1.5)
	if speed_ratio > 0.45 and _ghost_t <= 0.0 and not _is_dead:
		_ghost_t = 0.045
		_spawn_ghost()

	# --- Gun tracking and firing ---
	if _gun:
		if GameManager and GameManager.is_armed(player_id) and not _is_dead:
			_gun.visible = true
			var mouse_pos = get_global_mouse_position()
			var world_angle := (mouse_pos - global_position).angle()
			
			_gun.global_rotation = world_angle
			_gun.position = _current_points["hand_r"]
		else:
			_gun.visible = false

	if GameManager and GameManager.is_armed(player_id) and not _is_dead:
		if _cd <= 0.0 and (Input.is_action_just_pressed(_act_fire) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			_fire()


func _determine_state() -> void:
	if _is_dead:
		_current_state = MoveState.FLOOR
		return
		
	if is_on_floor():
		_current_state = MoveState.FLOOR
	elif is_on_wall():
		if get_wall_normal().x > 0:
			_current_state = MoveState.WALL_LEFT
		else:
			_current_state = MoveState.WALL_RIGHT
	elif is_on_ceiling():
		_current_state = MoveState.CEILING
	else:
		_current_state = MoveState.AIR


func _update_facing(move_dir: float) -> void:
	if _is_dead:
		return
	if GameManager and GameManager.is_armed(player_id):
		var mouse_pos = get_global_mouse_position()
		_facing_right = mouse_pos.x > global_position.x
	else:
		if _current_state == MoveState.WALL_LEFT:
			_facing_right = false
		elif _current_state == MoveState.WALL_RIGHT:
			_facing_right = true
		else:
			if move_dir > 0.1:
				_facing_right = true
			elif move_dir < -0.1:
				_facing_right = false


func _animate_stickman(delta: float, move_dir: float, is_running: bool, is_crouching: bool) -> void:
	var state = POSE_IDLE
	if _is_dead:
		state = POSE_DEATH
	elif _has_won:
		state = POSE_VICTORY
	else:
		if _current_state == MoveState.WALL_LEFT or _current_state == MoveState.WALL_RIGHT:
			state = POSE_CLIMB
		elif _current_state == MoveState.CEILING:
			state = POSE_MONKEY_BAR
		elif _current_state == MoveState.AIR:
			state = POSE_JUMP
		elif _is_shooting:
			state = POSE_COMBAT
		elif is_crouching and _current_state == MoveState.FLOOR:
			state = POSE_CROUCH
		elif abs(move_dir) > 0.1 and is_running:
			state = POSE_RUN
		elif abs(move_dir) > 0.1:
			state = POSE_WALK
		else:
			state = POSE_IDLE

	if state == POSE_WALK or state == POSE_RUN or state == POSE_CLIMB or state == POSE_MONKEY_BAR:
		_anim_time += delta * (15.0 if state == POSE_RUN else 8.0)
	else:
		_anim_time += delta * 3.0

	var tp = _target_points

	if state == POSE_IDLE:
		var breath = sin(_anim_time) * 1.5
		tp["head"] = Vector2(0, -55 + breath); tp["neck"] = Vector2(0, -45 + breath); tp["hip"] = Vector2(0, -25 + breath)
		tp["elbow_l"] = Vector2(-5, -35); tp["hand_l"] = Vector2(-8, -22)
		tp["elbow_r"] = Vector2(5, -35); tp["hand_r"] = Vector2(8, -22)
		tp["knee_l"] = Vector2(-4, -15); tp["foot_l"] = Vector2(-6, 0)
		tp["knee_r"] = Vector2(4, -15); tp["foot_r"] = Vector2(6, 0)

	elif state == POSE_WALK or state == POSE_RUN:
		var lean = 12.0 if state == POSE_RUN else 5.0
		tp["head"] = Vector2(lean, -55); tp["neck"] = Vector2(lean, -45); tp["hip"] = Vector2(lean * 0.5, -25)
		
		var s = sin(_anim_time)
		var c = cos(_anim_time)
		var stride = 20.0 if state == POSE_RUN else 12.0
		var lift = 12.0 if state == POSE_RUN else 6.0
		
		tp["knee_l"] = Vector2(-s * stride * 0.5, -15 - c * lift * 0.5)
		tp["foot_l"] = Vector2(-s * stride, -max(0, c) * lift)
		
		tp["knee_r"] = Vector2(s * stride * 0.5, -15 + c * lift * 0.5)
		tp["foot_r"] = Vector2(s * stride, -max(0, -c) * lift)
		
		var arm_sw = 15.0 if state == POSE_RUN else 8.0
		tp["elbow_l"] = Vector2(s * arm_sw * 0.6, -35 - abs(c)*2)
		tp["hand_l"] = Vector2(s * arm_sw, -25 - abs(c)*4)
		
		tp["elbow_r"] = Vector2(-s * arm_sw * 0.6, -35 - abs(c)*2)
		tp["hand_r"] = Vector2(-s * arm_sw, -25 - abs(c)*4)

	elif state == POSE_CLIMB:
		# Face the wall (+X in local orientation)
		tp["head"] = Vector2(5, -45); tp["neck"] = Vector2(0, -35); tp["hip"] = Vector2(-5, -20)
		var is_armed = GameManager and GameManager.is_armed(player_id)
		
		if move_dir != 0:
			var reach = sin(_anim_time * 8.0) * 15.0
			tp["hand_l"] = Vector2(10, -45 + reach)
			tp["elbow_l"] = Vector2(5, -40 + reach * 0.5)
			
			if is_armed:
				# Hold gun down and swing slightly while climbing
				tp["hand_r"] = Vector2(5, -20 + sin(_anim_time * 4.0) * 5.0)
				tp["elbow_r"] = Vector2(0, -25)
			else:
				tp["hand_r"] = Vector2(10, -45 - reach)
				tp["elbow_r"] = Vector2(5, -40 - reach * 0.5)
				
			tp["foot_l"] = Vector2(8, -10 - reach * 0.8)
			tp["foot_r"] = Vector2(8, -10 + reach * 0.8)
			tp["knee_l"] = Vector2(0, -15 - reach * 0.4)
			tp["knee_r"] = Vector2(0, -15 + reach * 0.4)
		else:
			tp["hand_l"] = Vector2(12, -45)
			tp["elbow_l"] = Vector2(5, -40)
			
			if is_armed:
				# Rest gun hand swinging slightly like holding a heavy gun
				tp["hand_r"] = Vector2(5, -20 + sin(_anim_time * 2.0) * 2.0)
				tp["elbow_r"] = Vector2(0, -25)
			else:
				tp["hand_r"] = Vector2(12, -35)
				tp["elbow_r"] = Vector2(5, -30)
				
			tp["foot_l"] = Vector2(10, -10); tp["foot_r"] = Vector2(10, 0)
			tp["knee_l"] = Vector2(2, -15); tp["knee_r"] = Vector2(2, -5)

	elif state == POSE_MONKEY_BAR:
		# Hanging from ceiling
		tp["head"] = Vector2(0, -35); tp["neck"] = Vector2(0, -25); tp["hip"] = Vector2(0, -10)
		var s = sin(_anim_time * 1.5)
		var c = cos(_anim_time * 1.5)
		
		if move_dir != 0:
			tp["hand_l"] = Vector2(5 + s * 10, -50); tp["hand_r"] = Vector2(5 - s * 10, -50)
			tp["elbow_l"] = Vector2(0 + s * 5, -40); tp["elbow_r"] = Vector2(0 - s * 5, -40)
			tp["foot_l"] = Vector2(-s * 5, 0 + c * 5); tp["foot_r"] = Vector2(s * 5, 0 - c * 5)
			tp["knee_l"] = Vector2(-s * 2, -5 + c * 2); tp["knee_r"] = Vector2(s * 2, -5 - c * 2)
		else:
			tp["hand_l"] = Vector2(5, -50); tp["hand_r"] = Vector2(-5, -50)
			tp["elbow_l"] = Vector2(2, -40); tp["elbow_r"] = Vector2(-2, -40)
			tp["foot_l"] = Vector2(3, 0); tp["foot_r"] = Vector2(-3, 0)
			tp["knee_l"] = Vector2(2, -5); tp["knee_r"] = Vector2(-2, -5)

	elif state == POSE_CROUCH:
		tp["head"] = Vector2(10, -35); tp["neck"] = Vector2(5, -30); tp["hip"] = Vector2(-5, -20)
		tp["hand_l"] = Vector2(5, -5); tp["elbow_l"] = Vector2(0, -15)
		tp["hand_r"] = Vector2(15, -5); tp["elbow_r"] = Vector2(10, -15)
		tp["foot_l"] = Vector2(-15, 0); tp["knee_l"] = Vector2(-15, -10)
		tp["foot_r"] = Vector2(5, 0); tp["knee_r"] = Vector2(10, -15)

	elif state == POSE_JUMP:
		tp["head"] = Vector2(10, -40); tp["neck"] = Vector2(0, -30); tp["hip"] = Vector2(-5, -15)
		tp["hand_l"] = Vector2(20, -50); tp["elbow_l"] = Vector2(10, -40)
		tp["hand_r"] = Vector2(15, -55); tp["elbow_r"] = Vector2(5, -45)
		tp["foot_l"] = Vector2(-15, -15); tp["knee_l"] = Vector2(-20, -20)
		tp["foot_r"] = Vector2(-5, -5); tp["knee_r"] = Vector2(-10, -15)

	elif state == POSE_COMBAT:
		tp["head"] = Vector2(5, -50); tp["neck"] = Vector2(0, -40); tp["hip"] = Vector2(-5, -25)
		# Right arm aims gun forward
		tp["elbow_r"] = Vector2(5, -35); tp["hand_r"] = Vector2(15, -35)
		# Left arm supports
		tp["elbow_l"] = Vector2(-2, -32); tp["hand_l"] = Vector2(8, -35)
		# Legs braced
		tp["foot_l"] = Vector2(-15, 0); tp["knee_l"] = Vector2(-15, -15)
		tp["foot_r"] = Vector2(15, 0); tp["knee_r"] = Vector2(10, -15)

	elif state == POSE_DEATH:
		tp["head"] = Vector2(15, -5); tp["neck"] = Vector2(5, -3); tp["hip"] = Vector2(-10, -2)
		tp["elbow_l"] = Vector2(-5, -1); tp["hand_l"] = Vector2(-15, 0)
		tp["elbow_r"] = Vector2(10, -1); tp["hand_r"] = Vector2(25, 0)
		tp["knee_l"] = Vector2(-20, -2); tp["foot_l"] = Vector2(-30, 0)
		tp["knee_r"] = Vector2(-10, -4); tp["foot_r"] = Vector2(0, 0)

	elif state == POSE_VICTORY:
		tp["head"] = Vector2(0, -45); tp["neck"] = Vector2(0, -35); tp["hip"] = Vector2(0, -15)
		tp["hand_l"] = Vector2(-15, -55); tp["elbow_l"] = Vector2(-10, -45)
		tp["hand_r"] = Vector2(15, -55); tp["elbow_r"] = Vector2(10, -45)
		tp["foot_l"] = Vector2(-15, 0); tp["knee_l"] = Vector2(-10, -10)
		tp["foot_r"] = Vector2(15, 0); tp["knee_r"] = Vector2(10, -10)

	# Apply Facing Flip — a touch more interpolation for weighted, fluid motion.
	var flip = -1.0 if not _facing_right else 1.0
	for k in _pt_names:
		var p = tp[k]
		_current_points[k] = _current_points[k].lerp(Vector2(p.x * flip, p.y), 28.0 * delta)

	# Build limb segments once, then feed both the glow rim and the black core.
	var seg := _limb_segments()
	for n in LIMB_NAMES:
		_limb_core[n].points = seg[n]
		_limb_glow[n].points = seg[n]

	_head_core.position = _current_points["head"]
	_head_glow.position = _current_points["head"]
	_head_core.scale.x = flip



func _limb_segments() -> Dictionary:
	return {
		"body": [_current_points["neck"], _current_points["hip"]],
		"arm_l": [_current_points["neck"], _current_points["elbow_l"], _current_points["hand_l"]],
		"arm_r": [_current_points["neck"], _current_points["elbow_r"], _current_points["hand_r"]],
		"leg_l": [_current_points["hip"], _current_points["knee_l"], _current_points["foot_l"]],
		"leg_r": [_current_points["hip"], _current_points["knee_r"], _current_points["foot_r"]],
	}


func _spawn_ghost() -> void:
	# A frozen, fading copy of the current silhouette left behind in world space.
	if get_parent() == null:
		return
	var ghost := Node2D.new()
	get_parent().add_child(ghost)
	ghost.global_transform = _skeleton.global_transform
	ghost.z_index = -1   # behind the live body

	var col := _team_color
	col.a = 0.28

	var seg := _limb_segments()
	for n in seg.keys():
		var l := Line2D.new()
		l.default_color = col
		l.width = LIMB_WIDTHS[n]
		l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		l.end_cap_mode = Line2D.LINE_CAP_ROUND
		l.joint_mode = Line2D.LINE_JOINT_ROUND
		l.points = seg[n]
		ghost.add_child(l)

	var h := Polygon2D.new()
	h.color = col
	h.polygon = _generate_circle(6.5, 16)
	h.position = _current_points["head"]
	ghost.add_child(h)

	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
	tw.tween_callback(ghost.queue_free)


func _spawn_muzzle_flash_2d() -> void:
	if _gun == null:
		return
	var flash := Polygon2D.new()
	flash.color = Color(1.0, 0.85, 0.4, 0.95)
	flash.polygon = _generate_circle(9.0, 10)
	flash.position = Vector2(20, 0)   # gun tip (gun is 20px long, muzzle out front)
	_gun.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector2(2.2, 2.2), 0.06)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.06)
	tw.tween_callback(flash.queue_free)


func _fire() -> void:
	_cd = fire_cooldown
	_is_shooting = true
	get_tree().create_timer(0.2).timeout.connect(func(): _is_shooting = false)
	_spawn_muzzle_flash_2d()
	
	var target_id: int = 1 if player_id == 2 else 2
	var space := get_world_2d().direct_space_state
	var mouse_pos = get_global_mouse_position()
	var dir_to_target := (mouse_pos - global_position).normalized()
	
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + dir_to_target * weapon_range)
	query.exclude = [get_rid()]

	_recoil_vel = -dir_to_target * 200.0 
	
	var hit := space.intersect_ray(query)
	var hit_pos := global_position + dir_to_target * weapon_range
	
	if not hit.is_empty():
		hit_pos = hit.get("position")
		var hit_normal = hit.get("normal", Vector2.UP)
		var collider = hit.get("collider")
		if collider != null and collider.is_in_group("p%d_body_2d" % target_id):
			if GameManager:
				GameManager.apply_damage(target_id, damage)
			_spawn_blood_2d(hit_pos, hit_normal)
			
	_draw_tracer_2d(global_position + dir_to_target * 16.0, hit_pos)


func _spawn_blood_2d(pos: Vector2, normal: Vector2) -> void:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 300
	particles.lifetime = 0.8
	particles.explosiveness = 0.98
	particles.direction = normal
	particles.spread = 55.0
	particles.initial_velocity_min = 250.0
	particles.initial_velocity_max = 800.0
	particles.scale_amount_min = 4.0
	particles.scale_amount_max = 14.0
	particles.color = Color(0.8, 0.05, 0.05)
	
	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)


func _draw_tracer_2d(start: Vector2, end: Vector2) -> void:
	var bullet := ColorRect.new()
	bullet.size = Vector2(16, 4)
	bullet.color = Color(1.0, 0.9, 0.2)
	bullet.pivot_offset = Vector2(8, 2)
	
	get_tree().root.add_child(bullet)
	bullet.global_position = start
	bullet.rotation = (end - start).angle()
	
	var distance = start.distance_to(end)
	var travel_time = clampf(distance / 2000.0, 0.01, 0.5)
	
	var tween := create_tween()
	tween.tween_property(bullet, "global_position", end, travel_time)
	tween.tween_callback(bullet.queue_free)
