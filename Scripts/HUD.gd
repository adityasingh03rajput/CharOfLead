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


func _ready() -> void:
	GameManager.health_changed.connect(_on_health_changed)
	GameManager.mode_changed.connect(_on_mode_changed)
	GameManager.swap_incoming.connect(_on_swap_incoming)
	GameManager.game_over.connect(_on_game_over)
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
	if winner_label:
		winner_label.visible = true
		winner_label.text = "PLAYER %d WINS!" % winner_id


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
