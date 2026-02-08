## Visual effects manager for MIDNIGHT GRIND.
## Handles tire smoke, nitro flames, collision sparks, rain system,
## neon light flickering, speed lines, and drift trail marks.
## All particle systems are created via code using GPUParticles3D.
class_name VFXManager
extends Node3D

# --- Configuration ---
@export var enable_tire_smoke: bool = true
@export var enable_rain: bool = false
@export var rain_intensity: float = 1.0  ## 0.0-1.0, controls particle count/speed

# --- References ---
var _tire_smoke_left: GPUParticles3D = null
var _tire_smoke_right: GPUParticles3D = null
var _nitro_flame: GPUParticles3D = null
var _nitro_flame_secondary: GPUParticles3D = null
var _spark_emitter: GPUParticles3D = null
var _rain_system: GPUParticles3D = null
var _speed_lines: GPUParticles3D = null
var _drift_trail_left: MeshInstance3D = null
var _drift_trail_right: MeshInstance3D = null

# --- Neon flicker tracking ---
var _flickering_lights: Array[Dictionary] = []  # [{light: OmniLight3D, timer: float, ...}]

# --- Drift trail state ---
var _drift_trail_points_left: PackedVector3Array = PackedVector3Array()
var _drift_trail_points_right: PackedVector3Array = PackedVector3Array()
const MAX_TRAIL_POINTS := 200
const TRAIL_WIDTH := 0.25

# --- Internal ---
var _speed_line_active: bool = false


func _ready() -> void:
	_setup_tire_smoke()
	_setup_nitro_flame()
	_setup_spark_emitter()
	_setup_speed_lines()
	if enable_rain:
		_setup_rain_system()
	print("[VFXManager] Initialized all VFX systems")


func _process(delta: float) -> void:
	_update_neon_flickers(delta)


# ===========================================================================
# PUBLIC API
# ===========================================================================

## Activate tire smoke at the rear wheel positions. Call each frame while drifting.
func set_tire_smoke_active(active: bool, left_pos: Vector3 = Vector3.ZERO, right_pos: Vector3 = Vector3.ZERO) -> void:
	if _tire_smoke_left:
		_tire_smoke_left.emitting = active and enable_tire_smoke
		if active:
			_tire_smoke_left.global_position = left_pos
	if _tire_smoke_right:
		_tire_smoke_right.emitting = active and enable_tire_smoke
		if active:
			_tire_smoke_right.global_position = right_pos


## Fire nitro flame VFX at the given exhaust position. Call when nitro activates.
func set_nitro_active(active: bool, exhaust_pos: Vector3 = Vector3.ZERO, exhaust_dir: Vector3 = Vector3.BACK) -> void:
	if _nitro_flame:
		_nitro_flame.emitting = active
		if active:
			_nitro_flame.global_position = exhaust_pos
			# Orient to point backward
			if exhaust_dir.length() > 0.01:
				_nitro_flame.global_transform = _nitro_flame.global_transform.looking_at(
					exhaust_pos + exhaust_dir, Vector3.UP
				)
	if _nitro_flame_secondary:
		_nitro_flame_secondary.emitting = active
		if active:
			_nitro_flame_secondary.global_position = exhaust_pos


## Emit a burst of sparks at the collision/scrape point.
func emit_sparks(world_position: Vector3, impact_normal: Vector3 = Vector3.UP) -> void:
	if _spark_emitter:
		_spark_emitter.global_position = world_position
		_spark_emitter.emitting = false  # Reset
		_spark_emitter.restart()
		_spark_emitter.emitting = true
		print("[VFXManager] Sparks at %s" % str(world_position))


## Enable/disable rain particle system.
func set_rain_active(active: bool, intensity: float = 1.0) -> void:
	enable_rain = active
	rain_intensity = clampf(intensity, 0.0, 1.0)
	if active and _rain_system == null:
		_setup_rain_system()
	if _rain_system:
		_rain_system.emitting = active
		_rain_system.amount = int(lerpf(500, 3000, rain_intensity))


