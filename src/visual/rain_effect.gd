## Rain particle system for MIDNIGHT GRIND weather.
## Spawns rain streaks in a box around the camera with configurable intensity
## and wind angle. Includes ground splash particles and a windshield rain
## overlay for close/first-person cameras.
class_name RainEffect
extends GPUParticles3D

# ── Configuration ────────────────────────────────────────────────────────────
## Maximum particle count at full intensity (storm).
const MAX_PARTICLES := 5000
## Particle count for light rain (intensity ~0.3).
const LIGHT_RAIN_PARTICLES := 500
## Particle count for heavy rain (intensity ~0.7).
const HEAVY_RAIN_PARTICLES := 3000

## Emission box size around the camera.
@export var emission_extents: Vector3 = Vector3(50.0, 1.0, 50.0)
## Height above camera where rain spawns.
@export var spawn_height: float = 25.0

# ── Splash system ────────────────────────────────────────────────────────────
var _splash_particles: GPUParticles3D = null

# ── Windshield overlay ───────────────────────────────────────────────────────
var _windshield_overlay: ColorRect = null
var _windshield_material: ShaderMaterial = null

# ── State ────────────────────────────────────────────────────────────────────
var _intensity: float = 0.0
var _wind_direction: Vector3 = Vector3.ZERO
var _wind_strength: float = 0.0
var _rain_process_mat: ParticleProcessMaterial = null


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	name = "RainEffect"
	_setup_rain_particles()
	_setup_splash_particles()
	_setup_windshield_overlay()
	emitting = false
	print("[Rain] Rain effect initialized")


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func set_intensity(intensity: float) -> void:
	## Set rain intensity from 0.0 (none) to 1.0 (full storm).
	_intensity = clampf(intensity, 0.0, 1.0)

	if _intensity <= 0.01:
		emitting = false
		if _splash_particles:
			_splash_particles.emitting = false
		_set_windshield_intensity(0.0)
		return

	emitting = true

	# Scale particle count with intensity
	var particle_count := int(lerpf(float(LIGHT_RAIN_PARTICLES), float(MAX_PARTICLES), _intensity))
	amount = particle_count

	# Adjust rain speed and spread based on intensity
	if _rain_process_mat:
		# Light rain: slow thin streaks. Heavy/storm: fast thick spread
		_rain_process_mat.initial_velocity_min = lerpf(8.0, 20.0, _intensity)
		_rain_process_mat.initial_velocity_max = lerpf(12.0, 30.0, _intensity)
		_rain_process_mat.spread = lerpf(3.0, 12.0, _intensity)
		_rain_process_mat.gravity = Vector3(
			_wind_direction.x * _wind_strength * 15.0,
			lerpf(-12.0, -20.0, _intensity),
			_wind_direction.z * _wind_strength * 15.0
		)
		# Wider emission box for heavier rain
		_rain_process_mat.emission_box_extents = Vector3(
			lerpf(30.0, 60.0, _intensity),
			0.5,
			lerpf(30.0, 60.0, _intensity)
		)

	# Update rain drop visual size
	if draw_pass_1 is QuadMesh:
		var quad := draw_pass_1 as QuadMesh
		# Thicker streaks for heavier rain
		quad.size = Vector2(
			lerpf(0.015, 0.04, _intensity),
			lerpf(0.3, 0.6, _intensity)
		)

	# Splash particles scale with intensity
	if _splash_particles:
		_splash_particles.emitting = true
		_splash_particles.amount = int(lerpf(100.0, 1500.0, _intensity))

	# Windshield rain overlay
	_set_windshield_intensity(_intensity)


func set_wind(direction: Vector3, strength: float) -> void:
	## Set wind direction and strength. Affects rain angle.
	_wind_direction = direction.normalized() if direction.length() > 0.01 else Vector3.ZERO
	_wind_strength = clampf(strength, 0.0, 1.0)

	if _rain_process_mat:
		# Angle rain by adjusting the gravity/direction vector
		var wind_force := _wind_direction * _wind_strength * 15.0
		_rain_process_mat.direction = Vector3(
			wind_force.x * 0.3,
			-1.0,
			wind_force.z * 0.3
		).normalized()
		_rain_process_mat.gravity = Vector3(
			wind_force.x,
			lerpf(-12.0, -20.0, _intensity),
			wind_force.z
		)

	# Update windshield overlay wind angle
	if _windshield_material:
		var wind_angle := atan2(_wind_direction.x, _wind_direction.z)
		_windshield_material.set_shader_parameter("wind_angle", wind_angle)


