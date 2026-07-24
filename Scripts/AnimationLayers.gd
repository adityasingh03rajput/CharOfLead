extends Node3D
class_name AnimationLayers

## Drives all procedural joint rotations via a single shared target-pose dict.
##
## Flow each frame:
##   compute(tp, ...)       — fills tp with base pose (idle/walk/jump/etc.)
##   [SpineController, HeadController, SecondaryMotion add their contributions]
##   apply_pose(tp, delta)  — clamps + lerps every joint toward tp ONCE
##
## No system other than apply_pose() writes directly to joint.rotation.

# ── Anatomical limits (max abs rotation per axis, in radians) ─────────────────
const LIMITS: Dictionary = {
	"head":      Vector3(0.55, 1.15, 0.30),
	"neck":      Vector3(0.40, 0.80, 0.22),
	"torso":     Vector3(0.65, 0.55, 0.30),
	"spine":     Vector3(0.55, 0.45, 0.25),
	"pelvis":    Vector3(0.35, 0.35, 0.20),
	"shoulder_l":Vector3(2.8,  0.60, 0.80),
	"shoulder_r":Vector3(2.8,  0.60, 0.80),
	"elbow_l":   Vector3(1.6,  0.20, 0.20),
	"elbow_r":   Vector3(1.6,  0.20, 0.20),
	"hand_l":    Vector3(0.6,  0.40, 0.40),
	"hand_r":    Vector3(0.6,  0.40, 0.40),
	"hip_l":     Vector3(1.6,  0.40, 0.50),
	"hip_r":     Vector3(1.6,  0.40, 0.50),
	"knee_l":    Vector3(1.6,  0.10, 0.15),
	"knee_r":    Vector3(1.6,  0.10, 0.15),
	"foot_l":    Vector3(0.50, 0.20, 0.35),
	"foot_r":    Vector3(0.50, 0.20, 0.35),
}

var _player:    CharacterBody3D
var _skeleton:  Node3D
var _walk:      Node3D
var _weapon:    Node
var _player_id: int   = 1
var _time:      float = 0.0


func init(player: CharacterBody3D, skeleton: Node3D,
		walk: Node3D, weapon: Node, pid: int) -> void:
	_player    = player
	_skeleton  = skeleton
	_walk      = walk
	_weapon    = weapon
	_player_id = pid


