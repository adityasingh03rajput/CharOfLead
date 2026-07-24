extends RigidBody3D
class_name Bomb

var owner_id: int = 1
var is_stuck: bool = false
var _exploded: bool = false
var _blink_timer: float = 0.0

var _led: OmniLight3D = null

var _marker_2d: Node2D = null
var _ring_line: Line2D = null
var _prompt_label: Label = null

const BLUE_DETONATE_RANGE_PX := 90.0
var _blue_in_range: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_led = get_node_or_null("LEDLight")
	body_entered.connect(_on_body_entered)

	if GameManager:
		GameManager.mode_changed.connect(_on_mode_changed)

func _on_body_entered(_body: Node) -> void:
	if is_stuck or _exploded:
		return
	is_stuck = true
	freeze = true
	add_to_group("sticky_bombs_3d")

	if GameManager and not GameManager.is_3d_mode:
		_create_marker_2d()

func _on_mode_changed(is_3d_mode: bool) -> void:
	_sync_dimension(is_3d_mode)

func _sync_dimension(is_3d_mode: bool) -> void:
	for child in get_children():
		if child is VisualInstance3D or child is OmniLight3D:
			(child as Node3D).visible = is_3d_mode

	if is_3d_mode:
		if _marker_2d and is_instance_valid(_marker_2d):
			_marker_2d.queue_free()
		_marker_2d = null
		_ring_line = null
		_prompt_label = null
	else:
		if is_stuck and not _exploded:
			_create_marker_2d()

func _create_marker_2d() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if not main:
		return
	var env2d: Node2D = main.get("env_2d")
	if not env2d:
		return

	var bx := clampf(global_position.x * 32.0, -420.0, 420.0)
	var by := clampf(global_position.z * 32.0, -300.0, 300.0)

	_marker_2d = Node2D.new()
	_marker_2d.name = "BombMarker2D"
	_marker_2d.position = Vector2(bx, by)
	env2d.add_child(_marker_2d)

	_marker_2d.add_child(_build_bomb_icon())

	_prompt_label = Label.new()
	_prompt_label.text = "G  ·  DETONATE"
	_prompt_label.add_theme_font_size_override("font_size", 11)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	_prompt_label.position = Vector2(-38, 18)
	_prompt_label.visible = false
	_marker_2d.add_child(_prompt_label)

	set_meta("bomb_2d", _marker_2d)

func _process(delta: float) -> void:
	if _exploded:
		return

	var is_3d := GameManager == null or GameManager.is_3d_mode

	_blink_timer += delta * (14.0 if is_stuck else 7.0)
	if _led:
		_led.light_energy = 6.0 if sin(_blink_timer) > 0.0 else 0.2

	if not is_3d and _marker_2d and is_instance_valid(_marker_2d):
		_update_marker_2d()

	if not is_stuck:
		return

	if Input.is_physical_key_pressed(KEY_G):
		if is_3d:
			if owner_id == 1:
				explode()
		else:
			explode()

func _update_marker_2d() -> void:
	if _prompt_label:
		_prompt_label.visible = true

	_marker_2d.modulate.a = 0.65 + sin(_blink_timer) * 0.35

