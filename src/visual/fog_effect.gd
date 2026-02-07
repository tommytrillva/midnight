## Fog effect controller for MIDNIGHT GRIND weather system.
## Adjusts WorldEnvironment fog parameters for atmospheric effects.
## Supports volumetric fog with color shifts near street lights and
## a low-lying ground fog layer for eerie PSX horror vibes.
class_name FogEffect
extends Node

# ── Fog presets ──────────────────────────────────────────────────────────────
## Fog density values for each fog level.
const FOG_NONE_DENSITY := 0.0
const FOG_LIGHT_DENSITY := 0.002
const FOG_HEAVY_DENSITY := 0.01

# ── Export configuration ─────────────────────────────────────────────────────
@export_group("References")
## WorldEnvironment node to control fog parameters on.
@export var world_environment: WorldEnvironment = null

@export_group("Fog Colors")
## Base fog color for open areas (cool night blue).
@export var fog_color_base: Color = Color(0.12, 0.14, 0.22, 1.0)
## Warm fog color near street lights (orange sodium glow).
@export var fog_color_warm: Color = Color(0.35, 0.25, 0.12, 1.0)
## Cool fog color for open/waterfront areas.
@export var fog_color_cool: Color = Color(0.1, 0.12, 0.2, 1.0)

@export_group("Ground Fog")
## Enable low-lying rolling ground fog layer.
@export var enable_ground_fog: bool = true
## Height of ground fog layer.
@export var ground_fog_height: float = 2.0
## Ground fog density multiplier.
@export var ground_fog_density: float = 0.5

@export_group("Volumetric Fog")
## Volumetric fog light energy (how much light scatters through fog).
@export var fog_light_energy: float = 0.3
## How much the sky contributes to fog color.
@export var fog_sky_affect: float = 0.3

# ── State ────────────────────────────────────────────────────────────────────
var _current_density: float = 0.0
var _target_density: float = 0.0
var _transition_speed: float = 0.0
var _transitioning: bool = false

# Ground fog particle system
var _ground_fog_particles: GPUParticles3D = null

# Cached environment reference
var _environment: Environment = null


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_cache_environment()
	if enable_ground_fog:
		_setup_ground_fog()
	print("[Fog] Fog effect initialized")


func _process(delta: float) -> void:
	if _transitioning:
		_update_transition(delta)

	_update_ground_fog(delta)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func set_fog_level(level: float, transition_time: float = 2.0) -> void:
	## Set the fog density level. If transition_time > 0, smoothly interpolates.
	## level: target fog density (0.0 = clear, 0.01 = heavy fog).
	_target_density = maxf(level, 0.0)

	if transition_time <= 0.01:
		# Immediate application
		_current_density = _target_density
		_transitioning = false
		_apply_fog_density(_current_density)
	else:
		_transition_speed = absf(_target_density - _current_density) / transition_time
		_transitioning = true


func get_fog_density() -> float:
	return _current_density


func set_fog_color(color: Color) -> void:
	## Override the fog color directly.
	if _environment:
		_environment.fog_light_color = color


# ═══════════════════════════════════════════════════════════════════════════════
#  ENVIRONMENT SETUP
# ═══════════════════════════════════════════════════════════════════════════════

func _cache_environment() -> void:
	if world_environment and world_environment.environment:
		_environment = world_environment.environment
		print("[Fog] WorldEnvironment cached")
	else:
		# Try to find WorldEnvironment in the scene tree
		var we := _find_world_environment()
		if we and we.environment:
			world_environment = we
			_environment = we.environment
			print("[Fog] WorldEnvironment found in scene tree")
		else:
			print("[Fog] WARNING: No WorldEnvironment found. Fog will have no effect.")


func _find_world_environment() -> WorldEnvironment:
	## Search the scene tree for a WorldEnvironment node.
	var root := get_tree().root if get_tree() else null
	if root == null:
		return null
	return _find_node_of_type(root) as WorldEnvironment


func _find_node_of_type(node: Node) -> Node:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var result := _find_node_of_type(child)
		if result:
			return result
	return null


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSITION
# ═══════════════════════════════════════════════════════════════════════════════

func _update_transition(delta: float) -> void:
	_current_density = move_toward(_current_density, _target_density, _transition_speed * delta)

	_apply_fog_density(_current_density)

	if absf(_current_density - _target_density) < 0.0001:
		_current_density = _target_density
		_transitioning = false


