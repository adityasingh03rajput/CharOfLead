extends CharacterBody3D
## Player3D — thin orchestrator.
## Systems: SkeletonBuilder · AnimationLayers · WalkCycle · WeaponFactory
##          SpineController · HeadController · FootIK · SecondaryMotion
##          AudioController · CosmeticSystem

const _SkelScript   = preload("res://Scripts/SkeletonBuilder.gd")
const _AnimScript   = preload("res://Scripts/AnimationLayers.gd")
const _WalkScript   = preload("res://Scripts/WalkCycle.gd")
const _WpnScript    = preload("res://Scripts/WeaponFactory.gd")
const _DataScript   = preload("res://Scripts/HumanData.gd")
const _SpineScript  = preload("res://Scripts/SpineController.gd")
const _HeadScript   = preload("res://Scripts/HeadController.gd")
const _FootScript   = preload("res://Scripts/FootIK.gd")
const _SecScript    = preload("res://Scripts/SecondaryMotion.gd")
const _AudioScript  = preload("res://Scripts/AudioController.gd")
const _CosScript    = preload("res://Scripts/CosmeticSystem.gd")

# Weapon indices — mirrors WeaponFactory.Weapon enum
const WPN_PISTOL  = 0
const WPN_RIFLE   = 1
const WPN_SHOTGUN = 2
const WPN_BOMB    = 3

@export var player_id:     int   = 1
@export var is_hunter:     bool  = false
@export var walk_speed:    float = 4.5
@export var run_speed:     float = 8.0
@export var gravity:       float = 20.0
@export var jump_velocity: float = 8.0
@export var turn_speed:    float = 10.0

# ── Movement constants ────────────────────────────────────────────────────────
const ACCEL_GROUND := 28.0
const DECEL_GROUND := 22.0
const ACCEL_AIR    := 8.0
const DECEL_AIR    := 3.0
const COYOTE_TIME  := 0.12
const JUMP_BUFFER  := 0.12

# ── Runtime state ─────────────────────────────────────────────────────────────
var _is_dead:       bool  = false
var _has_won:       bool  = false
var _is_prone:      bool  = false
var _melee_t:       float = 0.0
var _visual_yaw:    float = 0.0
var _coyote_timer:  float = 0.0
var _jump_buffer:   float = 0.0
var _on_floor_last: bool  = false
var _last_health:   float = 100.0

# ── Body-Hopping (P2) ─────────────────────────────────────────────────────────
var is_idle_clone: bool = false
var clone_number:  int  = 0
static var active_clones:  Array = []
static var clone_counter:  int   = 0
var _selector_ui: CanvasLayer

# ── Input action strings ──────────────────────────────────────────────────────
@onready var _act_up:    String = "p%d_up"    % player_id
@onready var _act_down:  String = "p%d_down"  % player_id
@onready var _act_left:  String = "p%d_left"  % player_id
@onready var _act_right: String = "p%d_right" % player_id
@onready var _act_jump:  String = "p%d_jump"  % player_id
@onready var _act_fire:  String = "p%d_fire"  % player_id

# ── Sub-systems (Node3D to avoid class_name resolution at script-load time) ───
var _skeleton:  Node3D
var _anim:      Node3D
var _walk:      Node3D
var _weapon:    Node3D
var _spine:     Node3D
var _head_ctrl: Node3D
var _foot_ik:   Node3D
var _secondary: Node3D
var _audio:     Node3D
var _cosmetic:  Node3D


