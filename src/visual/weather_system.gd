## Visual weather controller for MIDNIGHT GRIND.
## Responds to WorldTimeSystem weather changes and coordinates all weather
## subsystems: rain particles, fog, lightning, road wetness, and lighting.
## Provides grip/visibility multipliers for vehicle physics and AI.
class_name WeatherSystem
extends Node3D

# ── Weather state constants ──────────────────────────────────────────────────
const WEATHER_CLEAR := "clear"
const WEATHER_LIGHT_RAIN := "light_rain"
const WEATHER_HEAVY_RAIN := "heavy_rain"
const WEATHER_FOG := "fog"
const WEATHER_STORM := "storm"

# ── Weather parameter tables ─────────────────────────────────────────────────
# Rain intensity per weather state (0.0 = none, 1.0 = max)
const RAIN_INTENSITY := {
	"clear": 0.0,
	"light_rain": 0.3,
	"heavy_rain": 0.7,
	"fog": 0.0,
	"storm": 1.0,
}

# Fog density per weather state
const FOG_DENSITY := {
	"clear": 0.0,
	"light_rain": 0.001,
	"heavy_rain": 0.003,
	"fog": 0.01,
	"storm": 0.004,
}

# Ambient light energy multiplier per weather state
const AMBIENT_ENERGY := {
	"clear": 1.0,
	"light_rain": 0.8,
	"heavy_rain": 0.5,
	"fog": 0.6,
	"storm": 0.35,
}

# Wind strength per weather state (affects rain angle and particles)
const WIND_STRENGTH := {
	"clear": 0.0,
	"light_rain": 0.1,
	"heavy_rain": 0.3,
	"fog": 0.05,
	"storm": 0.7,
}

# Grip multiplier per weather state (mirrors WorldTimeSystem for direct access)
const GRIP_MULTIPLIER := {
	"clear": 1.0,
	"light_rain": 0.85,
	"heavy_rain": 0.70,
	"fog": 0.95,
	"storm": 0.65,
}

# Visibility multiplier per weather state
const VISIBILITY_MULTIPLIER := {
	"clear": 1.0,
	"light_rain": 0.9,
	"heavy_rain": 0.7,
	"fog": 0.5,
	"storm": 0.6,
}

# ── Export configuration ─────────────────────────────────────────────────────
@export_group("References")
## WorldEnvironment node for fog and ambient adjustments.
@export var world_environment: WorldEnvironment = null
## DirectionalLight3D used as the main scene light (moon/sky).
@export var main_light: DirectionalLight3D = null

@export_group("Transition")
## Default transition time in seconds when weather changes.
@export var default_transition_time: float = 5.0

@export_group("Wind")
## Base wind direction (XZ plane, normalized internally).
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.3)

@export_group("Cloud Shadow")
## Speed of cloud shadow movement across the ground.
@export var cloud_shadow_speed: float = 2.0
## Enable cloud shadow panning on the main light cookie.
@export var enable_cloud_shadows: bool = true

# ── Subsystem references ─────────────────────────────────────────────────────
var rain_effect: RainEffect = null
var fog_effect: FogEffect = null
var lightning_effect: LightningEffect = null
var road_wetness: RoadWetness = null

# ── Runtime state ────────────────────────────────────────────────────────────
var _current_weather: String = WEATHER_CLEAR
var _target_weather: String = WEATHER_CLEAR
var _transition_progress: float = 1.0  # 1.0 = fully transitioned
var _transition_duration: float = 5.0
var _transitioning: bool = false

# Interpolated values during transitions
var _current_rain_intensity: float = 0.0
var _current_fog_density: float = 0.0
var _current_ambient_energy: float = 1.0
var _current_wind_strength: float = 0.0

# Source values (state we are transitioning FROM)
var _source_rain_intensity: float = 0.0
var _source_fog_density: float = 0.0
var _source_ambient_energy: float = 1.0
var _source_wind_strength: float = 0.0

# Cloud shadow offset
var _cloud_shadow_offset: Vector2 = Vector2.ZERO


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_subsystems()
	_connect_signals()
	_apply_weather_immediate(WEATHER_CLEAR)
	print("[Weather] Weather system initialized")


