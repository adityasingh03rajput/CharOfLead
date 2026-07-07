extends Camera2D
## CameraController2D.gd — Handles camera presets for the 2D arena.
## Press 'C' to toggle between Full Map Overview and a zoomed-in "Eye View" follow camera.

var target: Node2D
var _current_preset: int = 0

func _ready() -> void:
	_apply_preset(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		_current_preset = (_current_preset + 1) % 2
		_apply_preset(_current_preset)


func _apply_preset(idx: int) -> void:
	pass


func _process(delta: float) -> void:
	# If this camera is not inside the active environment, do nothing
	if get_parent() and not get_parent().visible:
		return
		
	if _current_preset == 0:
		# Overview
		global_position = global_position.lerp(Vector2.ZERO, 5.0 * delta)
		zoom = zoom.lerp(Vector2(0.75, 0.75), 5.0 * delta)
		rotation = lerp_angle(rotation, 0.0, 5.0 * delta)
	else:
		# First-Person / Follow View (Looking towards Red)
		if target:
			var enemy := get_tree().get_first_node_in_group("p1_body_2d") as Node2D
			var desired_pos := target.global_position
			var desired_rot := rotation
			
			if enemy:
				# Pull the camera heavily towards the Red player's direction
				# This keeps Blue on screen but centers the view on the space between them
				desired_pos = target.global_position.lerp(enemy.global_position, 0.45)
				# Point the camera "forward" towards the enemy by rotating it.
				# In Godot, -Y (UP) is the top of the screen. 
				# We add PI/2 (90 deg) to the vector angle to make it face UP.
				var angle_to_enemy = (enemy.global_position - target.global_position).angle()
				desired_rot = angle_to_enemy + PI / 2.0
			else:
				# Fallback if Red is missing
				var mouse_pos = get_global_mouse_position()
				var look_ahead = (mouse_pos - target.global_position).clamp(Vector2(-300, -300), Vector2(300, 300)) * 0.3
				desired_pos = target.global_position + look_ahead
				
			global_position = global_position.lerp(desired_pos, 8.0 * delta)
			zoom = zoom.lerp(Vector2(1.8, 1.8), 5.0 * delta)
			rotation = lerp_angle(rotation, desired_rot, 6.0 * delta)
