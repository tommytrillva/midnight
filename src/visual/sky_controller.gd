## Manages the procedural sky: gradient colors, stars, moon position/phase,
## and cloud wisps. Works with both ProceduralSkyMaterial and the custom
## sky_gradient.gdshader for the full retro night-sky look.
class_name SkyController
extends Node

# --- Moon Orbit ---
# Simple circular orbit: moon rises in east, sets in west.
# Orbit period is one full game night cycle.
const MOON_ORBIT_TILT := 30.0  # Degrees above horizon at peak
const MOON_BASE_ELEVATION := 0.15  # Minimum Y component when visible

# --- Moon Phase ---
# Phase changes every few in-game days. 8 phases, cosmetic only.
const MOON_PHASE_CYCLE_DAYS := 8  # Full cycle in game days

# --- Star Configuration ---
const STAR_FADE_SPEED := 2.0  # How fast stars fade in/out

# --- State ---
var _sky_top_color: Color = Color(0.03, 0.03, 0.12)
var _sky_horizon_color: Color = Color(0.06, 0.04, 0.18)
var _sky_ground_color: Color = Color(0.02, 0.01, 0.06)
var _star_visibility: float = 1.0
var _target_star_visibility: float = 1.0
var _moon_intensity: float = 0.3
var _moon_direction: Vector3 = Vector3(0.3, 0.6, -0.4)
var _moon_phase: float = 0.5  # 0.0 = new moon, 0.5 = full moon, 1.0 = new moon again

# Cached references
var _sky_shader_material: ShaderMaterial = null
var _procedural_sky_material: ProceduralSkyMaterial = null
var _moon_glow_light: OmniLight3D = null


func _ready() -> void:
	# Create the distant moon glow light
	_create_moon_glow_light()
	print("[Sky] SkyController ready")


func _process(delta: float) -> void:
	# Smoothly fade stars
	_star_visibility = move_toward(_star_visibility, _target_star_visibility, delta * STAR_FADE_SPEED)

	# Update moon glow light position
	_update_moon_glow_light()


# --- Public API ---

func update_sky(
	sky_top: Color, sky_horizon: Color, sky_ground: Color,
	star_vis: float, moon_int: float, time_of_day: float
) -> void:
	## Called by DayNightCycle each frame with interpolated values.
	_sky_top_color = sky_top
	_sky_horizon_color = sky_horizon
	_sky_ground_color = sky_ground
	_target_star_visibility = star_vis
	_moon_intensity = moon_int

	# Update moon orbit position based on time
	_update_moon_orbit(time_of_day)

	# Update moon phase based on day count
	_update_moon_phase()

	# Push to shader if available
	_apply_to_shader()


func get_moon_direction() -> Vector3:
	return _moon_direction


func get_moon_phase() -> float:
	return _moon_phase


func get_star_visibility() -> float:
	return _star_visibility


# --- Moon Orbit ---

func _update_moon_orbit(time_of_day: float) -> void:
	## Calculate moon position based on time of day.
	## Moon rises around dusk (18:00), peaks at midnight, sets around dawn (6:00).

	# Normalize time to moon's visible arc: 18:00 to 6:00 maps to 0.0 to 1.0
	var moon_time: float
	if time_of_day >= 18.0:
		moon_time = (time_of_day - 18.0) / 12.0
	elif time_of_day < 6.0:
		moon_time = (time_of_day + 6.0) / 12.0
	else:
		# Daytime: moon is below horizon
		_moon_direction = Vector3(0.3, -0.2, -0.5).normalized()
		return

	# Arc from east to west
	var arc_angle := moon_time * PI  # 0 to PI

	# Moon X: east (-1) to west (+1)
	var moon_x := -cos(arc_angle)
	# Moon Y: elevation (sin curve, peaks at midnight)
	var moon_y := sin(arc_angle) * sin(deg_to_rad(MOON_ORBIT_TILT)) + MOON_BASE_ELEVATION
	# Moon Z: slight forward offset
	var moon_z := -0.4

	_moon_direction = Vector3(moon_x, moon_y, moon_z).normalized()


func _update_moon_phase() -> void:
	## Cosmetic moon phase based on in-game day count.
	if not GameManager.world_time:
		return

	var day := GameManager.world_time.day_count
	# Phase oscillates 0 -> 1 over MOON_PHASE_CYCLE_DAYS
	_moon_phase = fmod(float(day) / float(MOON_PHASE_CYCLE_DAYS), 1.0)


