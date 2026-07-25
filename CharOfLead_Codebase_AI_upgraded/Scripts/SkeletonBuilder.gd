extends Node3D
class_name SkeletonBuilder

## Builds and owns the entire procedural rig hierarchy.
## Exposes `joints` dict (name -> Node3D) and `rig` (visual root).
## No animation logic lives here — only construction.

const _DataScript = preload("res://Scripts/HumanData.gd")

var joints: Dictionary = {}
var rig: Node3D
var hand_r: Node3D

static var _mat_cache: Dictionary = {}


func build(data: Resource, weapon_factory: Node) -> void:
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)

	var skin  := _mat(data.team_color, 0.1, 0.55)
	var dark  := _mat(data.team_color.darkened(0.5), 0.15, 0.65)
	var gear  := _mat(Color(0.08, 0.08, 0.1), 0.6, 0.35)
	var eyes  := _mat_emissive(data.team_color.lightened(0.5), 2.5)

	# Pelvis (skeleton root), ~0.9 m above feet
	var pelvis := _joint("pelvis", rig, Vector3(0, 0.95, 0))
	_box(pelvis, Vector3(0.36, 0.16, 0.22), Vector3.ZERO, gear)
	_box(pelvis, Vector3(0.38, 0.08, 0.24), Vector3.ZERO, dark)
	_box(pelvis, Vector3(0.1, 0.12, 0.1),   Vector3(0.12, 0.0, -0.12), gear)
	_box(pelvis, Vector3(0.1, 0.12, 0.1),   Vector3(-0.12, 0.0, -0.12), gear)

	# Spine / lower torso
	var spine := _joint("spine", pelvis, Vector3(0, 0.08, 0))
	_box(spine, Vector3(0.32, 0.22, 0.20), Vector3(0, 0.11, 0), dark)

	# Chest / upper torso
	var torso := _joint("torso", spine, Vector3(0, 0.22, 0))
	_box(torso, Vector3(0.44, 0.32, 0.24), Vector3(0, 0.16, 0), skin)
	_box(torso, Vector3(0.3, 0.4, 0.15),   Vector3(0, 0.15, 0.18), gear)  # backpack
	_sphere(torso, 0.08, Vector3(-0.26, 0.26, 0), dark)
	_sphere(torso, 0.08, Vector3(0.26, 0.26, 0),  dark)

	# Neck
	var neck := _joint("neck", torso, Vector3(0, 0.32, 0))
	_cyl(neck, 0.06, 0.12, Vector3(0, 0.06, 0), skin)

	# Head + visor + eyes
	var head := _joint("head", neck, Vector3(0, 0.12, 0))
	_sphere(head, 0.15,  Vector3(0, 0.15, 0), skin)
	_box(head,   Vector3(0.22, 0.08, 0.06), Vector3(0, 0.17, -0.13), gear)
	_sphere(head, 0.025, Vector3(-0.06, 0.17, -0.16), eyes)
	_sphere(head, 0.025, Vector3(0.06,  0.17, -0.16), eyes)

	# Arms
	_build_arm("l", torso, Vector3(-0.28, 0.26, 0), dark, gear)
	hand_r = _build_arm("r", torso, Vector3(0.28, 0.26, 0), dark, gear)

	# Legs
	_build_leg("l", pelvis, Vector3(-0.13, -0.08, 0), skin, dark)
	_build_leg("r", pelvis, Vector3(0.13,  -0.08, 0), skin, dark)

	# Let WeaponFactory attach its nodes to hand_r.
	# Use call() — weapon_factory is typed as Node so direct method access is unsafe.
	if data.is_hunter and weapon_factory and weapon_factory.has_method("build"):
		weapon_factory.call("build", hand_r, gear)


func _build_arm(side: String, parent: Node3D, shoulder_pos: Vector3,
		limb: StandardMaterial3D, joint_mat: StandardMaterial3D) -> Node3D:
	var sh := _joint("shoulder_" + side, parent, shoulder_pos)
	_cyl(sh, 0.055, 0.30, Vector3(0, -0.15, 0), limb)
	var el := _joint("elbow_" + side, sh, Vector3(0, -0.3, 0))
	_sphere(el, 0.04, Vector3.ZERO, joint_mat)
	_cyl(el, 0.048, 0.28, Vector3(0, -0.14, 0), limb)
	var hand := _joint("hand_" + side, el, Vector3(0, -0.28, 0))
	_box(hand, Vector3(0.06, 0.12, 0.08), Vector3(0, -0.06, 0), joint_mat)
	return hand


func _build_leg(side: String, parent: Node3D, hip_pos: Vector3,
		skin: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var hip := _joint("hip_" + side, parent, hip_pos)
	_taper(hip, 0.075, 0.060, 0.44, Vector3(0, -0.22, 0), skin)
	_sphere(hip, 0.075, Vector3.ZERO, skin)

	var knee := _joint("knee_" + side, hip, Vector3(0, -0.44, 0))
	_sphere(knee, 0.06, Vector3.ZERO, dark)
	_taper(knee, 0.060, 0.045, 0.38, Vector3(0, -0.19, 0), dark)

	var foot := _joint("foot_" + side, knee, Vector3(0, -0.38, 0))
	_sphere(foot, 0.045, Vector3.ZERO, dark)
	_box(foot, Vector3(0.13, 0.11, 0.36), Vector3(0, -0.055, -0.08), dark)


# ── Joint helper ─────────────────────────────────────────────────────────────
func _joint(jname: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = jname
	parent.add_child(n)
	n.position = pos
	joints[jname] = n
	return n


# ── Mesh helpers ──────────────────────────────────────────────────────────────
func _box(parent: Node3D, size: Vector3, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var m  := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	mi.position = offset
	parent.add_child(mi)

func _sphere(parent: Node3D, r: float, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var m  := SphereMesh.new()
	m.radius = r
	m.height  = r * 2.0
	m.material = mat
	mi.mesh = m
	mi.position = offset
	parent.add_child(mi)

func _cyl(parent: Node3D, r: float, h: float, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var m  := CylinderMesh.new()
	m.top_radius    = r
	m.bottom_radius = r
	m.height        = h
	m.material      = mat
	mi.mesh = m
	mi.position = offset
	parent.add_child(mi)

func _taper(parent: Node3D, top_r: float, bot_r: float, h: float,
		offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var m  := CylinderMesh.new()
	m.top_radius    = top_r
	m.bottom_radius = bot_r
	m.height        = h
	m.material      = mat
	mi.mesh = m
	mi.position = offset
	parent.add_child(mi)


# ── Material cache ────────────────────────────────────────────────────────────
func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var key := "norm_%s_%.2f_%.2f" % [c.to_html(), metallic, roughness]
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic     = metallic
	m.roughness    = roughness
	_mat_cache[key] = m
	return m

func _mat_emissive(c: Color, energy: float) -> StandardMaterial3D:
	var key := "emis_%s_%.2f" % [c.to_html(), energy]
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color            = c
	m.emission_enabled        = true
	m.emission                = c
	m.emission_energy_multiplier = energy
	m.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m
