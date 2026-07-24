extends Node3D
class_name FootIK

## Phase 11 — Foot IK
## Every frame: raycast down from each foot's world position,
## read the ground normal, then tilt the ankle joint to conform.
## Also adjusts pelvis height to prevent feet from clipping into slopes.

const RAYCAST_ORIGIN_HEIGHT := 0.5   # cast from this height above foot
const RAYCAST_LENGTH        := 0.8   # cast this far down
const FOOT_TILT_SPEED       := 12.0  # lerp speed for ankle rotation

var _player:   CharacterBody3D
var _skeleton: Node3D

var _foot_l_rot: Vector3 = Vector3.ZERO
var _foot_r_rot: Vector3 = Vector3.ZERO
var _pelvis_offset: float = 0.0


func init(player: CharacterBody3D, skeleton: Node3D) -> void:
	_player   = player
	_skeleton = skeleton


func apply(delta: float) -> void:
	var joints: Dictionary = _skeleton.get("joints")
	if joints.is_empty() or not _player.is_on_floor(): return

	var space := _player.get_world_3d().direct_space_state

	# Sample both feet
	var l_result := _cast_foot(space, joints, "foot_l")
	var r_result := _cast_foot(space, joints, "foot_r")

	# Tilt ankles to match ground normal
	if l_result.hit and joints.has("foot_l"):
		var target_rot := _normal_to_ankle_rot(l_result.normal)
		_foot_l_rot = _foot_l_rot.lerp(target_rot, FOOT_TILT_SPEED * delta)
		(joints["foot_l"] as Node3D).rotation += _foot_l_rot
	else:
		_foot_l_rot = _foot_l_rot.lerp(Vector3.ZERO, FOOT_TILT_SPEED * delta)

	if r_result.hit and joints.has("foot_r"):
		var target_rot := _normal_to_ankle_rot(r_result.normal)
		_foot_r_rot = _foot_r_rot.lerp(target_rot, FOOT_TILT_SPEED * delta)
		(joints["foot_r"] as Node3D).rotation += _foot_r_rot
	else:
		_foot_r_rot = _foot_r_rot.lerp(Vector3.ZERO, FOOT_TILT_SPEED * delta)

	# Raise pelvis if the lowest foot is above the character's floor origin
	# (prevents legs from stretching through stairs/slopes)
	var low_foot_y := minf(l_result.ground_y, r_result.ground_y)
	var target_offset := clampf(low_foot_y - _player.global_position.y, -0.2, 0.15)
	_pelvis_offset = lerpf(_pelvis_offset, target_offset, 8.0 * delta)
	if joints.has("pelvis"):
		(joints["pelvis"] as Node3D).position.y += _pelvis_offset


# Returns hit normal and ground Y in world space
func _cast_foot(space: PhysicsDirectSpaceState3D, joints: Dictionary, jname: String) -> Dictionary:
	var result := {"hit": false, "normal": Vector3.UP, "ground_y": _player.global_position.y}
	if not joints.has(jname): return result

	var foot_world := (joints[jname] as Node3D).global_position
	var from := foot_world + Vector3.UP * RAYCAST_ORIGIN_HEIGHT
	var to   := foot_world + Vector3.DOWN * RAYCAST_LENGTH

	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1   # environment only

	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		result["hit"]      = true
		result["normal"]   = hit.get("normal", Vector3.UP)
		result["ground_y"] = (hit.get("position") as Vector3).y
	return result


# Convert a ground normal into ankle rotation (pitch + roll to match slope)
func _normal_to_ankle_rot(normal: Vector3) -> Vector3:
	var rig: Node3D = _skeleton.get("rig")
	var local_normal := normal
	if rig:
		local_normal = rig.global_transform.basis.inverse() * normal
	# Pitch: slope in Z direction; Roll: slope in X direction
	return Vector3(
		-asin(clampf(local_normal.z, -1.0, 1.0)) * 0.6,
		0.0,
		 asin(clampf(local_normal.x, -1.0, 1.0)) * 0.6)