func _process(delta: float) -> void:
	if _transitioning:
		_update_transition(delta)

	_update_cloud_shadow(delta)

	# Keep rain following the camera
	if rain_effect:
		var camera := get_viewport().get_camera_3d()
		if camera:
			rain_effect.global_position = Vector3(
				camera.global_position.x,
				camera.global_position.y + 25.0,
				camera.global_position.z
			)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func set_weather(weather: String, transition_time: float = 5.0) -> void:
	## Transition to a new weather state over the given duration.
	if weather == _current_weather and not _transitioning:
		return

	if weather not in RAIN_INTENSITY:
		print("[Weather] WARNING: Unknown weather state '%s'" % weather)
		return

	var old_weather := _current_weather
	_target_weather = weather
	_transition_duration = maxf(transition_time, 0.1)
	_transition_progress = 0.0
	_transitioning = true

	# Snapshot current interpolated values as transition source
	_source_rain_intensity = _current_rain_intensity
	_source_fog_density = _current_fog_density
	_source_ambient_energy = _current_ambient_energy
	_source_wind_strength = _current_wind_strength

	# Emit changing signal
	EventBus.weather_changing.emit(old_weather, weather)
	print("[Weather] Transitioning: %s -> %s (%.1fs)" % [old_weather, weather, transition_time])

	# Start/stop lightning for storm transitions
	if lightning_effect:
		if weather == WEATHER_STORM:
			lightning_effect.start_storm()
		elif _current_weather == WEATHER_STORM:
			lightning_effect.stop_storm()


func get_current_weather() -> String:
	## Returns the current (or target if transitioning) weather state.
	return _target_weather if _transitioning else _current_weather


func get_grip_multiplier() -> float:
	## Returns the current grip multiplier for vehicle physics.
	## Interpolated during transitions for smooth gameplay changes.
	if _transitioning:
		var from_grip: float = GRIP_MULTIPLIER.get(_current_weather, 1.0)
		var to_grip: float = GRIP_MULTIPLIER.get(_target_weather, 1.0)
		return lerpf(from_grip, to_grip, _transition_progress)
	return GRIP_MULTIPLIER.get(_current_weather, 1.0)


func get_visibility_multiplier() -> float:
	## Returns the current visibility multiplier for AI and rendering.
	## Interpolated during transitions.
	if _transitioning:
		var from_vis: float = VISIBILITY_MULTIPLIER.get(_current_weather, 1.0)
		var to_vis: float = VISIBILITY_MULTIPLIER.get(_target_weather, 1.0)
		return lerpf(from_vis, to_vis, _transition_progress)
	return VISIBILITY_MULTIPLIER.get(_current_weather, 1.0)


func get_wind_direction() -> Vector3:
	## Returns the current wind direction scaled by strength.
	return wind_direction.normalized() * _current_wind_strength


func get_rain_intensity() -> float:
	return _current_rain_intensity


# ═══════════════════════════════════════════════════════════════════════════════
#  SETUP
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_subsystems() -> void:
	# Rain
	rain_effect = RainEffect.new()
	rain_effect.name = "RainEffect"
	add_child(rain_effect)

	# Fog
	fog_effect = FogEffect.new()
	fog_effect.name = "FogEffect"
	add_child(fog_effect)

	# Lightning
	lightning_effect = LightningEffect.new()
	lightning_effect.name = "LightningEffect"
	add_child(lightning_effect)

	# Road wetness
	road_wetness = RoadWetness.new()
	road_wetness.name = "RoadWetness"
	add_child(road_wetness)

	# Pass references
	if world_environment:
		fog_effect.world_environment = world_environment

	if main_light:
		lightning_effect.main_light = main_light

	print("[Weather] Subsystems created: Rain, Fog, Lightning, RoadWetness")


func _connect_signals() -> void:
	EventBus.weather_changed.connect(_on_weather_changed)


func _on_weather_changed(condition: String) -> void:
	## Respond to WorldTimeSystem weather rolls.
	set_weather(condition, default_transition_time)


# ═══════════════════════════════════════════════════════════════════════════════
#  TRANSITIONS
# ═══════════════════════════════════════════════════════════════════════════════