# --- Moon Glow Light ---

func _create_moon_glow_light() -> void:
	## Creates a distant OmniLight3D to simulate moonlight glow.
	_moon_glow_light = OmniLight3D.new()
	_moon_glow_light.name = "MoonGlowLight"
	_moon_glow_light.light_color = Color(0.7, 0.75, 0.95)
	_moon_glow_light.light_energy = 0.0
	_moon_glow_light.omni_range = 500.0
	_moon_glow_light.omni_attenuation = 0.5
	_moon_glow_light.shadow_enabled = false
	_moon_glow_light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(_moon_glow_light)
	print("[Sky] Moon glow light created")


func _update_moon_glow_light() -> void:
	## Position and intensity of the moon glow light.
	if not _moon_glow_light:
		return

	# Place the light very far away in the moon direction
	var moon_pos := _moon_direction * 300.0
	_moon_glow_light.global_position = moon_pos

	# Intensity follows moon visibility
	_moon_glow_light.light_energy = _moon_intensity * 0.5

	# Color shifts slightly with phase (fuller = brighter/whiter)
	var phase_brightness := 0.5 + 0.5 * sin(_moon_phase * PI)
	_moon_glow_light.light_color = Color(
		0.65 + phase_brightness * 0.15,
		0.7 + phase_brightness * 0.15,
		0.9 + phase_brightness * 0.1
	)


# --- Shader Application ---

func _apply_to_shader() -> void:
	## Push current values to whichever sky material is in use.
	# Try to find the sky material if we haven't cached it
	if not _sky_shader_material and not _procedural_sky_material:
		_find_sky_material()

	if _sky_shader_material:
		_sky_shader_material.set_shader_parameter("sky_top_color",
			Vector3(_sky_top_color.r, _sky_top_color.g, _sky_top_color.b))
		_sky_shader_material.set_shader_parameter("sky_horizon_color",
			Vector3(_sky_horizon_color.r, _sky_horizon_color.g, _sky_horizon_color.b))
		_sky_shader_material.set_shader_parameter("sky_ground_color",
			Vector3(_sky_ground_color.r, _sky_ground_color.g, _sky_ground_color.b))
		_sky_shader_material.set_shader_parameter("star_visibility", _star_visibility)
		_sky_shader_material.set_shader_parameter("moon_intensity", _moon_intensity)
		_sky_shader_material.set_shader_parameter("moon_direction", _moon_direction)
		_sky_shader_material.set_shader_parameter("moon_phase", _moon_phase)

		# Horizon glow stronger at night (city light pollution)
		var glow_strength := 0.4 * clampf(_moon_intensity + 0.1, 0.0, 0.6)
		_sky_shader_material.set_shader_parameter("horizon_glow_strength", glow_strength)

	elif _procedural_sky_material:
		# ProceduralSkyMaterial has limited parameters but we use what's available
		_procedural_sky_material.sky_top_color = _sky_top_color
		_procedural_sky_material.sky_horizon_color = _sky_horizon_color
		_procedural_sky_material.ground_bottom_color = _sky_ground_color
		_procedural_sky_material.ground_horizon_color = _sky_horizon_color.lerp(_sky_ground_color, 0.5)


func _find_sky_material() -> void:
	## Search for the sky material in the scene's WorldEnvironment.
	var we_nodes := get_tree().get_nodes_in_group("world_environment")
	var world_env: WorldEnvironment = null

	if we_nodes.size() > 0:
		world_env = we_nodes[0] as WorldEnvironment
	else:
		# Fallback: search scene tree
		world_env = _find_world_environment(get_tree().current_scene)

	if not world_env or not world_env.environment:
		return
	if not world_env.environment.sky:
		return

	var mat := world_env.environment.sky.sky_material
	if mat is ShaderMaterial:
		_sky_shader_material = mat
		print("[Sky] Found ShaderMaterial sky")
	elif mat is ProceduralSkyMaterial:
		_procedural_sky_material = mat
		print("[Sky] Found ProceduralSkyMaterial sky")


func _find_world_environment(root: Node) -> WorldEnvironment:
	if root == null:
		return null
	if root is WorldEnvironment:
		return root as WorldEnvironment
	for child in root.get_children():
		var found := _find_world_environment(child)
		if found:
			return found
	return null
