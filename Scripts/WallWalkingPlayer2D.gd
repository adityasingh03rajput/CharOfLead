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
var _gun: Node2D
var _was_on_floor := true
var _recoil_vel := Vector2.ZERO

var _is_dead := false
var _has_won := false
var _is_shooting := false

# Realistic Movement States
enum MoveState { FLOOR, WALL_LEFT, WALL_RIGHT, CEILING, AIR, GRAPPLE }
var _current_state := MoveState.AIR

# ── 2D Tactical Grapple (only the UNARMED victim gets this) ──
@export_group("Grapple")
@export var grapple_range: float = 560.0     # max reticle/anchor distance
@export var reticle_speed: float = 480.0     # px/s while steering with Ctrl+WASD
@export var zip_speed: float = 1550.0        # max traverse speed toward anchor
@export var zip_accel: float = 6500.0        # how hard the cable yanks you in
@export var arrival_dist: float = 26.0       # detach when this close to the anchor
@export var grapple_timeout: float = 1.6     # safety auto-release
@export var grapple_kick: float = 520.0      # E/jump bail-out impulse

enum GrappleState { OFF, AIMING, ZIPPING }
var _grapple_state: int = GrappleState.OFF
var _reticle_pos: Vector2 = Vector2.ZERO     # world-space aim point
var _anchor: Vector2 = Vector2.ZERO          # world-space attached point
var _grapple_t: float = 0.0                  # timeout accumulator
var _fire_was_down: bool = false             # F edge-detect
var _e_was_down: bool = false                # E edge-detect
const GRAPPLE_COLOR := Color(0.25, 0.8, 1.0) # electric-blue cable/reticle

# Grapple visuals (top_level so they live in world space, not the rotating rig)
var _cable: Line2D
var _spike: Node2D
var _reticle: Node2D

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
const POSE_WALL_COMBAT_IDLE := 11
const POSE_WALL_COMBAT_MOVE := 12
const POSE_GRAPPLE          := 13

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
const LIMB_WIDTHS := {"body": 12.0, "arm_l": 5.0, "arm_r": 5.0, "leg_l": 6.5, "leg_r": 6.5}

var _pouch: Polygon2D

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
@onready var _act_grapple: String = "p%d_grapple" % player_id


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
	_setup_grapple_visuals()

	if GameManager:
		GameManager.player_died.connect(_on_player_died)
		GameManager.game_over.connect(_on_game_over)
		GameManager.mode_changed.connect(_on_mode_changed_grapple)


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
	_head_core.polygon = _generate_circle(8.0, 20)
	_skeleton.add_child(_head_core)

	# Faint team-coloured eye so facing still reads on the shadow.
	_eye = Polygon2D.new()
	_eye.color = Color(_team_color.r, _team_color.g, _team_color.b, 0.9)
	_eye.polygon = _generate_circle(1.8, 8)
	_eye.position = Vector2(3, -2)
	_head_core.add_child(_eye)

	# Gun — Tactical Suppressed Pistol
	_gun = Node2D.new()
	_skeleton.add_child(_gun)
	
	var gun_body = _make_line(CORE_COLOR, 4.0)
	gun_body.points = [Vector2(0, 0), Vector2(10, 0)]
	var gun_grip = _make_line(CORE_COLOR, 3.5)
	gun_grip.points = [Vector2(2, 0), Vector2(4, 6)]
	var silencer = _make_line(CORE_COLOR, 3.0)
	silencer.points = [Vector2(10, 0), Vector2(22, 0)]
	
	gun_body.reparent(_gun)
	gun_grip.reparent(_gun)
	silencer.reparent(_gun)

	var gun_hi = _make_line(Color(0.4, 0.4, 0.4, 0.8), 1.5)
	gun_hi.points = [Vector2(0, -1), Vector2(8, -1)]
	gun_hi.reparent(_gun)
	
	# Tactical Thigh Pouch
	_pouch = Polygon2D.new()
	_pouch.color = CORE_COLOR
	_pouch.polygon = PackedVector2Array([Vector2(-3.5, -4.5), Vector2(3.5, -4.5), Vector2(3.5, 4.5), Vector2(-3.5, 4.5)])
	_skeleton.add_child(_pouch)

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


