extends Node3D
class_name WeaponFactory

## Builds all gun meshes, manages weapon state, fires projectiles, and
## spawns visual effects. Expose shoot_t / hurt_t so AnimationLayers can read them.

enum Weapon { PISTOL, RIFLE, SHOTGUN, BOMB }

@export var damage:       float = 34.0
@export var weapon_range: float = 50.0
@export var fire_cooldown: float = 0.35
@export var muzzle_height: float = 1.2

var shoot_t:    float = 0.0
var hurt_t:     float = 0.0
var cooldown:   float = 0.0
var grenade_cd: float = 0.0
var current_weapon: int = Weapon.PISTOL

const GUN_REST := Vector3(0, -0.2, 0)

var _player:       CharacterBody3D
var _player_id:    int = 1

var _gun_pistol:  Node3D
var _gun_rifle:   Node3D
var _gun_shotgun: Node3D
var _gun_bomb:    Node3D
var _muzzle_light: OmniLight3D
var _muzzle_flash: MeshInstance3D
var _hand_r:       Node3D


func init(player: CharacterBody3D, pid: int) -> void:
	_player    = player
	_player_id = pid


## Called by SkeletonBuilder — attaches all weapon nodes to hand_r.
func build(hand_r: Node3D, gear: StandardMaterial3D) -> void:
	_hand_r = hand_r
	_build_pistol(gear)
	_build_rifle(gear)
	_build_shotgun(gear)
	_build_bomb()
	_build_muzzle_fx()


func tick(delta: float) -> void:
	if cooldown  > 0.0: cooldown  -= delta
	if shoot_t   > 0.0: shoot_t   -= delta
	if hurt_t    > 0.0: hurt_t    -= delta
	if grenade_cd > 0.0: grenade_cd -= delta


func set_weapon(w: int) -> void:
	if current_weapon == w: return
	current_weapon = w
	if _gun_pistol:  _gun_pistol.visible  = (w == Weapon.PISTOL)
	if _gun_rifle:   _gun_rifle.visible   = (w == Weapon.RIFLE)
	if _gun_shotgun: _gun_shotgun.visible = (w == Weapon.SHOTGUN)
	if _gun_bomb:    _gun_bomb.visible    = (w == Weapon.BOMB)
	cooldown = 0.3
	if GameManager:
		GameManager.pop_weapon_name(_player_id, get_weapon_name(w))


func get_weapon_name(w: int) -> String:
	match w:
		Weapon.PISTOL:  return "PISTOL"
		Weapon.RIFLE:   return "ASSAULT RIFLE"
		Weapon.SHOTGUN: return "TACTICAL SHOTGUN"
		Weapon.BOMB:    return "C4 STICKY BOMB"
	return "UNKNOWN"


func try_fire() -> void:
	if cooldown > 0.0: return
	if current_weapon == Weapon.BOMB:
		throw_bomb()
		return
	_fire()


