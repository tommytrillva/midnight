## Full AI racer controller with path-following, lookahead steering, corner
## detection, rubber banding, and difficulty scaling. Communicates through
## EventBus signals and RaceManager checkpoint/finish reporting.
##
## Replaces the previous race_ai.gd stub with complete driving behavior.
## Designed to be instantiated from scenes/racing/ai_racer.tscn.
class_name RaceAI
extends CharacterBody3D

## Named difficulty presets mapped from the continuous 0.0-1.0 scale.
enum DifficultyLevel { EASY, MEDIUM, HARD, EXPERT }

# ===========================================================================
# Exported properties — set by RaceSession before add_child()
# ===========================================================================

## Continuous difficulty from RaceData.ai_difficulty (0.0 = easy, 1.0 = expert).
@export var difficulty: float = 0.5
## The Path3D racing line this AI follows.
@export var path: Path3D = null
## Unique identifier matching the RacerState in RaceManager.
@export var racer_id: int = 1
## Display name shown in HUD and results.
@export var display_name: String = "AI Racer"

# ===========================================================================
# Difficulty-scaled parameters (computed in _apply_difficulty)
# ===========================================================================

var _max_speed: float = 20.0           # m/s top speed on straights
var _acceleration: float = 10.0        # m/s^2 throttle response
var _braking_decel: float = 15.0       # m/s^2 braking for corners
var _line_accuracy: float = 0.8        # 0-1 how tightly AI follows ideal line
var _reaction_delay: float = 0.2       # seconds of latency reacting to corners
var _rubber_band_strength: float = 0.3 # how aggressively speed adjusts to player gap
var _lookahead_dist: float = 12.0      # meters ahead on curve to steer toward
var _corner_min_speed: float = 0.4     # fraction of max speed kept in sharpest corner
var _speed_noise_amp: float = 3.0      # m/s amplitude of natural speed oscillation

# ===========================================================================
# Racing state
# ===========================================================================

var _current_speed: float = 0.0        # actual movement speed in m/s
var _path_offset: float = 0.0          # meters along curve (monotonic across laps)
var _path_length: float = 0.0          # baked length of one lap on the curve
var _progress: float = 0.0             # 0.0-1.0 overall race progress
var _is_racing: bool = false
var _is_finished: bool = false
var _gravity_vel: float = 0.0          # accumulated downward velocity when airborne

# ===========================================================================
# Rubber banding
# ===========================================================================

var _player_progress: float = 0.0
var _speed_multiplier: float = 1.0

# ===========================================================================
# Checkpoint and finish tracking
# ===========================================================================

var _next_checkpoint_idx: int = 0
var _checkpoint_offsets: PackedFloat64Array = PackedFloat64Array()
var _total_checkpoints: int = 0
var _finish_offset: float = 0.0

# ===========================================================================
# Circuit / lap tracking
# ===========================================================================

var _is_circuit: bool = false
var _lap_count: int = 1
var _current_lap: int = 0

# ===========================================================================
# Reaction delay state
# ===========================================================================

var _target_speed: float = 0.0
var _delayed_speed: float = 0.0

# ===========================================================================
# Constants
# ===========================================================================

const GRAVITY: float = 9.8
const GRAVITY_MAX: float = 30.0
## Meters between forward samples when detecting curvature.
const CURVE_SAMPLE_SPACING: float = 5.0
## Number of forward samples for corner detection.
const CURVE_SAMPLE_COUNT: int = 5
## Distance (m) from ideal line at which path correction reaches full weight.
const PATH_CORRECTION_RANGE: float = 5.0
## Speed of vertical interpolation toward path height.
const HEIGHT_TRACK_SPEED: float = 8.0
## If the AI falls this far below the path, teleport recovery fires.
const RECOVERY_FALL_THRESHOLD: float = 15.0

## Preset per-slot racer colours applied at runtime to the mesh material.
const SLOT_COLORS := [
	Color(0.9, 0.15, 0.15),   # Slot 1 — Red
	Color(0.15, 0.2, 0.9),    # Slot 2 — Blue
	Color(0.1, 0.75, 0.2),    # Slot 3 — Green
	Color(0.95, 0.55, 0.1),   # Slot 4 — Orange
	Color(0.65, 0.15, 0.8),   # Slot 5 — Purple
	Color(0.1, 0.8, 0.75),    # Slot 6 — Cyan
	Color(0.9, 0.85, 0.1),    # Slot 7 — Yellow
	Color(0.85, 0.2, 0.55),   # Slot 8 — Pink
]

