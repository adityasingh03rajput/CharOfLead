extends Node
## GameManager.gd (Autoload) — the single brain of Di-Wall.
## Owns the random dimension-swap timer AND the shared, cross-dimension health
## so damage dealt in either State persists through swaps. Everything else
## listens; nothing else decides.

# --- Dimension state ---
# is_3d_mode == true  -> State A (3D Ground-Walk. Red Soldier is powerful.)
# is_3d_mode == false -> State B (2D Wall-Walk.   Blue Assassin is powerful.)
signal mode_changed(is_3d_mode)
signal swap_incoming(next_is_3d_mode)   # fired warning_lead_time before a swap

# --- Combat / shared health ---
signal health_changed(player_id, current, maximum)
signal player_died(player_id)
signal game_over(winner_id)
signal damage_dealt(target_id, amount)   # a shot actually connected (for hit markers)
signal weapon_changed(player_id, weapon_name)

@export var min_swap_time: float = 15.0
@export var max_swap_time: float = 45.0
@export var warning_lead_time: float = 3.0
@export var max_health: float = 100.0

var is_3d_mode: bool = true

var timer: Timer
var _warning_timer: Timer
var _warned_this_cycle: bool = false

var _health: Dictionary = {1: 100.0, 2: 100.0}
var _is_over: bool = false


func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS  # never freeze the swap brain

	_health = {1: max_health, 2: max_health}

	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

	_warning_timer = Timer.new()
	_warning_timer.one_shot = true
	_warning_timer.timeout.connect(_on_warning_timeout)
	add_child(_warning_timer)

	_start_random_timer()


func restart() -> void:
	_is_over = false
	_health = {1: max_health, 2: max_health}
	is_3d_mode = true
	timer.stop()
	_warning_timer.stop()
	get_tree().reload_current_scene()
	_start_random_timer()


func _start_random_timer() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_warned_this_cycle = false
	var next_interval: float = randf_range(min_swap_time, max_swap_time)
	timer.start(next_interval)

	var warn_at: float = next_interval - warning_lead_time
	if warn_at > 0.0:
		_warning_timer.start(warn_at)


func _on_warning_timeout() -> void:
	if _warned_this_cycle:
		return
	_warned_this_cycle = true
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("warning_rpc", not is_3d_mode)
	else:
		warning_rpc(not is_3d_mode)

@rpc("call_local", "authority", "reliable")
func warning_rpc(next_is_3d_mode: bool) -> void:
	swap_incoming.emit(next_is_3d_mode)

func _on_timer_timeout() -> void:
	swap_dimension()


## Flip the active dimension. Public so a debug key can force it.
func swap_dimension() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return # Only server decides to swap
	if multiplayer.has_multiplayer_peer():
		rpc("swap_dimension_rpc", not is_3d_mode)
	else:
		swap_dimension_rpc(not is_3d_mode)

@rpc("call_local", "authority", "reliable")
func swap_dimension_rpc(new_mode: bool) -> void:
	is_3d_mode = new_mode
	mode_changed.emit(is_3d_mode)
	_play_state_change_cues(is_3d_mode)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_start_random_timer()


func _play_state_change_cues(_is_3d_mode: bool) -> void:
	# The HUD turns these into a real screen flash.
	pass


# ---------------------------------------------------------------------------
# Combat API — the single source of truth for both dimensions.
# ---------------------------------------------------------------------------

## True when this player is the powerful/armed one in the CURRENT mode.
## Weapons query this before firing, so an "unarmed" player simply can't shoot.
func is_armed(player_id: int) -> bool:
	if player_id == 1:
		return is_3d_mode          # Red Soldier is armed in State A (3D).
	return not is_3d_mode          # Blue Assassin is armed in State B (2D).


func get_health(player_id: int) -> float:
	return _health.get(player_id, 0.0)


func apply_damage(target_id: int, amount: float) -> void:
	if _is_over or not _health.has(target_id):
		return
	_health[target_id] = clampf(_health[target_id] - amount, 0.0, max_health)
	health_changed.emit(target_id, _health[target_id], max_health)
	damage_dealt.emit(target_id, amount)
	if _health[target_id] <= 0.0:
		_end_game(target_id)


func _end_game(dead_id: int) -> void:
	_is_over = true
	timer.stop()
	_warning_timer.stop()
	var winner_id: int = 2 if dead_id == 1 else 1
	player_died.emit(dead_id)
	game_over.emit(winner_id)


func pop_weapon_name(player_id: int, weapon_name: String) -> void:
	weapon_changed.emit(player_id, weapon_name)


# Debug: force an immediate swap. Bind the "force_swap" action in the Input Map.
func _unhandled_input(event: InputEvent) -> void:
	if _is_over:
		return
	if event.is_action_pressed("force_swap"):
		timer.stop()
		_warning_timer.stop()
		swap_dimension()