## Enable speed lines effect (radial blur particles at high speed).
func set_speed_lines_active(active: bool, speed_factor: float = 1.0) -> void:
	_speed_line_active = active
	if _speed_lines:
		_speed_lines.emitting = active
		# Adjust lifetime based on speed -- faster = shorter lines
		if _speed_lines.process_material is ParticleProcessMaterial:
			var pmat: ParticleProcessMaterial = _speed_lines.process_material as ParticleProcessMaterial
			pmat.initial_velocity_min = lerpf(5.0, 30.0, clampf(speed_factor, 0.0, 1.0))
			pmat.initial_velocity_max = lerpf(8.0, 40.0, clampf(speed_factor, 0.0, 1.0))


## Register a light for neon flicker effect.
func register_neon_flicker(light: Light3D, flicker_speed: float = 3.0, flicker_amount: float = 0.3) -> void:
	_flickering_lights.append({
		"light": light,
		"base_energy": light.light_energy,
		"speed": flicker_speed,
		"amount": flicker_amount,
		"timer": randf() * TAU,  # Random phase offset
		"on": true,
		"off_timer": 0.0,
		"off_chance": 0.002,  # Small chance per frame to briefly go dark
	})


## Unregister a light from neon flicker.
func unregister_neon_flicker(light: Light3D) -> void:
	for i in range(_flickering_lights.size() - 1, -1, -1):
		if _flickering_lights[i]["light"] == light:
			_flickering_lights.remove_at(i)
			break


## Add a drift trail point at the given world position.
func add_drift_trail_point(left_pos: Vector3, right_pos: Vector3) -> void:
	_drift_trail_points_left.append(left_pos)
	_drift_trail_points_right.append(right_pos)
	if _drift_trail_points_left.size() > MAX_TRAIL_POINTS:
		_drift_trail_points_left = _drift_trail_points_left.slice(1)
	if _drift_trail_points_right.size() > MAX_TRAIL_POINTS:
		_drift_trail_points_right = _drift_trail_points_right.slice(1)
	_rebuild_drift_trail_mesh()


## Clear all drift trail marks.
func clear_drift_trails() -> void:
	_drift_trail_points_left.clear()
	_drift_trail_points_right.clear()
	if _drift_trail_left and _drift_trail_left.mesh:
		_drift_trail_left.mesh = null
	if _drift_trail_right and _drift_trail_right.mesh:
		_drift_trail_right.mesh = null


# ===========================================================================
# TIRE SMOKE SETUP
# ===========================================================================

func _setup_tire_smoke() -> void:
	_tire_smoke_left = _create_particle_system("TireSmokeL", 64)
	add_child(_tire_smoke_left)

	_tire_smoke_right = _create_particle_system("TireSmokeR", 64)
	add_child(_tire_smoke_right)

	# Configure both with same material
	for particles in [_tire_smoke_left, _tire_smoke_right]:
		var pmat := ParticleProcessMaterial.new()
		pmat.direction = Vector3(0, 1, 0)
		pmat.spread = 30.0
		pmat.initial_velocity_min = 0.5
		pmat.initial_velocity_max = 2.0
		pmat.gravity = Vector3(0, 0.3, 0)
		pmat.damping_min = 2.0
		pmat.damping_max = 4.0
		pmat.scale_min = 0.3
		pmat.scale_max = 1.2
		pmat.color = Color(0.7, 0.7, 0.7, 0.4)

		# Color ramp: white-grey fading to transparent
		var color_ramp := GradientTexture1D.new()
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.8, 0.8, 0.8, 0.5))
		gradient.add_point(0.5, Color(0.6, 0.6, 0.6, 0.25))
		gradient.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
		color_ramp.gradient = gradient
		pmat.color_ramp = color_ramp

		particles.process_material = pmat
		particles.lifetime = 1.5
		particles.emitting = false
		particles.local_coords = false

		# Draw pass: simple quad mesh for billboarded smoke
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.5)
		var smoke_mat := StandardMaterial3D.new()
		smoke_mat.albedo_color = Color(1, 1, 1, 1)
		smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke_mat.vertex_color_use_as_albedo = true
		quad.material = smoke_mat
		particles.draw_pass_1 = quad