# ===========================================================================
# Lifecycle
# ===========================================================================

func _ready() -> void:
	_apply_difficulty()
	_apply_racer_color()

	EventBus.race_started.connect(_on_race_started)
	EventBus.race_countdown_tick.connect(_on_countdown_tick)

	print("[AIRacer] %s (ID:%d) initialized — difficulty %.2f (%s)" % [
		display_name,
		racer_id,
		difficulty,
		DifficultyLevel.keys()[difficulty_to_level(difficulty)],
	])


func _exit_tree() -> void:
	if EventBus.race_started.is_connected(_on_race_started):
		EventBus.race_started.disconnect(_on_race_started)
	if EventBus.race_countdown_tick.is_connected(_on_countdown_tick):
		EventBus.race_countdown_tick.disconnect(_on_countdown_tick)


func _physics_process(delta: float) -> void:
	if _is_finished:
		_coast_to_stop(delta)
		return

	if not _is_racing:
		# Idle: only apply gravity so the car sits on the ground at the grid.
		_apply_gravity(delta)
		velocity = Vector3(0.0, -_gravity_vel, 0.0)
		move_and_slide()
		return

	_poll_player_progress()
	_update_rubber_banding()
	_calculate_target_speed()
	_apply_reaction_delay(delta)
	_update_current_speed(delta)
	_advance_path_offset(delta)
	_steer_and_move(delta)
	_check_checkpoints()
	_check_finish()
	_sync_racer_progress()

# ===========================================================================
# Setup — called by RaceSession after the node is in the tree and positioned
# ===========================================================================

func setup_track(track: RaceTrack) -> void:
	## Provide track context so the AI can track checkpoints and finish.
	_is_circuit = track.is_circuit
	_lap_count = track.lap_count
	_init_path()
	_compute_checkpoint_offsets(track)
	print("[AIRacer] %s track ready — %d CPs, finish at %.1f / %.1f m, circuit=%s, laps=%d" % [
		display_name,
		_total_checkpoints,
		_finish_offset,
		_path_length,
		_is_circuit,
		_lap_count,
	])

# ===========================================================================
# Internal setup helpers
# ===========================================================================

func _apply_difficulty() -> void:
	## Lerp every tuning parameter between its easy and expert bounds.
	_max_speed = lerpf(14.0, 30.0, difficulty)
	_acceleration = lerpf(6.0, 18.0, difficulty)
	_braking_decel = lerpf(10.0, 24.0, difficulty)
	_line_accuracy = lerpf(0.55, 1.0, difficulty)
	_reaction_delay = lerpf(0.55, 0.0, difficulty)
	_rubber_band_strength = lerpf(0.45, 0.08, difficulty)
	_lookahead_dist = lerpf(8.0, 22.0, difficulty)
	_corner_min_speed = lerpf(0.3, 0.65, difficulty)
	_speed_noise_amp = lerpf(4.0, 1.0, difficulty)


func _init_path() -> void:
	## Cache path length and compute starting offset from current position.
	if path == null or path.curve == null:
		push_warning("[AIRacer] %s — no path assigned." % display_name)
		return
	_path_length = path.curve.get_baked_length()
	_path_offset = path.curve.get_closest_offset(
		path.to_local(global_position)
	)
	_path_offset = maxf(_path_offset, 0.0)


func _compute_checkpoint_offsets(track: RaceTrack) -> void:
	## Project every checkpoint and the finish line onto the curve to get
	## their offsets in meters. Used for self-reporting to RaceManager.
	_checkpoint_offsets = PackedFloat64Array()

	for cp: Area3D in track.checkpoints:
		var local_pos := path.to_local(cp.global_position)
		var offset := path.curve.get_closest_offset(local_pos)
		_checkpoint_offsets.append(offset)

	_total_checkpoints = _checkpoint_offsets.size()

	if track.finish_line:
		var fin_local := path.to_local(track.finish_line.global_position)
		_finish_offset = path.curve.get_closest_offset(fin_local)
	else:
		# Fallback: treat 98 % of path length as the finish.
		_finish_offset = _path_length * 0.98


func _apply_racer_color() -> void:
	## Set a unique material colour on the mesh based on racer slot.
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var idx := (racer_id - 1) % SLOT_COLORS.size()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SLOT_COLORS[idx]
	mat.roughness = 0.35
	mat.metallic = 0.45
	mesh.material_override = mat

