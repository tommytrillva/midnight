## Manages persistent game settings. Loads/saves from user://settings.cfg.
## Applies audio, display, and gameplay settings on startup and when changed.
extends Node

# Note: No class_name to avoid conflict with autoload singleton name

const SETTINGS_PATH := "user://settings.cfg"

# --- Default Values ---
const DEFAULT_MASTER_VOLUME := 80
const DEFAULT_MUSIC_VOLUME := 70
const DEFAULT_SFX_VOLUME := 80
const DEFAULT_ENGINE_VOLUME := 75
const DEFAULT_CAMERA_SENSITIVITY := 50
const DEFAULT_PSX_SHADER_INTENSITY := 70
const DEFAULT_FULLSCREEN := false
const DEFAULT_VSYNC := true
const DEFAULT_SHOW_FPS := false

# --- Current Values ---
var master_volume: int = DEFAULT_MASTER_VOLUME
var music_volume: int = DEFAULT_MUSIC_VOLUME
var sfx_volume: int = DEFAULT_SFX_VOLUME
var engine_volume: int = DEFAULT_ENGINE_VOLUME
var camera_sensitivity: int = DEFAULT_CAMERA_SENSITIVITY
var psx_shader_intensity: int = DEFAULT_PSX_SHADER_INTENSITY
var fullscreen: bool = DEFAULT_FULLSCREEN
var vsync: bool = DEFAULT_VSYNC
var show_fps: bool = DEFAULT_SHOW_FPS

var _config: ConfigFile = null


func _ready() -> void:
	_config = ConfigFile.new()
	load_settings()
	apply_all()
	print("[Settings] Settings loaded and applied.")


func load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		print("[Settings] No settings file found, using defaults.")
		_apply_defaults()
		return

	master_volume = _config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)
	music_volume = _config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)
	sfx_volume = _config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)
	engine_volume = _config.get_value("audio", "engine_volume", DEFAULT_ENGINE_VOLUME)
	fullscreen = _config.get_value("display", "fullscreen", DEFAULT_FULLSCREEN)
	vsync = _config.get_value("display", "vsync", DEFAULT_VSYNC)
	show_fps = _config.get_value("display", "show_fps", DEFAULT_SHOW_FPS)
	camera_sensitivity = _config.get_value("gameplay", "camera_sensitivity", DEFAULT_CAMERA_SENSITIVITY)
	psx_shader_intensity = _config.get_value("gameplay", "psx_shader_intensity", DEFAULT_PSX_SHADER_INTENSITY)


func save_settings() -> void:
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)
	_config.set_value("audio", "engine_volume", engine_volume)
	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "vsync", vsync)
	_config.set_value("display", "show_fps", show_fps)
	_config.set_value("gameplay", "camera_sensitivity", camera_sensitivity)
	_config.set_value("gameplay", "psx_shader_intensity", psx_shader_intensity)
	_config.save(SETTINGS_PATH)
	print("[Settings] Settings saved to %s" % SETTINGS_PATH)


func apply_all() -> void:
	apply_audio()
	apply_display()


func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Engine", engine_volume)


func apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func set_master_volume(value: int) -> void:
	master_volume = clampi(value, 0, 100)
	_set_bus_volume("Master", master_volume)


func set_music_volume(value: int) -> void:
	music_volume = clampi(value, 0, 100)
	_set_bus_volume("Music", music_volume)


func set_sfx_volume(value: int) -> void:
	sfx_volume = clampi(value, 0, 100)
	_set_bus_volume("SFX", sfx_volume)


func set_engine_volume(value: int) -> void:
	engine_volume = clampi(value, 0, 100)
	_set_bus_volume("Engine", engine_volume)


func set_camera_sensitivity(value: int) -> void:
	camera_sensitivity = clampi(value, 0, 100)


func set_psx_shader_intensity(value: int) -> void:
	psx_shader_intensity = clampi(value, 0, 100)


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_display()


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	apply_display()


func set_show_fps(enabled: bool) -> void:
	show_fps = enabled


func get_camera_sensitivity_float() -> float:
	## Returns camera sensitivity as a 0.1 to 2.0 range for use by camera systems.
	return lerpf(0.1, 2.0, camera_sensitivity / 100.0)


func get_psx_shader_intensity_float() -> float:
	## Returns PSX shader intensity as a 0.0 to 1.0 range for shader uniforms.
	return psx_shader_intensity / 100.0


func _set_bus_volume(bus_name: String, value: int) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		push_warning("[Settings] Audio bus '%s' not found." % bus_name)
		return

	if value <= 0:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value / 100.0))


func _apply_defaults() -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	engine_volume = DEFAULT_ENGINE_VOLUME
	fullscreen = DEFAULT_FULLSCREEN
	vsync = DEFAULT_VSYNC
	show_fps = DEFAULT_SHOW_FPS
	camera_sensitivity = DEFAULT_CAMERA_SENSITIVITY
	psx_shader_intensity = DEFAULT_PSX_SHADER_INTENSITY
