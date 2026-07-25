extends CanvasLayer
## MainMenu.gd — Full-screen launch menu for Di-Wall.
##
## Offers:
##   • Player vs Player  (local 2-player)
##   • Play as Red       (human Red vs AI Blue)
##   • Play as Blue      (human Blue vs AI Red)
##   • Host Online       (P2P ENet host with Room Code)
##   • Join Online       (P2P ENet join with Room Code)
##
## Sets GameManager.ai_mode, .ai_plays_as, .ai_difficulty, NetworkManager options, then starts the scene.

signal play_requested

const COLORS = {
	"bg":         Color(0.04, 0.04, 0.08),
	"panel":      Color(0.08, 0.08, 0.14, 0.95),
	"accent_red": Color(0.9,  0.15, 0.12),
	"accent_blu": Color(0.15, 0.35, 0.95),
	"accent_net": Color(0.20, 0.70, 0.85),
	"txt":        Color(0.92, 0.92, 0.96),
	"sub":        Color(0.55, 0.55, 0.70),
	"btn_bg":     Color(0.12, 0.12, 0.20),
	"btn_hover":  Color(0.20, 0.20, 0.32),
	"highlight":  Color(1.0,  0.85, 0.25),
}

var _selected_mode:       int = 0   # 0=PvP, 1=HumanRed, 2=HumanBlue, 3=HostNet, 4=JoinNet
var _selected_difficulty: int = 2   # 0=Easy, 1=Medium, 2=Hard
var _host_chosen_role:    int = 0   # 0=Random, 1=Red, 2=Blue

var _mode_btns:        Array[Button] = []
var _diff_btns:        Array[Button] = []
var _host_role_btns:   Array[Button] = []
var _start_btn:        Button
var _scanline:         ColorRect
var _diff_container:   Control   # toggled for AI mode
var _host_container:   Control   # toggled for Host mode
var _join_container:   Control   # toggled for Join mode

var _code_edit:        LineEdit
var _status_lbl:       Label
var _host_code_lbl:    Label
var _anim_time:        float = 0.0


