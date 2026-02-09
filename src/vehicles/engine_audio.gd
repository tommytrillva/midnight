## Engine sound system for MIDNIGHT GRIND vehicles.
## Pitch-shifts audio based on RPM, manages tire screech during drifts,
## and plays one-shot sounds for gear shifts and turbo blowoff.
class_name SimpleEngineAudio
extends Node3D

@export var min_pitch: float = 0.5
@export var max_pitch: float = 2.5
@export var min_rpm: float = 800.0
@export var max_rpm: float = 8000.0
@export var engine_volume: float = -6.0
@export var screech_volume: float = -12.0

var engine_player: AudioStreamPlayer3D = null
var tire_screech_player: AudioStreamPlayer3D = null
var shift_player: AudioStreamPlayer3D = null
var turbo_player: AudioStreamPlayer3D = null

var _current_rpm: float = 800.0
var _current_throttle: float = 0.0
var _is_drifting: bool = false
var _screech_intensity: float = 0.0


func _ready() -> void:
	_setup_audio_players()
	_connect_signals()
	print("[EngineAudio] Engine audio system ready.")


func _setup_audio_players() -> void:
	# Engine loop player
	engine_player = AudioStreamPlayer3D.new()
	engine_player.name = "EngineLoop"
	engine_player.bus = &"Engine"
	engine_player.max_distance = 50.0
	engine_player.volume_db = engine_volume
	add_child(engine_player)

	# Tire screech player
	tire_screech_player = AudioStreamPlayer3D.new()
	tire_screech_player.name = "TireScreech"
	tire_screech_player.bus = &"SFX"
	tire_screech_player.max_distance = 40.0
	tire_screech_player.volume_db = -60.0  # Start silent
	add_child(tire_screech_player)

	# Gear shift one-shot
	shift_player = AudioStreamPlayer3D.new()
	shift_player.name = "GearShift"
	shift_player.bus = &"Engine"
	shift_player.max_distance = 30.0
	add_child(shift_player)

	# Turbo blowoff one-shot
	turbo_player = AudioStreamPlayer3D.new()
	turbo_player.name = "TurboBlowoff"
	turbo_player.bus = &"Engine"
	turbo_player.max_distance = 35.0
	add_child(turbo_player)

	# Try loading audio streams (gracefully handle missing files)
	_try_load_stream(engine_player, "res://assets/audio/sfx/engine_loop.ogg")
	_try_load_stream(tire_screech_player, "res://assets/audio/sfx/tire_screech_loop.ogg")
	_try_load_stream(shift_player, "res://assets/audio/sfx/gear_shift.ogg")
	_try_load_stream(turbo_player, "res://assets/audio/sfx/turbo_blowoff.ogg")


func _try_load_stream(player: AudioStreamPlayer3D, path: String) -> void:
	if ResourceLoader.exists(path):
		player.stream = load(path)
	# If file doesn't exist, the player just won't play — no crash


func _connect_signals() -> void:
	if not has_node("/root/EventBus"):
		print("[EngineAudio] WARNING: EventBus not found, signals not connected.")
		return

	var bus: Node = get_node("/root/EventBus")

	if bus.has_signal("engine_rpm_updated"):
		bus.engine_rpm_updated.connect(_on_rpm_updated)
	if bus.has_signal("drift_started"):
		bus.drift_started.connect(_on_drift_started)
	if bus.has_signal("drift_ended"):
		bus.drift_ended.connect(_on_drift_ended)
	if bus.has_signal("gear_shifted"):
		bus.gear_shifted.connect(_on_gear_shifted)
	if bus.has_signal("turbo_blowoff"):
		bus.turbo_blowoff.connect(_on_turbo_blowoff)
	if bus.has_signal("tire_screech"):
		bus.tire_screech.connect(_on_tire_screech)


func _physics_process(delta: float) -> void:
	_update_engine_pitch(delta)
	_update_screech(delta)


func _update_engine_pitch(delta: float) -> void:
	if engine_player.stream == null:
		return

	# Start playing if not already
	if not engine_player.playing:
		engine_player.play()

	# Map RPM to pitch
	var t: float = clampf((_current_rpm - min_rpm) / (max_rpm - min_rpm), 0.0, 1.0)
	var target_pitch: float = lerpf(min_pitch, max_pitch, t)
	engine_player.pitch_scale = lerpf(engine_player.pitch_scale, target_pitch, 8.0 * delta)

	# Volume based on throttle (idle = quieter)
	var target_vol: float = lerpf(engine_volume - 12.0, engine_volume, clampf(_current_throttle, 0.2, 1.0))
	engine_player.volume_db = lerpf(engine_player.volume_db, target_vol, 5.0 * delta)


func _update_screech(delta: float) -> void:
	if tire_screech_player.stream == null:
		return

	if _is_drifting and _screech_intensity > 0.0:
		if not tire_screech_player.playing:
			tire_screech_player.play()
		var target_vol: float = lerpf(screech_volume - 20.0, screech_volume, _screech_intensity)
		tire_screech_player.volume_db = lerpf(tire_screech_player.volume_db, target_vol, 6.0 * delta)
		tire_screech_player.pitch_scale = lerpf(0.8, 1.2, _screech_intensity)
	else:
		tire_screech_player.volume_db = lerpf(tire_screech_player.volume_db, -60.0, 8.0 * delta)
		if tire_screech_player.volume_db < -55.0 and tire_screech_player.playing:
			tire_screech_player.stop()


func update_engine_sound(rpm: float, throttle: float) -> void:
	_current_rpm = rpm
	_current_throttle = throttle


# ── Signal Callbacks ──────────────────────────────────────────────────

func _on_rpm_updated(_vehicle_id: int, rpm: float, throttle: float) -> void:
	update_engine_sound(rpm, throttle)


func _on_drift_started(_vehicle_id: int) -> void:
	_is_drifting = true


func _on_drift_ended(_vehicle_id: int, _score: float) -> void:
	_is_drifting = false
	_screech_intensity = 0.0


func _on_gear_shifted(_vehicle_id: int, _gear: int) -> void:
	if shift_player.stream:
		shift_player.play()
	# Brief pitch dip on shift for feel
	engine_player.pitch_scale *= 0.85


func _on_turbo_blowoff(_vehicle_id: int) -> void:
	if turbo_player.stream:
		turbo_player.play()


func _on_tire_screech(_vehicle_id: int, intensity: float) -> void:
	_screech_intensity = intensity
