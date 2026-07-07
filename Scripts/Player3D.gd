extends CharacterBody3D
## Player3D.gd — a fully procedural humanoid soldier for State A (the 3D arena).
##
## No external model assets: the whole character is built at runtime from box /
## sphere primitives arranged into a bone hierarchy, then animated procedurally.
## Supported animation states:
##   idle · walk · run · jump/airborne · shoot · hurt (flinch) · die · victory
##
## Player 1 (Red) is the armed hunter in 3D; Player 2 (Blue) is unarmed and evades.

@export var player_id: int = 1
@export var is_hunter: bool = false
@export var walk_speed: float = 4.5
@export var run_speed: float = 8.0
@export var gravity: float = 20.0
@export var jump_velocity: float = 8.0
@export var turn_speed: float = 10.0

@export_group("Weapon")
@export var damage: float = 34.0
@export var weapon_range: float = 50.0
@export var fire_cooldown: float = 0.35
@export var muzzle_height: float = 1.2

# ── Runtime state ──
var _cd: float = 0.0
var _is_dead := false
var _has_won := false
var _shoot_t: float = 0.0
var _hurt_t: float = 0.0
var _time: float = 0.0
var _anim_phase: float = 0.0
var _last_health: float = 100.0

# ── Procedural rig ──
var _rig: Node3D
var _team_color: Color
var _joints: Dictionary = {}   # name -> Node3D pivot
var _hand_r: Node3D
var _gun: MeshInstance3D
var _muzzle_light: OmniLight3D
var _muzzle_flash: MeshInstance3D

const GUN_REST := Vector3(0, -0.2, 0)

@onready var _act_up: String = "p%d_up" % player_id
@onready var _act_down: String = "p%d_down" % player_id
@onready var _act_left: String = "p%d_left" % player_id
@onready var _act_right: String = "p%d_right" % player_id
@onready var _act_jump: String = "p%d_jump" % player_id
@onready var _act_fire: String = "p%d_fire" % player_id


func _ready() -> void:
	add_to_group("p%d_body_3d" % player_id)
	_team_color = Color(0.85, 0.15, 0.15) if player_id == 1 else Color(0.2, 0.4, 0.95)

	_build_rig()

	if GameManager:
		GameManager.player_died.connect(_on_player_died)
		GameManager.game_over.connect(_on_game_over)
		GameManager.health_changed.connect(_on_health_changed)
		_last_health = GameManager.get_health(player_id)


# ====================================================================
# RIG CONSTRUCTION — premium procedural humanoid from cylinders & spheres.
# ====================================================================
func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	var skin := _mat_rig(_team_color, 0.1, 0.55)
	var dark := _mat_rig(_team_color.darkened(0.5), 0.15, 0.65)
	var gear := _mat_rig(Color(0.08, 0.08, 0.1), 0.6, 0.35)
	var eye_mat := _mat_rig_emissive(_team_color.lightened(0.5), 2.5)

	# Pelvis (root of animated skeleton), ~0.9m above feet
	var pelvis := _joint("pelvis", _rig, Vector3(0, 0.9, 0))
	_mesh_box(pelvis, Vector3(0.36, 0.16, 0.22), Vector3(0, 0, 0), gear)
	
	# Utility Belt / Pouches
	_mesh_box(pelvis, Vector3(0.38, 0.08, 0.24), Vector3(0, 0.0, 0), dark)
	_mesh_box(pelvis, Vector3(0.1, 0.12, 0.1), Vector3(0.12, 0.0, -0.12), gear)
	_mesh_box(pelvis, Vector3(0.1, 0.12, 0.1), Vector3(-0.12, 0.0, -0.12), gear)

	# Torso / chest — tapered look with a box
	var torso := _joint("torso", pelvis, Vector3(0, 0, 0))
	_mesh_box(torso, Vector3(0.44, 0.5, 0.24), Vector3(0, 0.28, 0), skin)
	
	# Tactical Backpack
	_mesh_box(torso, Vector3(0.3, 0.4, 0.15), Vector3(0, 0.25, 0.18), gear)
	
	# Shoulder pads
	_mesh_sphere(torso, 0.08, Vector3(-0.26, 0.48, 0), dark)
	_mesh_sphere(torso, 0.08, Vector3(0.26, 0.48, 0), dark)

	# Head
	var head := _joint("head", torso, Vector3(0, 0.56, 0))
	_mesh_sphere(head, 0.15, Vector3(0, 0.15, 0), skin)
	# Visor / face plate
	_mesh_box(head, Vector3(0.22, 0.08, 0.06), Vector3(0, 0.17, -0.13), gear)
	# Emissive eyes (two small glowing dots)
	_mesh_sphere(head, 0.025, Vector3(-0.06, 0.17, -0.16), eye_mat)
	_mesh_sphere(head, 0.025, Vector3(0.06, 0.17, -0.16), eye_mat)

	# Arms (cylindrical limbs)
	_build_arm("l", torso, Vector3(-0.28, 0.48, 0), dark, gear)
	_hand_r = _build_arm("r", torso, Vector3(0.28, 0.48, 0), dark, gear)

	# Legs (cylindrical limbs)
	_build_leg("l", pelvis, Vector3(-0.13, 0, 0), skin, dark)
	_build_leg("r", pelvis, Vector3(0.13, 0, 0), skin, dark)

	# Gun for the armed hunter
	if is_hunter:
		_build_gun(gear)


