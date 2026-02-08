## Procedural engine sound synthesizer using AudioStreamGenerator.
## Produces a multi-harmonic tone driven by RPM and throttle, with
## turbo whine, blow-off valve pops, exhaust crackle, and gear-shift
## transients.  Attach as a child of VehicleController (or any Node3D).
##
## Uses AudioStreamPlayer3D for spatial positioning in the 3D world.
## The generator writes raw PCM samples each frame via a push-buffer.
class_name EngineAudio
extends AudioStreamPlayer3D

# ── Tuning Constants ─────────────────────────────────────────────────
const RPM_IDLE := 800.0
const RPM_REDLINE := 8000.0
const SAMPLE_RATE := 22050.0   ## Low rate = retro feel + cheap to fill
const BUFFER_LENGTH := 0.05     ## Seconds of audio to push per frame

## Fundamental frequency range mapped from RPM.
## Idle ~55 Hz (A1-ish), redline ~220 Hz (A3).
const FREQ_IDLE := 55.0
const FREQ_REDLINE := 220.0

## Harmonic amplitudes (relative to fundamental).
## These give the engine its "character".  Index 0 = fundamental.
const HARMONICS: Array[float] = [1.0, 0.5, 0.35, 0.15, 0.08, 0.04]

## Volume range in dB
const VOL_IDLE_DB := -18.0
const VOL_FULL_DB := 0.0

# ── Turbo ────────────────────────────────────────────────────────────
const TURBO_ONSET_RPM := 3500.0        ## Turbo starts spooling here
const TURBO_FREQ_MIN := 2000.0         ## Hz — low whistle
const TURBO_FREQ_MAX := 6000.0         ## Hz — high whine at full boost
const TURBO_AMPLITUDE := 0.12          ## Relative to engine fundamental
const BLOWOFF_DURATION := 0.25         ## Seconds of blow-off noise burst

# ── Exhaust Crackle ──────────────────────────────────────────────────
const CRACKLE_PROBABILITY := 0.15      ## Per-sample chance during decel
const CRACKLE_DECAY := 0.92            ## How fast each pop fades
const CRACKLE_THROTTLE_THRESHOLD := 0.1

# ── Internal State ───────────────────────────────────────────────────
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null

var _current_rpm: float = RPM_IDLE
var _target_rpm: float = RPM_IDLE
var _throttle: float = 0.0
var _phase: float = 0.0              ## Main oscillator phase [0, TAU)
var _turbo_phase: float = 0.0
var _turbo_boost: float = 0.0        ## 0-1 normalized boost level
var _blowoff_timer: float = 0.0      ## > 0 while blow-off is active
var _was_high_boost: bool = false
var _crackle_amplitude: float = 0.0  ## Decaying pop amplitude
var _is_decelerating: bool = false

## Gear shift transient
var _shift_transient_timer: float = 0.0
var _shift_direction: int = 0  ## 1=up, -1=down
const SHIFT_TRANSIENT_DURATION := 0.08

## Connected vehicle reference (optional — can also drive via signals)
var _vehicle: VehicleController = null

# ── Preloaded SFX (optional file-based sounds mixed in) ─────────────
## These are optional .wav/.ogg that layer on top of the synth.
var _blowoff_stream: AudioStream = null
var _shift_up_stream: AudioStream = null
var _shift_down_stream: AudioStream = null

# One-shot player for layered file-based SFX
var _oneshot_player: AudioStreamPlayer3D = null


# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	bus = "Engine"

	# Create the generator stream
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = SAMPLE_RATE
	_generator.buffer_length = BUFFER_LENGTH * 4.0  # Some headroom
	stream = _generator

	# One-shot player for file-based layered sounds
	_oneshot_player = AudioStreamPlayer3D.new()
	_oneshot_player.bus = "Engine"
	_oneshot_player.name = "EngineOneShot"
	add_child(_oneshot_player)

	# Try to load optional file-based SFX
	_blowoff_stream = _try_load("res://assets/audio/engine/turbo_blowoff.ogg")
	_shift_up_stream = _try_load("res://assets/audio/engine/shift_up.ogg")
	_shift_down_stream = _try_load("res://assets/audio/engine/shift_down.ogg")

	# Connect EventBus signals
	EventBus.gear_shifted.connect(_on_gear_shifted)
	EventBus.nitro_activated.connect(_on_nitro_activated)
	EventBus.nitro_depleted.connect(_on_nitro_depleted)

	# Auto-detect parent VehicleController
	if get_parent() is VehicleController:
		_vehicle = get_parent() as VehicleController
		print("[Engine] Attached to VehicleController: %s" % _vehicle.name)

	play()
	# Need one frame for the playback object to become available
	await get_tree().process_frame
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		print("[Engine] WARNING — could not get generator playback.")
	else:
		print("[Engine] Procedural engine synth started (%.0f Hz sample rate)." % SAMPLE_RATE)


