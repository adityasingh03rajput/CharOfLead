class_name TraversalExecutor2D
extends RefCounted
## TraversalExecutor2D.gd — Data-driven, event-based macro execution engine for 2D AI traversal.
##
## Converts high-level edge traversal commands (e.g. CORNER_LEAP + LEFT) into
## multi-frame controller input sequences. Verifies SUCCESS vs FAILURE conditions.

enum TraversalType { WALK, CLIMB, CORNER_LEAP, WALL_JUMP, DROP, CEILING_SLIDE, ZIP }
enum Direction { NONE, LEFT, RIGHT, UP, DOWN }

enum Phase { IMPULSE, HOLD_DIRECTION }

var _current_edge: Dictionary = {}
var _phase: int = Phase.IMPULSE
var _timer: float = 0.0
var _timeout: float = 1.2
var _start_pos: Vector2 = Vector2.ZERO

func start_edge(edge_info: Dictionary, self_pos: Vector2) -> void:
	_current_edge = edge_info
	_phase = Phase.IMPULSE
	_timer = 0.0
	_timeout = float(edge_info.get("timeout", 1.2))
	_start_pos = self_pos


func tick(delta: float, body: CharacterBody2D, current_pos: Vector2) -> Dictionary:
	var result := {
		"move": Vector2.ZERO,
		"jump": false,
		"grapple": false,
		"completed": false,
		"failed": false
	}

	if _current_edge.is_empty() or not is_instance_valid(body):
		result.completed = true
		result.failed = false
		return result

	_timer += delta

	var ttype: int = int(_current_edge.get("type", TraversalType.WALK))
	var dir: int   = int(_current_edge.get("dir", Direction.NONE))
	var target_pos: Vector2 = _current_edge.get("pos_to", current_pos)

	# Global Safety Timeout — if macro exceeds timeout, mark as failed
	if _timer >= _timeout:
		result.completed = true
		result.failed = true
		return result

	# Direction vector calculation
	var dir_vec := Vector2.ZERO
	match dir:
		Direction.LEFT:  dir_vec = Vector2.LEFT
		Direction.RIGHT: dir_vec = Vector2.RIGHT
		Direction.UP:    dir_vec = Vector2.UP
		Direction.DOWN:  dir_vec = Vector2.DOWN

	var dist_to_target := current_pos.distance_to(target_pos)

	match ttype:
		TraversalType.WALK:
			var dx := target_pos.x - current_pos.x
			result.move.x = signf(dx)
			if absf(dx) < 25.0 or dist_to_target < 30.0:
				result.completed = true
				result.failed = false
			elif _timer > 0.6 and body.get_real_velocity().length_squared() < 10.0:
				result.completed = true
				result.failed = true

		TraversalType.CLIMB:
			var dy := target_pos.y - current_pos.y
			result.move.y = signf(dy)
			result.move.x = dir_vec.x
			if absf(dy) < 35.0 or dist_to_target < 30.0:
				result.completed = true
				result.failed = false
			elif _timer > 0.6 and body.get_real_velocity().length_squared() < 10.0:
				result.completed = true
				result.failed = true

		TraversalType.CORNER_LEAP:
			# Multi-phase leap for inside/outside corners:
			# IMPULSE: Jump + Direction bias
			# HOLD_DIRECTION: Hold direction toward target until reaching target surface
			if _phase == Phase.IMPULSE:
				result.jump = true
				result.move = (target_pos - current_pos).normalized()
				if result.move.y == 0.0:
					result.move.y = -1.0
				_phase = Phase.HOLD_DIRECTION
			elif _phase == Phase.HOLD_DIRECTION:
				result.jump = false
				result.move = (target_pos - current_pos).normalized()

				# SUCCESS: Reached target proximity or attached to target surface
				if dist_to_target < 40.0 or body.is_on_ceiling() or (target_pos.y > current_pos.y and body.is_on_floor()):
					result.completed = true
					result.failed = false
				# FAILURE: Fell back down to starting surface without reaching target
				elif _timer > 0.35 and body.is_on_floor() and current_pos.distance_to(_start_pos) < 60.0:
					result.completed = true
					result.failed = true

		TraversalType.WALL_JUMP:
			if _phase == Phase.IMPULSE:
				result.jump = true
				result.move = (target_pos - current_pos).normalized()
				_phase = Phase.HOLD_DIRECTION
			elif _phase == Phase.HOLD_DIRECTION:
				result.jump = false
				result.move = (target_pos - current_pos).normalized()

				if dist_to_target < 40.0 or (body.is_on_wall() and current_pos.distance_to(_start_pos) > 50.0):
					result.completed = true
					result.failed = false
				elif _timer > 0.40 and body.is_on_floor():
					result.completed = true
					result.failed = true

		TraversalType.DROP:
			result.move = dir_vec
			if body.is_on_floor() or dist_to_target < 30.0:
				result.completed = true
				result.failed = false

		TraversalType.CEILING_SLIDE:
			result.move.x = dir_vec.x
			result.move.y = -0.5
			if absf(target_pos.x - current_pos.x) < 30.0 or dist_to_target < 30.0:
				result.completed = true
				result.failed = false

		TraversalType.ZIP:
			result.grapple = true
			if dist_to_target < 40.0:
				result.completed = true
				result.failed = false

	return result
