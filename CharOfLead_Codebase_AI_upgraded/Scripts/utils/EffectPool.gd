class_name EffectPool
extends RefCounted

# Singleton pattern
static var _instance
static func get_instance():
	if not _instance:
		_instance = load("res://Scripts/utils/EffectPool.gd").new()
	return _instance

# Pool storage
var _pools: Dictionary = {
	"blood": [],
	"spark": [],
	"tracer": [],
	"decal": []
}
var _max_pool_size: int = 20
var _active_effects: Array = []

# Preload templates
var _templates: Dictionary = {}

func _init():
	_initialize_templates()

func _initialize_templates() -> void:
	# Blood template
	var blood_template = CPUParticles3D.new()
	blood_template.amount = 60
	blood_template.lifetime = 0.6
	blood_template.explosiveness = 0.95
	blood_template.direction = Vector3.UP
	blood_template.spread = 55.0
	blood_template.initial_velocity_min = 5.0
	blood_template.initial_velocity_max = 16.0
	blood_template.gravity = Vector3(0, -12, 0)
	blood_template.damping_min = 3.0
	blood_template.damping_max = 6.0
	blood_template.scale_amount_min = 0.6
	blood_template.scale_amount_max = 1.4
	
	var blood_mesh = SphereMesh.new()
	blood_mesh.radius = 0.04
	blood_mesh.height = 0.08
	
	var blood_mat = StandardMaterial3D.new()
	blood_mat.albedo_color = Color(0.85, 0.04, 0.04)
	blood_mat.emission_enabled = true
	blood_mat.emission = Color(0.7, 0.02, 0.02)
	blood_mat.emission_energy_multiplier = 1.5
	blood_mesh.material = blood_mat
	
	blood_template.mesh = blood_mesh
	_templates["blood"] = blood_template
	
	# Spark template
	var spark_template = CPUParticles3D.new()
	spark_template.amount = 20
	spark_template.lifetime = 0.3
	spark_template.explosiveness = 0.95
	spark_template.direction = Vector3.UP
	spark_template.spread = 45.0
	spark_template.initial_velocity_min = 3.0
	spark_template.initial_velocity_max = 10.0
	spark_template.gravity = Vector3(0, -8, 0)
	
	var spark_mesh = SphereMesh.new()
	spark_mesh.radius = 0.02
	spark_mesh.height = 0.04
	
	var spark_mat = StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.85, 0.3)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.8, 0.3)
	spark_mat.emission_energy_multiplier = 3.0
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material = spark_mat
	
	spark_template.mesh = spark_mesh
	_templates["spark"] = spark_template
	
	# Tracer template
	var tracer_template = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.5
	
	var cyl_mat := StandardMaterial3D.new()
	cyl_mat.albedo_color = Color(1.0, 0.92, 0.3)
	cyl_mat.emission_enabled = true
	cyl_mat.emission = Color(1.0, 0.9, 0.3)
	cyl_mat.emission_energy_multiplier = 4.0
	cyl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl_mat.albedo_color.a = 0.85
	cyl.material = cyl_mat
	tracer_template.mesh = cyl
	
	# We store the lifetime of tracer in a meta variable for tracking
	tracer_template.set_meta("lifetime", 0.4)
	
	_templates["tracer"] = tracer_template

func get_effect(effect_type: String) -> Node3D:
	var pool = _pools.get(effect_type, [])
	var effect: Node3D
	
	if pool.size() > 0:
		effect = pool.pop_back()
		# Reset effect for reuse
		if effect is CPUParticles3D:
			effect.emitting = false
			effect.amount = _templates[effect_type].amount
			effect.lifetime = _templates[effect_type].lifetime
			effect.one_shot = true
			effect.visible = true
		elif effect is MeshInstance3D:
			effect.visible = true
			effect.scale = Vector3.ONE
	else:
		# Create new effect from template
		var template = _templates.get(effect_type)
		if not template:
			return null
		
		effect = template.duplicate()
		
		# Add cleanup callback
		effect.tree_exited.connect(_cleanup_effect.bind(effect))
	
	var lifetime = 2.0
	if effect is CPUParticles3D:
		lifetime = effect.lifetime + 0.2
	elif effect.has_meta("lifetime"):
		lifetime = effect.get_meta("lifetime")
	
	# Add to active tracking
	_active_effects.append({
		"node": effect,
		"type": effect_type,
		"timeout": lifetime
	})
	
	return effect

func recycle_effect(effect: Node3D) -> void:
	if not effect or effect.is_queued_for_deletion():
		return
	
	if effect is CPUParticles3D:
		effect.emitting = false
	effect.visible = false
	
	# Remove from active tracking
	for i in range(_active_effects.size() - 1, -1, -1):
		if _active_effects[i]["node"] == effect:
			_active_effects.remove_at(i)
			break
	
	# Add back to pool
	var effect_type = _get_effect_type(effect)
	if effect_type and _pools.has(effect_type):
		var pool = _pools[effect_type]
		if pool.size() < _max_pool_size:
			if effect.get_parent():
				effect.get_parent().remove_child(effect)
			pool.append(effect)
		else:
			effect.queue_free()

func _cleanup_effect(effect: Node3D) -> void:
	# Called when effect is about to be freed
	recycle_effect(effect)

func _get_effect_type(effect: Node3D) -> String:
	# Try to determine effect type from mesh color or other properties
	if effect is CPUParticles3D and effect.mesh is SphereMesh:
		var mat = effect.mesh.material as StandardMaterial3D
		if mat:
			if mat.albedo_color == Color(0.85, 0.04, 0.04):
				return "blood"
			elif mat.albedo_color == Color(1.0, 0.85, 0.3):
				return "spark"
	elif effect is MeshInstance3D and effect.mesh is CylinderMesh:
		return "tracer"
	return ""

func cleanup_all() -> void:
	for effect_data in _active_effects:
		var effect = effect_data["node"]
		if is_instance_valid(effect):
			effect.queue_free()
	
	_active_effects.clear()
	
	# Clear pools
	for pool in _pools.values():
		for item in pool:
			if is_instance_valid(item):
				item.queue_free()
		pool.clear()

func _get_size() -> int:
	var total = 0
	for pool in _pools.values():
		total += pool.size()
	return total
