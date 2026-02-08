## Road wetness manager for MIDNIGHT GRIND weather system.
## Controls wet road material application, gradual wetness buildup/drying,
## puddle formation, and tire spray particles from vehicles driving on
## wet surfaces.
class_name RoadWetness
extends Node

# ── Configuration ────────────────────────────────────────────────────────────
@export_group("Wetness Timing")
## Seconds of rain required to reach full wetness.
@export var wet_buildup_time: float = 30.0
## Seconds after rain stops to fully dry.
@export var dry_time: float = 120.0

@export_group("Puddles")
## Minimum wetness level before puddles start forming.
@export var puddle_threshold: float = 0.4
## Maximum puddle amount at full wetness.
@export var max_puddle_amount: float = 0.8

@export_group("Tire Spray")
## Enable tire spray particles behind vehicles on wet roads.
@export var enable_tire_spray: bool = true
## Minimum speed (km/h) for tire spray to activate.
@export var spray_min_speed: float = 30.0
## Maximum particle count for tire spray.
@export var spray_max_particles: int = 200

# ── State ────────────────────────────────────────────────────────────────────
var _wetness: float = 0.0
var _is_raining: bool = false
var _previous_wetness_bucket: int = -1

# Road material references (assigned via apply_to_roads)
var _wet_road_materials: Array[ShaderMaterial] = []

# Tire spray particle systems (one per tracked vehicle)
var _tire_spray_systems: Dictionary = {}  # vehicle_id -> GPUParticles3D

# Puddle spots (optional MeshInstance3D overlays)
var _puddle_meshes: Array[MeshInstance3D] = []

# Wet road shader path
const WET_ROAD_SHADER_PATH := "res://assets/shaders/wet_road.gdshader"


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	print("[Weather] Road wetness system initialized")


func _process(delta: float) -> void:
	_update_wetness(delta)
	_update_materials()
	_update_tire_spray()


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func set_wetness(level: float) -> void:
	## Directly set the wetness level (0.0 = dry, 1.0 = fully wet).
	_wetness = clampf(level, 0.0, 1.0)
	_emit_wetness_signal()


func get_wetness() -> float:
	return _wetness


func set_raining(raining: bool) -> void:
	## Tell the system whether it is currently raining.
	## Wetness builds up while raining, dries when not.
	_is_raining = raining


func apply_to_road(mesh_instance: MeshInstance3D) -> void:
	## Apply the wet road shader to a road surface MeshInstance3D.
	## Creates a ShaderMaterial and tracks it for wetness updates.
	if mesh_instance == null:
		return

	var shader: Shader = null
	if ResourceLoader.exists(WET_ROAD_SHADER_PATH):
		shader = load(WET_ROAD_SHADER_PATH)
	else:
		print("[Weather] WARNING: wet_road.gdshader not found at %s" % WET_ROAD_SHADER_PATH)
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("wetness", _wetness)
	mat.set_shader_parameter("puddle_amount", 0.0)
	mat.set_shader_parameter("reflection_strength", 0.5)

	# Preserve existing albedo texture if the mesh had one
	if mesh_instance.material_override is StandardMaterial3D:
		var old_mat := mesh_instance.material_override as StandardMaterial3D
		if old_mat.albedo_texture:
			mat.set_shader_parameter("albedo_texture", old_mat.albedo_texture)
		mat.set_shader_parameter("albedo_color", old_mat.albedo_color)

	mesh_instance.material_override = mat
	_wet_road_materials.append(mat)
	print("[Weather] Wet road material applied to: %s" % mesh_instance.name)


func remove_from_road(mesh_instance: MeshInstance3D) -> void:
	## Remove the wet road shader from a road surface.
	if mesh_instance == null:
		return

	# Find and remove tracked material
	for i in range(_wet_road_materials.size() - 1, -1, -1):
		if mesh_instance.material_override == _wet_road_materials[i]:
			_wet_road_materials.remove_at(i)
			break

	mesh_instance.material_override = null


func register_vehicle_for_spray(vehicle_id: int, vehicle_node: Node3D) -> void:
	## Register a vehicle to generate tire spray when driving on wet roads.
	if not enable_tire_spray:
		return
	if vehicle_id in _tire_spray_systems:
		return

	var spray := _create_tire_spray_system()
	vehicle_node.add_child(spray)
	spray.position = Vector3(0.0, 0.1, 1.2)  # Behind and low
	_tire_spray_systems[vehicle_id] = {
		"particles": spray,
		"vehicle": vehicle_node,
	}
	print("[Weather] Tire spray registered for vehicle %d" % vehicle_id)


func unregister_vehicle_spray(vehicle_id: int) -> void:
	## Remove tire spray tracking for a vehicle.
	if vehicle_id in _tire_spray_systems:
		var entry: Dictionary = _tire_spray_systems[vehicle_id]
		var particles: GPUParticles3D = entry["particles"]
		if is_instance_valid(particles):
			particles.queue_free()
		_tire_spray_systems.erase(vehicle_id)


# ═══════════════════════════════════════════════════════════════════════════════
#  WETNESS SIMULATION
# ═══════════════════════════════════════════════════════════════════════════════