func explode() -> void:
	if _exploded:
		return
	_exploded = true
	remove_from_group("sticky_bombs_3d")

	var gm = get_node_or_null("/root/GameManager")

	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 6.0
	q.shape = ss
	q.transform = global_transform
	for h in space.intersect_shape(q):
		var col = h.get("collider")
		if col:
			var tid := 0
			if col.is_in_group("p1_body_3d"): tid = 1
			elif col.is_in_group("p2_body_3d"): tid = 2
			if tid > 0:
				var dist := global_position.distance_to(col.global_position)
				if gm:
					gm.apply_damage(tid, lerpf(75.0, 25.0, clampf(dist / 6.0, 0.0, 1.0)))

	var bx := clampf(global_position.x * 32.0, -420.0, 420.0)
	var by := clampf(global_position.z * 32.0, -300.0, 300.0)
	var b2d := Vector2(bx, by)
	
	for grp in ["p1_body_2d", "p2_body_2d"]:
		for node in get_tree().get_nodes_in_group(grp):
			var d := b2d.distance_to((node as Node2D).global_position)
			if d < 192.0:
				var tid2 := 1 if grp == "p1_body_2d" else 2
				if gm:
					gm.apply_damage(tid2, lerpf(75.0, 20.0, clampf(d / 192.0, 0.0, 1.0)))
				if node.has_method("_spawn_blood_2d"):
					node.call("_spawn_blood_2d", node.global_position, Vector2.UP)

	if _marker_2d and is_instance_valid(_marker_2d):
		_marker_2d.queue_free()
	_marker_2d = null
	_ring_line = null
	_prompt_label = null

	var is_3d := GameManager == null or GameManager.is_3d_mode
	if is_3d:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.has_method("shake_hit"):
			cam.shake_hit()

		var expl := CPUParticles3D.new()
		expl.emitting = false; expl.one_shot = true; expl.amount = 120
		expl.lifetime = 0.7; expl.explosiveness = 0.95
		var em := SphereMesh.new()
		em.radius = 0.25; em.height = 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.45, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.1)
		mat.emission_energy_multiplier = 6.0
		em.material = mat; expl.mesh = em
		expl.direction = Vector3.UP; expl.spread = 180.0
		expl.initial_velocity_min = 8.0; expl.initial_velocity_max = 20.0
		expl.gravity = Vector3(0, -6, 0)
		get_tree().root.add_child(expl)
		expl.global_position = global_position
		expl.emitting = true
		get_tree().create_timer(1.2).timeout.connect(expl.queue_free)

		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.7, 0.2)
		fl.light_energy = 25.0; fl.omni_range = 15.0
		get_tree().root.add_child(fl)
		fl.global_position = global_position
		var lt = create_tween()
		lt.tween_property(fl, "light_energy", 0.0, 0.45)
		lt.tween_callback(fl.queue_free)
	else:
		var main := get_tree().root.get_node_or_null("Main")
		if main and main.get("env_2d"):
			var env2d: Node2D = main.get("env_2d")
			var b2d_pos := b2d
			
			var expl2d := CPUParticles2D.new()
			expl2d.emitting = false; expl2d.one_shot = true; expl2d.amount = 100
			expl2d.lifetime = 0.5; expl2d.explosiveness = 0.95
			expl2d.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			expl2d.emission_sphere_radius = 8.0
			expl2d.direction = Vector2.UP; expl2d.spread = 180.0
			expl2d.gravity = Vector2(0, 0)
			expl2d.initial_velocity_min = 50.0; expl2d.initial_velocity_max = 250.0
			expl2d.scale_amount_min = 3.0; expl2d.scale_amount_max = 8.0
			expl2d.color = Color(1.0, 0.45, 0.05)
			
			env2d.add_child(expl2d)
			expl2d.global_position = b2d_pos
			expl2d.emitting = true
			get_tree().create_timer(1.0).timeout.connect(expl2d.queue_free)

	queue_free()

func _build_ring(radius: float, col: Color) -> Line2D:
	var ring := Line2D.new()
	ring.name = "ProximityRing"
	ring.width = 2.0
	ring.default_color = col
	ring.closed = true
	ring.begin_cap_mode = Line2D.LINE_CAP_NONE
	ring.end_cap_mode = Line2D.LINE_CAP_NONE
	var pts := PackedVector2Array()
	for i in range(24):
		var a := (float(i) / 24.0) * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	return ring

func _build_bomb_icon() -> Node2D:
	var icon := Node2D.new()
	icon.name = "Icon"

	var body := Polygon2D.new()
	body.color = Color(0.18, 0.20, 0.22)
	var bpts := PackedVector2Array()
	for i in range(8):
		var a := (float(i) / 8.0) * TAU + (PI / 8.0)
		bpts.append(Vector2(cos(a), sin(a)) * 9.0)
	body.polygon = bpts
	icon.add_child(body)

	var strip := Polygon2D.new()
	strip.color = Color(0.95, 0.15, 0.1)
	strip.polygon = PackedVector2Array([
		Vector2(-6.0, -1.5), Vector2(6.0, -1.5),
		Vector2( 6.0,  1.5), Vector2(-6.0,  1.5),
	])
	icon.add_child(strip)

	var dot := Polygon2D.new()
	dot.name = "LEDDot"
	dot.color = Color(1.0, 0.15, 0.1)
	var dpts := PackedVector2Array()
	for i in range(8):
		var a := (float(i) / 8.0) * TAU
		dpts.append(Vector2(cos(a), sin(a)) * 2.2)
	dot.polygon = dpts
	icon.add_child(dot)

	return icon
