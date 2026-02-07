## Controls all visual lighting based on the WorldTime system.
## Orchestrates sun/moon, sky, neon signs, street lights, and atmosphere
## to create smooth transitions between time periods.
class_name DayNightCycle
extends Node

# --- Period Constants (normalized 0-24 hour ranges) ---
const PERIOD_LATE_NIGHT := "late_night"  # 0:00 - 4:00
const PERIOD_DAWN := "dawn"              # 4:00 - 6:00
const PERIOD_DAY := "day"                # 6:00 - 18:00
const PERIOD_DUSK := "dusk"              # 18:00 - 20:00
const PERIOD_NIGHT := "night"            # 20:00 - 24:00

# Period time boundaries (normalized hours 0-24)
const PERIOD_RANGES := {
	PERIOD_LATE_NIGHT: { "start": 0.0, "end": 4.0 },
	PERIOD_DAWN:       { "start": 4.0, "end": 6.0 },
	PERIOD_DAY:        { "start": 6.0, "end": 18.0 },
	PERIOD_DUSK:       { "start": 18.0, "end": 20.0 },
	PERIOD_NIGHT:      { "start": 20.0, "end": 24.0 },
}

# Order of periods for transition blending
const PERIOD_ORDER: Array[String] = [
	PERIOD_LATE_NIGHT, PERIOD_DAWN, PERIOD_DAY, PERIOD_DUSK, PERIOD_NIGHT
]

# --- Preset Data ---
var presets: Dictionary = {}
var district_modifiers: Dictionary = {}
var transition_durations: Dictionary = {}
var current_district: String = "downtown"

# --- Cached Scene References ---
var directional_light: DirectionalLight3D = null
var world_environment: WorldEnvironment = null

# --- Sub-controllers ---
var sky_controller: SkyController = null
var neon_controller: NeonController = null
var street_light_controller: StreetLightController = null

# --- State ---
var _current_period: String = PERIOD_NIGHT
var _previous_period: String = ""
var _current_ambient_brightness: float = 0.1
var _headlights_needed: bool = true
var _transition_tween: Tween = null
var _initialized: bool = false

# Interpolated values (current visual state)
var _sun_color: Color = Color.BLACK
var _sun_intensity: float = 0.0
var _sun_angle: float = 0.0
var _ambient_color: Color = Color.BLACK
var _ambient_energy: float = 0.0
var _fog_color: Color = Color.BLACK
var _fog_density: float = 0.0
var _neon_intensity: float = 1.0
var _street_lights_on: bool = true
var _star_visibility: float = 1.0
var _moon_intensity: float = 0.3
var _shadow_opacity: float = 0.7
var _tonemap_exposure: float = 1.0
var _tonemap_white: float = 1.3
var _sky_top: Color = Color.BLACK
var _sky_horizon: Color = Color.BLACK
var _sky_ground: Color = Color.BLACK


func _ready() -> void:
	_load_presets()
	_create_sub_controllers()
	_find_scene_nodes()

	# Listen for period changes and district transitions
	EventBus.time_period_changed.connect(_on_time_period_changed)
	EventBus.district_entered.connect(_on_district_entered)

	# Apply initial lighting state based on current time
	if GameManager.world_time:
		var normalized_hour := _normalize_hour(GameManager.world_time.game_hour)
		_current_period = _get_period_for_hour(normalized_hour)
		_apply_preset_immediate(_current_period)
		update_lighting(normalized_hour)

	_initialized = true
	print("[DayNight] Day/night cycle initialized. Period: %s" % _current_period)


func _process(delta: float) -> void:
	if not _initialized:
		return
	if not GameManager.world_time:
		return
	if GameManager.current_state == GameManager.GameState.MENU:
		return

	var normalized_hour := _normalize_hour(GameManager.world_time.game_hour)
	update_lighting(normalized_hour)


# --- Public API ---