func _update_wetness(delta: float) -> void:
	var old_wetness := _wetness

	if _is_raining:
		# Build up wetness gradually
		var buildup_rate := 1.0 / maxf(wet_buildup_time, 0.1)
		_wetness = minf(_wetness + buildup_rate * delta, 1.0)
	else:
		# Dry out gradually
		var dry_rate := 1.0 / maxf(dry_time, 0.1)
		_wetness = maxf(_wetness - dry_rate * delta, 0.0)

	# Emit signal when wetness crosses a threshold
	if _wetness != old_wetness:
		_emit_wetness_signal()


func _emit_wetness_signal() -> void:
	# Bucket wetness to avoid per-frame signal spam (every 5%)
	var bucket := int(_wetness * 20.0)
	if bucket != _previous_wetness_bucket:
		_previous_wetness_bucket = bucket
		EventBus.road_wetness_changed.emit(_wetness)


# ═══════════════════════════════════════════════════════════════════════════════
#  MATERIAL UPDATES
# ═══════════════════════════════════════════════════════════════════════════════

func _update_materials() -> void:
	# Calculate puddle amount based on wetness
	var puddle_level := 0.0
	if _wetness > puddle_threshold:
		var puddle_t := (_wetness - puddle_threshold) / (1.0 - puddle_threshold)
		puddle_level = puddle_t * max_puddle_amount

	# Update all tracked wet road materials
	for i in range(_wet_road_materials.size() - 1, -1, -1):
		var mat: ShaderMaterial = _wet_road_materials[i]
		if mat == null:
			_wet_road_materials.remove_at(i)
			continue

		mat.set_shader_parameter("wetness", _wetness)
		mat.set_shader_parameter("puddle_amount", puddle_level)
		mat.set_shader_parameter("reflection_strength", lerpf(0.2, 0.8, _wetness))


# ═══════════════════════════════════════════════════════════════════════════════
#  TIRE SPRAY
# ═══════════════════════════════════════════════════════════════════════════════

func _create_tire_spray_system() -> GPUParticles3D:
	## Create a tire spray particle system for wet road driving.
	var particles := GPUParticles3D.new()
	particles.name = "TireSpray"
	particles.amount = spray_max_particles
	particles.lifetime = 0.8
	particles.emitting = false
	particles.local_coords = false
	particles.randomness = 0.4

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 1.0).normalized()  # Up and backward
	pmat.spread = 40.0
	pmat.initial_velocity_min = 2.0
	pmat.initial_velocity_max = 6.0
	pmat.gravity = Vector3(0.0, -5.0, 0.0)
	pmat.damping_min = 2.0
	pmat.damping_max = 5.0
	pmat.scale_min = 0.1
	pmat.scale_max = 0.4

	# Emission from a narrow strip behind the wheels
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(0.8, 0.05, 0.2)

	# Spray color: grey-white mist
	var spray_gradient := GradientTexture1D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(0.7, 0.72, 0.78, 0.4))
	sg.add_point(0.3, Color(0.65, 0.68, 0.75, 0.3))
	sg.add_point(0.7, Color(0.6, 0.63, 0.7, 0.15))
	sg.set_color(1, Color(0.55, 0.58, 0.65, 0.0))
	spray_gradient.gradient = sg
	pmat.color_ramp = spray_gradient

	particles.process_material = pmat

	# Spray mesh: small billboarded quad
	var spray_mesh := QuadMesh.new()
	spray_mesh.size = Vector2(0.3, 0.3)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	spray_mesh.material = smat
	particles.draw_pass_1 = spray_mesh

	return particles


func _update_tire_spray() -> void:
	## Activate/deactivate tire spray based on wetness and vehicle speed.
	if not enable_tire_spray or _wetness < 0.1:
		# Disable all spray
		for entry in _tire_spray_systems.values():
			var particles: GPUParticles3D = entry["particles"]
			if is_instance_valid(particles):
				particles.emitting = false
		return

	for vehicle_id in _tire_spray_systems:
		var entry: Dictionary = _tire_spray_systems[vehicle_id]
		var particles: GPUParticles3D = entry["particles"]
		var vehicle: Node3D = entry["vehicle"]

		if not is_instance_valid(particles) or not is_instance_valid(vehicle):
			continue

		# Check if vehicle is moving fast enough
		var speed_kmh := 0.0
		if vehicle is VehicleBody3D:
			speed_kmh = (vehicle as VehicleBody3D).linear_velocity.length() * 3.6

		var should_spray := speed_kmh > spray_min_speed and _wetness > 0.1
		particles.emitting = should_spray

		if should_spray:
			# Scale spray intensity with speed and wetness
			var speed_factor := clampf((speed_kmh - spray_min_speed) / 80.0, 0.0, 1.0)
			var spray_amount := int(lerpf(30.0, float(spray_max_particles), speed_factor * _wetness))
			particles.amount = maxi(spray_amount, 10)

			# Faster vehicles throw spray higher and further
			if particles.process_material is ParticleProcessMaterial:
				var pmat := particles.process_material as ParticleProcessMaterial
				pmat.initial_velocity_min = lerpf(1.5, 5.0, speed_factor)
				pmat.initial_velocity_max = lerpf(3.0, 10.0, speed_factor)
