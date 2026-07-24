extends Node3D
class_name SpineController

## Phase 12 — Spine Controller
## Contributes to the shared target-pose dict (does NOT write joints directly).
## Adds: forward lean, landing impact squish, crouch hunch.
## Aim pitch is handled by AnimationLayers to avoid double-application.

const SPEED := 9.0

var _player:   CharacterBody3D
var _skeleton: Node3D

var _fwd_lean_cur:  float = 0.0
var _impact_cur:    float = 0.0
var _was_on_floor:  bool  = true


func init(player: CharacterBody3D, skeleton: Node3D, _pid: int) -> void:
	_player   = player
	_skeleton = skeleton


## Adds spine contributions to tp. Call after AnimationLayers.compute().
func contribute(tp: Dictionary, delta: float, moving: bool,
		running: bool, crouching: bool, is_dead: bool, has_won: bool) -> void:
	if is_dead or has_won: return

	var on_floor := _player.is_on_floor()

	# Landing impact
	if not _was_on_floor and on_floor: _impact_cur = 0.14
	_impact_cur  = lerpf(_impact_cur,  0.0, 11.0 * delta)
	_was_on_floor = on_floor

	# Forward lean into travel direction
	var rig: Node3D = _skeleton.get("rig")
	var fwd_vel := 0.0
	if rig and moving:
		var lv := rig.global_transform.basis.inverse() * _player.velocity
		fwd_vel = clampf(-lv.z / maxf(_player.velocity.length(), 0.1), -1.0, 1.0)
	var lean_target := fwd_vel * (0.06 if running else 0.03)
	_fwd_lean_cur = lerpf(_fwd_lean_cur, lean_target, SPEED * delta)

	var total := _fwd_lean_cur - _impact_cur * 0.4
	tp["pelvis"] = tp.get("pelvis", Vector3.ZERO) + Vector3(total * 0.10, 0.0, 0.0)
	tp["spine"]  = tp.get("spine",  Vector3.ZERO) + Vector3(total * 0.35, 0.0, 0.0)
	tp["torso"]  = tp.get("torso",  Vector3.ZERO) + Vector3(total * 0.55, 0.0, 0.0)