func _setup_grapple_visuals() -> void:
	# P2 Blue is always the armed assassin — THEY never grapple.
	# P1 Red is always the victim who grapples in 2D.
	# We check player_id, NOT is_armed(), because is_armed() changes
	# with dimension swaps and this runs at _ready() time (always 3D at boot).
	if player_id == 2:
		return

	# ── Cable ───────────────────────────────────────────────────────────
	_cable = Line2D.new()
	_cable.top_level = true
	_cable.width = 2.5
	_cable.default_color = GRAPPLE_COLOR
	_cable.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_cable.end_cap_mode = Line2D.LINE_CAP_ROUND
	_cable.z_index = 5
	_cable.visible = false
	add_child(_cable)

	# ── Anchor spike ────────────────────────────────────────────────────
	_spike = Node2D.new()
	_spike.top_level = true
	_spike.z_index = 6
	_spike.visible = false
	add_child(_spike)
	var spike_glow := Polygon2D.new()
	spike_glow.color = Color(GRAPPLE_COLOR.r, GRAPPLE_COLOR.g, GRAPPLE_COLOR.b, 0.35)
	spike_glow.polygon = _generate_circle(10.0, 16)
	_spike.add_child(spike_glow)
	var spike_core := Polygon2D.new()
	spike_core.color = GRAPPLE_COLOR
	spike_core.polygon = _generate_circle(3.5, 12)
	_spike.add_child(spike_core)
	# Diamond shape around anchor
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var diamond_tick := Line2D.new()
		diamond_tick.width = 1.5
		diamond_tick.default_color = GRAPPLE_COLOR
		var dv := Vector2(cos(angle), sin(angle))
		diamond_tick.points = [dv * 5.0, dv * 13.0]
		_spike.add_child(diamond_tick)

	# ── Reticle (tactical crosshair + animated ring) ─────────────────────
	_reticle = Node2D.new()
	_reticle.top_level = true
	_reticle.z_index = 10
	_reticle.visible = false
	add_child(_reticle)

	# Outer glow ring (large, semi-transparent)
	var ring_glow := Line2D.new()
	ring_glow.name = "ring_glow"
	ring_glow.width = 4.0
	ring_glow.default_color = Color(GRAPPLE_COLOR.r, GRAPPLE_COLOR.g, GRAPPLE_COLOR.b, 0.2)
	ring_glow.closed = true
	ring_glow.points = _generate_circle(22.0, 32)
	_reticle.add_child(ring_glow)

	# Middle solid ring
	var ring_mid := Line2D.new()
	ring_mid.name = "ring_mid"
	ring_mid.width = 1.8
	ring_mid.default_color = GRAPPLE_COLOR
	ring_mid.closed = true
	ring_mid.points = _generate_circle(18.0, 32)
	_reticle.add_child(ring_mid)

	# Inner tight ring
	var ring_inner := Line2D.new()
	ring_inner.name = "ring_inner"
	ring_inner.width = 1.0
	ring_inner.default_color = Color(GRAPPLE_COLOR.r, GRAPPLE_COLOR.g, GRAPPLE_COLOR.b, 0.6)
	ring_inner.closed = true
	ring_inner.points = _generate_circle(8.0, 20)
	_reticle.add_child(ring_inner)

	# Four crosshair arms (gap in centre)
	for arm_a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var arm := Line2D.new()
		arm.width = 1.5
		arm.default_color = GRAPPLE_COLOR
		var dv := Vector2(cos(arm_a), sin(arm_a))
		arm.points = [dv * 5.0, dv * 22.0]
		_reticle.add_child(arm)

	# Centre dot
	var centre := Polygon2D.new()
	centre.name = "centre_dot"
	centre.color = GRAPPLE_COLOR
	centre.polygon = _generate_circle(2.5, 12)
	_reticle.add_child(centre)

	# Dashed preview line from player to reticle (world-space, top-level)
	var preview := Line2D.new()
	preview.name = "preview_line"
	preview.top_level = true
	preview.width = 1.2
	preview.default_color = Color(GRAPPLE_COLOR.r, GRAPPLE_COLOR.g, GRAPPLE_COLOR.b, 0.45)
	preview.z_index = 8
	preview.visible = false
	add_child(preview)


