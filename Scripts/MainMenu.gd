extends CanvasLayer
## MainMenu.gd — Full-screen launch menu for Di-Wall.
##
## Offers:
##   • Player vs Player  (local 2-player)
##   • Play as Red       (human Red vs AI Blue)
##   • Play as Blue      (human Blue vs AI Red)
## Difficulty: Easy / Medium / Hard
##
## Sets GameManager.ai_mode, .ai_plays_as, .ai_difficulty, then starts the scene.

signal play_requested

const COLORS = {
	"bg":         Color(0.04, 0.04, 0.08),
	"panel":      Color(0.08, 0.08, 0.14, 0.95),
	"accent_red": Color(0.9,  0.15, 0.12),
	"accent_blu": Color(0.15, 0.35, 0.95),
	"txt":        Color(0.92, 0.92, 0.96),
	"sub":        Color(0.55, 0.55, 0.70),
	"btn_bg":     Color(0.12, 0.12, 0.20),
	"btn_hover":  Color(0.20, 0.20, 0.32),
	"highlight":  Color(1.0,  0.85, 0.25),
}

var _selected_mode:       int = 0   # 0=PvP, 1=HumanRed, 2=HumanBlue
var _selected_difficulty: int = 2   # 0=Easy, 1=Medium, 2=Hard

var _mode_btns:   Array[Button] = []
var _diff_btns:   Array[Button] = []
var _start_btn:   Button
var _scanline:    ColorRect
var _diff_container: Control   # stored directly so we can toggle visible

var _anim_time: float = 0.0


func _ready() -> void:
	layer = 100
	_build_ui()
	_update_selections()


func _process(delta: float) -> void:
	_anim_time += delta
	if _scanline:
		_scanline.position.y = fmod(_anim_time * 120.0, get_viewport().size.y)


# ====================================================================
# UI BUILD
# ====================================================================
func _build_ui() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# ── Background ──────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = COLORS["bg"]
	add_child(bg)

	# Scan-line strip
	_scanline = ColorRect.new()
	_scanline.size = Vector2(vp.x, 2.0)
	_scanline.color = Color(0.5, 0.7, 1.0, 0.06)
	_scanline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scanline)

	# ── Center panel ────────────────────────────────────────────────────────
	var panel_sz := Vector2(minf(640, vp.x * 0.85), minf(700, vp.y * 0.88))
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_sz * 0.5
	panel.custom_minimum_size = panel_sz

	var ps := StyleBoxFlat.new()
	ps.bg_color = COLORS["panel"]
	ps.corner_radius_top_left     = 12
	ps.corner_radius_top_right    = 12
	ps.corner_radius_bottom_left  = 12
	ps.corner_radius_bottom_right = 12
	ps.border_width_left   = 1; ps.border_width_right  = 1
	ps.border_width_top    = 1; ps.border_width_bottom = 1
	ps.border_color = Color(0.25, 0.30, 0.55, 0.6)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	# ── Title ────────────────────────────────────────────────────────────────
	_add_spacer(vbox, 10)
	var title := Label.new()
	title.text = "DI-WALL"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", COLORS["txt"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "DUAL DIMENSION PvP"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", COLORS["sub"])
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	_add_separator(vbox, COLORS["accent_red"])
	_add_section_label(vbox, "GAME MODE")

	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 8)
	mode_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(mode_hbox)

	var mode_defs := [
		["⚔  PvP",          Color(0.25, 0.50, 0.28)],
		["🔴  Play as Red",  COLORS["accent_red"]],
		["🔵  Play as Blue", COLORS["accent_blu"]],
	]
	for i in mode_defs.size():
		var def = mode_defs[i]
		var btn := _make_toggle_btn(def[0], def[1])
		mode_hbox.add_child(btn)
		_mode_btns.append(btn)
		var idx := i
		btn.pressed.connect(func():
			_selected_mode = idx
			_update_selections()
		)

	_add_separator(vbox, COLORS["accent_blu"])

	# ── Difficulty container (hidden in PvP mode) ─────────────────────────────
	_diff_container = VBoxContainer.new()
	_diff_container.name = "DiffContainer"
	_diff_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_diff_container)

	_add_section_label(_diff_container, "AI DIFFICULTY")

	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 8)
	diff_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_diff_container.add_child(diff_hbox)

	var diff_defs := [
		["EASY",   Color(0.20, 0.65, 0.25)],
		["MEDIUM", Color(0.80, 0.60, 0.10)],
		["HARD",   Color(0.85, 0.15, 0.12)],
	]
	for i in diff_defs.size():
		var def = diff_defs[i]
		var btn := _make_toggle_btn(def[0], def[1])
		diff_hbox.add_child(btn)
		_diff_btns.append(btn)
		var idx := i
		btn.pressed.connect(func():
			_selected_difficulty = idx
			_update_selections()
		)

	_add_separator(vbox, Color(0.3, 0.3, 0.4, 0.4))
	_add_controls_box(vbox)

	# ── Start button (centred via CenterContainer) ────────────────────────────
	_add_spacer(vbox, 4)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(center)
	_start_btn = _make_start_btn()
	center.add_child(_start_btn)
	_add_spacer(vbox, 12)

	var ver := Label.new()
	ver.text = "v0.1.0 — Ctrl+R to restart in-game"
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", COLORS["sub"])
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ver)


