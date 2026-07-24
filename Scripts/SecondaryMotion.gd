extends Node3D
class_name SecondaryMotion

## Phase 14 — Secondary Motion
## Contributes micro-inertia to the shared target-pose dict via spring physics.
## Values are deliberately small — this adds FEEL, not visible swing.
## Nothing here should ever compete with the base pose or aim system.

var _springs: Dictionary = {}
var _prev_velocity: Vector3 = Vector3.ZERO
var _player:  CharacterBody3D
var _skeleton: Node3D
var _weapon_bob_target: Vector3 = Vector3.ZERO


func init(player: CharacterBody3D, skeleton: Node3D) -> void:
	_player   = player
	_skeleton = skeleton
	_register("chest",  14.0, 7.0)
	_register("head",   12.0, 6.5)
	_register("weapon", 18.0, 8.0)
	_register("lean",    8.0, 5.0)


## Set each frame by Player3D from walk-cycle phase.
func set_weapon_bob(bob: Vector3) -> void:
	_weapon_bob_target = bob


## Contributes spring offsets to tp. Call after HeadController.contribute().
func contribute(tp: Dictionary, delta: float) -> void:
	var vel: Vector3   = _player.velocity
	var accel: Vector3 = (vel - _prev_velocity) / maxf(delta, 0.001)
	_prev_velocity = vel

	var rig: Node3D = _skeleton.get("rig")
	var local_accel := Vector3.ZERO
	if rig: local_accel = rig.global_transform.basis.inverse() * accel

	# Chest tilts opposite to acceleration (tiny)
	var chest_target := Vector3(
		clampf(-local_accel.z * 0.0015, -0.03, 0.03),
		0.0,
		clampf( local_accel.x * 0.0015, -0.02, 0.02))
	var chest := _tick("chest", chest_target, delta)

	# Head counter-moves slightly
	var head_target := Vector3(-chest.x * 0.3, clampf(-local_accel.x * 0.0008, -0.02, 0.02), 0.0)
	var head  := _tick("head",  head_target,  delta)

	# Weapon bob from walk phase
	var weapon := _tick("weapon", _weapon_bob_target, delta)

	# Lateral lean on strafe
	var lean_target := Vector3(0.0, 0.0, clampf(local_accel.x * -0.0010, -0.02, 0.02))
	var lean  := _tick("lean",  lean_target,  delta)

	# Write into tp — these are additive nudges, not replacements
	tp["torso"]      = tp.get("torso",      Vector3.ZERO) + Vector3(chest.x, 0.0, chest.z)
	tp["head"]       = tp.get("head",       Vector3.ZERO) + head
	tp["shoulder_r"] = tp.get("shoulder_r", Vector3.ZERO) + Vector3(weapon.y * 0.25, weapon.x * 0.12, 0.0)

	# Lean is applied to the rig root, not a joint — handle separately
	if rig:
		rig.rotation.z = lerpf(rig.rotation.z, lean.z, 5.0 * delta)


# ── Spring internals ──────────────────────────────────────────────────────────
func _register(name: String, k: float, d: float) -> void:
	_springs[name] = {"v": Vector3.ZERO, "val": Vector3.ZERO, "k": k, "d": d}

func _tick(name: String, target: Vector3, delta: float) -> Vector3:
	var s: Dictionary = _springs[name]
	var f: Vector3 = (target - s["val"]) * s["k"] - s["v"] * s["d"]
	s["v"]   += f * delta
	s["val"] += s["v"] * delta
	return s["val"]
