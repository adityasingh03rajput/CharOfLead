extends CanvasLayer
## HUD.gd — health bars, current-mode banner, dimension-swap flash overlay, and
## the win banner. The flash turns GameManager's print cues into a real
## screen effect (red for Soldier dominance, blue for Assassin dominance).

@export var p1_bar: ProgressBar
@export var p2_bar: ProgressBar
@export var mode_label: Label
@export var winner_label: Label
@export var flash: ColorRect          # full-screen overlay, starts transparent
@export var hitmarker: Control        # Free Fire style ✕ that pops on a connect
@export var weapon_popup: Control     # Gun name pop-up banner

@export var flash_duration: float = 0.45
@export var flash_peak_alpha: float = 0.55

var _flash_t: float = 0.0
var _flash_rgb: Color = Color(1, 0, 0)
var _hit_t: float = 0.0
var _weapon_pop_t: float = 0.0
const HITMARKER_DURATION := 0.18

const RED_CUE := Color(1.0, 0.15, 0.15)
const BLUE_CUE := Color(0.2, 0.4, 1.0)

# ── Key-help overlay ──
var _help_panel: PanelContainer
var _help_visible: bool = false


var _rematch_modal: PanelContainer
var _rematch_title_lbl: Label

func _ready() -> void:
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.mode_changed.connect(_on_mode_changed)
	GameManager.swap_incoming.connect(_on_swap_incoming)
	GameManager.game_over.connect(_on_game_over)
	GameManager.match_restarted.connect(_on_match_restarted)
	GameManager.damage_dealt.connect(_on_damage_dealt)
	GameManager.weapon_changed.connect(_on_weapon_changed)

	_on_health_changed(1, GameManager.get_health(1), GameManager.max_health)
	_on_health_changed(2, GameManager.get_health(2), GameManager.max_health)
	_on_mode_changed(GameManager.is_3d_mode)

	if winner_label:
		winner_label.visible = false
	if hitmarker:
		hitmarker.visible = false
	if weapon_popup:
		weapon_popup.visible = false
	if flash:
		flash.color = Color(_flash_rgb, 0.0)


func _process(delta: float) -> void:
	if _flash_t > 0.0 and flash:
		_flash_t -= delta
		var a: float = clampf(_flash_t / flash_duration, 0.0, 1.0) * flash_peak_alpha
		flash.color = Color(_flash_rgb, a)

	if _hit_t > 0.0 and hitmarker:
		_hit_t -= delta
		hitmarker.modulate.a = clampf(_hit_t / HITMARKER_DURATION, 0.0, 1.0)
		if _hit_t <= 0.0:
			hitmarker.visible = false

	if _weapon_pop_t > 0.0 and weapon_popup:
		_weapon_pop_t -= delta
		if _weapon_pop_t <= 0.4:
			weapon_popup.modulate.a = clampf(_weapon_pop_t / 0.4, 0.0, 1.0)
		if _weapon_pop_t <= 0.0:
			weapon_popup.visible = false