# ===========================================================================
# Per-frame racing logic
# ===========================================================================

func _poll_player_progress() -> void:
	for racer in GameManager.race_manager.racers:
		if racer.is_player:
			_player_progress = racer.progress
			return


func _update_rubber_banding() -> void:
	## Adjust _speed_multiplier so the AI speeds up when behind and eases off
	## when ahead. Strength is scaled by difficulty (easier = stronger band).
	var gap := _player_progress - _progress
	if absf(gap) < 0.02:
		_speed_multiplier = 1.0
	elif gap > 0.0:
		# Player is ahead — AI speeds up.
		_speed_multiplier = 1.0 + gap * _rubber_band_strength * 5.0
	else:
		# AI is ahead — AI eases off (weaker effect).
		_speed_multiplier = 1.0 + gap * _rubber_band_strength * 2.5
	_speed_multiplier = clampf(_speed_multiplier, 0.7, 1.45)


func _calculate_target_speed() -> void:
	## Determine the ideal speed considering rubber banding, corners, and
	## natural variation.
	var base := _max_speed * _speed_multiplier

	# Scale down for upcoming curvature.
	var corner_factor := _detect_curvature_ahead()
	var cornering_speed := base * corner_factor

	# Natural per-racer speed oscillation so AI doesn't feel robotic.
	var noise := sinf(
		Time.get_ticks_msec() * 0.001 + float(racer_id) * 2.71
	) * _speed_noise_amp

	_target_speed = maxf(cornering_speed + noise, 3.0)


func _detect_curvature_ahead() -> float:
	## Sample the curve ahead of the current position and return a speed
	## factor in [_corner_min_speed, 1.0].  1.0 = straight road,
	## _corner_min_speed = sharpest detectable corner.
	if path == null or _path_length <= 0.0:
		return 1.0

	var base_ofs := _get_curve_offset()
	var worst_angle := 0.0
	var prev_dir := Vector3.ZERO

	for i in range(CURVE_SAMPLE_COUNT + 1):
		var ofs_a := base_ofs + float(i) * CURVE_SAMPLE_SPACING
		var ofs_b := ofs_a + CURVE_SAMPLE_SPACING

		ofs_a = _wrap_or_clamp_offset(ofs_a)
		ofs_b = _wrap_or_clamp_offset(ofs_b)

		var pa := path.curve.sample_baked(ofs_a)
		var pb := path.curve.sample_baked(ofs_b)

		var seg_dir := pb - pa
		seg_dir.y = 0.0
		if seg_dir.length_squared() < 0.001:
			continue
		seg_dir = seg_dir.normalized()

		if prev_dir.length_squared() > 0.5:
			var angle := prev_dir.angle_to(seg_dir)
			worst_angle = maxf(worst_angle, angle)

		prev_dir = seg_dir

	# Map worst detected angle to a 0-1 sharpness value.  Angles above
	# ~35 degrees between 5 m segments are treated as maximum sharpness.
	var sharpness := clampf(worst_angle / deg_to_rad(35.0), 0.0, 1.0)
	return lerpf(1.0, _corner_min_speed, sharpness)


func _apply_reaction_delay(delta: float) -> void:
	## Smoothly converge _delayed_speed toward _target_speed based on the
	## difficulty-dependent reaction delay.  Easier AI reacts later to corners.
	if _reaction_delay < 0.001:
		_delayed_speed = _target_speed
		return
	var rate := 1.0 / maxf(_reaction_delay, 0.01)
	_delayed_speed = lerpf(_delayed_speed, _target_speed, rate * delta)


func _update_current_speed(delta: float) -> void:
	## Accelerate or brake toward the delayed target speed.
	if _delayed_speed > _current_speed:
		_current_speed = move_toward(
			_current_speed, _delayed_speed, _acceleration * delta
		)
	else:
		_current_speed = move_toward(
			_current_speed, _delayed_speed, _braking_decel * delta
		)


func _advance_path_offset(delta: float) -> void:
	## Move the abstract position along the curve by current speed.
	_path_offset += _current_speed * delta

	if not _is_circuit:
		_path_offset = minf(_path_offset, _path_length)

	# Compute overall progress [0, 1] for RaceManager position sorting.
	if _path_length > 0.0:
		if _is_circuit and _lap_count > 0:
			var total_dist := _path_length * float(_lap_count)
			_progress = clampf(_path_offset / total_dist, 0.0, 1.0)
		else:
			_progress = clampf(_path_offset / _path_length, 0.0, 1.0)