func _ready() -> void:
	layer = 100
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	var panel_sz := Vector2(minf(700, vp.x * 0.90), minf(740, vp.y * 0.92))
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
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	# ── Title ────────────────────────────────────────────────────────────────
	_add_spacer(vbox, 8)
	var title := Label.new()
	title.text = "DI-WALL"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", COLORS["txt"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "DUAL DIMENSION PvP & ONLINE MULTIPLAYER"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", COLORS["sub"])
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	_add_separator(vbox, COLORS["accent_red"])
	_add_section_label(vbox, "GAME MODE")

	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 6)
	mode_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(mode_hbox)

	var mode_defs := [
		["⚔ Local PvP",      Color(0.25, 0.50, 0.28)],
		["🔴 vs AI (Red)",    COLORS["accent_red"]],
		["🔵 vs AI (Blue)",   COLORS["accent_blu"]],
		["🌐 Host Online",    COLORS["accent_net"]],
		["🔗 Join Online",    Color(0.85, 0.45, 0.15)],
	]
	for i in mode_defs.size():
		var def = mode_defs[i]
		var btn := _make_toggle_btn(def[0], def[1], Vector2(125, 46))
		mode_hbox.add_child(btn)
		_mode_btns.append(btn)
		var idx := i
		btn.pressed.connect(func():
			_selected_mode = idx
			_update_selections()
		)

	_add_separator(vbox, COLORS["accent_blu"])

	# ── AI Difficulty container (hidden outside AI mode) ──────────────────────
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
		var btn := _make_toggle_btn(def[0], def[1], Vector2(140, 42))
		diff_hbox.add_child(btn)
		_diff_btns.append(btn)
		var idx := i
		btn.pressed.connect(func():
			_selected_difficulty = idx
			_update_selections()
		)

	# ── Online Host container ─────────────────────────────────────────────────
	_host_container = VBoxContainer.new()
	_host_container.name = "HostContainer"
	_host_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_host_container)

	_add_section_label(_host_container, "YOUR HOST ROLE")
	var role_hbox := HBoxContainer.new()
	role_hbox.add_theme_constant_override("separation", 8)
	role_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_host_container.add_child(role_hbox)

	var role_defs := [
		["🎲 Random", COLORS["txt"]],
		["🔴 Red Soldier", COLORS["accent_red"]],
		["🔵 Blue Assassin", COLORS["accent_blu"]],
	]
	for i in role_defs.size():
		var def = role_defs[i]
		var btn := _make_toggle_btn(def[0], def[1], Vector2(150, 40))
		role_hbox.add_child(btn)
		_host_role_btns.append(btn)
		var idx := i
		btn.pressed.connect(func():
			_host_chosen_role = idx
			_update_selections()
		)

	var code_box := VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 2)
	_host_container.add_child(code_box)

	var room_code := NetworkManager.get_room_code() if NetworkManager else "1050"
	_host_code_lbl = Label.new()
	_host_code_lbl.text = "YOUR ROOM CODE:  %s" % room_code
	_host_code_lbl.add_theme_font_size_override("font_size", 22)
	_host_code_lbl.add_theme_color_override("font_color", COLORS["highlight"])
	_host_code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_box.add_child(_host_code_lbl)

	var ip_info := Label.new()
	var local_ip := NetworkManager.get_local_ip() if NetworkManager else "127.0.0.1"
	ip_info.text = "Share this Room Code with your friend! (Local IP: %s)" % local_ip
	ip_info.add_theme_font_size_override("font_size", 11)
	ip_info.add_theme_color_override("font_color", COLORS["sub"])
	ip_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_box.add_child(ip_info)

	# ── Online Join container ─────────────────────────────────────────────────
	_join_container = VBoxContainer.new()
	_join_container.name = "JoinContainer"
	_join_container.add_theme_constant_override("separation", 6)
	vbox.add_child(_join_container)

	_add_section_label(_join_container, "ENTER ROOM CODE TO JOIN")
	var join_hbox := HBoxContainer.new()
	join_hbox.add_theme_constant_override("separation", 10)
	join_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_container.add_child(join_hbox)

	var code_input_lbl := Label.new()
	code_input_lbl.text = "Room Code:"
	code_input_lbl.add_theme_font_size_override("font_size", 14)
	code_input_lbl.add_theme_color_override("font_color", COLORS["txt"])
	join_hbox.add_child(code_input_lbl)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "e.g. 1050 or 'local'"
	_code_edit.custom_minimum_size = Vector2(220, 42)
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_size_override("font_size", 16)
	if NetworkManager:
		var last_c := NetworkManager.load_last_code()
		if last_c != "":
			_code_edit.text = last_c
	join_hbox.add_child(_code_edit)

	var local_hint := Label.new()
	local_hint.text = "Testing 2 instances on 1 laptop? Type the Room Code or 'local'!"
	local_hint.add_theme_font_size_override("font_size", 11)
	local_hint.add_theme_color_override("font_color", COLORS["sub"])
	local_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_container.add_child(local_hint)

	# ── Status Label ──────────────────────────────────────────────────────────
	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", COLORS["accent_net"])
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_lbl)

	_add_separator(vbox, Color(0.3, 0.3, 0.4, 0.4))
	_add_controls_box(vbox)

	# ── Start button ──────────────────────────────────────────────────────────
	_add_spacer(vbox, 4)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(center)
	_start_btn = _make_start_btn()
	center.add_child(_start_btn)
	_add_spacer(vbox, 8)

	var ver := Label.new()
	ver.text = "v0.2.0 — Dual-Dimension Online Room Code Matchmaking"
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


func _make_toggle_btn(txt: String, accent: Color, sz: Vector2 = Vector2(160, 52)) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = sz
	btn.add_theme_font_size_override("font_size", 13)
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
	s.border_color = border if selected else Color(border.r, border.g, border.b, 0.35)
	s.corner_radius_top_left     = 6
	s.corner_radius_top_right    = 6
	s.corner_radius_bottom_left  = 6
	s.corner_radius_bottom_right = 6
	return s