# ===========================================================================
# NITRO FLAME SETUP
# ===========================================================================

func _setup_nitro_flame() -> void:
	# Primary flame (blue core)
	_nitro_flame = _create_particle_system("NitroFlameCore", 48)
	add_child(_nitro_flame)

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 0, -1)  # Backward
	pmat.spread = 8.0
	pmat.initial_velocity_min = 8.0
	pmat.initial_velocity_max = 15.0
	pmat.gravity = Vector3(0, 1.0, 0)
	pmat.damping_min = 1.0
	pmat.damping_max = 3.0
	pmat.scale_min = 0.1
	pmat.scale_max = 0.4

	var flame_gradient := GradientTexture1D.new()
	var fg := Gradient.new()
	fg.set_color(0, Color(0.3, 0.5, 1.0, 1.0))    # Bright blue core
	fg.add_point(0.3, Color(0.2, 0.4, 1.0, 0.9))
	fg.add_point(0.6, Color(1.0, 0.5, 0.1, 0.6))   # Orange edge
	fg.set_color(1, Color(1.0, 0.3, 0.0, 0.0))      # Fade out
	flame_gradient.gradient = fg
	pmat.color_ramp = flame_gradient

	_nitro_flame.process_material = pmat
	_nitro_flame.lifetime = 0.3
	_nitro_flame.emitting = false
	_nitro_flame.local_coords = false

	var flame_quad := QuadMesh.new()
	flame_quad.size = Vector2(0.3, 0.3)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(0.3, 0.5, 1.0)
	flame_mat.emission_energy_multiplier = 3.0
	flame_quad.material = flame_mat
	_nitro_flame.draw_pass_1 = flame_quad

	# Secondary flame (orange outer glow)
	_nitro_flame_secondary = _create_particle_system("NitroFlameOuter", 32)
	add_child(_nitro_flame_secondary)

	var pmat2 := ParticleProcessMaterial.new()
	pmat2.direction = Vector3(0, 0, -1)
	pmat2.spread = 15.0
	pmat2.initial_velocity_min = 5.0
	pmat2.initial_velocity_max = 10.0
	pmat2.gravity = Vector3(0, 2.0, 0)
	pmat2.scale_min = 0.2
	pmat2.scale_max = 0.6

	var outer_gradient := GradientTexture1D.new()
	var og := Gradient.new()
	og.set_color(0, Color(1.0, 0.6, 0.1, 0.8))
	og.add_point(0.4, Color(1.0, 0.3, 0.0, 0.5))
	og.set_color(1, Color(0.5, 0.1, 0.0, 0.0))
	outer_gradient.gradient = og
	pmat2.color_ramp = outer_gradient

	_nitro_flame_secondary.process_material = pmat2
	_nitro_flame_secondary.lifetime = 0.4
	_nitro_flame_secondary.emitting = false
	_nitro_flame_secondary.local_coords = false

	var outer_quad := QuadMesh.new()
	outer_quad.size = Vector2(0.4, 0.4)
	var outer_mat := StandardMaterial3D.new()
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.vertex_color_use_as_albedo = true
	outer_quad.material = outer_mat
	_nitro_flame_secondary.draw_pass_1 = outer_quad


# ===========================================================================
# SPARK EMITTER SETUP
# ===========================================================================