# ====================================================================
# GRAPPLE LOGIC  (P1 Red / victim only)
# Controls:
#   F          → open reticle on nearest wall  /  fire when already aiming
#   Ctrl+WASD  → snap reticle to next wall in that direction
#   E          → cancel aim OR release mid-traverse (keeps momentum)
# ====================================================================
func _handle_grapple(delta: float, input_x: float, input_y: float) -> bool:
	# Cable is null for P2. Dimension guard stops P1 from grappling in 3D.
	if _cable == null or _is_dead or _has_won or not is_multiplayer_authority():
		return false
	if GameManager and GameManager.is_armed(player_id):
		# Armed right now (3D mode) — hide visuals, reset state, do nothing.
		if _grapple_state != GrappleState.OFF:
			_grapple_state = GrappleState.OFF
		if _reticle: _reticle.visible = false
		if _cable:   _cable.visible   = false
		if _spike:   _spike.visible   = false
		return false

	# ── F (grapple key) edge-detect ──────────────────────────────────────
	var grapple_action := _act_grapple
	if not InputMap.has_action(grapple_action):
		grapple_action = _act_fire
	var fire_down    := Input.is_action_pressed(grapple_action)
	var fire_pressed := fire_down and not _fire_was_down
	_fire_was_down   = fire_down

	# ── E key edge-detect (bail / cancel) ────────────────────────────────
	var e_down    := Input.is_key_pressed(KEY_E)
	var e_pressed := e_down and not _e_was_down
	_e_was_down   = e_down

	# ── Ctrl held → WASD steers reticle wall-to-wall ─────────────────────
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)

	match _grapple_state:
		# ── OFF: press F to open reticle ─────────────────────────────────
		GrappleState.OFF:
			if fire_pressed:
				# If a direction key is held simultaneously with F,
				# snap the reticle to the nearest wall in that direction.
				var dir := Vector2(input_x, input_y)
				if dir.length() > 0.3:
					var wall_pt := _find_wall_in_direction(dir.normalized())
					_reticle_pos = wall_pt if wall_pt != Vector2.ZERO else _find_nearest_wall_point()
				else:
					# F alone → smart sweep (ceiling preferred).
					_reticle_pos = _find_nearest_wall_point()
				_grapple_state = GrappleState.AIMING
			return false

		# ── AIMING: steer / confirm / cancel ─────────────────────────────
		GrappleState.AIMING:
			# F again → fire toward current reticle position.
			if fire_pressed:
				_fire_grapple()
				return false

			# E → cancel aim.
			if e_pressed:
				_grapple_state = GrappleState.OFF
				return false

			# Ctrl + WASD: snap reticle to next wall in that direction.
			if ctrl_held:
				var steer := Vector2(input_x, input_y)
				if steer.length() > 0.3:
					var wall_pt := _find_wall_in_direction(steer.normalized())
					if wall_pt != Vector2.ZERO:
						_reticle_pos = wall_pt
					return true   # consume movement input this frame
			return false

		# ── ZIPPING: auto-traverse toward anchor ──────────────────────────
		GrappleState.ZIPPING:
			_grapple_t += delta
			if e_pressed:
				_release_grapple(true)      # bail: fling away from anchor
			elif _grapple_t >= grapple_timeout:
				_release_grapple(false)
			return false

	return false