func _ready() -> void:
	add_to_group("p%d_body_3d" % player_id)

	var data: Resource = _DataScript.new()
	data.team_color = Color(0.85, 0.15, 0.15) if player_id == 1 else Color(0.2, 0.4, 0.95)
	data.player_id  = player_id
	data.is_hunter  = is_hunter

	_weapon = _WpnScript.new()
	_weapon.name = "WeaponFactory"
	_weapon.call("init", self, player_id)
	add_child(_weapon)

	_skeleton = _SkelScript.new()
	add_child(_skeleton)
	_skeleton.call("build", data, _weapon if is_hunter else null)

	_walk = _WalkScript.new()
	add_child(_walk)
	_walk.call("init", self, _skeleton.get("rig"))

	_anim = _AnimScript.new()
	add_child(_anim)
	_anim.call("init", self, _skeleton, _walk, _weapon, player_id)

	# Phase 12 — Spine Controller
	_spine = _SpineScript.new()
	add_child(_spine)
	_spine.call("init", self, _skeleton, player_id)

	# Phase 13 — Head Controller
	_head_ctrl = _HeadScript.new()
	add_child(_head_ctrl)
	_head_ctrl.call("init", self, _skeleton, player_id)

	# Phase 11 — Foot IK
	_foot_ik = _FootScript.new()
	add_child(_foot_ik)
	_foot_ik.call("init", self, _skeleton)

	# Phase 14 — Secondary Motion
	_secondary = _SecScript.new()
	add_child(_secondary)
	_secondary.call("init", self, _skeleton)

	# Phase 16 — Audio Controller
	_audio = _AudioScript.new()
	add_child(_audio)
	_audio.call("init", self, player_id)

	# Phase 20 — Cosmetic System
	_cosmetic = _CosScript.new()
	add_child(_cosmetic)
	_cosmetic.call("init", _skeleton)

	# Warn about any null subsystems — helps diagnose init failures
	for _pair in [["_skeleton", _skeleton], ["_walk", _walk], ["_anim", _anim],
			["_spine", _spine], ["_head_ctrl", _head_ctrl], ["_foot_ik", _foot_ik],
			["_secondary", _secondary], ["_audio", _audio]]:
		if _pair[1] == null:
			push_warning("Player3D P%d: subsystem '%s' is null after _ready()" % [player_id, _pair[0]])

	# Sync spawn rotation into visual rig
	_visual_yaw = rotation.y
	var rig: Node3D = _skeleton.get("rig") if _skeleton else null
	if rig: rig.rotation.y = _visual_yaw
	rotation.y = 0.0

	if is_hunter:
		_weapon.call("set_weapon", WPN_PISTOL)

	if not is_idle_clone:
		if GameManager:
			GameManager.player_died.connect(_on_player_died)
			GameManager.game_over.connect(_on_game_over)
			GameManager.health_changed.connect(_on_health_changed)
			_last_health = GameManager.get_health(player_id)
		if player_id == 2:
			active_clones.clear()
			clone_counter = 0
			_build_selector_ui()
	else:
		var lbl := Label3D.new()
		lbl.text             = str(clone_number)
		lbl.pixel_size       = 0.015
		lbl.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position         = Vector3(0, 2.2, 0)
		lbl.modulate         = Color.WHITE
		lbl.outline_modulate = Color.BLACK
		lbl.font_size        = 100
		add_child(lbl)


# ── Helper called by WeaponFactory to snap visual yaw on fire ─────────────────
func _sync_visual_yaw(yaw: float) -> void:
	_visual_yaw = yaw
	var rig: Node3D = _skeleton.get("rig")
	if rig: rig.rotation.y = _visual_yaw


# ── Convenience accessors to avoid repeated get() calls ──────────────────────
func _rig() -> Node3D:
	return _skeleton.get("rig") as Node3D


