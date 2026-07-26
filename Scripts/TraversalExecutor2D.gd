class_name TraversalExecutor2D
extends RefCounted
## TraversalExecutor2D.gd — Data-driven, event-based macro execution engine for 2D AI traversal.
##
## Converts high-level edge traversal commands (e.g. CORNER_LEAP + LEFT) into
## multi-frame controller input sequences. Uses physical completion events
## (is_on_ceiling, is_on_wall, is_on_floor, velocity) rather than fixed frame counts.

enum TraversalType { WALK, CLIMB, CORNER_LEAP, WALL_JUMP, DROP, CEILING_SLIDE, ZIP }
enum Direction { NONE, LEFT, RIGHT, UP, DOWN }

# Internal phase state during a multi-frame macro
enum Phase { IMPULSE, HOLD_DIRECTION, LANDING_WAIT }

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
		"completed": false
	}

	if _current_edge.is_empty() or not is_instance_valid(body):
		result.completed = true
		return result

	_timer += delta

	# Global Safety Timeout — if any macro takes longer than 1.5s, force completion
	if _timer >= _timeout:
		result.completed = true
		return result

	var ttype: int = int(_current_edge.get("type", TraversalType.WALK))
	var dir: int   = int(_current_edge.get("dir", Direction.NONE))
	var target_pos: Vector2 = _current_edge.get("pos_to", current_pos)

	# Convert direction enum to vector
	var dir_vec := Vector2.ZERO
	match dir:
		Direction.LEFT:  dir_vec = Vector2.LEFT
		Direction.RIGHT: dir_vec = Vector2.RIGHT
		Direction.UP:    dir_vec = Vector2.UP
		Direction.DOWN:  dir_vec = Vector2.DOWN

	match ttype:
		TraversalType.WALK:
			# Direct floor walk toward target waypoint
			var dx := target_pos.x - current_pos.x
			result.move.x = signf(dx)
			if absf(dx) < 25.0:
				result.completed = true

		TraversalType.CLIMB:
			# Wall climb along vertical face
			var dy := target_pos.y - current_pos.y
			result.move.y = signf(dy)
			result.move.x = dir_vec.x
			if absf(dy) < 35.0:
				result.completed = true

		TraversalType.CORNER_LEAP:
			# Multi-phase macro for vaulting over inside/outside corners:
			# Phase 0 (IMPULSE): Jump + Direction simultaneously
			# Phase 1 (HOLD): Hold Direction while airborne until attached to ceiling/floor
			if _phase == Phase.IMPULSE:
				result.jump = true
				result.move = dir_vec
				if result.move.y == 0.0:
					result.move.y = -1.0  # upward bias for corner clearance
				_phase = Phase.HOLD_DIRECTION
			elif _phase == Phase.HOLD_DIRECTION:
				result.jump = false
				result.move = dir_vec
				# Event completion: attached to ceiling, landed on floor, or attached to wall
				if body.is_on_ceiling() or body.is_on_floor() or (_timer > 0.15 and body.is_on_wall()):
					result.completed = true

		TraversalType.WALL_JUMP:
			# Wall-to-wall leap across open gap
			if _phase == Phase.IMPULSE:
				result.jump = true
				result.move = dir_vec
				_phase = Phase.HOLD_DIRECTION
			elif _phase == Phase.HOLD_DIRECTION:
				result.jump = false
				result.move = dir_vec
				if _timer > 0.15 and (body.is_on_wall() or body.is_on_floor()):
					result.completed = true

		TraversalType.DROP:
			# Releasing ceiling/wall to drop down
			result.move = dir_vec
			if body.is_on_floor() or current_pos.distance_to(target_pos) < 30.0:
				result.completed = true

		TraversalType.CEILING_SLIDE:
			# Moving horizontally along ceiling
			result.move.x = dir_vec.x
			result.move.y = -0.5 # keep ceiling attachment
			if absf(target_pos.x - current_pos.x) < 30.0:
				result.completed = true

		TraversalType.ZIP:
			# Grapple zip line macro
			result.grapple = true
			if current_pos.distance_to(target_pos) < 40.0:
				result.completed = true

	# Arrival threshold fallback for all macros
	if current_pos.distance_to(target_pos) < 30.0:
		result.completed = true

	return result