func _process(delta: float) -> void:
	_read_vehicle_state()
	_update_turbo(delta)
	_update_blowoff(delta)
	_update_crackle(delta)
	_update_shift_transient(delta)
	_fill_audio_buffer()


# ═════════════════════════════════════════════════════════════════════
#  Vehicle State Reading
# ═════════════════════════════════════════════════════════════════════

func _read_vehicle_state() -> void:
	if _vehicle == null:
		return
	_target_rpm = _vehicle.current_rpm
	_throttle = _vehicle.input_throttle
	_is_decelerating = _throttle < CRACKLE_THROTTLE_THRESHOLD and _current_rpm > 2000.0

	# Smoothly approach target RPM (prevents audio pops on sudden changes)
	_current_rpm = lerpf(_current_rpm, _target_rpm, 0.15)

	# Emit RPM signal for other systems
	EventBus.engine_rpm_updated.emit(0, _current_rpm, _throttle)


## Allow external systems to drive the engine sound without a VehicleController.
func set_rpm_and_throttle(rpm: float, throttle: float) -> void:
	_target_rpm = clampf(rpm, RPM_IDLE, RPM_REDLINE)
	_throttle = clampf(throttle, 0.0, 1.0)
	_is_decelerating = _throttle < CRACKLE_THROTTLE_THRESHOLD and _current_rpm > 2000.0
	_current_rpm = lerpf(_current_rpm, _target_rpm, 0.15)


# ═════════════════════════════════════════════════════════════════════
#  Turbo Simulation
# ═════════════════════════════════════════════════════════════════════

func _update_turbo(delta: float) -> void:
	## Turbo boost ramps up above TURBO_ONSET_RPM when throttle is applied.
	var target_boost := 0.0
	if _current_rpm > TURBO_ONSET_RPM and _throttle > 0.3:
		var rpm_factor := clampf(
			(_current_rpm - TURBO_ONSET_RPM) / (RPM_REDLINE - TURBO_ONSET_RPM),
			0.0, 1.0
		)
		target_boost = rpm_factor * _throttle

	# Spool up/down rates (spool-up is slower than spool-down for realism)
	var rate := 2.0 if target_boost > _turbo_boost else 5.0
	_turbo_boost = move_toward(_turbo_boost, target_boost, rate * delta)

	# Detect blow-off: sudden throttle lift while boost is high
	if _was_high_boost and _throttle < 0.15 and _turbo_boost > 0.3:
		_trigger_blowoff()
	_was_high_boost = _turbo_boost > 0.5


func _trigger_blowoff() -> void:
	_blowoff_timer = BLOWOFF_DURATION
	EventBus.turbo_blowoff.emit(0)
	print("[Engine] Turbo blow-off!")

	# Play file-based blow-off if available
	if _blowoff_stream and _oneshot_player:
		_oneshot_player.stream = _blowoff_stream
		_oneshot_player.play()


func _update_blowoff(delta: float) -> void:
	if _blowoff_timer > 0.0:
		_blowoff_timer = maxf(_blowoff_timer - delta, 0.0)


# ═════════════════════════════════════════════════════════════════════
#  Exhaust Crackle / Pop
# ═════════════════════════════════════════════════════════════════════

func _update_crackle(_delta: float) -> void:
	## Crackle amplitude decays each frame; new pops are injected
	## per-sample in _fill_audio_buffer when decelerating.
	_crackle_amplitude *= CRACKLE_DECAY
	if _is_decelerating and _crackle_amplitude < 0.01:
		# Chance to fire a new crackle burst
		if randf() < 0.08:
			_crackle_amplitude = randf_range(0.15, 0.4)
			EventBus.exhaust_pop.emit(0)


# ═════════════════════════════════════════════════════════════════════
#  Gear Shift Transient
# ═════════════════════════════════════════════════════════════════════

func _update_shift_transient(delta: float) -> void:
	if _shift_transient_timer > 0.0:
		_shift_transient_timer = maxf(_shift_transient_timer - delta, 0.0)


func _on_gear_shifted(vehicle_id: int, gear: int) -> void:
	_shift_transient_timer = SHIFT_TRANSIENT_DURATION

	# Determine shift direction from gear number change
	# (We don't track old gear here, so use a heuristic based on RPM drop)
	if _current_rpm > RPM_REDLINE * 0.8:
		_shift_direction = 1  # Upshift (RPM was near redline)
	else:
		_shift_direction = -1  # Downshift

	# Play file-based shift sound if available
	if _shift_direction > 0 and _shift_up_stream:
		_oneshot_player.stream = _shift_up_stream
		_oneshot_player.play()
	elif _shift_direction < 0 and _shift_down_stream:
		_oneshot_player.stream = _shift_down_stream
		_oneshot_player.play()