func update_lighting(time_of_day: float) -> void:
	## Main update called each frame. time_of_day is normalized 0.0-24.0.
	var period := _get_period_for_hour(time_of_day)
	var blend := _get_blend_factor(time_of_day, period)

	# Determine which two presets to interpolate between
	var current_preset: Dictionary = presets.get(period, {})
	var prev_period := _get_previous_period(period)
	var prev_preset: Dictionary = presets.get(prev_period, {})

	# Blend at the start of each period for smooth transitions
	var transition_blend := _get_transition_factor(time_of_day, period)

	if transition_blend < 1.0:
		# In transition zone: blend between previous and current preset
		_interpolate_presets(prev_preset, current_preset, transition_blend)
	else:
		# Fully in current period
		_apply_preset_values(current_preset)

	# Apply district modifiers
	_apply_district_modifiers()

	# Push values to scene nodes
	_apply_to_directional_light()
	_apply_to_world_environment()

	# Update sub-controllers
	if sky_controller:
		sky_controller.update_sky(
			_sky_top, _sky_horizon, _sky_ground,
			_star_visibility, _moon_intensity, time_of_day
		)

	if neon_controller:
		neon_controller.set_neon_intensity(_neon_intensity)

	if street_light_controller:
		street_light_controller.set_lights_enabled(_street_lights_on)

	# Track headlights state changes
	var needs_headlights := is_headlights_needed()
	if needs_headlights != _headlights_needed:
		_headlights_needed = needs_headlights
		EventBus.headlights_needed_changed.emit(_headlights_needed)

	_current_ambient_brightness = _ambient_energy


func get_ambient_brightness() -> float:
	## Returns current ambient brightness level (0.0 to 1.0).
	return _current_ambient_brightness


func is_headlights_needed() -> bool:
	## Returns true if ambient light is low enough to require headlights.
	return _ambient_energy < 0.25


func get_sun_direction() -> Vector3:
	## Returns the current sun/moon direction vector based on angle.
	var angle_rad := deg_to_rad(_sun_angle)
	return Vector3(0.0, sin(angle_rad), -cos(angle_rad)).normalized()


func get_current_period() -> String:
	return _current_period


func set_district(district_id: String) -> void:
	## Set the current district for color personality modifiers.
	current_district = district_id
	print("[DayNight] District set: %s" % district_id)


# --- Preset Loading ---

func _load_presets() -> void:
	var file := FileAccess.open("res://data/lighting/time_presets.json", FileAccess.READ)
	if not file:
		push_error("[DayNight] Failed to load time_presets.json")
		_create_fallback_presets()
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("[DayNight] JSON parse error in time_presets.json: %s" % json.get_error_message())
		_create_fallback_presets()
		return

	var data: Dictionary = json.data
	presets = data.get("presets", {})
	transition_durations = data.get("transition_durations", {})
	district_modifiers = data.get("district_modifiers", {})
	print("[DayNight] Loaded %d presets, %d district modifiers" % [presets.size(), district_modifiers.size()])


func _create_fallback_presets() -> void:
	## Hardcoded fallback if JSON fails to load.
	presets = {
		PERIOD_NIGHT: {
			"sun_color": "#2233aa", "sun_intensity": 0.05, "sun_angle": -15.0,
			"ambient_color": "#0d0d33", "ambient_energy": 0.1,
			"fog_color": "#080818", "fog_density": 0.0008,
			"sky_top": "#080820", "sky_horizon": "#111133", "sky_ground": "#040410",
			"neon_intensity": 1.0, "street_lights": true, "headlights_needed": true,
			"star_visibility": 0.9, "moon_intensity": 0.25,
			"shadow_opacity": 0.7, "tonemap_exposure": 0.9, "tonemap_white": 1.3,
		}
	}
	push_warning("[DayNight] Using fallback presets (night only)")


# --- Sub-controller Creation ---