func _build_arm(side: String, torso: Node3D, shoulder_pos: Vector3, limb_mat: StandardMaterial3D, joint_mat: StandardMaterial3D) -> Node3D:
	var shoulder := _joint("shoulder_" + side, torso, shoulder_pos)
	_mesh_cyl(shoulder, 0.055, 0.30, Vector3(0, -0.15, 0), limb_mat)
	# Elbow joint ball
	var elbow := _joint("elbow_" + side, shoulder, Vector3(0, -0.3, 0))
	_mesh_sphere(elbow, 0.04, Vector3.ZERO, joint_mat)
	_mesh_cyl(elbow, 0.048, 0.28, Vector3(0, -0.14, 0), limb_mat)
	var hand := _joint("hand_" + side, elbow, Vector3(0, -0.28, 0))
	# Tactical Glove block
	_mesh_box(hand, Vector3(0.06, 0.12, 0.08), Vector3(0, -0.06, 0), joint_mat)
	return hand


func _build_leg(side: String, pelvis: Node3D, hip_pos: Vector3, skin: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var hip := _joint("hip_" + side, pelvis, hip_pos)
	_mesh_cyl(hip, 0.07, 0.44, Vector3(0, -0.22, 0), skin)
	# Knee joint ball
	var knee := _joint("knee_" + side, hip, Vector3(0, -0.44, 0))
	_mesh_sphere(knee, 0.05, Vector3.ZERO, dark)
	_mesh_cyl(knee, 0.06, 0.42, Vector3(0, -0.21, 0), dark)
	# Combat Boot
	_mesh_box(knee, Vector3(0.12, 0.12, 0.28), Vector3(0, -0.42, -0.05), dark)


func _build_gun(gear: StandardMaterial3D) -> void:
	_gun = MeshInstance3D.new()
	_gun.name = "Gun"
	var gm := BoxMesh.new()
	gm.size = Vector3(0.08, 0.45, 0.08)
	gm.material = gear
	_gun.mesh = gm
	_gun.position = GUN_REST
	_hand_r.add_child(_gun)

	# Magazine (protruding block beneath barrel)
	var mag := MeshInstance3D.new()
	var mag_mesh := BoxMesh.new()
	mag_mesh.size = Vector3(0.06, 0.12, 0.06)
	var mag_mat := StandardMaterial3D.new()
	mag_mat.albedo_color = Color(0.06, 0.06, 0.08)
	mag_mat.metallic = 0.7
	mag_mat.roughness = 0.3
	mag_mesh.material = mag_mat
	mag.mesh = mag_mesh
	mag.position = Vector3(0, -0.1, 0.06)
	_gun.add_child(mag)

	# Scope dot (small emissive red sphere on top of barrel)
	var scope := MeshInstance3D.new()
	var scope_mesh := SphereMesh.new()
	scope_mesh.radius = 0.015
	scope_mesh.height = 0.03
	var scope_mat := StandardMaterial3D.new()
	scope_mat.albedo_color = Color(1.0, 0.2, 0.1)
	scope_mat.emission_enabled = true
	scope_mat.emission = Color(1.0, 0.2, 0.1)
	scope_mat.emission_energy_multiplier = 3.0
	scope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scope_mesh.material = scope_mat
	scope.mesh = scope_mesh
	scope.position = Vector3(0, 0.05, -0.04)
	_gun.add_child(scope)

	# Muzzle flash
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.85, 0.45)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 6.0
	_muzzle_light.position = Vector3(0, -0.26, 0)
	_gun.add_child(_muzzle_light)

	_muzzle_flash = MeshInstance3D.new()
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2(0.6, 0.6)
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.albedo_color = Color(1.0, 0.8, 0.35, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.85, 0.4)
	flash_mat.emission_energy_multiplier = 5.0
	flash_quad.material = flash_mat
	_muzzle_flash.mesh = flash_quad
	_muzzle_flash.position = Vector3(0, -0.28, 0)
	_muzzle_flash.visible = false
	_gun.add_child(_muzzle_flash)


