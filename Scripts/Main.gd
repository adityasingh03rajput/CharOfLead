extends Node
## Main.gd — Builds the entire Di-Wall game at runtime.
## This avoids all .tscn parsing issues by constructing the node tree in code.

var env_3d: Node3D
var env_2d: Node2D
var hud: CanvasLayer

# Player references for position resets
var p1_3d: CharacterBody3D
var p2_3d: CharacterBody3D
var p1_2d: CharacterBody2D
var p2_2d: CharacterBody2D

var _hud_crosshair: ColorRect

# Spawn positions
const P1_3D_SPAWN := Vector3(-8, 0.9, 8)
const P2_3D_SPAWN := Vector3(8, 0.9, -8)
const P1_2D_SPAWN := Vector2(-300, 280)
const P2_2D_SPAWN := Vector2(300, -280)

func _ready() -> void:
	_build_3d_environment()
	_build_2d_environment()
	_build_hud()
	
	GameManager.mode_changed.connect(_on_mode_changed)
	_on_mode_changed(GameManager.is_3d_mode)


func _on_mode_changed(is_3d_mode: bool) -> void:
	# Map player positions between dimensions (Scale: 32 units = 1 meter)
	if is_3d_mode:
		if p1_2d and p1_3d:
			p1_3d.global_position = Vector3(
				clampf(p1_2d.global_position.x / 32.0, -11.5, 11.5),
				0.9,
				clampf(p1_2d.global_position.y / 32.0, -11.5, 11.5)
			)
			# Carry 2D grapple momentum into 3D so a fast zip flings you into the arena.
			var v2 := p1_2d.velocity
			p1_3d.velocity = Vector3(
				clampf(v2.x / 32.0, -12.0, 12.0),
				0.0,
				clampf(v2.y / 32.0, -12.0, 12.0)
			)
		if p2_2d and p2_3d:
			p2_3d.global_position = Vector3(
				clampf(p2_2d.global_position.x / 32.0, -11.5, 11.5),
				0.9,
				clampf(p2_2d.global_position.y / 32.0, -11.5, 11.5)
			)
			var v2b := p2_2d.velocity
			p2_3d.velocity = Vector3(
				clampf(v2b.x / 32.0, -12.0, 12.0),
				0.0,
				clampf(v2b.y / 32.0, -12.0, 12.0)
			)
	else:
		if p1_3d and p1_2d:
			p1_2d.global_position = Vector2(
				clampf(p1_3d.global_position.x * 32.0, -410.0, 410.0),
				clampf(p1_3d.global_position.z * 32.0, -280.0, 280.0)
			)
			p1_2d.velocity = Vector2.ZERO
		if p2_3d and p2_2d:
			p2_2d.global_position = Vector2(
				clampf(p2_3d.global_position.x * 32.0, -410.0, 410.0),
				clampf(p2_3d.global_position.z * 32.0, -280.0, 280.0)
			)
			p2_2d.velocity = Vector2.ZERO

	# Toggle environments
	if env_3d:
		env_3d.visible = is_3d_mode
		env_3d.process_mode = Node.PROCESS_MODE_INHERIT if is_3d_mode else Node.PROCESS_MODE_DISABLED
	if env_2d:
		env_2d.visible = not is_3d_mode
		env_2d.process_mode = Node.PROCESS_MODE_INHERIT if not is_3d_mode else Node.PROCESS_MODE_DISABLED

	if is_3d_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _hud_crosshair:
			_hud_crosshair.visible = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _hud_crosshair:
			_hud_crosshair.visible = false