func _fire_grapple() -> void:
	# Raycast from the player toward the reticle; attach to the first wall hit.
	var space := get_world_2d().direct_space_state
	var aim := (_reticle_pos - global_position)
	if aim.length() < 1.0:
		aim = Vector2.UP
	var to := global_position + aim.normalized() * grapple_range
	var query := PhysicsRayQueryParameters2D.create(global_position, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1   # walls only
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		# Missed — snap back to idle, no anchor.
		_grapple_state = GrappleState.OFF
		return
	_anchor = hit.get("position")
	_grapple_state = GrappleState.ZIPPING
	_grapple_t = 0.0


func _release_grapple(kick: bool) -> void:
	if _grapple_state == GrappleState.ZIPPING and kick:
		# Bail-out fling: nudge away from the anchor so E feels like a dismount.
		var away := (global_position - _anchor).normalized()
		if away == Vector2.ZERO:
			away = Vector2.UP
		velocity += away * grapple_kick
	velocity = velocity.limit_length(zip_speed)
	_grapple_state = GrappleState.OFF


func _find_nearest_wall_point() -> Vector2:
	# Cast rays in 16 directions, then score each hit:
	#   - Skip anything whose normal points DOWN (floor surface — not a grapple target).
	#   - Among the rest, prefer the nearest CEILING first, then nearest side-wall.
	# This stops the reticle from snapping to floor-corners on diagonal rays.
	var space := get_world_2d().direct_space_state
	var best  := Vector2.ZERO
	var best_score := -INF   # higher = better anchor

	for i in range(16):
		var a   := (float(i) / 16.0) * TAU
		var dir := Vector2(cos(a), sin(a))
		var query := PhysicsRayQueryParameters2D.create(
			global_position, global_position + dir * grapple_range)
		query.exclude        = [get_rid()]
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		var p:      Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		var d := global_position.distance_to(p)

		# Skip surfaces the player is already touching (min 55 px).
		if d < 55.0:
			continue

		# Skip floor-type surfaces: normal points upward (normal.y < -0.5 = floor).
		# normal.y < 0 means surface faces UP (= floor in Godot 2D Y-down coords).
		if normal.y < -0.5:
			continue

		# Score: ceiling is best (normal faces DOWN = normal.y > 0.5),
		# side-walls are good (|normal.x| > 0.5), platforms facing up are ok.
		# Prefer closer hits among same-type surfaces.
		var type_bonus := 0.0
		if normal.y > 0.5:            # ceiling — best for grapple up
			type_bonus = 1000.0
		elif abs(normal.x) > 0.5:     # left/right wall — good
			type_bonus = 500.0

		var score := type_bonus - d   # farther = lower score within same type
		if score > best_score:
			best_score = score
			best       = p

	# Fallback: no valid anchor found — aim straight up.
	if best == Vector2.ZERO:
		best = global_position + Vector2.UP * (grapple_range * 0.5)
	return best


func _find_wall_in_direction(dir: Vector2) -> Vector2:
	# Cast a single ray in dir; return the hit point (offset slightly off the surface).
	# Used by Ctrl+WASD to snap the reticle to the wall face in that direction.
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position, global_position + dir * grapple_range)
	query.exclude        = [get_rid()]
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector2.ZERO
	# Pull the anchor point 4 px back from the wall surface so the spike
	# visually sits on the wall face rather than clipping into it.
	var normal: Vector2 = hit["normal"]
	return hit["position"] + normal * 4.0


func _update_grapple_visuals() -> void:
	if _cable == null:
		return
	var aiming := _grapple_state == GrappleState.AIMING
	var zipping := _grapple_state == GrappleState.ZIPPING

	# Preview dashed line while aiming.
	var preview: Line2D = get_node_or_null("preview_line") as Line2D
	if preview == null:
		# Find it among direct children (it's top_level so parented directly).
		for c in get_children():
			if c is Line2D and c.name == "preview_line":
				preview = c
				break

	# Reticle: show and spin while aiming.
	_reticle.visible = aiming
	if aiming:
		_reticle.global_position = _reticle_pos
		# Spin the outer glow ring for a radar-sweep feel.
		_reticle.rotation += get_process_delta_time() * 1.2
		
		# Show dashed preview line from hand to reticle.
		if preview:
			preview.visible = true
			var hand_world: Vector2 = global_position
			if _skeleton:
				hand_world = _skeleton.to_global(_current_points.get("hand_r", Vector2.ZERO))
			# Dashed: emit 6-point zigzag between hand and reticle.
			var seg_count := 12
			var pts := PackedVector2Array()
			for i in range(seg_count + 1):
				var t := float(i) / float(seg_count)
				var p := hand_world.lerp(_reticle_pos, t)
				# Tiny perpendicular jitter on odd segments for dashed look.
				if i % 2 == 1:
					var perp := (_reticle_pos - hand_world).normalized().rotated(PI * 0.5) * 2.5
					p += perp
				pts.append(p)
			preview.points = pts
	else:
		if preview:
			preview.visible = false

	# Cable + spike only while zipping.
	_cable.visible = zipping
	_spike.visible = zipping
	if zipping:
		var hand := global_position
		if _skeleton:
			hand = _skeleton.to_global(_current_points.get("hand_r", Vector2.ZERO))
		_cable.points = [hand, _anchor]
		_spike.global_position = _anchor
		# Pulse the spike rotation.
		_spike.rotation += get_process_delta_time() * 3.0