# ====================================================================
# PHYSICS / INPUT
# ====================================================================
func _physics_process(delta: float) -> void:
	if _is_dead: return

	_weapon.call("tick", delta)
	if _melee_t > 0.0: _melee_t -= delta

	var on_floor := is_on_floor()

	# ── Body-Hop selector (P2) ────────────────────────────────────────────────
	if player_id == 2 and not is_idle_clone and not _is_dead \
			and GameManager and not GameManager.is_armed(2):
		if Input.is_physical_key_pressed(KEY_Q):
			if _selector_ui and not _selector_ui.visible:
				_selector_ui.visible = true
				Engine.time_scale = 0.1
			for i in range(1, 10):
				if Input.is_physical_key_pressed(KEY_0 + i):
					_try_body_hop(i)
					break
		else:
			if _selector_ui and _selector_ui.visible:
				_selector_ui.visible = false
				Engine.time_scale = 1.0

	# ── Idle clone: gravity only, idle pose ───────────────────────────────────
	if is_idle_clone:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0) if not on_floor else 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		var rig_yaw2 := (_rig().rotation.y if _rig() else 0.0)
		var tp2 = _anim.call("compute", delta, false, false, false, false,
			false, false, 0.0, _visual_yaw, rig_yaw2)
		if not tp2 is Dictionary: tp2 = {}
		_head_ctrl.call("contribute", tp2, delta, false, false, false, rig_yaw2)
		_secondary.call("contribute", tp2, delta)
		_anim.call("apply_pose", tp2, delta)
		return

	# ── Coyote + jump buffer ──────────────────────────────────────────────────
	if on_floor:
		_coyote_timer = COYOTE_TIME
	elif _coyote_timer > 0.0:
		_coyote_timer -= delta

	if Input.is_action_just_pressed(_act_jump):
		_jump_buffer = JUMP_BUFFER
	elif _jump_buffer > 0.0:
		_jump_buffer -= delta

	if not on_floor:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)

	# ── Jump ──────────────────────────────────────────────────────────────────
	if is_auth and _jump_buffer > 0.0 and _coyote_timer > 0.0 and not _has_won:
		velocity.y    = jump_velocity
		_jump_buffer  = 0.0
		_coyote_timer = 0.0
		if _rig(): _rig().scale = Vector3(0.82, 1.25, 0.82)

	# ── Landing squash ────────────────────────────────────────────────────────
	if not _on_floor_last and on_floor:
		if _rig(): _rig().scale = Vector3(1.18, 0.78, 1.18)
	if _rig():
		_rig().scale = _rig().scale.lerp(Vector3.ONE, 12.0 * delta)
	_on_floor_last = on_floor

	# ── Input ─────────────────────────────────────────────────────────────────
	var is_running   := false
	var is_crouching := false
	if is_auth:
		is_running   = _get_run_input()
		is_crouching = _get_crouch_input()
		_is_prone = Input.is_key_pressed(KEY_Z)

	# Weapon switching (P1 hunter)
	if is_auth and is_hunter and GameManager and GameManager.is_armed(player_id) and not _has_won and not _is_dead:
		var q := Input.is_physical_key_pressed(KEY_Q)
		if Input.is_physical_key_pressed(KEY_1) and not q: _weapon.call("set_weapon", WPN_PISTOL)
		if Input.is_physical_key_pressed(KEY_2) and not q: _weapon.call("set_weapon", WPN_RIFLE)
		if Input.is_physical_key_pressed(KEY_3) and not q: _weapon.call("set_weapon", WPN_SHOTGUN)
		if Input.is_physical_key_pressed(KEY_4) and not q: _weapon.call("set_weapon", WPN_BOMB)

	# Melee
	if is_auth:
		var melee_pressed := Input.is_physical_key_pressed(KEY_F) if player_id == 1 else (
			Input.is_action_just_pressed(_act_fire) or
			Input.is_physical_key_pressed(KEY_ENTER) or
			Input.is_physical_key_pressed(KEY_M))
		if melee_pressed and _melee_t <= 0.0 and on_floor and not _is_dead and not _has_won:
			_melee_t = 0.4
			_weapon.call("do_melee", _rig())

	# Speed
	var top_speed: float
	if _is_prone:      top_speed = walk_speed * 0.2
	elif is_crouching: top_speed = walk_speed * 0.45
	elif is_running:   top_speed = run_speed
	else:              top_speed = walk_speed

	# ── Camera-relative movement ──────────────────────────────────────────────
	var input_dir := Vector2.ZERO
	var target_vel := Vector3.ZERO
	var is_auth := is_multiplayer_authority()

	if is_auth and not _has_won:
		var cam := get_viewport().get_camera_3d()
		if cam:
			input_dir = Input.get_vector(_act_left, _act_right, _act_up, _act_down)
			var cf := -cam.global_transform.basis.z
			var cr :=  cam.global_transform.basis.x
			cf.y = 0.0
			if cf.length_squared() < 0.001: cf = cam.global_transform.basis.y; cf.y = 0.0
			cf = cf.normalized()
			cr.y = 0.0; cr = cr.normalized()
	
			var is_aiming := GameManager and GameManager.is_armed(player_id) and (
				Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or
				Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	
			if input_dir != Vector2.ZERO:
				target_vel = (cr * input_dir.x + cf * -input_dir.y).normalized() * top_speed
	
			var shoot_t: float = _weapon.get("shoot_t")
			if is_aiming or shoot_t > 0.0:
				var ty := atan2(-cf.x, -cf.z)
				_visual_yaw = lerp_angle(_visual_yaw, ty, 25.0 * delta)
				if _rig(): _rig().rotation.y = lerp_angle(_rig().rotation.y, _visual_yaw, 25.0 * delta)
			elif input_dir != Vector2.ZERO:
				var ty := atan2(-target_vel.x, -target_vel.z)
				_visual_yaw = lerp_angle(_visual_yaw, ty, turn_speed * delta)
				if _rig(): _rig().rotation.y = lerp_angle(_rig().rotation.y, _visual_yaw, 18.0 * delta)
	elif not is_auth:
		# Sync visual yaw from authority
		if _rig(): _rig().rotation.y = lerp_angle(_rig().rotation.y, _visual_yaw, 25.0 * delta)

	# ── Acceleration ──────────────────────────────────────────────────────────
	if is_auth:
		var accel := ACCEL_GROUND if on_floor else ACCEL_AIR
		var decel := DECEL_GROUND if on_floor else DECEL_AIR
		if target_vel.length_squared() > 0.01:
			velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * top_speed)
			velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * top_speed)
		else:
			velocity.x = move_toward(velocity.x, 0.0, decel * delta * top_speed)
			velocity.z = move_toward(velocity.z, 0.0, decel * delta * top_speed)

	# ── Firing ────────────────────────────────────────────────────────────────
	if is_auth and is_hunter and GameManager and GameManager.is_armed(player_id) \
			and not _has_won and _melee_t <= 0.0 and not _is_prone:
		var cur_wpn: int = _weapon.get("current_weapon")
		var firing := false
		if cur_wpn == WPN_RIFLE:
			firing = Input.is_action_pressed(_act_fire) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		else:
			firing = Input.is_action_just_pressed(_act_fire) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if firing: _weapon.call("try_fire")

	# ── Locomotion + animation ────────────────────────────────────────────────
	var moving  := input_dir != Vector2.ZERO
	var rig_yaw := (_rig().rotation.y if _rig() else 0.0)
	if _walk: _walk.call("advance", delta, moving, is_running)

	# 1) Build base target-pose dict
	var tp = {}
	if _anim:
		tp = _anim.call("compute", delta, moving, is_running,
			is_crouching, _is_prone, _is_dead, _has_won, _melee_t, _visual_yaw, rig_yaw)
		if not tp is Dictionary: tp = {}

	# 2) Each layer adds its contribution to tp (no joint writes yet)
	if _spine:     _spine.call("contribute", tp, delta, moving, is_running, is_crouching, _is_dead, _has_won)
	if _head_ctrl: _head_ctrl.call("contribute", tp, delta, moving, _is_dead, _has_won, rig_yaw)

	var anim_phase: float = (_walk.get("anim_phase") if _walk else 0.0)
	if _secondary:
		_secondary.call("set_weapon_bob",
			Vector3(sin(anim_phase) * 0.025, cos(anim_phase * 2.0) * 0.015, 0.0))
		_secondary.call("contribute", tp, delta)

	# 3) Single clamped lerp pass — the ONLY place joints are written
	if _anim: _anim.call("apply_pose", tp, delta)

	# FootIK runs after pose is applied (adjusts ankle rotation on top, bounded by its own limits)
	if _foot_ik: _foot_ik.call("apply", delta)

	# Footstep audio
	if _audio: _audio.call("update", delta, moving, is_running)

	move_and_slide()