func _create_sub_controllers() -> void:
	sky_controller = SkyController.new()
	sky_controller.name = "SkyController"
	add_child(sky_controller)

	neon_controller = NeonController.new()
	neon_controller.name = "NeonController"
	add_child(neon_controller)

	street_light_controller = StreetLightController.new()
	street_light_controller.name = "StreetLightController"
	add_child(street_light_controller)

	print("[DayNight] Sub-controllers created")


func _find_scene_nodes() -> void:
	## Finds DirectionalLight3D and WorldEnvironment in the scene tree.
	## Deferred to allow the scene tree to finish loading.
	await get_tree().process_frame

	# Search for WorldEnvironment
	var we_nodes := get_tree().get_nodes_in_group("world_environment")
	if we_nodes.size() > 0:
		world_environment = we_nodes[0] as WorldEnvironment
	else:
		# Search the scene tree for WorldEnvironment
		world_environment = _find_node_of_type(get_tree().current_scene, "WorldEnvironment") as WorldEnvironment

	# Search for DirectionalLight3D (sun/moon)
	var dl_nodes := get_tree().get_nodes_in_group("sun_light")
	if dl_nodes.size() > 0:
		directional_light = dl_nodes[0] as DirectionalLight3D
	else:
		directional_light = _find_node_of_type(get_tree().current_scene, "DirectionalLight3D") as DirectionalLight3D

	if world_environment:
		print("[DayNight] Found WorldEnvironment: %s" % world_environment.name)
	else:
		push_warning("[DayNight] No WorldEnvironment found in scene")

	if directional_light:
		print("[DayNight] Found DirectionalLight3D: %s" % directional_light.name)
	else:
		push_warning("[DayNight] No DirectionalLight3D found in scene")


func _find_node_of_type(root: Node, type_name: String) -> Node:
	## Recursively find the first node of the given type.
	if root == null:
		return null
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null


# --- Time Utilities ---

func _normalize_hour(game_hour: float) -> float:
	## Converts WorldTimeSystem's game_hour (19.0-30.0) to normalized 0-24.
	return fmod(game_hour, 24.0)


func _get_period_for_hour(hour: float) -> String:
	## Determine which time period the given hour falls into.
	if hour >= 0.0 and hour < 4.0:
		return PERIOD_LATE_NIGHT
	elif hour >= 4.0 and hour < 6.0:
		return PERIOD_DAWN
	elif hour >= 6.0 and hour < 18.0:
		return PERIOD_DAY
	elif hour >= 18.0 and hour < 20.0:
		return PERIOD_DUSK
	else:  # 20.0 - 24.0
		return PERIOD_NIGHT


func _get_previous_period(period: String) -> String:
	## Get the period that comes before this one in the cycle.
	var idx := PERIOD_ORDER.find(period)
	if idx <= 0:
		return PERIOD_ORDER[PERIOD_ORDER.size() - 1]
	return PERIOD_ORDER[idx - 1]


func _get_transition_factor(hour: float, period: String) -> float:
	## Returns 0.0 at the very start of a period, ramping to 1.0.
	## The transition zone is the first portion of each period.
	var range_data: Dictionary = PERIOD_RANGES.get(period, {})
	var period_start: float = range_data.get("start", 0.0)
	var period_end: float = range_data.get("end", 24.0)
	var period_duration: float = period_end - period_start

	# Transition occupies the first 30% of the period (or 1 hour, whichever is smaller)
	var transition_duration := minf(period_duration * 0.3, 1.0)
	var time_into_period := hour - period_start

	if time_into_period < 0.0:
		# Handle wrap-around for late_night crossing midnight
		time_into_period += 24.0

	if time_into_period >= transition_duration:
		return 1.0

	return clampf(time_into_period / transition_duration, 0.0, 1.0)


func _get_blend_factor(hour: float, period: String) -> float:
	## Returns how far through the current period we are (0.0 to 1.0).
	var range_data: Dictionary = PERIOD_RANGES.get(period, {})
	var period_start: float = range_data.get("start", 0.0)
	var period_end: float = range_data.get("end", 24.0)
	var period_duration: float = period_end - period_start
	var time_into_period := hour - period_start

	if time_into_period < 0.0:
		time_into_period += 24.0

	return clampf(time_into_period / period_duration, 0.0, 1.0)