func _add_spacer(parent: Control, height: int) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	parent.add_child(sp)


func _add_separator(parent: Control, col: Color) -> void:
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(col.r, col.g, col.b, 0.35)
	parent.add_child(sep)


func _add_section_label(parent: Control, txt: String) -> void:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COLORS["sub"])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)


func _make_toggle_btn(txt: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(160, 52)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COLORS["txt"])
	btn.toggle_mode = false
	btn.add_theme_stylebox_override("normal",  _btn_style(COLORS["btn_bg"],          accent, false))
	btn.add_theme_stylebox_override("hover",   _btn_style(COLORS["btn_hover"],       accent, false))
	btn.add_theme_stylebox_override("pressed", _btn_style(accent.darkened(0.25),     accent, true))
	btn.add_theme_stylebox_override("focus",   _btn_style(COLORS["btn_hover"],       accent, false))
	return btn


func _btn_style(bg: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left   = 1; s.border_width_right  = 1
	s.border_width_top    = 2 if selected else 1
	s.border_width_bottom = 2 if selected else 1
	# Fix: Color constructor needs 4 floats, not (Color, float)
	s.border_color = border if selected else Color(border.r, border.g, border.b, 0.35)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s


func _make_start_btn() -> Button:
	var btn := Button.new()
	btn.text = "▶  START MATCH"
	btn.custom_minimum_size = Vector2(300, 56)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))

	var s_n := StyleBoxFlat.new()
	s_n.bg_color = COLORS["highlight"]
	s_n.corner_radius_top_left     = 8
	s_n.corner_radius_top_right    = 8
	s_n.corner_radius_bottom_left  = 8
	s_n.corner_radius_bottom_right = 8

	var s_h := s_n.duplicate() as StyleBoxFlat
	s_h.bg_color = COLORS["highlight"].lightened(0.12)

	var s_p := s_n.duplicate() as StyleBoxFlat
	s_p.bg_color = COLORS["highlight"].darkened(0.15)

	btn.add_theme_stylebox_override("normal",  s_n)
	btn.add_theme_stylebox_override("hover",   s_h)
	btn.add_theme_stylebox_override("pressed", s_p)
	btn.add_theme_stylebox_override("focus",   s_h)
	btn.pressed.connect(_on_start_pressed)
	return btn


func _add_controls_box(parent: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)

	var rows := [
		["Red (3D): WASD+Space", "Mouse aim / LMB fire", "Blue (2D): Arrow keys", "Mouse aim / . fire"],
		["C: camera cycle",      "P: force swap",        "Ctrl+R: restart",       "O: track cam switch"],
	]
	for row in rows:
		for cell in row:
			var lbl := Label.new()
			lbl.text = cell
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", COLORS["sub"])
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(lbl)


func _update_selections() -> void:
	var is_ai := _selected_mode != 0

	# Toggle difficulty panel visibility
	if _diff_container:
		_diff_container.visible = is_ai

	# Highlight mode buttons
	var mode_colors := [Color(0.25, 0.50, 0.28), COLORS["accent_red"], COLORS["accent_blu"]]
	for i in _mode_btns.size():
		var btn := _mode_btns[i]
		var sel := (i == _selected_mode)
		var accent: Color = mode_colors[i]
		btn.add_theme_stylebox_override("normal", _btn_style(
			accent.darkened(0.45) if sel else COLORS["btn_bg"], accent, sel))
		btn.modulate = Color.WHITE if sel else Color(0.75, 0.75, 0.85)

	# Highlight difficulty buttons
	var diff_colors := [Color(0.20, 0.65, 0.25), Color(0.80, 0.60, 0.10), Color(0.85, 0.15, 0.12)]
	for i in _diff_btns.size():
		var btn := _diff_btns[i]
		var sel := (i == _selected_difficulty)
		var accent: Color = diff_colors[i]
		btn.add_theme_stylebox_override("normal", _btn_style(
			accent.darkened(0.4) if sel else COLORS["btn_bg"], accent, sel))
		btn.modulate = Color.WHITE if sel else Color(0.65, 0.65, 0.75)

	# Update start button label
	if _start_btn:
		match _selected_mode:
			0: _start_btn.text = "▶  START PvP MATCH"
			1: _start_btn.text = "▶  PLAY AS RED vs AI"
			2: _start_btn.text = "▶  PLAY AS BLUE vs AI"


func _on_start_pressed() -> void:
	# Push config into GameManager BEFORE freeing this node
	if GameManager:
		GameManager.ai_mode      = (_selected_mode != 0)
		# _selected_mode 1 = Human plays Red -> AI plays Blue (2)
		# _selected_mode 2 = Human plays Blue -> AI plays Red (1)
		GameManager.ai_plays_as  = 2 if _selected_mode == 1 else 1 if _selected_mode == 2 else 0
		GameManager.ai_difficulty = _selected_difficulty
	# Emit BEFORE queue_free so the connection in Main.gd receives the signal
	play_requested.emit()
	queue_free()
