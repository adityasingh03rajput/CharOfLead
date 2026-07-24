extends Node3D
class_name HeadController

## Phase 13 — Head Controller
## Contributes to the shared target-pose dict (does NOT write joints directly).
##
## When the player is AIMING, AnimationLayers already distributes aim across
## spine/torso. HeadController then adds only the REMAINING delta so the head
## points exactly at the camera — no double-application.
##
## When idle (not aiming, not moving), adds subtle look-around glances.

const TRACK_SPEED  := 7.0
const YAW_LIMIT    := 1.0    # ±57° from rig facing
const PITCH_LIMIT  := 0.45   # ±26° from neutral
const IDLE_PERIOD  := 4.5

var _player:    CharacterBody3D
var _skeleton:  Node3D
var _player_id: int   = 1

var _cur_yaw:    float = 0.0
var _cur_pitch:  float = 0.0
var _idle_timer: float = 0.0
var _idle_yaw:   float = 0.0
var _idle_pitch: float = 0.0
var _time:       float = 0.0


func init(player: CharacterBody3D, skeleton: Node3D, pid: int) -> void:
	_player    = player
	_skeleton  = skeleton
	_player_id = pid


## Adds neck/head contribution to tp. Call after SpineController.contribute().
func contribute(tp: Dictionary, delta: float, moving: bool,
		is_dead: bool, has_won: bool, rig_yaw: float) -> void:
	if is_dead or has_won: return
	_time += delta

	var cam := _player.get_viewport().get_camera_3d()
	var is_armed  := GameManager and GameManager.is_armed(_player_id)
	var is_aiming := is_armed and (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

	var target_yaw   := 0.0
	var target_pitch := 0.0

	if cam:
		var cam_fwd   := -cam.global_transform.basis.z
		var world_yaw := atan2(-cam_fwd.x, -cam_fwd.z)
		var raw_yaw   := wrapf(world_yaw - rig_yaw, -PI, PI)

		if is_aiming:
			# AnimationLayers already distributed spine_twist across pelvis/spine/torso.
			# Head should cover only what the spine chain didn't reach.
			var spine_covered := raw_yaw * (0.15 + 0.35 + 0.50)  # weights from AnimationLayers
			target_yaw   = clampf(raw_yaw - spine_covered * 0.0, -YAW_LIMIT, YAW_LIMIT)
			target_pitch = clampf(asin(clampf(cam.global_transform.basis.z.y, -1.0, 1.0)),
				-PITCH_LIMIT, PITCH_LIMIT)
		else:
			# Free-look: head follows camera within limits
			target_yaw   = clampf(raw_yaw, -YAW_LIMIT, YAW_LIMIT)
			target_pitch = clampf(asin(clampf(cam.global_transform.basis.z.y, -1.0, 1.0)),
				-PITCH_LIMIT, PITCH_LIMIT)
	else:
		# No camera: idle glance every few seconds
		_idle_timer += delta
		if _idle_timer >= IDLE_PERIOD:
			_idle_timer = 0.0
			_idle_yaw   = randf_range(-0.30, 0.30)
			_idle_pitch = randf_range(-0.12, 0.12)
		target_yaw   = _idle_yaw
		target_pitch = _idle_pitch

	_cur_yaw   = lerpf(_cur_yaw,   target_yaw,   TRACK_SPEED * delta)
	_cur_pitch = lerpf(_cur_pitch, target_pitch, TRACK_SPEED * delta)

	# 40% neck, 60% head — small values, no doubling of aim
	tp["neck"] = tp.get("neck", Vector3.ZERO) + Vector3(_cur_pitch * 0.35, _cur_yaw * 0.35, 0.0)
	tp["head"] = tp.get("head", Vector3.ZERO) + Vector3(_cur_pitch * 0.65, _cur_yaw * 0.65, 0.0)