func throw_bomb() -> void:
	cooldown   = 0.8
	shoot_t    = 0.3
	grenade_cd = 1.0

	var cam := _player.get_viewport().get_camera_3d()
	var cam_fwd: Vector3 = -cam.global_transform.basis.z if cam else \
		-_player.global_transform.basis.z
	cam_fwd = cam_fwd.normalized()
	var spawn_pos := _player.global_position + Vector3.UP * 1.4 + cam_fwd * 0.6

	var bomb := RigidBody3D.new()
	bomb.contact_monitor = true
	bomb.max_contacts_reported = 4

	var cs   := CollisionShape3D.new()
	var bshp := BoxShape3D.new()
	bshp.size = Vector3(0.2, 0.12, 0.3)
	cs.shape = bshp
	bomb.add_child(cs)

	var mi   := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size  = Vector3(0.2, 0.12, 0.3)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.22, 0.25)
	bmat.roughness    = 0.7
	bm.material = bmat
	mi.mesh = bm
	bomb.add_child(mi)

	var strip := MeshInstance3D.new()
	var sm    := BoxMesh.new()
	sm.size   = Vector3(0.21, 0.03, 0.1)
	var smat  := StandardMaterial3D.new()
	smat.albedo_color          = Color(0.95, 0.15, 0.1)
	smat.emission_enabled      = true
	smat.emission              = Color(0.95, 0.15, 0.1)
	smat.emission_energy_multiplier = 1.5
	sm.material  = smat
	strip.position = Vector3(0, 0.05, 0)
	bomb.add_child(strip)

	var led := OmniLight3D.new()
	led.name          = "LEDLight"
	led.light_color   = Color(1.0, 0.1, 0.1)
	led.light_energy  = 3.0
	led.omni_range    = 2.5
	bomb.add_child(led)

	_attach_bomb_script(bomb)
	_player.get_tree().root.add_child(bomb)
	bomb.global_position = spawn_pos
	bomb.linear_velocity  = cam_fwd * 18.0 + Vector3(0, 7.5, 0)
	bomb.angular_velocity = Vector3(
		randf_range(-14.0, 14.0),
		randf_range(-8.0,  8.0),
		randf_range(-14.0, 14.0))

	if _gun_bomb:
		_gun_bomb.position  = GUN_REST + Vector3(0, 0.25, -0.35)
		_gun_bomb.rotation.x = -0.7
		var tw := _player.create_tween().set_parallel(true)
		tw.tween_property(_gun_bomb, "position",   GUN_REST, 0.35).set_ease(Tween.EASE_OUT)
		tw.tween_property(_gun_bomb, "rotation:x", 0.0,      0.35).set_ease(Tween.EASE_OUT)


func do_melee(rig: Node3D) -> void:
	var space := _player.get_world_3d().direct_space_state
	var mpos  := _player.global_position + Vector3(0, 1.0, 0)
	var dir   := -rig.global_transform.basis.z

	var q  := PhysicsShapeQueryParameters3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.8
	q.shape     = ss
	q.transform = Transform3D(Basis(), mpos + dir * 0.8)
	q.exclude   = [_player.get_rid()]

	var hits := space.intersect_shape(q)
	var target_id := 2 if _player_id == 1 else 1
	for hit in hits:
		if hit.get("collider"):
			var col = hit.collider
			if col.is_in_group("p%d_body_3d" % target_id) and GameManager:
				GameManager.apply_damage(target_id, 25.0)
				spawn_blood(_player.global_position + Vector3(0, 1.0, 0),
					(_player.global_position - col.global_position).normalized())
				break