func _setup_spark_emitter() -> void:
	_spark_emitter = _create_particle_system("Sparks", 32)
	_spark_emitter.one_shot = true
	_spark_emitter.explosiveness = 0.95
	add_child(_spark_emitter)

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 60.0
	pmat.initial_velocity_min = 3.0
	pmat.initial_velocity_max = 8.0
	pmat.gravity = Vector3(0, -9.8, 0)
	pmat.damping_min = 0.5
	pmat.damping_max = 2.0
	pmat.scale_min = 0.02
	pmat.scale_max = 0.08

	var spark_gradient := GradientTexture1D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.9, 0.3, 1.0))     # Bright yellow-white
	sg.add_point(0.3, Color(1.0, 0.6, 0.1, 0.9))    # Orange
	sg.set_color(1, Color(1.0, 0.2, 0.0, 0.0))      # Fade to dark red
	spark_gradient.gradient = sg
	pmat.color_ramp = spark_gradient

	_spark_emitter.process_material = pmat
	_spark_emitter.lifetime = 0.6
	_spark_emitter.emitting = false
	_spark_emitter.local_coords = false

	# Tiny stretched quad for spark streaks
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.02, 0.15)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.8, 0.3)
	spark_mat.emission_energy_multiplier = 5.0
	spark_mesh.material = spark_mat
	_spark_emitter.draw_pass_1 = spark_mesh


# ===========================================================================
# RAIN SYSTEM SETUP
# ===========================================================================

func _setup_rain_system() -> void:
	_rain_system = _create_particle_system("Rain", int(lerpf(500, 3000, rain_intensity)))
	add_child(_rain_system)

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(-0.1, -1, 0.05)  # Slight wind angle
	pmat.spread = 5.0
	pmat.initial_velocity_min = 15.0
	pmat.initial_velocity_max = 25.0
	pmat.gravity = Vector3(0, -15.0, 0)

	# Emission box high above player
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(40.0, 0.5, 40.0)

	pmat.scale_min = 0.5
	pmat.scale_max = 1.0
	pmat.color = Color(0.6, 0.65, 0.8, 0.4)

	_rain_system.process_material = pmat
	_rain_system.lifetime = 1.2
	_rain_system.emitting = enable_rain
	_rain_system.local_coords = false

	# Position rain emitter above the scene origin (will follow camera)
	_rain_system.position = Vector3(0, 30, 0)

	# Rain drop mesh: thin stretched quad
	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.02, 0.4)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.albedo_color = Color(0.7, 0.75, 0.9, 0.35)
	rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_mesh.material = rain_mat
	_rain_system.draw_pass_1 = rain_mesh

	print("[VFXManager] Rain system initialized (intensity=%.1f)" % rain_intensity)


# ===========================================================================
# SPEED LINES SETUP
# ===========================================================================

func _setup_speed_lines() -> void:
	_speed_lines = _create_particle_system("SpeedLines", 80)
	add_child(_speed_lines)

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 0, 1)  # Toward camera (backward)
	pmat.spread = 45.0
	pmat.initial_velocity_min = 10.0
	pmat.initial_velocity_max = 25.0
	pmat.gravity = Vector3.ZERO
	pmat.damping_min = 0.0
	pmat.damping_max = 0.5

	# Emit from a ring/box around the camera
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(8.0, 5.0, 1.0)

	pmat.scale_min = 0.3
	pmat.scale_max = 0.8

	var speed_gradient := GradientTexture1D.new()
	var spg := Gradient.new()
	spg.set_color(0, Color(0.9, 0.9, 1.0, 0.0))
	spg.add_point(0.1, Color(0.9, 0.9, 1.0, 0.3))
	spg.add_point(0.8, Color(0.8, 0.85, 1.0, 0.15))
	spg.set_color(1, Color(0.8, 0.85, 1.0, 0.0))
	speed_gradient.gradient = spg
	pmat.color_ramp = speed_gradient

	_speed_lines.process_material = pmat
	_speed_lines.lifetime = 0.5
	_speed_lines.emitting = false
	_speed_lines.local_coords = false

	# Line mesh: very thin elongated quad
	var line_mesh := QuadMesh.new()
	line_mesh.size = Vector2(0.01, 1.5)
	var line_mat := StandardMaterial3D.new()
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mesh.material = line_mat
	_speed_lines.draw_pass_1 = line_mesh