func _steer_and_move(delta: float) -> void:
	## Core movement: steer toward the lookahead point on the curve, correct
	## drift from the ideal line, apply height tracking, and move_and_slide.
	if path == null or path.curve == null:
		_apply_gravity(delta)
		velocity = Vector3(0.0, -_gravity_vel, 0.0)
		move_and_slide()
		return

	var curve_ofs := _get_curve_offset()

	# Where we should be on the path right now.
	var path_pos := path.to_global(path.curve.sample_baked(curve_ofs))

	# Where we are steering toward (ahead on the curve).
	var look_ofs := _wrap_or_clamp_offset(curve_ofs + _lookahead_dist)
	var look_pos := path.to_global(path.curve.sample_baked(look_ofs))

	# --- Horizontal steering -------------------------------------------
	var to_path := path_pos - global_position
	to_path.y = 0.0
	var to_look := look_pos - global_position
	to_look.y = 0.0

	var off_track := to_path.length()
	var correction := clampf(off_track / PATH_CORRECTION_RANGE, 0.0, 0.7)

	var steer_dir := _blend_steering(to_path, to_look, correction, curve_ofs, path_pos)

	# Line-accuracy wobble: less accurate AI swerves slightly.
	if _line_accuracy < 1.0:
		var wobble_rad := (1.0 - _line_accuracy) * 0.18
		var noise_angle := sinf(
			Time.get_ticks_msec() * 0.002 + float(racer_id) * 1.93
		) * wobble_rad
		steer_dir = steer_dir.rotated(Vector3.UP, noise_angle)

	# --- Build horizontal velocity -------------------------------------
	velocity.x = steer_dir.x * _current_speed
	velocity.z = steer_dir.z * _current_speed

	# --- Vertical: track path height with gravity ----------------------
	var target_y := path_pos.y
	var y_diff := target_y - global_position.y

	if is_on_floor():
		_gravity_vel = 0.0
		if y_diff > 0.2:
			# Uphill or ramp — push upward to follow the path.
			velocity.y = y_diff * HEIGHT_TRACK_SPEED
		else:
			velocity.y = 0.0
	else:
		# Airborne: blend path-height tracking with gravity.
		_gravity_vel = minf(_gravity_vel + GRAVITY * delta, GRAVITY_MAX)
		velocity.y = y_diff * HEIGHT_TRACK_SPEED - _gravity_vel

	# --- Recovery from catastrophic fall --------------------------------
	if global_position.y < path_pos.y - RECOVERY_FALL_THRESHOLD:
		global_position = path_pos + Vector3.UP * 1.5
		_gravity_vel = 0.0
		print("[AIRacer] %s recovered from fall." % display_name)

	move_and_slide()

	# --- Smooth rotation toward movement direction ----------------------
	_rotate_toward_velocity(delta)


func _blend_steering(
	to_path: Vector3,
	to_look: Vector3,
	correction: float,
	curve_ofs: float,
	path_pos: Vector3,
) -> Vector3:
	## Blend path-correction and lookahead vectors into a single horizontal
	## steering direction.  Falls back to the path tangent when both are zero.
	var has_look := to_look.length_squared() > 0.001
	var has_path := to_path.length_squared() > 0.001

	if has_look and has_path:
		return (
			to_path.normalized() * correction
			+ to_look.normalized() * (1.0 - correction)
		).normalized()
	if has_look:
		return to_look.normalized()
	if has_path:
		return to_path.normalized()

	# Both are zero — use the path tangent as fallback direction.
	var tangent_ofs := _wrap_or_clamp_offset(curve_ofs + 0.5)
	var tangent_pos := path.to_global(path.curve.sample_baked(tangent_ofs))
	var t := tangent_pos - path_pos
	t.y = 0.0
	if t.length_squared() > 0.001:
		return t.normalized()

	# Absolute fallback: current forward direction.
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func _rotate_toward_velocity(delta: float) -> void:
	## Smoothly orient the body to face the horizontal movement direction
	## using spherical linear interpolation.
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length_squared() < 0.25:
		return

	var desired := flat_vel.normalized()
	var current_fwd := -global_transform.basis.z
	current_fwd.y = 0.0

	if current_fwd.length_squared() < 0.01:
		look_at(global_position + desired, Vector3.UP)
		return

	var current_n := current_fwd.normalized()

	# If nearly opposite, snap immediately to avoid slerp singularity.
	if current_n.dot(desired) < -0.99:
		look_at(global_position + desired, Vector3.UP)
		return

	var smoothed := current_n.slerp(desired, minf(8.0 * delta, 1.0))
	if smoothed.length_squared() > 0.001:
		look_at(global_position + smoothed, Vector3.UP)

