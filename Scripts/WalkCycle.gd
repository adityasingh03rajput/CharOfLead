extends Node3D
class_name WalkCycle

## Manages locomotion phase, foot-plant targets, and the 2-bone leg IK solver.
## Reads velocity from the owning CharacterBody3D; writes foot world positions.

var anim_phase: float = 0.0

var foot_l_local: Vector3 = Vector3(-0.13, 0.0, 0.0)
var foot_r_local: Vector3 = Vector3(0.13,  0.0, 0.0)
var step_l_t:    float = 0.0
var step_r_t:    float = 0.0

var _player: CharacterBody3D
var _rig:    Node3D   # visual root, owned by SkeletonBuilder


func init(player: CharacterBody3D, rig: Node3D) -> void:
	_player = player
	_rig    = rig


func advance(delta: float, moving: bool, running: bool) -> void:
	if moving and _player.is_on_floor():
		anim_phase += delta * (14.0 if running else 9.0)
		_update_foot_plants(delta, running)
	elif not moving:
		foot_l_local = foot_l_local.lerp(Vector3(-0.13, 0.0, 0.0), 6.0 * delta)
		foot_r_local = foot_r_local.lerp(Vector3(0.13,  0.0, 0.0), 6.0 * delta)


func reset_feet(delta: float) -> void:
	foot_l_local = foot_l_local.lerp(Vector3(-0.13, 0.0, 0.0), 0.1)
	foot_r_local = foot_r_local.lerp(Vector3(0.13,  0.0, 0.0), 0.1)


func _update_foot_plants(delta: float, running: bool) -> void:
	var local_vel := Vector3.ZERO
	if _rig:
		local_vel = _rig.global_transform.basis.inverse() * _player.velocity

	var stride    := local_vel.length() * (0.28 if running else 0.22)
	var step_spd  := 14.0 if running else 8.0
	var fwd       := local_vel.normalized()

	var left_target  := Vector3(-0.13, 0.0, 0.0) + fwd * (-stride * 0.5)
	var right_target := Vector3( 0.13, 0.0, 0.0) + fwd * ( stride * 0.5)

	var s      := sin(anim_phase)
	step_l_t = clampf(maxf(0.0,  s), 0.0, 1.0)
	step_r_t = clampf(maxf(0.0, -s), 0.0, 1.0)

	if step_l_t > 0.05:
		foot_l_local = foot_l_local.lerp(left_target,  delta * step_spd * step_l_t)
	if step_r_t > 0.05:
		foot_r_local = foot_r_local.lerp(right_target, delta * step_spd * step_r_t)


# ── 2-Bone IK (law of cosines) ────────────────────────────────────────────────
## Returns the knee world position given a hip→foot segment and bone lengths.
static func solve_leg_ik(hip: Vector3, foot: Vector3,
		thigh_len: float, shin_len: float, knee_out: float) -> Vector3:
	var leg_vec  := foot - hip
	var leg_dist := clampf(leg_vec.length(), 0.01, thigh_len + shin_len - 0.01)
	leg_vec = leg_vec.normalized() * leg_dist

	var cos_hip := (leg_dist * leg_dist + thigh_len * thigh_len - shin_len * shin_len) \
		/ (2.0 * leg_dist * thigh_len)
	cos_hip = clampf(cos_hip, -1.0, 1.0)
	var ang_hip := acos(cos_hip)

	var hint := Vector3(0.0, -1.0, knee_out).normalized()
	var perp  := leg_vec.normalized().cross(hint).normalized()
	perp = perp.cross(leg_vec.normalized()).normalized()

	return hip + leg_vec.normalized() * thigh_len * cos(ang_hip) \
		       + perp * thigh_len * sin(ang_hip)