func _on_mode_changed_grapple(_is_3d: bool) -> void:
	# Never let a stale zip resume after a dimension swap.
	if _grapple_state != GrappleState.OFF:
		_grapple_state = GrappleState.OFF
	if _cable:
		_cable.visible = false
	if _spike:
		_spike.visible = false
	if _reticle:
		_reticle.visible = false


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

	var is_auth := is_multiplayer_authority()
	var input_x = Input.get_axis(_act_left, _act_right) if is_auth else 0.0
	var input_y = Input.get_axis(_act_up, _act_down) if is_auth else 0.0
	var is_running := (Input.is_key_pressed(KEY_SHIFT) if player_id == 1 else Input.is_key_pressed(KEY_CTRL)) if is_auth else false
	var is_crouching := Input.is_action_pressed(_act_down) if is_auth else false

	# --- Grapple (victim only): F toggles aim, Ctrl+WASD steers reticle, F fires,
	# E bails. While steering the reticle, WASD drives it instead of the body. ---
	var steering_reticle := _handle_grapple(delta, input_x, input_y)
	if steering_reticle:
		input_x = 0.0
		input_y = 0.0

	var current_speed: float = speed * (1.5 if is_running else 1.0)
	if is_crouching:
		current_speed = speed * 0.5

	# While zipping, the grapple owns velocity — skip the surface state machine.
	var zipping := _grapple_state == GrappleState.ZIPPING
	if not zipping:
		_determine_state()

	# Apply state-based velocity & visual rotation
	var target_rotation: float = 0.0
	var move_intensity: float = 0.0

	if zipping:
		# Cable yanks the player straight toward the anchor, capped at zip_speed.
		var to_anchor := _anchor - global_position
		var dir := to_anchor.normalized()
		velocity = velocity.move_toward(dir * zip_speed, zip_accel * delta)
		target_rotation = 0.0
		_current_state = MoveState.GRAPPLE
	elif _current_state == MoveState.FLOOR:
		velocity.x = input_x * current_speed
		velocity.y += gravity * delta
		target_rotation = 0.0
		move_intensity = input_x
		
		if is_auth and Input.is_action_just_pressed(_act_jump) and not _is_dead:
			velocity.y = -jump_force
			if _skeleton: _skeleton.scale = Vector2(0.6, 1.4)

	elif _current_state == MoveState.WALL_LEFT or _current_state == MoveState.WALL_RIGHT:
		# Climbing Up/Down
		velocity.y = input_y * current_speed * climb_speed_mult
		
		# Stick to wall by pushing slightly into it
		var wall_dir = -1.0 if _current_state == MoveState.WALL_LEFT else 1.0
		velocity.x = wall_dir * 50.0 
		
		target_rotation = 0.0   # spider climb keeps the body upright, facing the wall
		move_intensity = input_y
		
		# Jump off the wall
		if is_auth and Input.is_action_just_pressed(_act_jump) and not _is_dead:
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
		if input_y > 0.5 or (is_auth and Input.is_action_just_pressed(_act_jump)):
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

	# Arrival / stuck detection for the zip (position is now updated).
	if zipping:
		if global_position.distance_to(_anchor) <= arrival_dist or is_on_wall():
			_release_grapple(false)   # keep momentum on arrival

	_update_grapple_visuals()

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
			_gun.position = _current_points["hand_r"]
			if is_auth:
				var mouse_pos = get_global_mouse_position()
				var world_angle := (mouse_pos - _gun.global_position).angle()
				_gun.global_rotation = world_angle
				_aim_angle = world_angle
			else:
				_gun.global_rotation = _aim_angle
			
			if _gun.global_rotation > PI/2 or _gun.global_rotation < -PI/2:
				_gun.scale.y = -1.0
			else:
				_gun.scale.y = 1.0
		else:
			_gun.visible = false

	if is_auth and GameManager and GameManager.is_armed(player_id) and not _is_dead:
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
		
	if _current_state == MoveState.GRAPPLE:
		# Face the anchor during zip — the body rotates to dive toward it.
		if _anchor != Vector2.ZERO:
			_facing_right = _anchor.x >= global_position.x
		return
	elif _current_state == MoveState.WALL_LEFT:
		_facing_right = false
	elif _current_state == MoveState.WALL_RIGHT:
		_facing_right = true
	elif GameManager and GameManager.is_armed(player_id):
		var mouse_pos = get_global_mouse_position()
		_facing_right = mouse_pos.x > global_position.x
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
			if GameManager and GameManager.is_armed(player_id):
				state = POSE_WALL_COMBAT_MOVE if abs(move_dir) > 0.1 else POSE_WALL_COMBAT_IDLE
			else:
				state = POSE_CLIMB
		elif _current_state == MoveState.GRAPPLE:
			state = POSE_GRAPPLE
		elif _current_state == MoveState.CEILING:
			state = POSE_MONKEY_BAR
		elif _current_state == MoveState.AIR:
			state = POSE_JUMP
		elif is_crouching and _current_state == MoveState.FLOOR:
			state = POSE_CROUCH
		elif abs(move_dir) > 0.1 and is_running:
			state = POSE_RUN
		elif abs(move_dir) > 0.1:
			state = POSE_WALK
		else:
			state = POSE_IDLE

	if state == POSE_WALK or state == POSE_RUN or state == POSE_CLIMB or state == POSE_MONKEY_BAR or state == POSE_WALL_COMBAT_MOVE:
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
		var s = sin(_anim_time)
		var c = cos(_anim_time)
		
		# Pelvis drops slightly during heel strike/push off, rises slightly at mid-stance.
		var bounce = -abs(c) * (4.0 if state == POSE_RUN else 2.0)
		
		# --- Inverted Pendulum Upper Body ---
		# Walk: Pelvis drives forward (+5), Chest lags behind (+2), Head stabilizes (0)
		# Run: Body leans into momentum (Hip +4, Neck +8, Head +12)
		var hip_fwd = 4.0 if state == POSE_RUN else 5.0
		var neck_fwd = 8.0 if state == POSE_RUN else 2.0
		var head_fwd = 12.0 if state == POSE_RUN else 0.0
		
		# Head/Neck barely bounce, stabilizing vision. Pelvis absorbs the shock.
		tp["head"] = Vector2(head_fwd, -55)
		tp["neck"] = Vector2(neck_fwd, -45 - bounce * 0.2)
		tp["hip"]  = Vector2(hip_fwd, -25 + bounce)
		
		var stride = 22.0 if state == POSE_RUN else 14.0
		var lift = 14.0 if state == POSE_RUN else 8.0
		
		# --- Right Leg (s, c) ---
		tp["foot_r"] = Vector2(s * stride, -max(0, c) * lift)
		# Knee leads the foot: drives forward during swing (c>0), stays slightly ahead during stance (c<0)
		tp["knee_r"] = Vector2((s * 0.4 + max(0, c) * 0.4 + 0.15) * stride, -14 - max(0, c) * (lift * 0.8) + max(0, -c) * 3.0)
		
		# --- Left Leg (-s, -c) ---
		tp["foot_l"] = Vector2(-s * stride, -max(0, -c) * lift)
		tp["knee_l"] = Vector2((-s * 0.4 + max(0, -c) * 0.4 + 0.15) * stride, -14 - max(0, -c) * (lift * 0.8) + max(0, c) * 3.0)
		
		var arm_sw = 15.0 if state == POSE_RUN else 8.0
		tp["elbow_l"] = Vector2(s * arm_sw * 0.6, -35 - abs(c)*2)
		tp["hand_l"] = Vector2(s * arm_sw, -25 - abs(c)*4)
		
		tp["elbow_r"] = Vector2(-s * arm_sw * 0.6, -35 - abs(c)*2)
		tp["hand_r"] = Vector2(-s * arm_sw, -25 - abs(c)*4)

	elif state == POSE_WALL_COMBAT_IDLE or state == POSE_WALL_COMBAT_MOVE:
		# --- ARMED WALL COMBAT STANCE ---
		# Authored for WALL_RIGHT (X > 0 is the wall, so X=14 is touching the wall)
		# Character faces LEFT (away from wall), back is to the wall (+X).
		const WALL_X = 14.0
		
		# Body is parallel to wall (upright, back against wall)
		tp["hip"] = Vector2(WALL_X - 2, -22)
		tp["neck"] = Vector2(WALL_X - 4, -45) # Leaning slightly away from wall
		tp["head"] = Vector2(WALL_X - 6, -53)
		
		# Top hand supports body flat on wall
		tp["hand_l"] = Vector2(WALL_X, -60)
		# Gun hand aims outward (-X)
		tp["hand_r"] = Vector2(WALL_X - 20, -40)
		
		var sway = sin(_anim_time * 3.0) * 0.5
		
		# Feet planted on wall
		var foot_high = Vector2(WALL_X, -10)
		var foot_low  = Vector2(WALL_X, 0)
		
		if state == POSE_WALL_COMBAT_MOVE:
			var phase = _anim_time * 1.5
			var step = sin(phase)
			
			# Upper body absorbs movement
			tp["hip"].y += step * 2.0
			tp["neck"].y += step * 1.0
			
			# Thighs reposition (feet step up/down wall)
			if cos(phase) > 0:
				tp["foot_l"] = foot_high + Vector2(0, max(0, step) * 12)
				tp["foot_r"] = foot_low
			else:
				tp["foot_l"] = foot_high
				tp["foot_r"] = foot_low + Vector2(0, max(0, -step) * 12)
		else:
			tp["foot_l"] = foot_high
			tp["foot_r"] = foot_low
			tp["hip"].y += sway
			tp["neck"].y += sway * 0.5
			
		# Elbows/Knees bend outward away from wall (-X)
		tp["elbow_l"] = (tp["neck"] + tp["hand_l"]) * 0.5 + Vector2(-6, 0)
		tp["elbow_r"] = (tp["neck"] + tp["hand_r"]) * 0.5 + Vector2(-6, 0)
		tp["knee_l"]  = (tp["hip"] + tp["foot_l"]) * 0.5 + Vector2(-15, 0)
		tp["knee_r"]  = (tp["hip"] + tp["foot_r"]) * 0.5 + Vector2(-15, 0)

	elif state == POSE_CLIMB:
		# --- UNARMED SPIDER CLIMB ---
		# Body stays UPRIGHT and faces the wall (the wall is on the +X side
		# in this authored frame; the facing-flip mirrors it for a left wall).
		# Hands reach overhead onto the wall; feet push against it below.
		# Elbows/knees are always solved BETWEEN their joints so limbs never
		# fold back into a blob.
		var reach := sin(_anim_time * 3.0)     # alternates which side reaches high
		var settle := cos(_anim_time * 3.0)

		# Upright spine, leaning slightly into the wall (+X).
		tp["hip"]  = Vector2(4, -25)
		tp["neck"] = Vector2(6, -45)
		tp["head"] = Vector2(9, -53)

		if move_dir != 0:
			# Diagonal climbing gait: opposite hand & foot advance together.
			var hi := 0.5 + reach * 0.5        # 0..1, right side reaches high near 1
			tp["hand_r"] = Vector2(14, -52 - hi * 12)          # reaches up to -64
			tp["hand_l"] = Vector2(12, -52 - (1.0 - hi) * 12)
			tp["foot_r"] = Vector2(11, -4 - (1.0 - hi) * 14)   # foot lifts while its hand plants
			tp["foot_l"] = Vector2(9, -4 - hi * 14)
			tp["hip"].y += settle * 1.5        # gentle pull-up bob
			tp["neck"].y += settle * 1.0
		else:
			# Clinging to the wall at rest — slow sway.
			var sway := sin(_anim_time * 2.0) * 1.5
			tp["hand_r"] = Vector2(14, -60 + sway)
			tp["hand_l"] = Vector2(12, -42 - sway)
			tp["foot_r"] = Vector2(11, -16 + sway)
			tp["foot_l"] = Vector2(9, -4 - sway)

		# Elbows bend outward, away from the wall (-X); knees bend into it (+X).
		tp["elbow_r"] = (tp["neck"] + tp["hand_r"]) * 0.5 + Vector2(-6, 0)
		tp["elbow_l"] = (tp["neck"] + tp["hand_l"]) * 0.5 + Vector2(-6, 0)
		tp["knee_r"]  = (tp["hip"] + tp["foot_r"]) * 0.5 + Vector2(7, 0)
		tp["knee_l"]  = (tp["hip"] + tp["foot_l"]) * 0.5 + Vector2(7, 0)

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

	elif state == POSE_GRAPPLE:
		# Body dives toward anchor — compute local aim vector from _anchor.
		var aim_local := Vector2(1, -0.3)  # fallback: forward-up
		if _skeleton and _anchor != Vector2.ZERO:
			var world_aim := (_anchor - global_position).normalized()
			# Bring into skeleton-local space (undo world rotation).
			aim_local = _skeleton.to_local(global_position + world_aim * 40.0)
			aim_local = aim_local.normalized()
		
		# Spine: head leads, hip trails
		var stretch = clampf(velocity.length() / zip_speed, 0.0, 1.0)
		tp["neck"] = Vector2(0, -38) + aim_local * 8.0 * stretch
		tp["head"] = tp["neck"] + aim_local * 10.0
		tp["hip"]  = Vector2(0, -22) - aim_local * 4.0 * stretch
		
		# Both hands reach FORWARD along aim — right hand grips the cable.
		var reach_r := aim_local * 18.0
		var reach_l := aim_local * 13.0 + Vector2(0, 4)  # slightly under the cable
		tp["hand_r"]  = tp["neck"] + reach_r
		tp["elbow_r"] = tp["neck"] + reach_r * 0.45 + Vector2(0, 5)
		tp["hand_l"]  = tp["neck"] + reach_l
		tp["elbow_l"] = tp["neck"] + reach_l * 0.45 + Vector2(0, 7)
		
		# Legs tuck behind, knees bent outward for aerodynamic silhouette.
		var trail := -aim_local
		tp["foot_r"] = tp["hip"] + trail * 14.0 + Vector2(4, 2)
		tp["knee_r"] = (tp["hip"] + tp["foot_r"]) * 0.5 + Vector2(10, 6)
		tp["foot_l"] = tp["hip"] + trail * 14.0 + Vector2(-4, 4)
		tp["knee_l"] = (tp["hip"] + tp["foot_l"]) * 0.5 + Vector2(-10, 6)


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

	# --- AIM & WEAPON LAYER ---
	var is_armed = GameManager and GameManager.is_armed(player_id)
	if is_armed and not _is_dead and not _has_won:
		var mouse_pos = get_global_mouse_position()
		# Localize mouse position to the skeleton to respect wall rotations
		var local_mouse = _skeleton.to_local(mouse_pos)
		
		# If facing left, the X coordinates are currently positive and will be flipped later.
		# Flip the target X so our aim vector calculates correctly on the positive side.
		if not _facing_right:
			local_mouse.x *= -1.0
			
		var aim_vec = (local_mouse - tp["neck"]).normalized()
		
		# Gun Arm (Right Arm) completely independent, pointing at target
		var arm_len = 24.0
		var shoulder_pos = tp["neck"] + Vector2(0, 3) # Shoulder down from neck
		tp["hand_r"] = shoulder_pos + aim_vec * arm_len
		# Elbow sags slightly due to gravity/bend
		tp["elbow_r"] = shoulder_pos + aim_vec * (arm_len * 0.4) + Vector2(0, 6)
		
		# Head tracks the aim directly
		var head_look = aim_vec * 6.0
		tp["head"] = tp["neck"] + Vector2(0, -10) + head_look
		
		# Chest rotates slightly into the aim
		tp["neck"] += aim_vec * 3.0
		
		# If standing/crouching, the free hand braces the gun for stability
		if state == POSE_IDLE or state == POSE_CROUCH:
			tp["hand_l"] = tp["hand_r"] - aim_vec * 6.0 + Vector2(0, 2)
			tp["elbow_l"] = shoulder_pos + aim_vec * 8.0 + Vector2(0, 10)
			
		# Shooting Chain Reaction (Recoil ripple through body)
		if _is_shooting:
			var recoil_dir = -aim_vec
			var recoil = 6.0
			tp["hand_r"] += recoil_dir * recoil
			tp["elbow_r"] += recoil_dir * (recoil * 0.7)
			tp["neck"] += recoil_dir * (recoil * 0.4)
			tp["hip"] += recoil_dir * (recoil * 0.2)
			# Opposite leg compensates slightly
			tp["foot_l"] += recoil_dir * (recoil * 0.1)

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
	
	if _pouch:
		var hip_pos = _current_points["hip"]
		var knee_r = _current_points["knee_r"]
		var thigh_dir = (knee_r - hip_pos).normalized()
		_pouch.position = hip_pos + thigh_dir * 8.0
		# Rotate pouch to align with the thigh, plus a slight offset to hang naturally
		_pouch.rotation = thigh_dir.angle() - PI/2.0



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
	var target_id: int = 1 if player_id == 2 else 2
	var space := get_world_2d().direct_space_state
	var mouse_pos = get_global_mouse_position()
	var dir_to_target := (mouse_pos - global_position).normalized()
	
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + dir_to_target * weapon_range)
	query.exclude = [get_rid()]

	var hit := space.intersect_ray(query)
	var hit_pos := global_position + dir_to_target * weapon_range
	var hit_normal := Vector2.UP
	var hit_player := false

	if not hit.is_empty():
		hit_pos = hit.get("position")
		hit_normal = hit.get("normal", Vector2.UP)
		var collider = hit.get("collider")
		if collider != null and collider.is_in_group("p%d_body_2d" % target_id):
			hit_player = true
			if GameManager:
				GameManager.apply_damage(target_id, damage)
	
	rpc("_fire_rpc", hit_pos, hit_normal, hit_player, dir_to_target)

@rpc("call_local", "any_peer")
func _fire_rpc(hit_pos: Vector2, hit_normal: Vector2, hit_player: bool, dir_to_target: Vector2) -> void:
	_cd = fire_cooldown
	_is_shooting = true
	get_tree().create_timer(0.2).timeout.connect(func(): _is_shooting = false)
	_spawn_muzzle_flash_2d()
	
	_recoil_vel = -dir_to_target * 25.0
	if hit_player:
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
