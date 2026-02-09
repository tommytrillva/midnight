## Manages Engine.time_scale for dramatic slow-motion moments.
## Provides smooth transitions in/out and adjusts audio pitch to match.
## Used for: crash moments, near-misses, finish lines, the Fall revelation.
class_name SlowMotion
extends Node

## Whether slow motion is currently active.
var _active: bool = false

## The current target time scale (1.0 = normal).
var _target_scale: float = 1.0

## Tween for smooth transitions.
var _tween: Tween = null

## Timer for auto-deactivation (0 = indefinite).
var _duration_timer: float = 0.0

## Whether we have a timed duration running.
var _timed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "SlowMotion"
	print("[SlowMo] System ready.")


func _process(delta: float) -> void:
	if not _timed or not _active:
		return

	# Count down using real (unscaled) delta
	# Note: PROCESS_MODE_ALWAYS doesn't unscale delta, so divide by time_scale
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	_duration_timer -= real_delta
	if _duration_timer <= 0.0:
		_timed = false
		deactivate(0.5)


## Activate slow motion with the given time scale over a smooth ramp duration.
## If duration > 0, slow-mo will automatically deactivate after that many
## real-time seconds. Pass 0 for indefinite (manual deactivate required).
func activate(scale: float, duration: float = 0.0, ramp_in: float = 0.3) -> void:
	if scale <= 0.0 or scale >= 1.0:
		push_warning("[SlowMo] Scale must be between 0.0 (exclusive) and 1.0 (exclusive). Got: %.2f" % scale)
		return

	_kill_tween()
	_active = true
	_target_scale = scale

	if duration > 0.0:
		_timed = true
		_duration_timer = duration
	else:
		_timed = false

	# Smooth ramp into slow motion
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_time_scale, Engine.time_scale, scale, ramp_in) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await _tween.finished

	EventBus.slow_motion_activated.emit(scale)
	print("[SlowMo] Activated: scale=%.2f, duration=%.1fs" % [scale, duration])


## Smoothly deactivate slow motion, returning to normal speed.
func deactivate(ramp_out: float = 0.5) -> void:
	if not _active:
		return

	_kill_tween()
	_active = false
	_timed = false
	_target_scale = 1.0

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_time_scale, Engine.time_scale, 1.0, ramp_out) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	await _tween.finished

	EventBus.slow_motion_deactivated.emit()
	print("[SlowMo] Deactivated — normal speed restored.")


## Instant snap to a time scale (no smooth transition). Use sparingly.
func set_immediate(scale: float) -> void:
	_kill_tween()
	_set_time_scale(scale)
	_active = scale < 1.0
	_target_scale = scale
	if _active:
		EventBus.slow_motion_activated.emit(scale)
		print("[SlowMo] Immediate set: scale=%.2f" % scale)
	else:
		EventBus.slow_motion_deactivated.emit()
		print("[SlowMo] Immediate reset to normal.")


## Returns true if slow motion is active.
func is_active() -> bool:
	return _active


## Returns the current time scale.
func get_current_scale() -> float:
	return Engine.time_scale


## Force-reset everything to normal. Safety method for cinematic cleanup.
func force_reset() -> void:
	_kill_tween()
	_active = false
	_timed = false
	_target_scale = 1.0
	Engine.time_scale = 1.0
	_adjust_audio_pitch(1.0)
	print("[SlowMo] Force reset.")


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Set both time scale and audio pitch together.
func _set_time_scale(scale: float) -> void:
	Engine.time_scale = scale
	_adjust_audio_pitch(scale)


## Adjust global audio pitch to match time scale for cinematic effect.
## This prevents audio from sounding unnaturally fast/slow during slo-mo.
func _adjust_audio_pitch(scale: float) -> void:
	# Adjust the pitch on the master bus to match time scale.
	# This gives that classic slow-mo deep audio effect.
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index == -1:
		return

	# We look for an AudioEffectPitchShift on the Master bus.
	# If one exists, adjust its pitch_scale. If not, we skip —
	# the project can add one when slow-mo audio is desired.
	for i in range(AudioServer.get_bus_effect_count(bus_index)):
		var effect := AudioServer.get_bus_effect(bus_index, i)
		if effect is AudioEffectPitchShift:
			effect.pitch_scale = clampf(scale, 0.5, 1.0)
			return


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