func _on_weapon_changed(_player_id: int, weapon_name: String) -> void:
	if weapon_popup:
		weapon_popup.visible = true
		weapon_popup.modulate.a = 1.0
		weapon_popup.pivot_offset = weapon_popup.size / 2.0
		weapon_popup.scale = Vector2(0.75, 0.75)
		
		var title_node = weapon_popup.find_child("Title", true, false)
		if title_node is Label:
			title_node.text = weapon_name
			
		var wtween = create_tween().set_parallel(true)
		wtween.tween_property(weapon_popup, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		
		_weapon_pop_t = 1.8


func _on_damage_dealt(_target_id: int, _amount: float) -> void:
	if hitmarker:
		hitmarker.visible = true
		hitmarker.modulate.a = 1.0
	_hit_t = HITMARKER_DURATION


func _on_health_changed(player_id: int, current: float, maximum: float) -> void:
	var bar: ProgressBar = p1_bar if player_id == 1 else p2_bar
	if bar:
		bar.max_value = maximum
		bar.value = current


func _on_mode_changed(is_3d_mode: bool) -> void:
	if mode_label:
		mode_label.text = "STATE A - 3D  (Red Soldier ARMED)" if is_3d_mode \
			else "STATE B - 2D  (Blue Assassin ARMED)"
	_do_flash(RED_CUE if is_3d_mode else BLUE_CUE)


func _on_swap_incoming(next_is_3d_mode: bool) -> void:
	_do_flash(RED_CUE if next_is_3d_mode else BLUE_CUE)


func _do_flash(rgb: Color) -> void:
	_flash_rgb = rgb
	_flash_t = flash_duration


func _on_game_over(winner_id: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if winner_label:
		winner_label.visible = false # replaced by full rematch modal window
	_show_rematch_modal(winner_id)


func _on_match_restarted() -> void:
	if _rematch_modal:
		_rematch_modal.visible = false


func _show_rematch_modal(winner_id: int) -> void:
	if not _rematch_modal:
		_rematch_modal = PanelContainer.new()
		_rematch_modal.name = "RematchModal"
		_rematch_modal.set_anchors_preset(Control.PRESET_CENTER)
		_rematch_modal.custom_minimum_size = Vector2(440, 260)
		_rematch_modal.position = Vector2(-220, -130)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.14, 0.95)
		style.border_width_left = 2; style.border_width_right = 2
		style.border_width_top = 2; style.border_width_bottom = 2
		style.border_color = Color(0.2, 0.7, 0.9, 0.8)
		style.corner_radius_top_left = 12; style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
		_rematch_modal.add_theme_stylebox_override("panel", style)

		var margin := MarginContainer.new()
		margin.name = "MarginContainer"
		margin.add_theme_constant_override("margin_left", 24)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_right", 24)
		margin.add_theme_constant_override("margin_bottom", 20)
		_rematch_modal.add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.name = "VBox"
		vbox.add_theme_constant_override("separation", 16)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(vbox)

		_rematch_title_lbl = Label.new()
		_rematch_title_lbl.name = "Title"
		_rematch_title_lbl.add_theme_font_size_override("font_size", 24)
		_rematch_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(_rematch_title_lbl)

		var sub := Label.new()
		sub.text = "MATCH FINISHED"
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.75))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sub)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(hbox)

		var rematch_btn := Button.new()
		rematch_btn.text = "▶  REMATCH"
		rematch_btn.custom_minimum_size = Vector2(160, 48)
		rematch_btn.add_theme_font_size_override("font_size", 16)
		rematch_btn.pressed.connect(func():
			_rematch_modal.visible = false
			if GameManager:
				GameManager.request_rematch()
		)
		hbox.add_child(rematch_btn)

		var menu_btn := Button.new()
		menu_btn.text = "🏠  MAIN MENU"
		menu_btn.custom_minimum_size = Vector2(160, 48)
		menu_btn.add_theme_font_size_override("font_size", 16)
		menu_btn.pressed.connect(func():
			_rematch_modal.visible = false
			var nm = get_node_or_null("/root/NetworkManager")
			if nm: nm.stop()
			get_tree().reload_current_scene()
		)
		hbox.add_child(menu_btn)

		add_child(_rematch_modal)

	if _rematch_title_lbl:
		if winner_id == 1:
			_rematch_title_lbl.text = "🔴 RED SOLDIER WINS!"
			_rematch_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		else:
			_rematch_title_lbl.text = "🔵 BLUE ASSASSIN WINS!"
			_rematch_title_lbl.add_theme_color_override("font_color", Color(0.25, 0.6, 1.0))

	_rematch_modal.visible = true


func _unhandled_input(event: InputEvent) -> void:
	# Shift + ? (which is Shift + /) to toggle help
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SLASH and event.shift_pressed:
			toggle_help()


func toggle_help() -> void:
	_help_visible = not _help_visible
	if _help_panel:
		_help_panel.visible = _help_visible


func set_help_panel(panel: PanelContainer) -> void:
	_help_panel = panel