# ====================================================================
# 3D ENVIRONMENT
# ====================================================================
func _build_3d_environment() -> void:
	env_3d = Node3D.new()
	env_3d.name = "Environment3D"
	add_child(env_3d)

	# === WORLD ENVIRONMENT (fog, glow, tonemap, ambient) ===
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# Sky — procedural dark sky for enclosed arena feel
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.07)

	# Ambient light — soft hemisphere
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.14, 0.22)
	env.ambient_light_energy = 0.4

	# Tonemap — ACES for cinematic contrast
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	# Glow (bloom) — makes emissive accents pop
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# Fog — depth fog for atmosphere
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.07, 0.12)
	env.fog_density = 0.008

	we.environment = env
	env_3d.add_child(we)

	# === LIGHTING ===
	# Key light — warm, strong shadow caster
	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	light.light_color = Color(1.0, 0.95, 0.88)
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-55, 35, 0)
	env_3d.add_child(light)

	# Fill light — cool blue from opposite side
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.3
	fill.light_color = Color(0.5, 0.6, 1.0)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-30, -145, 0)
	env_3d.add_child(fill)

	# === FLOOR ===
	var floor_mat := _mat_metallic(Color(0.12, 0.12, 0.16), 0.2, 0.6)
	_add_3d_box_mat(env_3d, Vector3(0, -0.5, 0), Vector3(24, 1, 24), floor_mat)

	# Floor grid lines (subtle emissive strips every 4 meters)
	var grid_mat := _mat_emissive(Color(0.15, 0.2, 0.35), 0.4)
	for i in range(-12, 13, 4):
		_add_3d_box_mat(env_3d, Vector3(float(i), 0.005, 0), Vector3(0.04, 0.01, 24.0), grid_mat)
		_add_3d_box_mat(env_3d, Vector3(0, 0.005, float(i)), Vector3(24.0, 0.01, 0.04), grid_mat)

	# === WALLS (outer) ===
	var wall_col := Color(0.16, 0.16, 0.22)
	var wall_mat := _mat_metallic(wall_col, 0.15, 0.7)
	_add_3d_box_mat(env_3d, Vector3(0, 2.5, -12.5), Vector3(25, 5, 1), wall_mat)
	_add_3d_box_mat(env_3d, Vector3(0, 2.5, 12.5),  Vector3(25, 5, 1), wall_mat)
	_add_3d_box_mat(env_3d, Vector3(-12.5, 2.5, 0),  Vector3(1, 5, 25), wall_mat)
	_add_3d_box_mat(env_3d, Vector3(12.5, 2.5, 0),   Vector3(1, 5, 25), wall_mat)

	# Wall trim: emissive accent strips at the base of outer walls
	var trim_red := _mat_emissive(Color(0.8, 0.15, 0.1), 1.2)
	var trim_blue := _mat_emissive(Color(0.1, 0.25, 0.9), 1.2)
	_add_3d_box_mat(env_3d, Vector3(0, 0.04, -12.0),  Vector3(24, 0.08, 0.08), trim_red)
	_add_3d_box_mat(env_3d, Vector3(0, 0.04, 12.0),   Vector3(24, 0.08, 0.08), trim_blue)
	_add_3d_box_mat(env_3d, Vector3(-12.0, 0.04, 0),   Vector3(0.08, 0.08, 24), trim_red)
	_add_3d_box_mat(env_3d, Vector3(12.0, 0.04, 0),    Vector3(0.08, 0.08, 24), trim_blue)

	# === INNER MAZE WALLS ===
	var inner_mat := _mat_metallic(Color(0.13, 0.13, 0.2), 0.1, 0.8)
	_add_3d_box_mat(env_3d, Vector3(-4, 2, -4), Vector3(8, 4, 1), inner_mat)   # A
	_add_3d_box_mat(env_3d, Vector3(0, 2, 0),   Vector3(1, 4, 9), inner_mat)   # B
	_add_3d_box_mat(env_3d, Vector3(4, 2, 4),   Vector3(8, 4, 1), inner_mat)   # C

	# Inner wall top edge glow
	var edge_mat := _mat_emissive(Color(0.3, 0.5, 0.8), 0.8)
	_add_3d_box_mat(env_3d, Vector3(-4, 4.02, -4), Vector3(8, 0.04, 1.02), edge_mat)
	_add_3d_box_mat(env_3d, Vector3(0, 4.02, 0),   Vector3(1.02, 0.04, 9), edge_mat)
	_add_3d_box_mat(env_3d, Vector3(4, 4.02, 4),   Vector3(8, 0.04, 1.02), edge_mat)

	# === SPAWN PADS (glowing team-colored platforms) ===
	var pad_red := _mat_emissive(Color(0.9, 0.12, 0.08), 1.5)
	var pad_blue := _mat_emissive(Color(0.08, 0.3, 0.95), 1.5)
	_add_3d_box_mat(env_3d, Vector3(-8, 0.02, 8),  Vector3(3, 0.04, 3), pad_red)
	_add_3d_box_mat(env_3d, Vector3(8, 0.02, -8),  Vector3(3, 0.04, 3), pad_blue)

	# === PLAYERS ===
	p1_3d = _make_player_3d(1, true,  P1_3D_SPAWN, Color(0.85, 0.15, 0.15))
	env_3d.add_child(p1_3d)
	p2_3d = _make_player_3d(2, false, P2_3D_SPAWN, Color(0.20, 0.40, 0.95))
	env_3d.add_child(p2_3d)

	# === CAMERA ===
	# Follows P1 (Red Soldier) by default — V key switches between P1/P2.
	var cam_script := load("res://Scripts/CameraController3D.gd") as GDScript
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 18, 12)
	cam.rotation_degrees = Vector3(-58, 0, 0)
	cam.set_script(cam_script)
	cam.set("target", p1_3d)
	env_3d.add_child(cam)
	# Wire both players AFTER add_child so _ready has run and the node is live
	cam.call("set_targets", [p1_3d, p2_3d])