func _get_run_input() -> bool:
	if InputMap.has_action("p%d_run" % player_id):
		return Input.is_action_pressed("p%d_run" % player_id)
	return Input.is_key_pressed(KEY_SHIFT) if player_id == 1 else Input.is_key_pressed(KEY_CTRL)

func _get_crouch_input() -> bool:
	if InputMap.has_action("p%d_crouch" % player_id):
		return Input.is_action_pressed("p%d_crouch" % player_id)
	return Input.is_key_pressed(KEY_ALT) if player_id == 1 else Input.is_key_pressed(KEY_TAB)


# ====================================================================
# SIGNALS — COMBAT REACTIONS
# ====================================================================
func _on_health_changed(pid: int, current: float, _maximum: float) -> void:
	if pid == player_id and current < _last_health and not _is_dead:
		_weapon.set("hurt_t", 0.22)
		_anim.call("trigger_hurt")
		var cam := get_viewport().get_camera_3d()
		if cam and cam.has_method("shake_hit"): cam.shake_hit()
	if pid == player_id: _last_health = current


func _on_player_died(dead_id: int) -> void:
	if dead_id != player_id or _is_dead: return
	_is_dead = true
	set_physics_process(false)

	var j: Dictionary = _skeleton.get("joints")
	if j.has("torso"):      (j["torso"] as Node3D).rotation      = Vector3(0.1,  0.0,  0.2)
	if j.has("head"):       (j["head"]  as Node3D).rotation      = Vector3(0.3,  0.0,  0.4)
	if j.has("shoulder_l"): (j["shoulder_l"] as Node3D).rotation = Vector3(-0.3, 0.0, -1.0)
	if j.has("shoulder_r"): (j["shoulder_r"] as Node3D).rotation = Vector3(-0.3, 0.0,  1.0)
	if j.has("elbow_l"):    (j["elbow_l"] as Node3D).rotation    = Vector3(-0.6, 0.0,  0.0)
	if j.has("elbow_r"):    (j["elbow_r"] as Node3D).rotation    = Vector3(-0.6, 0.0,  0.0)
	if j.has("hip_l"):      (j["hip_l"]   as Node3D).rotation    = Vector3( 0.4, 0.0,  0.3)
	if j.has("hip_r"):      (j["hip_r"]   as Node3D).rotation    = Vector3(-0.3, 0.0, -0.4)
	if j.has("knee_l"):     (j["knee_l"]  as Node3D).rotation    = Vector3( 1.2, 0.0,  0.0)
	if j.has("knee_r"):     (j["knee_r"]  as Node3D).rotation    = Vector3( 0.8, 0.0,  0.0)

	if _rig():
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_rig(), "rotation:z", PI / 2.0, 0.55).set_ease(Tween.EASE_IN)
		tw.tween_property(_rig(), "position:y", 0.12,     0.55).set_ease(Tween.EASE_IN)


