extends Node3D
class_name CosmeticSystem

## Phase 20 — Cosmetic System
## Manages attachment points on the skeleton so gear (helmets, capes,
## backpacks, glasses, etc.) can be added/removed without touching body code.
## Each attachment anchors to a named joint and inherits its world transform.

var _skeleton: Node3D

# Attachment point nodes (created lazily)
var _anchors: Dictionary = {}   # slot name -> Node3D

# Known slots and which joint they parent to
const SLOTS: Dictionary = {
	"helmet":    "head",
	"hat":       "head",
	"mask":      "head",
	"glasses":   "head",
	"backpack":  "torso",
	"cape":      "torso",
	"armor_chest": "torso",
	"armor_l":   "shoulder_l",
	"armor_r":   "shoulder_r",
	"holster_l": "hip_l",
	"holster_r": "hip_r",
}

# Equipped items: slot -> MeshInstance3D (or null)
var _equipped: Dictionary = {}


func init(skeleton: Node3D) -> void:
	_skeleton = skeleton
	# Pre-create anchor nodes parented to each joint
	var joints: Dictionary = skeleton.get("joints")
	for slot in SLOTS:
		var joint_name: String = SLOTS[slot]
		if joints.has(joint_name):
			var anchor := Node3D.new()
			anchor.name = "Anchor_" + slot
			(joints[joint_name] as Node3D).add_child(anchor)
			_anchors[slot] = anchor


## Equip a mesh at the given slot. Returns the MeshInstance3D for further tweaking.
func equip(slot: String, mesh: Mesh, offset: Vector3 = Vector3.ZERO,
		mat: StandardMaterial3D = null) -> MeshInstance3D:
	unequip(slot)
	if not _anchors.has(slot):
		push_warning("CosmeticSystem: unknown slot '%s'" % slot)
		return null

	var mi := MeshInstance3D.new()
	mi.mesh     = mesh
	mi.position = offset
	if mat: mi.set_surface_override_material(0, mat)
	(_anchors[slot] as Node3D).add_child(mi)
	_equipped[slot] = mi
	return mi


## Remove and free whatever is in the slot.
func unequip(slot: String) -> void:
	if _equipped.has(slot) and is_instance_valid(_equipped[slot]):
		(_equipped[slot] as Node3D).queue_free()
	_equipped.erase(slot)


func is_equipped(slot: String) -> bool:
	return _equipped.has(slot) and is_instance_valid(_equipped[slot])


## Convenience: equip a box-mesh helmet at the head slot.
func equip_helmet(color: Color = Color(0.1, 0.1, 0.12),
		size: Vector3 = Vector3(0.32, 0.22, 0.30)) -> MeshInstance3D:
	var bm  := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic     = 0.6
	mat.roughness    = 0.35
	bm.material      = mat
	return equip("helmet", bm, Vector3(0, 0.18, 0))


## Convenience: equip a simple cape (quad mesh hanging from torso).
func equip_cape(color: Color = Color(0.6, 0.05, 0.05)) -> MeshInstance3D:
	var qm    := QuadMesh.new()
	qm.size   = Vector2(0.34, 0.55)
	var mat   := StandardMaterial3D.new()
	mat.albedo_color      = color
	mat.transparency      = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a    = 0.92
	mat.cull_mode         = BaseMaterial3D.CULL_DISABLED
	qm.material = mat
	return equip("cape", qm, Vector3(0, -0.05, 0.22))