# ── Private fire ──────────────────────────────────────────────────────────────
func _fire() -> void:
	var w_dmg: float
	var w_cd:  float
	var is_shotgun := false

	match current_weapon:
		Weapon.PISTOL:  w_dmg = 28.0; w_cd = 0.35
		Weapon.RIFLE:   w_dmg = 14.0; w_cd = 0.1
		Weapon.SHOTGUN: w_dmg = 12.0; w_cd = 0.8; is_shotgun = true
		_:              w_dmg = damage; w_cd = fire_cooldown

	cooldown = w_cd
	shoot_t  = 0.2

	var active_gun: Node3D = _gun_pistol
	if current_weapon == Weapon.RIFLE:   active_gun = _gun_rifle
	if current_weapon == Weapon.SHOTGUN: active_gun = _gun_shotgun

	var cam := _player.get_viewport().get_camera_3d()
	if cam and cam.has_method("shake_fire"):
		cam.shake_fire()

	if _muzzle_flash:
		_muzzle_flash.visible = true
		_muzzle_flash.scale   = Vector3.ONE * randf_range(0.8, 1.4)
	if _muzzle_light:
		_muzzle_light.light_energy = 8.0
	_player.get_tree().create_timer(0.06).timeout.connect(func():
		if _muzzle_flash: _muzzle_flash.visible = false
		if _muzzle_light: _muzzle_light.light_energy = 0.0)

	if active_gun:
		active_gun.position  = GUN_REST + Vector3(0, 0.05, 0)
		active_gun.rotation.x = -0.2
		var tw := _player.create_tween().set_parallel(true)
		tw.tween_property(active_gun, "position",   GUN_REST, 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(active_gun, "rotation:x", 0.0,      0.15).set_ease(Tween.EASE_OUT)

	var space      := _player.get_world_3d().direct_space_state
	var muzzle_pos := _player.global_position + Vector3.UP * muzzle_height \
		+ _player.global_transform.basis.x * 0.4 \
		- _player.global_transform.basis.z * 0.4

	var screen_center := _player.get_viewport().get_visible_rect().size / 2.0
	var cam_from  := cam.project_ray_origin(screen_center) if cam else _player.global_position
	var cam_fwd   := cam.project_ray_normal(screen_center) if cam else -_player.global_transform.basis.z
	var target_pos := cam_from + cam_fwd * weapon_range

	if cam:
		var cq := PhysicsRayQueryParameters3D.create(cam_from, target_pos)
		var exc := [_player.get_rid()]
		for p in _player.get_tree().get_nodes_in_group("p1_body_3d") + \
				 _player.get_tree().get_nodes_in_group("p2_body_3d"):
			if p is CollisionObject3D and p != _player:
				exc.append(p.get_rid())
		cq.exclude = exc
		var ch := space.intersect_ray(cq)
		if ch: target_pos = ch.get("position")

		var cur_pitch = cam.get("_pitch")
		if cur_pitch != null:
			cam.set("_pitch", cur_pitch + (2.5 if is_shotgun else 1.5))

		var flat := (target_pos - _player.global_position)
		flat.y = 0.0
		if flat.length_squared() > 0.01 and _player.has_method("_sync_visual_yaw"):
			_player._sync_visual_yaw(atan2(-flat.x, -flat.z))

	var rays := 5 if is_shotgun else 1
	var target_id := 2 if _player_id == 1 else 1
	for _i in range(rays):
		var aim_dir := (target_pos - muzzle_pos).normalized()
		if is_shotgun:
			aim_dir = (aim_dir + Vector3(randf_range(-0.1,0.1), randf_range(-0.1,0.1), randf_range(-0.1,0.1))).normalized()

		var rq  := PhysicsRayQueryParameters3D.create(muzzle_pos, muzzle_pos + aim_dir * weapon_range)
		rq.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(rq)
		var final_pos := muzzle_pos + aim_dir * weapon_range

		if not hit.is_empty():
			final_pos    = hit.get("position")
			var hit_norm = hit.get("normal", Vector3.UP)
			var col      = hit.get("collider")
			if col != null and col.is_in_group("p%d_body_3d" % target_id):
				if GameManager: GameManager.apply_damage(target_id, w_dmg)
				spawn_blood(final_pos, hit_norm)
			else:
				spawn_spark(final_pos, hit_norm)
		draw_tracer(muzzle_pos, final_pos)


# ── Build helpers ─────────────────────────────────────────────────────────────
func _build_pistol(gear: StandardMaterial3D) -> void:
	_gun_pistol = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.35, 0.08)
	bm.material = gear
	mi.mesh = bm
	_gun_pistol.add_child(mi)
	_gun_pistol.position = GUN_REST
	_hand_r.add_child(_gun_pistol)

func _build_rifle(gear: StandardMaterial3D) -> void:
	_gun_rifle = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.8, 0.12)
	bm.material = gear
	mi.mesh = bm
	_gun_rifle.add_child(mi)
	_gun_rifle.position = GUN_REST + Vector3(0, 0, 0.2)
	_gun_rifle.visible  = false
	_hand_r.add_child(_gun_rifle)

func _build_shotgun(gear: StandardMaterial3D) -> void:
	_gun_shotgun = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.6, 0.1)
	bm.material = gear
	mi.mesh = bm
	_gun_shotgun.add_child(mi)
	_gun_shotgun.position = GUN_REST + Vector3(0, 0, 0.1)
	_gun_shotgun.visible  = false
	_hand_r.add_child(_gun_shotgun)

func _build_bomb() -> void:
	_gun_bomb = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.1, 0.24)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.2, 0.22)
	bm.material = mat
	mi.mesh = bm
	_gun_bomb.add_child(mi)

	var strip := MeshInstance3D.new()
	var sm    := BoxMesh.new()
	sm.size   = Vector3(0.17, 0.02, 0.08)
	var smat  := StandardMaterial3D.new()
	smat.albedo_color          = Color(1.0, 0.2, 0.1)
	smat.emission_enabled      = true
	smat.emission              = Color(1.0, 0.2, 0.1)
	smat.emission_energy_multiplier = 2.0
	sm.material = smat
	strip.position = Vector3(0, 0.04, 0)
	_gun_bomb.add_child(strip)

	_gun_bomb.position = GUN_REST + Vector3(0, 0, 0.05)
	_gun_bomb.visible  = false
	_hand_r.add_child(_gun_bomb)