func _on_nitro_activated(_vehicle_id: int) -> void:
	## Boost the engine volume slightly when nitro kicks in.
	volume_db = minf(volume_db + 3.0, VOL_FULL_DB + 3.0)


func _on_nitro_depleted(_vehicle_id: int) -> void:
	## Restore normal volume range.
	pass  # Volume is recalculated each buffer fill anyway


# ═════════════════════════════════════════════════════════════════════
#  Audio Buffer Generation  (the core synthesizer)
# ═════════════════════════════════════════════════════════════════════

func _fill_audio_buffer() -> void:
	if _playback == null:
		return

	var frames_available := _playback.get_frames_available()
	if frames_available <= 0:
		return

	# Pre-compute per-buffer values
	var rpm_t := clampf(
		(_current_rpm - RPM_IDLE) / (RPM_REDLINE - RPM_IDLE),
		0.0, 1.0
	)
	var base_freq := lerpf(FREQ_IDLE, FREQ_REDLINE, rpm_t)

	# Volume: louder with RPM and throttle
	var vol_t := clampf(rpm_t * 0.6 + _throttle * 0.4, 0.0, 1.0)
	var amplitude := lerpf(0.15, 0.7, vol_t)

	# Adjust volume_db on the player node
	volume_db = lerpf(VOL_IDLE_DB, VOL_FULL_DB, vol_t)

	# Turbo whine frequency
	var turbo_freq := lerpf(TURBO_FREQ_MIN, TURBO_FREQ_MAX, _turbo_boost)
	var turbo_amp := TURBO_AMPLITUDE * _turbo_boost

	# Phase increments per sample
	var phase_inc := base_freq / SAMPLE_RATE * TAU
	var turbo_phase_inc := turbo_freq / SAMPLE_RATE * TAU

	# Shift transient: brief silence/dip simulating clutch cut
	var shift_mute := 1.0
	if _shift_transient_timer > 0.0:
		var t := _shift_transient_timer / SHIFT_TRANSIENT_DURATION
		if _shift_direction > 0:
			# Upshift: brief dip then recovery
			shift_mute = 0.2 + 0.8 * (1.0 - t)
		else:
			# Downshift: rev blip (slight volume spike)
			shift_mute = 1.0 + 0.3 * t

	for i: int in range(frames_available):
		var sample := 0.0

		# --- Multi-harmonic engine tone ---
		for h: int in range(HARMONICS.size()):
			var harmonic_num := float(h + 1)
			var harmonic_amp: float = HARMONICS[h]

			# Odd harmonics slightly louder at high RPM for aggressive tone
			if h % 2 == 0 and rpm_t > 0.5:
				harmonic_amp *= 1.0 + (rpm_t - 0.5) * 0.6

			sample += sin(_phase * harmonic_num) * harmonic_amp

		# Normalize by sum of harmonic weights
		sample *= amplitude / 2.2

		# --- Turbo whine (sine with slight FM wobble) ---
		if _turbo_boost > 0.05:
			var wobble := sin(_turbo_phase * 0.1) * 0.02
			sample += sin(_turbo_phase + wobble) * turbo_amp

		# --- Blow-off valve (filtered noise burst) ---
		if _blowoff_timer > 0.0:
			var blowoff_env := _blowoff_timer / BLOWOFF_DURATION
			# Descending pitch noise
			var noise := (randf() * 2.0 - 1.0) * 0.35 * blowoff_env
			sample += noise

		# --- Exhaust crackle (random noise pops during decel) ---
		if _is_decelerating and _crackle_amplitude > 0.01:
			if randf() < CRACKLE_PROBABILITY:
				sample += (randf() * 2.0 - 1.0) * _crackle_amplitude
			_crackle_amplitude *= CRACKLE_DECAY

		# --- Shift transient ---
		sample *= shift_mute

		# Soft clip to prevent harsh distortion
		sample = _soft_clip(sample)

		# Push stereo frame (same value both channels for mono-ish engine)
		_playback.push_frame(Vector2(sample, sample))

		# Advance phases
		_phase = fmod(_phase + phase_inc, TAU)
		_turbo_phase = fmod(_turbo_phase + turbo_phase_inc, TAU)


func _soft_clip(x: float) -> float:
	## Attempt a warm, tube-like saturation curve.
	if x > 1.0:
		return 1.0
	elif x < -1.0:
		return -1.0
	return x - (x * x * x) / 3.0


# ═════════════════════════════════════════════════════════════════════
#  Utility
# ═════════════════════════════════════════════════════════════════════

func _try_load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is AudioStream:
			return res as AudioStream
	return null