# ===========================================================================
# Checkpoint and finish detection (offset-based, no Area3D needed)
# ===========================================================================

func _check_checkpoints() -> void:
	if _next_checkpoint_idx >= _total_checkpoints:
		return

	# Absolute offset of next checkpoint, accounting for current lap.
	var cp_absolute := _checkpoint_offsets[_next_checkpoint_idx]
	if _is_circuit:
		cp_absolute += float(_current_lap) * _path_length

	if _path_offset >= cp_absolute:
		GameManager.race_manager.report_checkpoint(racer_id, _next_checkpoint_idx)
		print("[AIRacer] %s passed checkpoint %d" % [
			display_name, _next_checkpoint_idx,
		])
		_next_checkpoint_idx += 1


func _check_finish() -> void:
	if _is_finished:
		return
	# Must have cleared all checkpoints for this lap.
	if _next_checkpoint_idx < _total_checkpoints:
		return

	var finish_absolute := _finish_offset
	if _is_circuit:
		finish_absolute += float(_current_lap) * _path_length

	if _path_offset >= finish_absolute:
		if _is_circuit and _current_lap < _lap_count - 1:
			# Lap completed — not the final one.
			_current_lap += 1
			_next_checkpoint_idx = 0
			GameManager.race_manager.report_lap(racer_id)
			print("[AIRacer] %s completed lap %d / %d" % [
				display_name, _current_lap, _lap_count,
			])
		else:
			# Race finished.
			_is_finished = true
			_is_racing = false
			GameManager.race_manager.report_finish(racer_id)
			print("[AIRacer] %s FINISHED the race." % display_name)


func _sync_racer_progress() -> void:
	## Push our progress into the RaceManager so position sorting works.
	for racer in GameManager.race_manager.racers:
		if racer.racer_id == racer_id:
			racer.progress = _progress
			return

# ===========================================================================
# Post-race: coast to a stop
# ===========================================================================

func _coast_to_stop(delta: float) -> void:
	_current_speed = move_toward(_current_speed, 0.0, _braking_decel * 0.5 * delta)
	if _current_speed < 0.1:
		_current_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
	else:
		_advance_path_offset(delta)
		_steer_and_move(delta)

# ===========================================================================
# Signal handlers
# ===========================================================================

func _on_race_started(_race_data: Dictionary) -> void:
	_is_racing = true
	_is_finished = false
	_current_speed = 0.0
	_delayed_speed = 0.0
	print("[AIRacer] %s — GO!" % display_name)


func _on_countdown_tick(_count: int) -> void:
	# Placeholder for engine-rev animation / audio during countdown.
	pass

# ===========================================================================
# Utility
# ===========================================================================

func _get_curve_offset() -> float:
	## Returns the offset within one lap, suitable for curve sampling.
	if _is_circuit and _path_length > 0.0:
		return fmod(_path_offset, _path_length)
	return clampf(_path_offset, 0.0, _path_length)


func _wrap_or_clamp_offset(raw: float) -> float:
	## Wrap on circuits, clamp on point-to-point.
	if _is_circuit and _path_length > 0.0:
		return fmod(raw, _path_length)
	return clampf(raw, 0.0, _path_length)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		_gravity_vel = 0.0
	else:
		_gravity_vel = minf(_gravity_vel + GRAVITY * delta, GRAVITY_MAX)


## Convert the continuous difficulty float to a named preset.
static func difficulty_to_level(diff: float) -> DifficultyLevel:
	if diff < 0.25:
		return DifficultyLevel.EASY
	elif diff < 0.5:
		return DifficultyLevel.MEDIUM
	elif diff < 0.75:
		return DifficultyLevel.HARD
	return DifficultyLevel.EXPERT


## Current speed in km/h — useful for HUD or debug overlays.
func get_speed_kmh() -> float:
	return _current_speed * 3.6