func _build_muzzle_fx() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color  = Color(1.0, 0.85, 0.45)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range   = 6.0
	_muzzle_light.position     = Vector3(0, -0.3, 0)
	_hand_r.add_child(_muzzle_light)

	_muzzle_flash = MeshInstance3D.new()
	var fq   := QuadMesh.new()
	fq.size  = Vector2(0.6, 0.6)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode     = BaseMaterial3D.BLEND_MODE_ADD
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.albedo_color   = Color(1.0, 0.8, 0.35, 1.0)
	fmat.emission_enabled = true
	fmat.emission       = Color(1.0, 0.85, 0.4)
	fmat.emission_energy_multiplier = 5.0
	fq.material = fmat
	_muzzle_flash.mesh     = fq
	_muzzle_flash.position = Vector3(0, -0.3, 0)
	_muzzle_flash.visible  = false
	_hand_r.add_child(_muzzle_flash)


# ── Effect helpers ────────────────────────────────────────────────────────────
func spawn_blood(pos: Vector3, normal: Vector3) -> void:
	var p   := CPUParticles3D.new()
	p.emitting      = false
	p.one_shot      = true
	p.amount        = 60
	p.lifetime      = 0.6
	p.explosiveness = 0.95
	var mesh := SphereMesh.new()
	mesh.radius = 0.04; mesh.height = 0.08
	var mat  := StandardMaterial3D.new()
	mat.albedo_color       = Color(0.85, 0.04, 0.04)
	mat.emission_enabled   = true
	mat.emission           = Color(0.7, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	mesh.material = mat
	p.mesh = mesh
	p.direction            = normal
	p.spread               = 55.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 16.0
	p.gravity              = Vector3(0, -12, 0)
	p.damping_min          = 3.0
	p.damping_max          = 6.0
	p.scale_amount_min     = 0.6
	p.scale_amount_max     = 1.4
	_player.get_tree().root.add_child(p)
	p.global_position = pos
	if normal.length_squared() > 0.001 and \
			normal.distance_squared_to(Vector3.UP) > 0.01 and \
			normal.distance_squared_to(Vector3.DOWN) > 0.01:
		p.look_at(pos + normal, Vector3.UP)
	p.emitting = true
	_player.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func spawn_spark(pos: Vector3, normal: Vector3) -> void:
	var p   := CPUParticles3D.new()
	p.emitting      = false
	p.one_shot      = true
	p.amount        = 20
	p.lifetime      = 0.3
	p.explosiveness = 0.95
	var mesh := SphereMesh.new()
	mesh.radius = 0.02; mesh.height = 0.04
	var mat  := StandardMaterial3D.new()
	mat.albedo_color       = Color(1.0, 0.85, 0.3)
	mat.emission_enabled   = true
	mat.emission           = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	p.direction            = normal
	p.spread               = 45.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 10.0
	p.gravity              = Vector3(0, -8, 0)
	_player.get_tree().root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_player.get_tree().create_timer(0.6).timeout.connect(p.queue_free)


func draw_tracer(start: Vector3, end: Vector3) -> void:
	var mi  := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.025
	cyl.bottom_radius = 0.025
	cyl.height        = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color       = Color(1.0, 0.92, 0.3, 0.85)
	mat.emission_enabled   = true
	mat.emission           = Color(1.0, 0.9, 0.3)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	mi.mesh = cyl
	_player.get_tree().root.add_child(mi)
	mi.global_position = start
	if start.distance_squared_to(end) > 0.01:
		var dir    := (end - start).normalized()
		var up_vec := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		mi.look_at(end, up_vec)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var travel := clampf(start.distance_to(end) / 300.0, 0.01, 0.4)
	var tw := _player.create_tween()
	tw.tween_property(mi, "global_position", end, travel)
	tw.tween_callback(mi.queue_free)


func _attach_bomb_script(bomb: RigidBody3D) -> void:
	bomb.set_script(preload("res://Scripts/Bomb.gd"))
	bomb.set_process(true)
	bomb.set("owner_id", _player_id)