func _apply_fog_density(density: float) -> void:
	if _environment == null:
		_cache_environment()
		if _environment == null:
			return

	if density <= 0.0001:
		# Disable fog entirely when density is negligible
		_environment.fog_enabled = false
		_environment.volumetric_fog_enabled = false
	else:
		_environment.fog_enabled = true
		_environment.fog_density = density

		# Fog color based on density level (denser = more atmospheric)
		var fog_intensity := clampf(density / FOG_HEAVY_DENSITY, 0.0, 1.0)
		_environment.fog_light_color = fog_color_base.lerp(fog_color_cool, fog_intensity * 0.3)
		_environment.fog_light_energy = lerpf(0.1, fog_light_energy, fog_intensity)
		_environment.fog_sky_affect = lerpf(0.1, fog_sky_affect, fog_intensity)

		# Volumetric fog for Godot 4
		if density > FOG_LIGHT_DENSITY * 0.5:
			_environment.volumetric_fog_enabled = true
			_environment.volumetric_fog_density = density * 0.5
			_environment.volumetric_fog_albedo = fog_color_base
			_environment.volumetric_fog_emission = fog_color_warm * 0.1
			_environment.volumetric_fog_emission_energy = lerpf(0.0, 0.5, fog_intensity)
			_environment.volumetric_fog_length = lerpf(64.0, 200.0, fog_intensity)
		else:
			_environment.volumetric_fog_enabled = false


# ═══════════════════════════════════════════════════════════════════════════════
#  GROUND FOG
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_ground_fog() -> void:
	## Creates a low-lying particle fog layer that rolls along the ground.
	_ground_fog_particles = GPUParticles3D.new()
	_ground_fog_particles.name = "GroundFog"
	_ground_fog_particles.amount = 100
	_ground_fog_particles.lifetime = 8.0
	_ground_fog_particles.emitting = false
	_ground_fog_particles.local_coords = false
	_ground_fog_particles.randomness = 0.5
	add_child(_ground_fog_particles)

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.3, 0.0, 0.1)  # Slow drift
	pmat.spread = 180.0
	pmat.initial_velocity_min = 0.2
	pmat.initial_velocity_max = 0.8
	pmat.gravity = Vector3(0.0, -0.1, 0.0)  # Keeps it low
	pmat.damping_min = 0.5
	pmat.damping_max = 1.5
	pmat.scale_min = 3.0
	pmat.scale_max = 8.0

	# Large emission area at ground level
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(60.0, 0.5, 60.0)

	# Color: pale grey-blue, very transparent
	var fog_gradient := GradientTexture1D.new()
	var fg := Gradient.new()
	fg.set_color(0, Color(0.7, 0.72, 0.8, 0.0))
	fg.add_point(0.15, Color(0.7, 0.72, 0.8, 0.08))
	fg.add_point(0.5, Color(0.65, 0.68, 0.78, 0.1))
	fg.add_point(0.85, Color(0.6, 0.65, 0.75, 0.06))
	fg.set_color(1, Color(0.6, 0.65, 0.75, 0.0))
	fog_gradient.gradient = fg
	pmat.color_ramp = fog_gradient

	_ground_fog_particles.process_material = pmat

	# Large billboarded quad for fog wisps
	var fog_mesh := QuadMesh.new()
	fog_mesh.size = Vector2(4.0, 2.0)
	var fmat := StandardMaterial3D.new()
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.vertex_color_use_as_albedo = true
	fmat.no_depth_test = true
	fog_mesh.material = fmat
	_ground_fog_particles.draw_pass_1 = fog_mesh

	# Position at ground level
	_ground_fog_particles.position = Vector3(0.0, ground_fog_height * 0.5, 0.0)


func _update_ground_fog(delta: float) -> void:
	if not enable_ground_fog or _ground_fog_particles == null:
		return

	# Ground fog activates when fog density is noticeable
	var should_emit := _current_density > FOG_LIGHT_DENSITY * 0.3
	_ground_fog_particles.emitting = should_emit

	# Scale ground fog density with overall fog level
	if should_emit and _ground_fog_particles.process_material is ParticleProcessMaterial:
		var pmat := _ground_fog_particles.process_material as ParticleProcessMaterial
		var ground_scale := clampf(_current_density / FOG_HEAVY_DENSITY, 0.0, 1.0)
		pmat.scale_min = lerpf(2.0, 5.0, ground_scale)
		pmat.scale_max = lerpf(4.0, 10.0, ground_scale)

	# Follow camera horizontally
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if camera and _ground_fog_particles:
		_ground_fog_particles.global_position = Vector3(
			camera.global_position.x,
			ground_fog_height * 0.5,
			camera.global_position.z
		)