# ===========================================================================
# NEON FLICKER
# ===========================================================================

func _update_neon_flickers(delta: float) -> void:
	for i in range(_flickering_lights.size() - 1, -1, -1):
		var entry: Dictionary = _flickering_lights[i]
		var light: Light3D = entry["light"] as Light3D
		if not is_instance_valid(light):
			_flickering_lights.remove_at(i)
			continue

		entry["timer"] += delta * entry["speed"]
		var base: float = entry["base_energy"]
		var amount: float = entry["amount"]

		# Sine wave flicker
		var flicker_val: float = sin(entry["timer"]) * sin(entry["timer"] * 2.3 + 1.0)
		light.light_energy = base + flicker_val * amount * base

		# Random brief blackout
		if entry["on"]:
			if randf() < entry["off_chance"]:
				entry["on"] = false
				entry["off_timer"] = randf_range(0.03, 0.15)
				light.light_energy = base * 0.05
		else:
			entry["off_timer"] -= delta
			if entry["off_timer"] <= 0:
				entry["on"] = true

		_flickering_lights[i] = entry


# ===========================================================================
# DRIFT TRAIL MARKS
# ===========================================================================

func _rebuild_drift_trail_mesh() -> void:
	_rebuild_single_trail(_drift_trail_left, _drift_trail_points_left, "DriftTrailL")
	_rebuild_single_trail(_drift_trail_right, _drift_trail_points_right, "DriftTrailR")


func _rebuild_single_trail(trail_mesh: MeshInstance3D, points: PackedVector3Array, trail_name: String) -> void:
	if points.size() < 2:
		return

	if trail_mesh == null:
		trail_mesh = MeshInstance3D.new()
		trail_mesh.name = trail_name
		# Dark rubber mark material
		var mark_mat := StandardMaterial3D.new()
		mark_mat.albedo_color = Color(0.02, 0.02, 0.02, 0.7)
		mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		trail_mesh.material_override = mark_mat
		add_child(trail_mesh)
		if trail_name == "DriftTrailL":
			_drift_trail_left = trail_mesh
		else:
			_drift_trail_right = trail_mesh

	# Build an ImmediateMesh (strip of quads along the trail)
	var imesh := ImmediateMesh.new()
	imesh.clear_surfaces()
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(points.size()):
		var pos: Vector3 = points[i]
		var tangent: Vector3
		if i < points.size() - 1:
			tangent = (points[i + 1] - pos).normalized()
		else:
			tangent = (pos - points[i - 1]).normalized()

		var right: Vector3 = tangent.cross(Vector3.UP).normalized() * TRAIL_WIDTH * 0.5
		# Alpha fades from old (transparent) to new (opaque)
		var alpha: float = float(i) / float(points.size())

		imesh.surface_set_color(Color(0.02, 0.02, 0.02, alpha * 0.7))
		imesh.surface_add_vertex(pos + right + Vector3(0, 0.01, 0))

		imesh.surface_set_color(Color(0.02, 0.02, 0.02, alpha * 0.7))
		imesh.surface_add_vertex(pos - right + Vector3(0, 0.01, 0))

	imesh.surface_end()
	trail_mesh.mesh = imesh


# ===========================================================================
# UTILITY
# ===========================================================================

func _create_particle_system(sys_name: String, amount: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = sys_name
	particles.amount = amount
	particles.emitting = false
	return particles


## Move the rain emitter to follow a target (usually the player camera).
func update_rain_follow(target_position: Vector3) -> void:
	if _rain_system:
		_rain_system.global_position = Vector3(target_position.x, target_position.y + 25.0, target_position.z)


## Move the speed lines to follow the camera.
func update_speed_lines_follow(camera_position: Vector3, camera_forward: Vector3) -> void:
	if _speed_lines:
		_speed_lines.global_position = camera_position + camera_forward * 5.0