func _add_3d_box(parent: Node3D, pos: Vector3, sz: Vector3, col: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)

	var shape := BoxShape3D.new()
	shape.size = sz
	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	body.add_child(col_shape)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh.material = mat
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)


func _add_3d_box_mat(parent: Node3D, pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)

	var shape := BoxShape3D.new()
	shape.size = sz
	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	body.add_child(col_shape)

	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh.material = mat
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)


func _mat_metallic(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	return m


func _mat_emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _make_player_3d(pid: int, hunter: bool, pos: Vector3, col: Color) -> CharacterBody3D:
	var script := load("res://Scripts/Player3D.gd") as GDScript
	var player := CharacterBody3D.new()
	player.name = "Player%d_3D" % pid
	player.position = pos
	player.set_script(script)
	player.set("player_id", pid)
	player.set("is_hunter", hunter)
	
	player.collision_layer = 2
	player.collision_mask = 3
	player.add_to_group("p%d_body_3d" % pid)

	var cap_shape := CapsuleShape3D.new()
	cap_shape.radius = 0.25
	cap_shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = cap_shape
	# Capsule origin is at center. Height=1.8 means half=0.9.
	# Position at 0.9 puts the bottom of the capsule exactly at Y=0 (the floor).
	cs.position = Vector3(0, 0.9, 0)
	player.add_child(cs)

	# The visible body is a procedural humanoid rig built by Player3D.gd itself
	# (see _build_rig) — no placeholder mesh needed here.
	return player

# ====================================================================
# 2D ENVIRONMENT
# ====================================================================
func _build_2d_environment() -> void:
	env_2d = Node2D.new()
	env_2d.name = "Environment2D"
	add_child(env_2d)

	var wall_col := Color(0.22, 0.22, 0.28)
	var inner_col := Color(0.30, 0.30, 0.38)

	# --- Outer box ---
	_add_2d_wall(env_2d, Vector2(0, 320), Vector2(900, 32), wall_col)    # floor
	_add_2d_wall(env_2d, Vector2(0, -320), Vector2(900, 32), wall_col)   # ceiling
	_add_2d_wall(env_2d, Vector2(-450, 0), Vector2(32, 672), wall_col)   # left
	_add_2d_wall(env_2d, Vector2(450, 0), Vector2(32, 672), wall_col)    # right

	# --- Inner maze walls (A, B, C layout matching the 3D map) ---
	# Scale factor: 32 units per 1 meter of 3D space
	_add_2d_wall(env_2d, Vector2(-128, -128), Vector2(256, 32), inner_col) # A
	_add_2d_wall(env_2d, Vector2(0, 0), Vector2(32, 288), inner_col)       # B
	_add_2d_wall(env_2d, Vector2(128, 128), Vector2(256, 32), inner_col)   # C

	# --- Player 1 (Red Soldier — unarmed in 2D) ---
	p1_2d = _make_player_2d(1, false, P1_2D_SPAWN, Color(0.85, 0.15, 0.15))
	env_2d.add_child(p1_2d)

	# --- Player 2 (Blue Assassin — armed in 2D) ---
	p2_2d = _make_player_2d(2, true, P2_2D_SPAWN, Color(0.20, 0.40, 1.0))
	env_2d.add_child(p2_2d)

	# --- 2D Camera ---
	var cam2d_script := load("res://Scripts/CameraController2D.gd") as GDScript
	var cam2d := Camera2D.new()
	cam2d.name = "Camera2D"
	cam2d.zoom = Vector2(0.75, 0.75)
	cam2d.set_script(cam2d_script)
	cam2d.set("target", p2_2d)
	env_2d.add_child(cam2d)


func _add_2d_wall(parent: Node2D, pos: Vector2, sz: Vector2, col: Color) -> void:
	var body := StaticBody2D.new()
	body.position = pos
	parent.add_child(body)

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = sz
	var cs := CollisionShape2D.new()
	cs.shape = rect_shape
	body.add_child(cs)

	var vis := ColorRect.new()
	vis.size = sz
	vis.position = -sz * 0.5
	vis.color = col
	body.add_child(vis)


func _make_player_2d(pid: int, assassin: bool, pos: Vector2, col: Color) -> CharacterBody2D:
	var script := load("res://Scripts/WallWalkingPlayer2D.gd") as GDScript
	var player := CharacterBody2D.new()
	player.name = "Player%d_2D" % pid
	player.position = pos
	player.set_script(script)
	player.set("player_id", pid)
	player.set("is_assassin", assassin)
	
	# Put players on layer 2, collide with walls(1) and players(2)
	player.collision_layer = 2
	player.collision_mask = 3

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(32, 60)
	var cs := CollisionShape2D.new()
	cs.shape = rect_shape
	player.add_child(cs)

	var vis := ColorRect.new()
	vis.size = Vector2(32, 60)
	vis.position = Vector2(-16, -30)
	vis.color = col
	player.add_child(vis)

	return player


# ====================================================================
# HUD
# ====================================================================
func _build_hud() -> void:
	var hud_script := load("res://Scripts/HUD.gd") as GDScript
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(hud_script)
	add_child(hud)

	# Flash overlay (full screen, transparent)
	var flash := ColorRect.new()
	flash.name = "Flash"
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.color = Color(1, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash)

	# Crosshair for 3D Mode
	_hud_crosshair = ColorRect.new()
	_hud_crosshair.name = "Crosshair"
	_hud_crosshair.size = Vector2(4, 4)
	_hud_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_hud_crosshair.color = Color(1, 1, 1, 0.8)
	_hud_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hud_crosshair)

	# Hit marker (Free Fire style ✕ that pops when a shot connects)
	var hitmarker := Label.new()
	hitmarker.name = "HitMarker"
	hitmarker.text = "✕"
	hitmarker.add_theme_font_size_override("font_size", 44)
	hitmarker.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.visible = false
	hud.add_child(hitmarker)

	# Health Bar Styles
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	var p1_fill = StyleBoxFlat.new()
	p1_fill.bg_color = Color(0.85, 0.15, 0.15)
	var p2_fill = StyleBoxFlat.new()
	p2_fill.bg_color = Color(0.20, 0.40, 1.0)

	# P1 Health Bar
	var p1_bar := ProgressBar.new()
	p1_bar.name = "P1Bar"
	p1_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p1_bar.position = Vector2(20, 20)
	p1_bar.size = Vector2(300, 28)
	p1_bar.max_value = 100.0
	p1_bar.value = 100.0
	p1_bar.add_theme_stylebox_override("background", bg_style)
	p1_bar.add_theme_stylebox_override("fill", p1_fill)
	hud.add_child(p1_bar)

	var p1_label := Label.new()
	p1_label.text = "P1 — RED SOLDIER"
	p1_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p1_label.position = Vector2(20, 52)
	hud.add_child(p1_label)

	# P2 Health Bar
	var p2_bar := ProgressBar.new()
	p2_bar.name = "P2Bar"
	p2_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p2_bar.position = Vector2(-320, 20)
	p2_bar.size = Vector2(300, 28)
	p2_bar.max_value = 100.0
	p2_bar.value = 100.0
	p2_bar.add_theme_stylebox_override("background", bg_style)
	p2_bar.add_theme_stylebox_override("fill", p2_fill)
	hud.add_child(p2_bar)

	var p2_label := Label.new()
	p2_label.text = "P2 — BLUE ASSASSIN"
	p2_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p2_label.position = Vector2(-320, 52)
	p2_label.size = Vector2(300, 30)
	p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(p2_label)

	# Mode Label (center top)
	var mode_label := Label.new()
	mode_label.name = "ModeLabel"
	mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mode_label.position = Vector2(-300, 20)
	mode_label.size = Vector2(600, 40)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_size_override("font_size", 28)
	mode_label.text = "STATE A — 3D GROUND-WALK"
	hud.add_child(mode_label)

	# Winner Label (center, hidden)
	var winner_label := Label.new()
	winner_label.name = "WinnerLabel"
	winner_label.visible = false
	winner_label.set_anchors_preset(Control.PRESET_CENTER)
	winner_label.position = Vector2(-500, -100)
	winner_label.size = Vector2(1000, 200)
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	winner_label.add_theme_font_size_override("font_size", 80)
	winner_label.text = "PLAYER X WINS!"
	hud.add_child(winner_label)

	# Weapon Pop-up (GTA 5 / Free Fire style gun name banner)
	var pop_panel := PanelContainer.new()
	pop_panel.name = "WeaponPopup"
	pop_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pop_panel.position = Vector2(-320, -110)
	pop_panel.size = Vector2(280, 65)
	pop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop_panel.visible = false

	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	pop_style.border_width_left = 4
	pop_style.border_width_top = 1
	pop_style.border_width_right = 1
	pop_style.border_width_bottom = 1
	pop_style.border_color = Color(1.0, 0.7, 0.15, 0.9)
	pop_style.corner_radius_top_left = 6
	pop_style.corner_radius_bottom_left = 6
	pop_style.corner_radius_top_right = 6
	pop_style.corner_radius_bottom_right = 6
	pop_panel.add_theme_stylebox_override("panel", pop_style)

	var pop_margin := MarginContainer.new()
	pop_margin.add_theme_constant_override("margin_left", 12)
	pop_margin.add_theme_constant_override("margin_top", 6)
	pop_margin.add_theme_constant_override("margin_right", 12)
	pop_margin.add_theme_constant_override("margin_bottom", 6)
	pop_panel.add_child(pop_margin)

	var pop_vbox := VBoxContainer.new()
	pop_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pop_vbox.add_theme_constant_override("separation", 1)
	pop_margin.add_child(pop_vbox)

	var pop_subtitle := Label.new()
	pop_subtitle.text = "EQUIPPED WEAPON"
	pop_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop_subtitle.add_theme_font_size_override("font_size", 11)
	pop_subtitle.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 0.85))
	pop_vbox.add_child(pop_subtitle)

	var pop_title := Label.new()
	pop_title.name = "Title"
	pop_title.text = "PISTOL"
	pop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop_title.add_theme_font_size_override("font_size", 22)
	pop_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	pop_vbox.add_child(pop_title)

	hud.add_child(pop_panel)

	# Wire the HUD exports
	hud.set("p1_bar", p1_bar)
	hud.set("p2_bar", p2_bar)
	hud.set("mode_label", mode_label)
	hud.set("winner_label", winner_label)
	hud.set("flash", flash)
	hud.set("hitmarker", hitmarker)
	hud.set("weapon_popup", pop_panel)
	
	# Build the key-help overlay (Shift + ?)
	var help_panel := _build_help_overlay()
	hud.add_child(help_panel)
	hud.call("set_help_panel", help_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and event.ctrl_pressed:
			if GameManager:
				GameManager.restart()
			else:
				get_tree().reload_current_scene()


func _build_help_overlay() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "HelpPanel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-400, -300)
	panel.size = Vector2(800, 600)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.3, 0.5, 0.8, 0.8)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", bg_style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	vbox.add_child(margin)
	
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	
	# Title
	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
	content.add_child(title)
	
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	content.add_child(spacer1)
	
	# P1 Section
	var p1_title := Label.new()
	p1_title.text = "PLAYER 1 — RED SOLDIER"
	p1_title.add_theme_font_size_override("font_size", 22)
	p1_title.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
	content.add_child(p1_title)
	
	_add_help_line(content, "WASD", "Move")
	_add_help_line(content, "Space", "Jump")
	_add_help_line(content, "Shift", "Run")
	_add_help_line(content, "Alt", "Crouch")
	_add_help_line(content, "Mouse / Left Click", "Aim & Shoot (3D Mode)")
	_add_help_line(content, "1, 2, 3, 4 / Scroll", "Switch Weapon (Pistol/Rifle/Shotgun/C4)")
	_add_help_line(content, "G / Right Click", "Throw / Detonate GTA 5 Sticky Bomb")
	_add_help_line(content, "F", "Grapple Hook (2D Mode)")
	_add_help_line(content, "Ctrl+WASD", "Steer Grapple Reticle")
	_add_help_line(content, "E", "Release Grapple")
	
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 15)
	content.add_child(spacer2)
	
	# P2 Section
	var p2_title := Label.new()
	p2_title.text = "PLAYER 2 — BLUE ASSASSIN"
	p2_title.add_theme_font_size_override("font_size", 22)
	p2_title.add_theme_color_override("font_color", Color(0.2, 0.4, 0.95))
	content.add_child(p2_title)
	
	_add_help_line(content, "Arrow Keys", "Move")
	_add_help_line(content, "RCtrl", "Jump / Drop from Ceiling")
	_add_help_line(content, "RShift", "Run")
	_add_help_line(content, "Tab", "Crouch")
	_add_help_line(content, "Mouse / Left Click", "Aim & Shoot (2D Mode)")
	
	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 15)
	content.add_child(spacer3)
	
	# General Controls
	var gen_title := Label.new()
	gen_title.text = "GENERAL"
	gen_title.add_theme_font_size_override("font_size", 22)
	gen_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	content.add_child(gen_title)
	
	_add_help_line(content, "Shift + ?", "Toggle This Help")
	_add_help_line(content, "Ctrl + R", "Restart Game")
	_add_help_line(content, "V", "Switch Camera (Red ↔ Blue)")
	
	var spacer4 := Control.new()
	spacer4.custom_minimum_size = Vector2(0, 10)
	content.add_child(spacer4)
	
	# Close hint
	var close_hint := Label.new()
	close_hint.text = "Press Shift + ? again to close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 16)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	content.add_child(close_hint)
	
	return panel


func _add_help_line(parent: VBoxContainer, key: String, action: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	parent.add_child(hbox)
	
	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(220, 0)
	key_label.add_theme_font_size_override("font_size", 18)
	key_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	hbox.add_child(key_label)
	
	var action_label := Label.new()
	action_label.text = action
	action_label.add_theme_font_size_override("font_size", 18)
	action_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	hbox.add_child(action_label)