func _update_transition(delta: float) -> void:
	_transition_progress += delta / _transition_duration
	_transition_progress = clampf(_transition_progress, 0.0, 1.0)

	# Smooth ease-in-out curve
	var t := _ease_in_out(_transition_progress)

	# Interpolate all weather parameters
	var target_rain: float = RAIN_INTENSITY.get(_target_weather, 0.0)
	var target_fog: float = FOG_DENSITY.get(_target_weather, 0.0)
	var target_ambient: float = AMBIENT_ENERGY.get(_target_weather, 1.0)
	var target_wind: float = WIND_STRENGTH.get(_target_weather, 0.0)

	_current_rain_intensity = lerpf(_source_rain_intensity, target_rain, t)
	_current_fog_density = lerpf(_source_fog_density, target_fog, t)
	_current_ambient_energy = lerpf(_source_ambient_energy, target_ambient, t)
	_current_wind_strength = lerpf(_source_wind_strength, target_wind, t)

	# Apply to subsystems
	_apply_rain(_current_rain_intensity)
	_apply_fog(_current_fog_density)
	_apply_ambient(_current_ambient_energy)
	_apply_wind(_current_wind_strength)

	# Update road wetness based on rain
	if road_wetness:
		road_wetness.set_raining(_current_rain_intensity > 0.05)

	# Transition complete
	if _transition_progress >= 1.0:
		_transitioning = false
		_current_weather = _target_weather
		EventBus.weather_changed.emit(_current_weather)
		print("[Weather] Transition complete: %s" % _current_weather)


func _apply_weather_immediate(weather: String) -> void:
	## Instantly snap to a weather state without transition.
	_current_weather = weather
	_target_weather = weather
	_transitioning = false
	_transition_progress = 1.0

	_current_rain_intensity = RAIN_INTENSITY.get(weather, 0.0)
	_current_fog_density = FOG_DENSITY.get(weather, 0.0)
	_current_ambient_energy = AMBIENT_ENERGY.get(weather, 1.0)
	_current_wind_strength = WIND_STRENGTH.get(weather, 0.0)

	_apply_rain(_current_rain_intensity)
	_apply_fog(_current_fog_density)
	_apply_ambient(_current_ambient_energy)
	_apply_wind(_current_wind_strength)

	if road_wetness:
		road_wetness.set_raining(_current_rain_intensity > 0.05)

	if lightning_effect:
		if weather == WEATHER_STORM:
			lightning_effect.start_storm()
		else:
			lightning_effect.stop_storm()


# ═══════════════════════════════════════════════════════════════════════════════
#  PARAMETER APPLICATION
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_rain(intensity: float) -> void:
	if rain_effect:
		rain_effect.set_intensity(intensity)


func _apply_fog(density: float) -> void:
	if fog_effect:
		fog_effect.set_fog_level(density, 0.0)  # Immediate when called from transition


func _apply_ambient(energy: float) -> void:
	if main_light:
		main_light.light_energy = energy


func _apply_wind(strength: float) -> void:
	if rain_effect:
		rain_effect.set_wind(wind_direction.normalized(), strength)


func _update_cloud_shadow(delta: float) -> void:
	if not enable_cloud_shadows or not main_light:
		return

	# Pan the cloud shadow texture offset over time
	var wind_dir_2d := Vector2(wind_direction.x, wind_direction.z).normalized()
	var speed := cloud_shadow_speed * _current_wind_strength
	_cloud_shadow_offset += wind_dir_2d * speed * delta

	# If the main light has a projector texture, update its UV offset
	# This integrates with whatever cloud shadow cookie is assigned in the editor
	# The offset wraps naturally through shader UVs


# ═══════════════════════════════════════════════════════════════════════════════
#  UTILITY
# ═══════════════════════════════════════════════════════════════════════════════

func _ease_in_out(t: float) -> float:
	## Smoothstep ease-in-out for natural weather transitions.
	return t * t * (3.0 - 2.0 * t)


func serialize() -> Dictionary:
	return {
		"current_weather": _current_weather,
		"road_wetness": road_wetness.get_wetness() if road_wetness else 0.0,
	}


func deserialize(data: Dictionary) -> void:
	var weather: String = data.get("current_weather", WEATHER_CLEAR)
	_apply_weather_immediate(weather)
	if road_wetness:
		road_wetness.set_wetness(data.get("road_wetness", 0.0))