# ═══════════════════════════════════════════════════════════════════════════════
#  RAIN PARTICLE SETUP
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_rain_particles() -> void:
	amount = LIGHT_RAIN_PARTICLES
	lifetime = 1.5
	local_coords = false
	explosiveness = 0.0
	randomness = 0.1

	# Process material for rain behavior
	_rain_process_mat = ParticleProcessMaterial.new()
	_rain_process_mat.direction = Vector3(0.0, -1.0, 0.0)
	_rain_process_mat.spread = 5.0
	_rain_process_mat.initial_velocity_min = 10.0
	_rain_process_mat.initial_velocity_max = 18.0
	_rain_process_mat.gravity = Vector3(0.0, -15.0, 0.0)
	_rain_process_mat.damping_min = 0.0
	_rain_process_mat.damping_max = 0.5

	# Emission: large box above the camera
	_rain_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process_mat.emission_box_extents = emission_extents

	# Slight scale variation for visual variety
	_rain_process_mat.scale_min = 0.6
	_rain_process_mat.scale_max = 1.2

	# Rain color: pale blue-white with transparency
	var rain_gradient := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 0.75, 0.9, 0.5))
	grad.add_point(0.5, Color(0.6, 0.65, 0.85, 0.4))
	grad.set_color(1, Color(0.5, 0.55, 0.75, 0.0))
	rain_gradient.gradient = grad
	_rain_process_mat.color_ramp = rain_gradient

	process_material = _rain_process_mat

	# Draw pass: elongated billboard quad for rain streaks
	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.02, 0.4)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.albedo_color = Color(0.75, 0.8, 0.95, 0.45)
	rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mat.vertex_color_use_as_albedo = true
	rain_mesh.material = rain_mat
	draw_pass_1 = rain_mesh


# ═══════════════════════════════════════════════════════════════════════════════
#  SPLASH PARTICLE SETUP
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_splash_particles() -> void:
	_splash_particles = GPUParticles3D.new()
	_splash_particles.name = "RainSplash"
	_splash_particles.amount = 200
	_splash_particles.lifetime = 0.4
	_splash_particles.emitting = false
	_splash_particles.local_coords = false
	_splash_particles.explosiveness = 0.0
	_splash_particles.randomness = 0.5
	add_child(_splash_particles)

	var splash_mat := ParticleProcessMaterial.new()
	splash_mat.direction = Vector3(0.0, 1.0, 0.0)
	splash_mat.spread = 80.0
	splash_mat.initial_velocity_min = 0.5
	splash_mat.initial_velocity_max = 2.0
	splash_mat.gravity = Vector3(0.0, -8.0, 0.0)
	splash_mat.damping_min = 3.0
	splash_mat.damping_max = 6.0
	splash_mat.scale_min = 0.05
	splash_mat.scale_max = 0.15

	# Spawn splashes at ground level in a wide area
	splash_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	splash_mat.emission_box_extents = Vector3(40.0, 0.1, 40.0)

	# White-blue splash fading to transparent
	var splash_gradient := GradientTexture1D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(0.8, 0.85, 1.0, 0.6))
	sg.add_point(0.3, Color(0.7, 0.75, 0.9, 0.4))
	sg.set_color(1, Color(0.6, 0.65, 0.8, 0.0))
	splash_gradient.gradient = sg
	splash_mat.color_ramp = splash_gradient

	_splash_particles.process_material = splash_mat

	# Splash drop mesh: small billboard circle-ish quad
	var splash_mesh := QuadMesh.new()
	splash_mesh.size = Vector2(0.1, 0.1)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	splash_mesh.material = smat
	_splash_particles.draw_pass_1 = splash_mesh

	# Position splash emitter at ground level
	_splash_particles.position = Vector3(0.0, -25.0, 0.0)  # Relative to rain (which is 25m up)


# ═══════════════════════════════════════════════════════════════════════════════
#  WINDSHIELD RAIN OVERLAY
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_windshield_overlay() -> void:
	## Creates a full-screen overlay using the rain_streak shader for
	## windshield/camera rain effect.
	_windshield_overlay = ColorRect.new()
	_windshield_overlay.name = "WindshieldRainOverlay"
	_windshield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Load the rain streak shader if available
	var shader_path := "res://assets/shaders/rain_streak.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader: Shader = load(shader_path)
		_windshield_material = ShaderMaterial.new()
		_windshield_material.shader = shader
		_windshield_material.set_shader_parameter("rain_intensity", 0.0)
		_windshield_material.set_shader_parameter("wind_angle", 0.0)
		_windshield_overlay.material = _windshield_material
	else:
		print("[Rain] rain_streak.gdshader not found, windshield overlay disabled")

	_windshield_overlay.visible = false

	# Defer adding to the CanvasLayer so it overlays the 3D scene
	call_deferred("_add_windshield_to_canvas")


func _add_windshield_to_canvas() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "RainOverlayCanvas"
	canvas_layer.layer = 90  # High layer to render on top
	add_child(canvas_layer)

	_windshield_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(_windshield_overlay)


func _set_windshield_intensity(intensity: float) -> void:
	if _windshield_overlay == null:
		return

	if intensity <= 0.01:
		_windshield_overlay.visible = false
		return

	_windshield_overlay.visible = true
	if _windshield_material:
		_windshield_material.set_shader_parameter("rain_intensity", intensity)
