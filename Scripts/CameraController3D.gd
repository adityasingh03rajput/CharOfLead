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


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	fov = default_fov
	_apply_preset(_current_preset)


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

	# Mouse movement rotates the orbit
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * mouse_sensitivity
		_target_pitch -= event.relative.y * mouse_sensitivity * 60.0
		_target_pitch = clampf(_target_pitch, min_pitch, max_pitch)

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


func _process(delta: float) -> void:
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
	
	var target_fov = ads_fov if _ads else default_fov
	if abs(fov - target_fov) > 0.1:
		fov = lerpf(fov, target_fov, fov_speed * delta)
		
	var eff_distance: float = ads_distance if _ads else distance

	# The point we orbit around (player position + height offset)
	var look_point := target.global_position + Vector3.UP * height_offset

	# Over-the-shoulder framing: shift the pivot along the camera's right axis
	# so the player sits to one side and the crosshair centre stays clear.
	if third_person:
		var shoulder_amt: float = ads_shoulder if _ads else shoulder_offset
		look_point += global_transform.basis.x * shoulder_amt

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
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			desired_pos = hit.get("position")
	else:
		# Raycast to prevent clipping through walls in third-person modes
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(look_point, desired_pos)
		
		var excludes = []
		var all_players = get_tree().get_nodes_in_group("p1_body_3d") + get_tree().get_nodes_in_group("p2_body_3d")
		for p in all_players:
			if p is CollisionObject3D:
				excludes.append(p.get_rid())
		query.exclude = excludes
		
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			desired_pos = hit.get("position") + (look_point - hit.get("position")).normalized() * 0.4

	# Smoothly follow
	global_position = global_position.lerp(desired_pos, follow_speed * delta)
	
	var look_dir = (look_point - global_position).normalized()
	var up_vec = Vector3.UP
	if abs(look_dir.y) > 0.99:
		# Use the orbital yaw to establish the 'up' direction to prevent 90-degree camera roll
		up_vec = Vector3(-sin(_yaw), 0, -cos(_yaw))
		if up_vec.length_squared() < 0.01:
			up_vec = Vector3.FORWARD
		
	look_at(look_point, up_vec)


