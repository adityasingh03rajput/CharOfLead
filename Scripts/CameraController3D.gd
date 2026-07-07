extends Camera3D
## CameraController3D.gd — GTA5-style third-person orbit camera.
## Mouse controls the camera orbit around the player.
## Smoothly follows the target from behind and above.

@export var target: Node3D

@export_group("Orbit")
@export var distance: float = 10.0
@export var min_distance: float = 4.0
@export var max_distance: float = 20.0
@export var height_offset: float = 2.0        # look-at point above player feet
@export var mouse_sensitivity: float = 0.003

@export_group("Pitch Limits")
@export var min_pitch: float = -80.0           # look almost straight down
@export var max_pitch: float = 60.0            # look up

@export_group("Smoothing")
@export var follow_speed: float = 8.0
@export var zoom_speed: float = 4.0

@export_group("Aim / Free Fire feel")
@export var default_fov: float = 75.0
@export var ads_fov: float = 45.0          # narrowed field-of-view when aiming
@export var ads_distance: float = 3.2      # camera pulls in over the shoulder
@export var fov_speed: float = 12.0
@export var shoulder_offset: float = 0.6   # over-the-shoulder framing (hip fire)
@export var ads_shoulder: float = 0.32     # tighter when aiming

var _ads: bool = false

var _yaw: float = 0.0        # horizontal orbit angle (radians)
var _pitch: float = -30.0    # vertical tilt (degrees, negative = looking down)

# Screen shake
var _shake_intensity: float = 0.0
var _shake_decay: float = 12.0
var _shake_offset: Vector3 = Vector3.ZERO

# Camera presets config
@export_group("Presets")
@export var preset_third_person := Vector2(-25.0, 10.0) # Pitch, Distance
@export var preset_birds_eye := Vector2(-85.0, 20.0)
@export var preset_isometric := Vector2(-40.0, 16.0)
@export var preset_first_person := Vector2(0.0, 0.0)

enum Preset { THIRD_PERSON, BIRDS_EYE, ISOMETRIC, FIRST_PERSON }
var _current_preset: int = Preset.THIRD_PERSON

var _target_pitch: float = -25.0
var _target_distance: float = 10.0

# New variables for auto-orbit stability
var _auto_orbit_angle: float = 0.0
var _is_auto_orbiting: bool = false
var _last_mouse_time: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	fov = default_fov
	near = 0.01
	_apply_preset(_current_preset)
	if target:
		_yaw = target.rotation.y  # Initialize to match player facing


func _apply_preset(idx: int) -> void:
	match idx:
		Preset.THIRD_PERSON:
			_target_pitch = preset_third_person.x
			_target_distance = preset_third_person.y
		Preset.BIRDS_EYE:
			_target_pitch = preset_birds_eye.x
			_target_distance = preset_birds_eye.y
		Preset.ISOMETRIC:
			_target_pitch = preset_isometric.x
			_target_distance = preset_isometric.y
		Preset.FIRST_PERSON:
			_target_pitch = preset_first_person.x
			_target_distance = preset_first_person.y


## Fire recoil shake — quick, directional (mostly up-kick).
func shake_fire() -> void:
	_shake_intensity = maxf(_shake_intensity, 0.08)