## Step 1: build the target-pose dict. Returns it so other systems can add.
func compute(delta: float, moving: bool, running: bool, crouching: bool,
		prone: bool, is_dead: bool, has_won: bool, melee_t: float,
		visual_yaw: float, rig_yaw: float) -> Dictionary:
	_time += delta

	var grounded := _player.is_on_floor()
	var joints: Dictionary = _skeleton.get("joints")
	var rig: Node3D = _skeleton.get("rig")

	# Pelvis height (positional, not rotational — write directly)
	var target_pelvis_y := 0.9
	if moving and grounded and not crouching:
		target_pelvis_y = 0.9 - absf(sin(_walk.get("anim_phase") * 2.0)) * (0.04 if running else 0.02)
	elif crouching:
		target_pelvis_y = 0.65
	if joints.has("pelvis"):
		(joints["pelvis"] as Node3D).position.y = lerpf(
			(joints["pelvis"] as Node3D).position.y, target_pelvis_y, 12.0 * delta)

	# Start with all joints at zero
	var tp: Dictionary = {}
	for k in joints.keys():
		tp[k] = Vector3.ZERO

	if not is_dead:
		if has_won:
			_pose_victory(tp)
		elif melee_t > 0.0:
			_pose_melee(tp, melee_t)
		elif prone:
			_pose_prone(tp, joints)
		elif crouching:
			_pose_crouch(tp)
		elif not grounded:
			if _player.velocity.y > 0: _pose_jump(tp)
			else:                       _pose_fall(tp)
		elif moving:
			_pose_walk(tp, running)
		else:
			_walk.call("reset_feet", delta)
			_pose_idle(tp)

	# ── Aiming / shooting layer (camera-relative, runs on top of base pose) ───
	var shoot_t: float = (_weapon.get("shoot_t") if _weapon else 0.0)
	var is_armed   := GameManager and GameManager.is_armed(_player_id)
	var is_aiming  := is_armed and (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

	var sway_x := sin(_time * 1.5) * 0.015
	var sway_y := cos(_time * 2.1) * 0.015
	if moving: sway_x += sin(_time * 12.0) * 0.03; sway_y += cos(_time * 24.0) * 0.03

	var recoil := 0.0
	if shoot_t > 0.0:
		recoil = clampf(shoot_t / 0.1, 0.0, 1.0)
		sway_x += randf_range(-0.04, 0.04) * recoil
		sway_y += recoil * 0.10

	if is_aiming and not has_won:
		var cam := _player.get_viewport().get_camera_3d()
		if cam:
			var cam_fwd    := -cam.global_transform.basis.z
			var aim_yaw    := atan2(-cam_fwd.x, -cam_fwd.z)
			var spine_twist := clampf(wrapf(aim_yaw - rig_yaw, -PI, PI), -1.2, 1.2)
			# clamp basis.z.y to [-1,1] so asin() never produces NaN
			var aim_pitch := clampf(asin(clampf(cam.global_transform.basis.z.y, -1.0, 1.0)), -0.7, 0.7)

			# GDScript can't mutate a dict value's field in-place (tp["k"].y += x is a no-op).
			# Read into a local var, modify, then write back.
			var pv: Vector3 = tp.get("pelvis", Vector3.ZERO)
			pv.y += spine_twist * 0.15
			tp["pelvis"] = pv

			var sv: Vector3 = tp.get("spine", Vector3.ZERO)
			sv.y += spine_twist * 0.35
			sv.x -= aim_pitch * 0.20
			tp["spine"] = sv

			var _tv: Vector3 = tp.get("torso", Vector3.ZERO)
			_tv.y += spine_twist * 0.50
			_tv.x -= aim_pitch * 0.35
			tp["torso"] = _tv

		# Recoil / sway accumulates on top of whatever cam block wrote
		var tv2: Vector3 = tp.get("torso", Vector3.ZERO)
		tv2.x += 0.04 - recoil * 0.10
		tv2.y += sway_x
		tp["torso"] = tv2

		tp["shoulder_r"] = Vector3(PI / 2.0 - 0.1 + recoil * 0.15, 0.0, sway_x)
		tp["elbow_r"]    = Vector3(-0.12 - recoil * 0.12, 0.0, 0.0)
		tp["hand_r"]     = Vector3(recoil * -0.15, 0.0, 0.0)
		tp["shoulder_l"] = Vector3(PI / 2.0 - 0.35 + recoil * 0.15, 0.0, 0.20 + sway_x)
		tp["elbow_l"]    = Vector3(-0.50 - recoil * 0.12, 0.0, 0.0)
		tp["hand_l"]     = Vector3(0.0, 0.08, 0.0)

		if not moving and not crouching and not prone and melee_t <= 0.0:
			tp["hip_l"]  = Vector3(0.0,  0.18,  0.08)
			tp["hip_r"]  = Vector3(0.0, -0.18, -0.08)
			tp["knee_l"] = Vector3(0.12, 0.0, 0.0)
			tp["knee_r"] = Vector3(0.12, 0.0, 0.0)
			tp["foot_l"] = Vector3(-0.12, 0.0, 0.0)
			tp["foot_r"] = Vector3(-0.12, 0.0, 0.0)

	return tp


## Step 2: clamp every value to anatomical limits, then lerp joints toward tp.
func apply_pose(tp: Dictionary, delta: float) -> void:
	var shoot_t: float = (_weapon.get("shoot_t") if _weapon else 0.0)
	var hurt_t:  float = (_weapon.get("hurt_t")  if _weapon else 0.0)
	var rate := clampf((16.0 if (shoot_t > 0.0 or hurt_t > 0.0) else 11.0) * delta, 0.0, 1.0)

	var joints: Dictionary = _skeleton.get("joints")
	for k in joints.keys():
		var rot: Vector3 = tp.get(k, Vector3.ZERO)
		# Clamp to anatomical limits
		if LIMITS.has(k):
			var lim: Vector3 = LIMITS[k]
			rot = Vector3(
				clampf(rot.x, -lim.x, lim.x),
				clampf(rot.y, -lim.y, lim.y),
				clampf(rot.z, -lim.z, lim.z))
		(joints[k] as Node3D).rotation = (joints[k] as Node3D).rotation.lerp(rot, rate)


## Trigger an immediate flinch (snappy — bypasses the lerp).
func trigger_hurt() -> void:
	var j: Dictionary = _skeleton.get("joints")
	if j.has("torso"):      (j["torso"]      as Node3D).rotation = Vector3(-0.28, 0.0,  0.10)
	if j.has("head"):       (j["head"]        as Node3D).rotation = Vector3(-0.22, 0.18, 0.0)
	if j.has("shoulder_l"): (j["shoulder_l"]  as Node3D).rotation = Vector3(-0.18, 0.0, -0.40)
	if j.has("shoulder_r"): (j["shoulder_r"]  as Node3D).rotation = Vector3(-0.18, 0.0,  0.40)


# ── Pose library ──────────────────────────────────────────────────────────────

func _pose_idle(tp: Dictionary) -> void:
	var b := sin(_time * 2.0) * 0.012
	tp["spine"]      = Vector3(b,    0.0,  0.0)
	tp["torso"]      = Vector3(b * 1.5, 0.0, 0.0)
	tp["shoulder_l"] = Vector3(0.04, 0.0, -0.10)
	tp["shoulder_r"] = Vector3(0.04, 0.0,  0.10)
	tp["elbow_l"]    = Vector3(0.14, 0.0,  0.0)
	tp["elbow_r"]    = Vector3(0.14, 0.0,  0.0)


func _pose_walk(tp: Dictionary, running: bool) -> void:
	var rig: Node3D = _skeleton.get("rig")
	var local_vel := Vector3.ZERO
	if rig: local_vel = rig.global_transform.basis.inverse() * _player.velocity
	var spd := maxf(local_vel.length(), 0.1)
	var fwd_ratio   := clampf(-local_vel.z / spd, -1.0, 1.0)
	var right_ratio := clampf( local_vel.x / spd, -1.0, 1.0)
	var move_mag    := minf(1.0, absf(fwd_ratio) + absf(right_ratio))

	var ph  : float = _walk.get("anim_phase")
	var s_l := sin(ph);  var c_l := cos(ph)
	var s_r := -s_l;     var c_r := -c_l
	var stride: float = 0.90 if running else 0.60

	tp["hip_l"]  = Vector3(s_l * stride * fwd_ratio,  0.0, s_l * stride * right_ratio * 0.6)
	tp["knee_l"] = Vector3(-(0.16 + maxf(0.0, c_l) * 0.80 * move_mag), 0.0, s_l * 0.025 * move_mag)
	tp["foot_l"] = Vector3((-0.15 * maxf(0.0, s_l) + 0.18 * maxf(0.0, -s_l)) * fwd_ratio, 0.0, 0.0)
	tp["hip_r"]  = Vector3(s_r * stride * fwd_ratio,  0.0, s_r * stride * right_ratio * 0.6)
	tp["knee_r"] = Vector3(-(0.16 + maxf(0.0, c_r) * 0.80 * move_mag), 0.0, s_r * 0.025 * move_mag)
	tp["foot_r"] = Vector3((-0.15 * maxf(0.0, s_r) + 0.18 * maxf(0.0, -s_r)) * fwd_ratio, 0.0, 0.0)

	var pelvis_twist := s_l * 0.13 * fwd_ratio
	tp["pelvis"] = Vector3(0.0, pelvis_twist, 0.0)
	var spine_twist := -pelvis_twist * 0.70
	var t_pitch     := 0.06 if running else -0.02
	tp["spine"] = Vector3(t_pitch * fwd_ratio * 0.5, spine_twist * 0.40 - right_ratio * 0.03, 0.0)
	tp["torso"] = Vector3(t_pitch * fwd_ratio,       spine_twist * 0.60 - right_ratio * 0.03, 0.0)
	# neck/head stabilise against spine — HeadController will refine further
	tp["neck"] = Vector3(-t_pitch * fwd_ratio * 0.4, -spine_twist * 0.25, 0.0)
	tp["head"] = Vector3(-t_pitch * fwd_ratio * 0.5, -spine_twist * 0.30, 0.0)

	var s_arm := sin(ph - 0.21)
	var arm_s : float = 0.75 if running else 0.45
	tp["shoulder_l"] = Vector3(s_r * arm_s * fwd_ratio, spine_twist * -0.2, -0.07 - right_ratio * 0.07)
	tp["shoulder_r"] = Vector3(s_l * arm_s * fwd_ratio, spine_twist *  0.2,  0.07 - right_ratio * 0.07)
	tp["elbow_l"]    = Vector3(0.38 + maxf(0.0,  s_arm * fwd_ratio) * 0.30, 0.0, 0.0)
	tp["elbow_r"]    = Vector3(0.38 + maxf(0.0, -s_arm * fwd_ratio) * 0.30, 0.0, 0.0)
	tp["hand_l"]     = Vector3(-0.07, 0.0, 0.0)
	tp["hand_r"]     = Vector3(-0.07, 0.0, 0.0)


func _pose_jump(tp: Dictionary) -> void:
	tp["spine"]      = Vector3(0.08,  0.0,  0.0)
	tp["torso"]      = Vector3(0.04,  0.0,  0.0)
	tp["hip_l"]      = Vector3(-0.50, 0.0,  0.05)
	tp["hip_r"]      = Vector3(-0.50, 0.0, -0.05)
	tp["knee_l"]     = Vector3(-0.85, 0.0,  0.0)
	tp["knee_r"]     = Vector3(-0.85, 0.0,  0.0)
	tp["foot_l"]     = Vector3(0.18,  0.0,  0.0)
	tp["foot_r"]     = Vector3(0.18,  0.0,  0.0)
	tp["shoulder_l"] = Vector3(-1.1,  0.0, -0.30)
	tp["shoulder_r"] = Vector3(-1.1,  0.0,  0.30)
	tp["elbow_l"]    = Vector3(0.45,  0.0,  0.0)
	tp["elbow_r"]    = Vector3(0.45,  0.0,  0.0)


func _pose_fall(tp: Dictionary) -> void:
	tp["spine"]      = Vector3(-0.04, 0.0,  0.0)
	tp["torso"]      = Vector3(-0.04, 0.0,  0.0)
	tp["neck"]       = Vector3( 0.08, 0.0,  0.0)
	tp["head"]       = Vector3( 0.08, 0.0,  0.0)
	tp["hip_l"]      = Vector3(-0.18, 0.0,  0.08)
	tp["hip_r"]      = Vector3(-0.18, 0.0, -0.08)
	tp["knee_l"]     = Vector3(-0.28, 0.0,  0.0)
	tp["knee_r"]     = Vector3(-0.28, 0.0,  0.0)
	tp["foot_l"]     = Vector3(-0.08, 0.0,  0.0)
	tp["foot_r"]     = Vector3(-0.08, 0.0,  0.0)
	tp["shoulder_l"] = Vector3(-0.28, 0.0, -0.55)
	tp["shoulder_r"] = Vector3(-0.28, 0.0,  0.55)
	tp["elbow_l"]    = Vector3(0.28,  0.0,  0.0)
	tp["elbow_r"]    = Vector3(0.28,  0.0,  0.0)


func _pose_crouch(tp: Dictionary) -> void:
	tp["spine"]      = Vector3( 0.18, 0.0,  0.0)
	tp["torso"]      = Vector3( 0.12, 0.0,  0.0)
	tp["neck"]       = Vector3(-0.08, 0.0,  0.0)
	tp["head"]       = Vector3(-0.10, 0.0,  0.0)
	tp["hip_l"]      = Vector3( 0.55, 0.0, -0.12)
	tp["hip_r"]      = Vector3( 0.55, 0.0,  0.12)
	tp["knee_l"]     = Vector3(-0.85, 0.0,  0.0)
	tp["knee_r"]     = Vector3(-0.85, 0.0,  0.0)
	tp["foot_l"]     = Vector3(-0.28, 0.0,  0.0)
	tp["foot_r"]     = Vector3(-0.28, 0.0,  0.0)
	tp["shoulder_l"] = Vector3(-0.28, 0.0, -0.12)
	tp["shoulder_r"] = Vector3(-0.28, 0.0,  0.12)
	tp["elbow_l"]    = Vector3( 0.55, 0.0,  0.0)
	tp["elbow_r"]    = Vector3( 0.55, 0.0,  0.0)


func _pose_prone(tp: Dictionary, joints: Dictionary) -> void:
	if joints.has("pelvis"):
		(joints["pelvis"] as Node3D).position.y = lerpf(
			(joints["pelvis"] as Node3D).position.y, 0.2, 0.2)
	tp["spine"]      = Vector3(1.2,  0.0,  0.0)
	tp["torso"]      = Vector3(0.18, 0.0,  0.0)
	tp["neck"]       = Vector3(-0.85, 0.0, 0.0)
	tp["head"]       = Vector3(-0.40, 0.0, 0.0)
	tp["hip_l"]      = Vector3(-1.3, 0.0, -0.18)
	tp["hip_r"]      = Vector3(-1.3, 0.0,  0.18)
	tp["knee_l"]     = Vector3(0.08, 0.0,  0.0)
	tp["knee_r"]     = Vector3(0.08, 0.0,  0.0)
	tp["foot_l"]     = Vector3(0.25, 0.0,  0.0)
	tp["foot_r"]     = Vector3(0.25, 0.0,  0.0)
	tp["shoulder_l"] = Vector3(1.1,  0.0, -0.35)
	tp["shoulder_r"] = Vector3(1.1,  0.0,  0.35)
	tp["elbow_l"]    = Vector3(-0.7, 0.0,  0.0)
	tp["elbow_r"]    = Vector3(-0.7, 0.0,  0.0)


func _pose_melee(tp: Dictionary, melee_t: float) -> void:
	var t := 1.0 - (melee_t / 0.4)
	if t < 0.5:
		tp["spine"]      = Vector3(0.0, -0.35, 0.0)
		tp["shoulder_r"] = Vector3(0.45, 0.0,  0.35)
		tp["elbow_r"]    = Vector3(-0.9, 0.0,  0.0)
	else:
		tp["spine"]      = Vector3(0.0,  0.45, 0.0)
		tp["shoulder_r"] = Vector3(1.2,  0.0, -0.18)
		tp["elbow_r"]    = Vector3(-0.08,0.0,  0.0)
		tp["hand_r"]     = Vector3(-0.18,0.0,  0.0)
	tp["hip_l"]  = Vector3(0.18, 0.0, 0.08)
	tp["knee_l"] = Vector3(-0.25,0.0, 0.0)


func _pose_victory(tp: Dictionary) -> void:
	tp["torso"]      = Vector3(-0.10, 0.0,  0.0)
	tp["shoulder_l"] = Vector3(-2.5,  0.0, -0.22)
	tp["shoulder_r"] = Vector3(-2.5,  0.0,  0.22)
	tp["elbow_l"]    = Vector3(0.35,  0.0,  0.0)
	tp["elbow_r"]    = Vector3(0.35,  0.0,  0.0)