func _make_start_btn() -> Button:
	var btn := Button.new()
	btn.text = "▶  START MATCH"
	btn.custom_minimum_size = Vector2(300, 52)
	btn.add_theme_font_size_override("font_size", 18)
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
	var is_ai := (_selected_mode == 1 or _selected_mode == 2)
	var is_host := (_selected_mode == 3)
	var is_join := (_selected_mode == 4)

	# Toggle panels
	if _diff_container: _diff_container.visible = is_ai
	if _host_container: _host_container.visible = is_host
	if _join_container: _join_container.visible = is_join

	# Highlight mode buttons
	var mode_colors := [
		Color(0.25, 0.50, 0.28),
		COLORS["accent_red"],
		COLORS["accent_blu"],
		COLORS["accent_net"],
		Color(0.85, 0.45, 0.15)
	]
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

	# Highlight host role buttons
	var role_colors := [COLORS["txt"], COLORS["accent_red"], COLORS["accent_blu"]]
	for i in _host_role_btns.size():
		var btn := _host_role_btns[i]
		var sel := (i == _host_chosen_role)
		var accent: Color = role_colors[i]
		btn.add_theme_stylebox_override("normal", _btn_style(
			accent.darkened(0.4) if sel else COLORS["btn_bg"], accent, sel))
		btn.modulate = Color.WHITE if sel else Color(0.65, 0.65, 0.75)

	# Update start button label
	if _start_btn:
		match _selected_mode:
			0: _start_btn.text = "▶  START LOCAL MATCH"
			1: _start_btn.text = "▶  PLAY AS RED vs AI"
			2: _start_btn.text = "▶  PLAY AS BLUE vs AI"
			3: _start_btn.text = "▶  OPEN LOBBY"
			4: _start_btn.text = "▶  JOIN ROOM CODE"


func _on_start_pressed() -> void:
	if _status_lbl:
		_status_lbl.text = ""

	match _selected_mode:
		0, 1, 2:
			if NetworkManager:
				NetworkManager.stop()
			if GameManager:
				GameManager.ai_mode       = (_selected_mode != 0)
				GameManager.ai_plays_as   = 2 if _selected_mode == 1 else 1 if _selected_mode == 2 else 0
				GameManager.ai_difficulty = _selected_difficulty
			play_requested.emit()
			queue_free()

		3: # Host Online
			if NetworkManager:
				var err := NetworkManager.start_host(_host_chosen_role)
				if err != "":
					if _status_lbl: _status_lbl.text = "Error: " + err
					return
				var room_code := NetworkManager.get_room_code()
				if _host_code_lbl:
					_host_code_lbl.text = "YOUR ROOM CODE:  %s" % room_code
				if _status_lbl:
					_status_lbl.text = "Lobby Open! Share Room Code: %s\nWaiting for friend to enter code..." % room_code
				_start_btn.disabled = true
				_start_btn.text = "⏳ WAITING FOR FRIEND..."
				if not NetworkManager.connected.is_connected(_on_net_connected):
					NetworkManager.connected.connect(_on_net_connected)
				if not NetworkManager.connection_failed.is_connected(_on_net_failed):
					NetworkManager.connection_failed.connect(_on_net_failed)

		4: # Join Online
			if NetworkManager:
				var user_input := _code_edit.text.strip_edges() if _code_edit else ""
				if user_input == "":
					if _status_lbl: _status_lbl.text = "Please enter a Room Code!"
					return
				var target_ip := NetworkManager.code_to_ip(user_input)
				var err := NetworkManager.start_join(user_input)
				if err != "":
					if _status_lbl: _status_lbl.text = "Error: " + err
					return
				if _status_lbl:
					_status_lbl.text = "Connecting via Room Code '%s' (%s)..." % [user_input, target_ip]
				_start_btn.disabled = true
				_start_btn.text = "⏳ CONNECTING..."
				if not NetworkManager.connected.is_connected(_on_net_connected):
					NetworkManager.connected.connect(_on_net_connected)
				if not NetworkManager.connection_failed.is_connected(_on_net_failed):
					NetworkManager.connection_failed.connect(_on_net_failed)


func _on_net_connected() -> void:
	play_requested.emit()
	queue_free()


func _on_net_failed() -> void:
	if _start_btn:
		_start_btn.disabled = false
		_start_btn.text = "▶ RETRY ROOM CODE"
	if _status_lbl:
		_status_lbl.text = "Connection Failed! Double-check the Room Code and try again."