func _on_game_over(winner_id: int) -> void:
	if winner_id == player_id and not _is_dead:
		_has_won = true


# ====================================================================
# INPUT — scroll wheel weapon swap
# ====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _is_dead or is_idle_clone or not is_multiplayer_authority(): return

	if is_hunter and GameManager and GameManager.is_armed(player_id) \
			and event is InputEventMouseButton and event.pressed:
		var cur: int = _weapon.get("current_weapon")
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_weapon.call("set_weapon", (cur + 3) % 4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_weapon.call("set_weapon", (cur + 1) % 4)

	if player_id != 2 or not GameManager or GameManager.is_armed(2): return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.get("_current_preset") == 1:
			var from := cam.project_ray_origin(event.position)
			var to   := from + cam.project_ray_normal(event.position) * 1000.0
			var q    := PhysicsRayQueryParameters3D.create(from, to)
			q.collision_mask = 1
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				_implant_clone(hit.get("position"))


# ====================================================================
# BODY HOPPING (P2 ability)
# ====================================================================
func _build_selector_ui() -> void:
	_selector_ui = CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selector_ui.add_child(bg)
	var lbl := Label.new()
	lbl.text = "HOLD [Q] AND PRESS [1-9] TO HOP"
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.add_theme_font_size_override("font_size", 42)
	_selector_ui.add_child(lbl)
	_selector_ui.visible = false
	add_child(_selector_ui)


func _implant_clone(pos: Vector3) -> void:
	if active_clones.size() >= 5: return
	var script := load("res://Scripts/Player3D.gd") as GDScript
	var clone  := CharacterBody3D.new()
	clone.set_script(script)
	clone.set("player_id", 2)
	clone.set("is_hunter", false)
	clone.position = pos
	clone.set("is_idle_clone", true)
	clone.collision_layer = 2
	clone.collision_mask  = 3
	var cs  := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.8
	cs.shape    = cap
	cs.position = Vector3(0, 0.9, 0)
	clone.add_child(cs)
	clone_counter += 1
	clone.set("clone_number", clone_counter)
	get_parent().add_child(clone)
	active_clones.append(clone)


func _try_body_hop(cnum: int) -> void:
	var target_clone = null
	for c in active_clones:
		if c.get("clone_number") == cnum and is_instance_valid(c):
			target_clone = c
			break
	if not target_clone: return

	var red_player = null
	for p in get_tree().get_nodes_in_group("p1_body_3d"):
		if p != self and p != target_clone:
			red_player = p
			break
	if red_player:
		var q := PhysicsRayQueryParameters3D.create(
			red_player.global_position + Vector3.UP * 1.5,
			self.global_position + Vector3.UP * 0.9)
		q.exclude = [red_player.get_rid(), self.get_rid(), target_clone.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty(): return

	target_clone.set("is_idle_clone", false)
	for child in target_clone.get_children():
		if child is Label3D: child.queue_free()
	active_clones.erase(target_clone)

	self.set("is_idle_clone", true)
	_on_player_died(player_id)

	var cam := get_viewport().get_camera_3d()
	if cam: cam.set("target", target_clone)

	if _selector_ui: _selector_ui.visible = false
	Engine.time_scale = 1.0

	if GameManager:
		GameManager.player_died.connect(target_clone._on_player_died)
		GameManager.game_over.connect(target_clone._on_game_over)
		GameManager.health_changed.connect(target_clone._on_health_changed)
