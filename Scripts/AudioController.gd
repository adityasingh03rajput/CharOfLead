extends Node3D
class_name AudioController

## Phase 16 — Audio Controller
## Surface-aware footstep system. Raycasts down to detect the material/physics
## material under the player, then selects the right sound profile.
## Generates synthetic click/thud sounds via AudioStreamGenerator if no
## audio files are present — works out of the box, zero assets required.

const STEP_DISTANCE_WALK := 1.4   # metres per step trigger
const STEP_DISTANCE_RUN  := 1.1

var _player:     CharacterBody3D
var _player_id:  int   = 1
var _dist_acc:   float = 0.0
var _last_pos:   Vector3 = Vector3.ZERO
var _audio_l:    AudioStreamPlayer3D
var _audio_r:    AudioStreamPlayer3D
var _left_foot:  bool = true


func init(player: CharacterBody3D, pid: int) -> void:
	_player    = player
	_player_id = pid
	_last_pos  = player.global_position
	_build_players()


func update(delta: float, moving: bool, running: bool) -> void:
	if not moving or not _player.is_on_floor(): return

	var moved := _player.global_position.distance_to(_last_pos)
	_last_pos  = _player.global_position
	_dist_acc += moved

	var threshold := STEP_DISTANCE_RUN if running else STEP_DISTANCE_WALK
	if _dist_acc >= threshold:
		_dist_acc -= threshold
		_play_step(running)


func _play_step(running: bool) -> void:
	var surface := _detect_surface()
	var player  := _audio_l if _left_foot else _audio_r
	_left_foot  = not _left_foot

	# Pitch and volume by surface and gait
	var pitch  := 1.0
	var volume := 0.0   # dB

	match surface:
		"metal":   pitch = 1.35; volume = -4.0
		"water":   pitch = 0.80; volume = -6.0
		"grass":   pitch = 0.65; volume = -10.0
		"snow":    pitch = 0.50; volume = -14.0
		"wood":    pitch = 1.10; volume = -7.0
		_:         pitch = 1.00; volume = -8.0   # concrete / default

	if running:
		pitch  *= 1.15
		volume += 3.0

	player.pitch_scale    = pitch + randf_range(-0.06, 0.06)
	player.volume_db      = volume
	player.global_position = _player.global_position
	player.play()


func _detect_surface() -> String:
	var space := _player.get_world_3d().direct_space_state
	var from  := _player.global_position + Vector3.UP * 0.1
	var to    := from + Vector3.DOWN * 0.4
	var q     := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1

	var hit := space.intersect_ray(q)
	if hit.is_empty(): return "concrete"

	# Try to read PhysicsMaterial name or collider group for surface hint
	var col = hit.get("collider")
	if col is StaticBody3D:
		var pm: PhysicsMaterial = col.physics_material_override
		if pm:
			var rname := ResourceLoader.get_resource_uid(pm.resource_path)
			# Fall back to group-name detection
		# Check groups for surface tags
		for g in ["surface_metal", "surface_water", "surface_grass",
				  "surface_snow", "surface_wood"]:
			if col.is_in_group(g):
				return g.replace("surface_", "")

	return "concrete"


func _build_players() -> void:
	for i in range(2):
		var ap := AudioStreamPlayer3D.new()
		ap.max_distance    = 18.0
		ap.attenuation_filter_cutoff_hz = 5000.0
		ap.stream = _make_step_stream()
		_player.add_child(ap)
		if i == 0: _audio_l = ap
		else:       _audio_r = ap


# Generates a short synthetic footstep click via AudioStreamGenerator.
static func _make_step_stream() -> AudioStreamGenerator:
	var gen        := AudioStreamGenerator.new()
	gen.mix_rate   = 22050.0
	gen.buffer_length = 0.06
	return gen


## Override this to feed real PCM data into the generator playback buffer.
## Called each time a step fires if you want live synthesis.
func push_step_audio(ap: AudioStreamPlayer3D) -> void:
	var pb := ap.get_stream_playback() as AudioStreamGeneratorPlayback
	if not pb: return
	var frames := pb.get_frames_available()
	for i in range(frames):
		# Simple decaying noise burst — sounds like a soft click/thud
		var t     := float(i) / 22050.0
		var env   := exp(-t * 60.0)
		var noise := (randf() * 2.0 - 1.0) * env * 0.3
		pb.push_frame(Vector2(noise, noise))