# --- Preset Interpolation ---

func _interpolate_presets(from: Dictionary, to: Dictionary, t: float) -> void:
	## Interpolate all visual values between two presets.
	_sun_color = _lerp_hex_color(from, to, "sun_color", t)
	_sun_intensity = lerpf(
		from.get("sun_intensity", 0.05),
		to.get("sun_intensity", 0.05), t
	)
	_sun_angle = lerpf(
		from.get("sun_angle", -15.0),
		to.get("sun_angle", -15.0), t
	)
	_ambient_color = _lerp_hex_color(from, to, "ambient_color", t)
	_ambient_energy = lerpf(
		from.get("ambient_energy", 0.1),
		to.get("ambient_energy", 0.1), t
	)
	_fog_color = _lerp_hex_color(from, to, "fog_color", t)
	_fog_density = lerpf(
		from.get("fog_density", 0.001),
		to.get("fog_density", 0.001), t
	)
	_sky_top = _lerp_hex_color(from, to, "sky_top", t)
	_sky_horizon = _lerp_hex_color(from, to, "sky_horizon", t)
	_sky_ground = _lerp_hex_color(from, to, "sky_ground", t)
	_neon_intensity = lerpf(
		from.get("neon_intensity", 1.0),
		to.get("neon_intensity", 1.0), t
	)
	_street_lights_on = to.get("street_lights", true) if t > 0.5 else from.get("street_lights", true)
	_star_visibility = lerpf(
		from.get("star_visibility", 0.0),
		to.get("star_visibility", 0.0), t
	)
	_moon_intensity = lerpf(
		from.get("moon_intensity", 0.0),
		to.get("moon_intensity", 0.0), t
	)
	_shadow_opacity = lerpf(
		from.get("shadow_opacity", 0.5),
		to.get("shadow_opacity", 0.5), t
	)
	_tonemap_exposure = lerpf(
		from.get("tonemap_exposure", 1.0),
		to.get("tonemap_exposure", 1.0), t
	)
	_tonemap_white = lerpf(
		from.get("tonemap_white", 1.0),
		to.get("tonemap_white", 1.0), t
	)


func _apply_preset_values(preset: Dictionary) -> void:
	## Apply a single preset's values directly (no blending).
	_sun_color = Color.html(preset.get("sun_color", "#2233aa"))
	_sun_intensity = preset.get("sun_intensity", 0.05)
	_sun_angle = preset.get("sun_angle", -15.0)
	_ambient_color = Color.html(preset.get("ambient_color", "#0d0d33"))
	_ambient_energy = preset.get("ambient_energy", 0.1)
	_fog_color = Color.html(preset.get("fog_color", "#080818"))
	_fog_density = preset.get("fog_density", 0.001)
	_sky_top = Color.html(preset.get("sky_top", "#080820"))
	_sky_horizon = Color.html(preset.get("sky_horizon", "#111133"))
	_sky_ground = Color.html(preset.get("sky_ground", "#040410"))
	_neon_intensity = preset.get("neon_intensity", 1.0)
	_street_lights_on = preset.get("street_lights", true)
	_star_visibility = preset.get("star_visibility", 0.0)
	_moon_intensity = preset.get("moon_intensity", 0.0)
	_shadow_opacity = preset.get("shadow_opacity", 0.5)
	_tonemap_exposure = preset.get("tonemap_exposure", 1.0)
	_tonemap_white = preset.get("tonemap_white", 1.0)


func _apply_preset_immediate(period: String) -> void:
	## Immediately apply a preset without transition.
	var preset: Dictionary = presets.get(period, {})
	if preset.is_empty():
		return
	_apply_preset_values(preset)
	_apply_district_modifiers()
	_apply_to_directional_light()
	_apply_to_world_environment()