## Impact shake — stronger, omni-directional.
func shake_hit() -> void:
	_shake_intensity = maxf(_shake_intensity, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	# C key cycles camera presets
	if event.is_action_pressed("toggle_camera"):
		_current_preset = (_current_preset + 1) % 4
		_apply_preset(_current_preset)
		if _current_preset == Preset.BIRDS_EYE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Mouse movement rotates the orbit (only if captured)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_target_pitch -= event.relative.y * mouse_sensitivity * 60.0
		_target_pitch = clampf(_target_pitch, min_pitch, max_pitch)
		
		# Reset auto-orbit when mouse moves
		_is_auto_orbiting = false
		_last_mouse_time = Time.get_ticks_msec() / 1000.0

	# Scroll wheel zooms in/out
	if event is InputEventMouseButton:
		var zoom_step = maxf(distance * 0.1, 0.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = maxf(_target_distance - zoom_step, min_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = minf(_target_distance + zoom_step, max_distance)

	# Dedicated input action for mouse toggle (instead of ui_cancel)
	if event.is_action_pressed("p1_jump"): # Can be replaced with actual toggle mapping later if needed
		pass


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
		
	_pitch = lerpf(_pitch, _target_pitch, 8.0 * delta)
	distance = lerpf(distance, _target_distance, 8.0 * delta)

	# Decay screen shake using offset
	if _shake_intensity > 0.001:
		h_offset = sin(Time.get_ticks_msec() * 0.05) * _shake_intensity * 0.5
		v_offset = cos(Time.get_ticks_msec() * 0.04) * _shake_intensity * 0.5
		_shake_intensity = lerpf(_shake_intensity, 0.0, _shake_decay * delta)
	else:
		h_offset = 0.0
		v_offset = 0.0
		_shake_intensity = 0.0

	var third_person := _current_preset != Preset.FIRST_PERSON

	# Free Fire aim-down-sights: hold Right Mouse (via action map if available)
	var ads_input = Input.is_action_pressed("p2_fire") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_ads = third_person and ads_input

	# IMPROVED: Auto-orbit with mouse input detection
	if third_person and not _ads:
		var dist_to_target := (global_position - target.global_position).length()
		var current_time := Time.get_ticks_msec() / 1000.0
		var time_since_mouse := current_time - _last_mouse_time
		
		# Only auto-orbit if mouse hasn't been moved recently and character is very close
		if dist_to_target < 2.5 and time_since_mouse > 0.1:
			_is_auto_orbiting = true
			var target_yaw = target.rotation.y
			
			# Check if we need to orbit (more than 30 degree difference)
			var angle_diff = abs(angle_difference(_yaw, target_yaw))
			if angle_diff > 0.3:
				# Smooth but controlled rotation
				var speed = clampf(10.0 * (1.0 - (dist_to_target / 3.0)), 2.0, 8.0)
				_yaw = lerp_angle(_yaw, target_yaw, speed * delta)
			else:
				_yaw = target_yaw
				_is_auto_orbiting = false
		else:
			_is_auto_orbiting = false
	
	var target_fov = ads_fov if _ads else default_fov
	if abs(fov - target_fov) > 0.1:
		fov = lerpf(fov, target_fov, fov_speed * delta)
		
	# Use different distance for ADS vs normal
	var eff_distance: float
	if third_person:
		eff_distance = maxf(ads_distance if _ads else distance, min_distance)
	else:
		eff_distance = 0.4  # First person

	# The point we orbit around (player position + height offset)
	var look_point := target.global_position + Vector3.UP * height_offset

	# Over-the-shoulder framing: shift the pivot along the camera's right axis
	if third_person:
		var shoulder_amt: float = ads_shoulder if _ads else shoulder_offset
		var camera_right := Vector3(cos(_yaw), 0.0, -sin(_yaw)).normalized()
		look_point += camera_right * shoulder_amt

	# Calculate desired camera position from yaw/pitch/distance
	var pitch_rad := deg_to_rad(_pitch)
	var offset := Vector3(
		sin(_yaw) * cos(pitch_rad) * eff_distance,
		-sin(pitch_rad) * eff_distance,
		cos(_yaw) * cos(pitch_rad) * eff_distance
	)

	var desired_pos := look_point + offset

	if not third_person:
		# First-person view
		var forward := Vector3(
			sin(_yaw) * cos(pitch_rad),
			-sin(pitch_rad),
			cos(_yaw) * cos(pitch_rad)
		).normalized()
		desired_pos = look_point - forward * 0.4
		
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(look_point, desired_pos)
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			desired_pos = hit.get("position")
	else:
		# IMPROVED: Raycast with better collision resolution
		var space := get_world_3d().direct_space_state
		
		# Use a shorter ray if we're auto-orbiting to prevent bouncing
		var ray_end = desired_pos
		if _is_auto_orbiting:
			# Temporarily reduce distance for auto-orbit to prevent jitter
			var temp_distance = lerp(eff_distance, eff_distance * 0.7, 0.5)
			ray_end = look_point + (desired_pos - look_point).normalized() * temp_distance
		
		var query := PhysicsRayQueryParameters3D.create(look_point, ray_end)
		query.hit_from_inside = true
		
		var excludes = []
		var all_players = get_tree().get_nodes_in_group("p1_body_3d") + get_tree().get_nodes_in_group("p2_body_3d")
		for p in all_players:
			if p is CollisionObject3D:
				excludes.append(p.get_rid())
		query.exclude = excludes
		
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			# Push camera away from wall with better offset
			var hit_pos: Vector3 = hit.get("position")
			var dir_from_wall := (hit_pos - look_point).normalized()
			
			# Larger offset to prevent camera from pushing through walls
			desired_pos = hit_pos + dir_from_wall * 0.5
			
			# Ensure we don't go below minimum distance
			var actual_dist = (desired_pos - look_point).length()
			if actual_dist < min_distance * 0.5:
				desired_pos = look_point + dir_from_wall * min_distance * 0.5
		elif _is_auto_orbiting:
			# If no wall hit during auto-orbit, ensure smooth transition
			var center_dir = (desired_pos - look_point).normalized()
			desired_pos = look_point + center_dir * min(eff_distance, distance * 0.9)

	# IMPROVED: Smoother following with different speeds for different situations
	var follow_speed_multiplier = 1.0
	if _is_auto_orbiting:
		# Faster follow during auto-orbit to keep up with player
		follow_speed_multiplier = 1.5
	
	var current_speed = follow_speed * follow_speed_multiplier
	
	# Limit maximum movement per frame to prevent teleporting
	var max_move = distance * 2.0 * delta
	var movement = desired_pos - global_position
	if movement.length() > max_move:
		movement = movement.normalized() * max_move
	
	global_position += movement
	
	var look_dir = (look_point - global_position).normalized()
	var up_vec = Vector3.UP
	if abs(look_dir.y) > 0.99:
		up_vec = Vector3(-sin(_yaw), 0, -cos(_yaw))
		if up_vec.length_squared() < 0.01:
			up_vec = Vector3.FORWARD
		
	look_at(look_point, up_vec)


# Helper function for angle difference
static func angle_difference(from: float, to: float) -> float:
	var diff = fmod(to - from, PI * 2)
	if diff > PI:
		diff -= PI * 2
	elif diff < -PI:
		diff += PI * 2
	return abs(diff)