# ── Rig material helpers ──
static var _mat_cache: Dictionary = {}

## Creates or fetches a cached physically-based material.
func _mat_rig(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key = "norm_%s_%.2f_%.2f" % [c.to_html(), metallic, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	_mat_cache[key] = m
	return m

## Creates or fetches a cached unshaded emissive material.
func _mat_rig_emissive(c: Color, energy: float) -> StandardMaterial3D:
	var key = "emis_%s_%.2f" % [c.to_html(), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


# ── Rig geometry helpers ──
func _joint(jname: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = jname
	parent.add_child(n)
	n.position = pos
	_joints[jname] = n
	return n


func _mesh_box(parent: Node3D, size: Vector3, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = offset
	parent.add_child(mi)


func _mesh_sphere(parent: Node3D, radius: float, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.material = mat
	mi.mesh = sph
	mi.position = offset
	parent.add_child(mi)


func _mesh_cyl(parent: Node3D, radius: float, height: float, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.material = mat
	mi.mesh = cyl
	mi.position = offset
	parent.add_child(mi)


# ====================================================================
# MOVEMENT + INPUT
# ====================================================================

# Movement feel constants
const ACCEL_GROUND   := 28.0   # How fast we ramp UP on the ground
const DECEL_GROUND   := 22.0   # How fast we slow DOWN on the ground
const ACCEL_AIR      := 8.0    # Much less control mid-air
const DECEL_AIR      := 3.0    # Drift slowly to a stop in air
const COYOTE_TIME    := 0.12   # Seconds after leaving a ledge you can still jump
const JUMP_BUFFER    := 0.12   # Seconds before landing that a jump press is remembered

var _coyote_timer: float = 0.0
var _jump_buffer: float = 0.0
var _on_floor_last: bool = false
var _visual_yaw: float = 0.0   # smoothly lagged body facing direction

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_time += delta
	if _cd > 0.0:     _cd -= delta
	if _shoot_t > 0.0: _shoot_t -= delta
	if _hurt_t > 0.0:  _hurt_t -= delta

	var on_floor := is_on_floor()

	# --- Coyote time: keep a grace window after stepping off a ledge ---
	if on_floor:
		_coyote_timer = COYOTE_TIME
	elif _coyote_timer > 0.0:
		_coyote_timer -= delta

	# --- Jump buffer: remember a jump press for a moment before landing ---
	if Input.is_action_just_pressed(_act_jump):
		_jump_buffer = JUMP_BUFFER
	elif _jump_buffer > 0.0:
		_jump_buffer -= delta

	# --- Gravity: apply with a terminal velocity cap ---
	if not on_floor:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)

	# --- Jump (coyote + buffered) ---
	if _jump_buffer > 0.0 and _coyote_timer > 0.0 and not _has_won:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote_timer = 0.0
		_rig.scale = Vector3(0.82, 1.25, 0.82)  # stretch on jump

	# --- Landing squash ---
	if not _on_floor_last and on_floor:
		_rig.scale = Vector3(1.18, 0.78, 1.18)
	_rig.scale = _rig.scale.lerp(Vector3.ONE, 12.0 * delta)
	_on_floor_last = on_floor

	# --- Input ---
	# Fallback to hardcoded keys if actions are not mapped in Project Settings
	var is_running := Input.is_action_pressed("p%d_run" % player_id) if InputMap.has_action("p%d_run" % player_id) else (Input.is_key_pressed(KEY_SHIFT) if player_id == 1 else Input.is_key_pressed(KEY_CTRL))
	var is_crouching := Input.is_action_pressed("p%d_crouch" % player_id) if InputMap.has_action("p%d_crouch" % player_id) else (Input.is_key_pressed(KEY_ALT) if player_id == 1 else Input.is_key_pressed(KEY_TAB))

	var top_speed: float
	if is_crouching:
		top_speed = walk_speed * 0.45
	elif is_running:
		top_speed = run_speed
	else:
		top_speed = walk_speed

	var input_dir := Input.get_vector(_act_left, _act_right, _act_up, _act_down)

	# --- Camera-relative movement direction ---
	var target_vel := Vector3.ZERO
	var cam = get_viewport().get_camera_3d()
	
	if not _has_won and cam:
		var cam_basis: Basis = cam.global_transform.basis
		var cam_forward: Vector3 = -cam_basis.z
		var cam_right: Vector3 = cam_basis.x
		
		# Ensure movement is strictly on the ground plane (ignore camera pitch)
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		cam_right.y = 0
		cam_right = cam_right.normalized()
		
		var is_aiming = GameManager and GameManager.is_armed(player_id) and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		var is_shooting = _shoot_t > 0.0
		
		if input_dir != Vector2.ZERO:
			# Negate input_dir.y so W (negative Y) goes forward along cam_forward
			var move_dir := (cam_right * input_dir.x + cam_forward * -input_dir.y).normalized()
			target_vel = move_dir * top_speed
			
			# Smooth body turn to movement direction always
			var target_yaw := atan2(-move_dir.x, -move_dir.z)
			_visual_yaw = lerp_angle(_visual_yaw, target_yaw, turn_speed * delta)
			_rig.rotation.y = lerp_angle(_rig.rotation.y, _visual_yaw, 18.0 * delta)
		elif is_aiming or is_shooting:
			# If standing still, face aim direction
			var target_yaw := atan2(-cam_forward.x, -cam_forward.z)
			_visual_yaw = lerp_angle(_visual_yaw, target_yaw, 25.0 * delta)
			_rig.rotation.y = lerp_angle(_rig.rotation.y, _visual_yaw, 25.0 * delta)

	# --- Acceleration / deceleration with separate ground vs air curves ---
	var accel := ACCEL_GROUND if on_floor else ACCEL_AIR
	var decel := DECEL_GROUND if on_floor else DECEL_AIR

	if target_vel.length_squared() > 0.01:
		# Accelerate toward target
		velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * top_speed)
		velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * top_speed)
	else:
		# Decelerate to a stop
		velocity.x = move_toward(velocity.x, 0.0, decel * delta * top_speed)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta * top_speed)

	# --- Weapon ---
	if is_hunter and GameManager and GameManager.is_armed(player_id) and not _has_won:
		if _cd <= 0.0 and (Input.is_action_just_pressed(_act_fire) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			_fire()

	# --- Drive procedural skeleton ---
	_animate(delta, input_dir != Vector2.ZERO, is_running, is_crouching)

	move_and_slide()



# ====================================================================
# PROCEDURAL ANIMATION — pick a state, build per-joint target rotations,
# then critically-damp every joint toward them.
# ====================================================================
func _animate(delta: float, moving: bool, running: bool, crouching: bool) -> void:
	var grounded := is_on_floor()

	# Advance the locomotion phase only while actually striding.
	if moving and grounded:
		_anim_phase += delta * (14.0 if running else 9.0)
	var s := sin(_anim_phase)
	var c := cos(_anim_phase)

	# Positional bobbing for the pelvis based on the walk cycle
	var target_pelvis_y := 0.9
	if moving and grounded and not crouching:
		target_pelvis_y = 0.9 + absf(c) * (0.12 if running else 0.06)
	elif crouching:
		target_pelvis_y = 0.65

	if _joints.has("pelvis"):
		_joints["pelvis"].position.y = lerpf(_joints["pelvis"].position.y, target_pelvis_y, 12.0 * delta)

	# Default target = rest pose (all joints zeroed).
	var tp: Dictionary = {}
	for k in _joints.keys():
		tp[k] = Vector3.ZERO

	# Base full-body states
	if _has_won:
		_pose_victory(tp)
	elif _hurt_t > 0.0:
		_pose_hurt(tp)
	elif not grounded:
		if velocity.y > 0.0:
			_pose_jump(tp)
		else:
			_pose_fall(tp)
	elif crouching:
		_pose_crouch(tp)
	elif moving:
		_pose_walk(tp, s, c, running)
	else:
		_pose_idle(tp)
		
	# Upper body overrides (GTA 5 Style Aiming)
	var is_aiming = GameManager and GameManager.is_armed(player_id) and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if (is_aiming or _shoot_t > 0.0) and not _has_won and _hurt_t <= 0.0:
		# Override arms and torso to aim forward
		tp["torso"] = Vector3(0.05, 0, 0)
		tp["head"] = Vector3(0.08, 0, 0)
		tp["shoulder_r"] = Vector3(-PI / 2.0 + 0.1, 0, 0)
		tp["elbow_r"] = Vector3(-0.12, 0, 0)
		tp["shoulder_l"] = Vector3(-PI / 2.0 + 0.35, 0, 0.25)
		tp["elbow_l"] = Vector3(-0.55, 0, 0)
		
		# Braced stance only if standing still
		if not moving and grounded and not crouching:
			tp["hip_l"] = Vector3(-0.2, 0, 0)
			tp["hip_r"] = Vector3(0.2, 0, 0)
			tp["knee_l"] = Vector3(0.25, 0, 0)
			tp["knee_r"] = Vector3(0.2, 0, 0)
			
		# Procedural spine twist and pitch tracking
		var cam = get_viewport().get_camera_3d()
		if cam:
			var cam_fwd = -cam.global_transform.basis.z
			var aim_yaw = atan2(-cam_fwd.x, -cam_fwd.z)
			var spine_twist = wrapf(aim_yaw - _rig.rotation.y, -PI, PI)
			var aim_pitch = asin(cam_fwd.y)
			
			# Distribute 100% of the twist across pelvis and torso so the gun aligns perfectly
			tp["pelvis"].y += spine_twist * 0.25
			tp["torso"].y += spine_twist * 0.75
			tp["head"].y += spine_twist * 0.2  # Head looks slightly further into the turn
			
			tp["head"].x -= aim_pitch * 0.6
			tp["shoulder_r"].x -= aim_pitch
			tp["shoulder_l"].x -= aim_pitch

	# Snappier response for shoot/hurt so they read as reactions.
	var rate: float = clampf((16.0 if (_shoot_t > 0.0 or _hurt_t > 0.0) else 11.0) * delta, 0.0, 1.0)
	for k in _joints.keys():
		var j: Node3D = _joints[k]
		j.rotation = j.rotation.lerp(tp[k], rate)


func _pose_idle(tp: Dictionary) -> void:
	var breath := sin(_time * 2.0)
	tp["torso"] = Vector3(0.02 * breath, 0, 0)
	tp["head"] = Vector3(0.03 * breath, 0, 0)
	tp["shoulder_l"] = Vector3(0.05, 0, -0.12)   # arms hang slightly out
	tp["shoulder_r"] = Vector3(0.05, 0, 0.12)
	tp["elbow_l"] = Vector3(-0.15, 0, 0)
	tp["elbow_r"] = Vector3(-0.15, 0, 0)


func _pose_walk(tp: Dictionary, s: float, c: float, running: bool) -> void:
	var stride: float = 1.1 if running else 0.7
	var lean: float = 0.35 if running else 0.15
	var arm: float = 0.9 if running else 0.55
	
	var s_l = s
	var c_l = c
	var s_r = -s
	var c_r = -c

	tp["torso"] = Vector3(lean, 0, 0)
	tp["pelvis"] = Vector3(0, s_l * 0.12, s_l * 0.05) # hip twist and slight roll
	tp["head"] = Vector3(-lean * 0.6, 0, 0)

	# Left leg
	tp["hip_l"] = Vector3(s_l * stride, 0, 0)
	tp["knee_l"] = Vector3(maxf(0.0, c_l) * 1.5, 0, 0) if running else Vector3(maxf(0.0, s_l + 0.2) * 1.2, 0, 0)

	# Right leg
	tp["hip_r"] = Vector3(s_r * stride, 0, 0)
	tp["knee_r"] = Vector3(maxf(0.0, c_r) * 1.5, 0, 0) if running else Vector3(maxf(0.0, s_r + 0.2) * 1.2, 0, 0)

	# Arms counter-swing the legs.
	tp["shoulder_l"] = Vector3(s_r * arm, 0, -0.1)
	tp["shoulder_r"] = Vector3(s_l * arm, 0, 0.1)
	tp["elbow_l"] = Vector3(-0.5 - maxf(0.0, c_r) * 0.5, 0, 0)
	tp["elbow_r"] = Vector3(-0.5 - maxf(0.0, c_l) * 0.5, 0, 0)


func _pose_jump(tp: Dictionary) -> void:
	tp["torso"] = Vector3(0.15, 0, 0)
	tp["hip_l"] = Vector3(-0.55, 0, 0.05)
	tp["hip_r"] = Vector3(-0.55, 0, -0.05)
	tp["knee_l"] = Vector3(0.9, 0, 0)
	tp["knee_r"] = Vector3(0.9, 0, 0)
	tp["shoulder_l"] = Vector3(-1.2, 0, -0.35)
	tp["shoulder_r"] = Vector3(-1.2, 0, 0.35)
	tp["elbow_l"] = Vector3(-0.5, 0, 0)
	tp["elbow_r"] = Vector3(-0.5, 0, 0)


func _pose_fall(tp: Dictionary) -> void:
	tp["torso"] = Vector3(-0.1, 0, 0)
	tp["head"] = Vector3(0.15, 0, 0)
	tp["hip_l"] = Vector3(-0.2, 0, 0.1)
	tp["hip_r"] = Vector3(-0.2, 0, -0.1)
	tp["knee_l"] = Vector3(0.3, 0, 0)
	tp["knee_r"] = Vector3(0.3, 0, 0)
	tp["shoulder_l"] = Vector3(-0.3, 0, -0.6)
	tp["shoulder_r"] = Vector3(-0.3, 0, 0.6)
	tp["elbow_l"] = Vector3(-0.3, 0, 0)
	tp["elbow_r"] = Vector3(-0.3, 0, 0)


func _pose_crouch(tp: Dictionary) -> void:
	tp["torso"] = Vector3(0.35, 0, 0)
	tp["head"] = Vector3(-0.2, 0, 0)
	tp["hip_l"] = Vector3(0.6, 0, -0.15)
	tp["hip_r"] = Vector3(0.6, 0, 0.15)
	tp["knee_l"] = Vector3(0.9, 0, 0)
	tp["knee_r"] = Vector3(0.9, 0, 0)
	tp["shoulder_l"] = Vector3(-0.3, 0, -0.15)
	tp["shoulder_r"] = Vector3(-0.3, 0, 0.15)
	tp["elbow_l"] = Vector3(-0.6, 0, 0)
	tp["elbow_r"] = Vector3(-0.6, 0, 0)


func _pose_hurt(tp: Dictionary) -> void:
	# Sharp flinch: torso and head jolt back, arms recoil outward.
	tp["torso"] = Vector3(-0.35, 0, 0.12)
	tp["head"] = Vector3(-0.3, 0.2, 0)
	tp["shoulder_l"] = Vector3(-0.2, 0, -0.5)
	tp["shoulder_r"] = Vector3(-0.2, 0, 0.5)
	tp["elbow_l"] = Vector3(-0.7, 0, 0)
	tp["elbow_r"] = Vector3(-0.7, 0, 0)
	tp["hip_l"] = Vector3(-0.15, 0, 0)
	tp["knee_l"] = Vector3(0.25, 0, 0)


func _pose_victory(tp: Dictionary) -> void:
	tp["torso"] = Vector3(-0.12, 0, 0)
	tp["head"] = Vector3(-0.12, 0, 0)
	tp["shoulder_l"] = Vector3(-2.7, 0, -0.25)   # arms thrust overhead
	tp["shoulder_r"] = Vector3(-2.7, 0, 0.25)
	tp["elbow_l"] = Vector3(-0.4, 0, 0)
	tp["elbow_r"] = Vector3(-0.4, 0, 0)


# ====================================================================
# COMBAT REACTIONS
# ====================================================================
func _on_health_changed(pid: int, current: float, _maximum: float) -> void:
	if pid == player_id and current < _last_health and not _is_dead:
		_hurt_t = 0.22   # trigger a flinch
		# Camera shake on hit
		var cam = get_viewport().get_camera_3d()
		if cam and cam.has_method("shake_hit"):
			cam.shake_hit()
	if pid == player_id:
		_last_health = current


func _on_player_died(dead_id: int) -> void:
	if dead_id != player_id or _is_dead:
		return
	_is_dead = true
	set_physics_process(false)

	# Crumple the limbs, then topple the whole rig sideways to the ground.
	_joints["torso"].rotation = Vector3(0.1, 0, 0.2)
	_joints["head"].rotation = Vector3(0.3, 0, 0.4)
	_joints["shoulder_l"].rotation = Vector3(-0.3, 0, -1.0)
	_joints["shoulder_r"].rotation = Vector3(-0.3, 0, 1.0)
	_joints["elbow_l"].rotation = Vector3(-0.6, 0, 0)
	_joints["elbow_r"].rotation = Vector3(-0.6, 0, 0)
	_joints["hip_l"].rotation = Vector3(0.4, 0, 0.3)
	_joints["hip_r"].rotation = Vector3(-0.3, 0, -0.4)
	_joints["knee_l"].rotation = Vector3(1.2, 0, 0)
	_joints["knee_r"].rotation = Vector3(0.8, 0, 0)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rig, "rotation:z", PI / 2.0, 0.55).set_ease(Tween.EASE_IN)
	tw.tween_property(_rig, "position:y", 0.12, 0.55).set_ease(Tween.EASE_IN)


func _on_game_over(winner_id: int) -> void:
	if winner_id == player_id and not _is_dead:
		_has_won = true


func _fire() -> void:
	_cd = fire_cooldown
	_shoot_t = 0.3   # hold the shoot pose briefly

	# Camera shake on fire
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("shake_fire"):
		cam.shake_fire()

	# Muzzle flash burst — light pop + emissive quad for one beat.
	if _muzzle_flash:
		_muzzle_flash.visible = true
		_muzzle_flash.scale = Vector3.ONE * randf_range(0.8, 1.4)
	if _muzzle_light:
		_muzzle_light.light_energy = 8.0
	get_tree().create_timer(0.06).timeout.connect(func():
		if _muzzle_flash: _muzzle_flash.visible = false
		if _muzzle_light: _muzzle_light.light_energy = 0.0
	)

	# Gun recoil kick (local to the hand).
	if _gun:
		_gun.position = GUN_REST + Vector3(0, 0.05, 0)
		_gun.rotation.x = -0.2
		var gtween := create_tween().set_parallel(true)
		gtween.tween_property(_gun, "position", GUN_REST, 0.15).set_ease(Tween.EASE_OUT)
		gtween.tween_property(_gun, "rotation:x", 0.0, 0.15).set_ease(Tween.EASE_OUT)

	# Aim: cast from the camera centre (crosshair) to find the exact target point.
	var space := get_world_3d().direct_space_state

	var muzzle_pos := global_position + Vector3.UP * muzzle_height + global_transform.basis.x * 0.4 - global_transform.basis.z * 0.4
	var target_pos := muzzle_pos - global_transform.basis.z * weapon_range

	if cam:
		var screen_center = get_viewport().get_visible_rect().size / 2.0
		var cam_from = cam.project_ray_origin(screen_center)
		var cam_forward = cam.project_ray_normal(screen_center)
		var cam_to = cam_from + cam_forward * weapon_range

		var cam_query = PhysicsRayQueryParameters3D.create(cam_from, cam_to)
		
		var excludes = [get_rid()]
		var all_players = get_tree().get_nodes_in_group("p1_body_3d") + get_tree().get_nodes_in_group("p2_body_3d")
		for p in all_players:
			if p is CollisionObject3D and p != self:
				excludes.append(p.get_rid())
		cam_query.exclude = excludes
		
		var cam_hit = space.intersect_ray(cam_query)

		if cam_hit:
			target_pos = cam_hit.get("position")
		else:
			target_pos = cam_to

		# Camera recoil (kick the view up a touch).
		var current_pitch = cam.get("_pitch")
		if current_pitch != null:
			cam.set("_pitch", current_pitch + 1.5)

		# Turn the character to face the shot horizontally.
		var flat_dir = (target_pos - global_position)
		flat_dir.y = 0
		if flat_dir.length_squared() > 0.01:
			rotation.y = atan2(-flat_dir.x, -flat_dir.z)

	# Trace from the muzzle to (slightly past) the crosshair target.
	var aim_dir = (target_pos - muzzle_pos).normalized()
	var query := PhysicsRayQueryParameters3D.create(muzzle_pos, target_pos + aim_dir * 1.0)
	query.exclude = [get_rid()]

	var hit := space.intersect_ray(query)
	var final_hit_pos := target_pos

	if not hit.is_empty():
		final_hit_pos = hit.get("position")
		var hit_normal = hit.get("normal", Vector3.UP)
		var collider = hit.get("collider")
		var target_id: int = 2 if player_id == 1 else 1
		if collider != null and collider.is_in_group("p%d_body_3d" % target_id):
			if GameManager:
				GameManager.apply_damage(target_id, damage)
			_spawn_blood_3d(final_hit_pos, hit_normal)
		else:
			# Wall/environment hit — spawn sparks
			_spawn_spark_3d(final_hit_pos, hit_normal)

	_draw_tracer_3d(muzzle_pos, final_hit_pos)


func _spawn_blood_3d(pos: Vector3, normal: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 60
	particles.lifetime = 0.6
	particles.explosiveness = 0.95

	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.04, 0.04)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	mesh.material = mat
	particles.mesh = mesh

	particles.direction = normal
	particles.spread = 55.0
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 16.0
	particles.gravity = Vector3(0, -12, 0)
	particles.damping_min = 3.0
	particles.damping_max = 6.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4

	get_tree().root.add_child(particles)
	particles.global_position = pos

	if normal.distance_squared_to(Vector3.UP) > 0.01 and normal.distance_squared_to(Vector3.DOWN) > 0.01:
		particles.look_at(pos + normal, Vector3.UP)

	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)


## Wall impact spark (for non-player hits)
func _spawn_spark_3d(pos: Vector3, normal: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 20
	particles.lifetime = 0.3
	particles.explosiveness = 0.95

	var mesh := SphereMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.04
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	particles.mesh = mesh

	particles.direction = normal
	particles.spread = 45.0
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 10.0
	particles.gravity = Vector3(0, -8, 0)

	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	get_tree().create_timer(0.6).timeout.connect(particles.queue_free)


func _draw_tracer_3d(start: Vector3, end: Vector3) -> void:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.3)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	cyl.material = mat
	mesh_inst.mesh = cyl

	get_tree().root.add_child(mesh_inst)
	mesh_inst.global_position = start

	if start.distance_squared_to(end) > 0.01:
		mesh_inst.look_at(end, Vector3.UP)
		mesh_inst.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	var dist = start.distance_to(end)
	var travel_time = clampf(dist / 300.0, 0.01, 0.4)

	var tween := create_tween()
	tween.tween_property(mesh_inst, "global_position", end, travel_time)
	tween.tween_callback(mesh_inst.queue_free)