func _lerp_hex_color(from: Dictionary, to: Dictionary, key: String, t: float) -> Color:
	## Interpolate between two hex color values.
	var from_color := Color.html(from.get(key, "#000000"))
	var to_color := Color.html(to.get(key, "#000000"))
	return from_color.lerp(to_color, t)


# --- District Modifiers ---

func _apply_district_modifiers() -> void:
	## Apply per-district color personality adjustments.
	var modifier: Dictionary = district_modifiers.get(current_district, {})
	if modifier.is_empty():
		return

	var ambient_boost: float = modifier.get("ambient_boost", 0.0)
	_ambient_energy = clampf(_ambient_energy + ambient_boost, 0.0, 1.0)

	var fog_mult: float = modifier.get("fog_density_mult", 1.0)
	_fog_density *= fog_mult


# --- Scene Application ---

func _apply_to_directional_light() -> void:
	## Push current values to the DirectionalLight3D node.
	if not directional_light:
		return

	directional_light.light_color = _sun_color
	directional_light.light_energy = _sun_intensity

	# Rotate to match sun angle (rotation around X axis)
	var angle_rad := deg_to_rad(_sun_angle)
	directional_light.rotation.x = angle_rad

	directional_light.shadow_enabled = _shadow_opacity > 0.1
	# Shadow opacity is not directly a Godot property; adjust energy to simulate
	# Brighter directional light = stronger shadow contrast


func _apply_to_world_environment() -> void:
	## Push current values to the WorldEnvironment node.
	if not world_environment:
		return
	if not world_environment.environment:
		return

	var env := world_environment.environment

	# Ambient light
	env.ambient_light_color = _ambient_color
	env.ambient_light_energy = _ambient_energy

	# Fog
	env.fog_light_color = _fog_color
	env.fog_density = _fog_density

	# Tonemap
	env.tonemap_exposure = _tonemap_exposure
	env.tonemap_white = _tonemap_white

	# Sky material colors (if using ProceduralSkyMaterial)
	if env.sky and env.sky.sky_material:
		var sky_mat := env.sky.sky_material
		if sky_mat is ProceduralSkyMaterial:
			sky_mat.sky_top_color = _sky_top
			sky_mat.sky_horizon_color = _sky_horizon
			sky_mat.ground_bottom_color = _sky_ground
			sky_mat.ground_horizon_color = _sky_horizon.lerp(_sky_ground, 0.5)
		elif sky_mat is ShaderMaterial:
			# Custom sky shader
			sky_mat.set_shader_parameter("sky_top_color", Vector3(_sky_top.r, _sky_top.g, _sky_top.b))
			sky_mat.set_shader_parameter("sky_horizon_color", Vector3(_sky_horizon.r, _sky_horizon.g, _sky_horizon.b))
			sky_mat.set_shader_parameter("sky_ground_color", Vector3(_sky_ground.r, _sky_ground.g, _sky_ground.b))
			sky_mat.set_shader_parameter("star_visibility", _star_visibility)
			sky_mat.set_shader_parameter("moon_intensity", _moon_intensity)


# --- Signal Handlers ---

func _on_time_period_changed(period: String) -> void:
	## Respond to WorldTime period change signals.
	_previous_period = _current_period
	_current_period = period

	# Map WorldTime period names to our visual period names
	# WorldTime uses: dusk, night, late_night, dawn
	# We additionally support: day
	print("[DayNight] Period transition: %s -> %s" % [_previous_period, _current_period])

	# Emit neon activation/deactivation signals at appropriate transitions
	if _current_period == PERIOD_DUSK and _previous_period in [PERIOD_DAY]:
		EventBus.neon_lights_activated.emit()
	elif _current_period == PERIOD_DAY:
		EventBus.neon_lights_deactivated.emit()


func _on_district_entered(district_id: String) -> void:
	set_district(district_id)
