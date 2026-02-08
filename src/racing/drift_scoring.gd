## Drift competition scoring system.
## Tracks drift angle, duration, speed, combos, zone bonuses, near-miss style points,
## and assigns per-section ranks (D/C/B/A/S). Integrates with VehicleController drift state
## and EventBus drift signals.
class_name DriftScoring
extends Node

# --- Scoring Tuning ---
## Points per degree of drift angle per second at 100 km/h baseline.
const BASE_POINTS_PER_DEG_SEC := 10.0
## Speed baseline for normalization (km/h). Scoring scales linearly above/below this.
const SPEED_BASELINE := 100.0
## Minimum drift angle (degrees) to count as actively drifting.
const MIN_DRIFT_ANGLE := 15.0
## Maximum drift angle before it counts as a spin-out and breaks combo.
const MAX_DRIFT_ANGLE := 120.0
## Seconds of non-drift before combo resets.
const COMBO_GRACE_PERIOD := 1.0
## Maximum combo multiplier cap.
const MAX_COMBO_MULTIPLIER := 8.0
## Distance (meters) threshold for near-miss wall bonus.
const NEAR_MISS_DISTANCE := 2.0
## Bonus points for a near-miss event.
const NEAR_MISS_BONUS := 500.0
## How close to a wall for maximum near-miss points (meters).
const NEAR_MISS_PERFECT_DISTANCE := 0.5
## Zone multiplier added on top of combo when inside a drift zone.
const DEFAULT_ZONE_MULTIPLIER := 1.5

# --- Section Rank Thresholds ---
## Score thresholds per section for rank assignment.
const RANK_THRESHOLDS := {
	"S": 50000.0,
	"A": 30000.0,
	"B": 15000.0,
	"C": 5000.0,
	"D": 0.0,
}

# --- State ---
var is_active: bool = false
var _vehicle: VehicleController = null

# Current drift state
var _is_in_drift: bool = false
var _drift_start_time: float = 0.0
var _current_drift_angle: float = 0.0
var _current_drift_speed: float = 0.0
var _current_drift_duration: float = 0.0
var _current_drift_points: float = 0.0

# Combo tracking
var _combo_count: int = 0
var _combo_multiplier: float = 1.0
var _combo_grace_timer: float = 0.0
var _combo_total_points: float = 0.0

# Zone tracking
var _in_drift_zone: bool = false
var _current_zone_name: String = ""
var _current_zone_multiplier: float = 1.0

# Section tracking
var _sections: Array[DriftSection] = []
var _current_section_index: int = 0
var _current_section_score: float = 0.0

# Near-miss tracking
var _wall_raycast_origins: Array[RayCast3D] = []
var _near_miss_cooldown: float = 0.0
const NEAR_MISS_COOLDOWN_TIME := 0.5

# Totals
var total_score: float = 0.0
var total_near_misses: int = 0
var total_drift_time: float = 0.0
var longest_drift_duration: float = 0.0
var highest_single_drift: float = 0.0
var section_scores: Array[float] = []
var section_ranks: Array[String] = []


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Initialize scoring for a drift race. Call after vehicle is spawned.
func activate(vehicle: VehicleController, sections: Array[DriftSection] = []) -> void:
	_vehicle = vehicle
	_sections = sections
	_current_section_index = 0
	_current_section_score = 0.0

	# Reset all state
	total_score = 0.0
	total_near_misses = 0
	total_drift_time = 0.0
	longest_drift_duration = 0.0
	highest_single_drift = 0.0
	section_scores.clear()
	section_ranks.clear()
	_combo_count = 0
	_combo_multiplier = 1.0
	_combo_grace_timer = 0.0
	_combo_total_points = 0.0
	_is_in_drift = false

	# Set up wall proximity raycasts on the vehicle
	_setup_wall_raycasts()

	is_active = true
	set_process(true)
	set_physics_process(true)
	print("[Drift] Scoring activated — %d sections defined" % _sections.size())


func deactivate() -> void:
	is_active = false
	set_process(false)
	set_physics_process(false)

	# Finalize current section if mid-drift
	if _is_in_drift:
		_end_current_drift()
	_finalize_current_section()

	print("[Drift] Scoring deactivated — Total: %.0f" % total_score)


func _process(delta: float) -> void:
	if not is_active or _vehicle == null:
		return
	_update_near_miss_cooldown(delta)


func _physics_process(delta: float) -> void:
	if not is_active or _vehicle == null:
		return
	_update_drift_state(delta)
	_check_wall_proximity()


# ---------------------------------------------------------------------------
# Drift State Machine
# ---------------------------------------------------------------------------

func _update_drift_state(delta: float) -> void:
	_current_drift_angle = _vehicle.drift_angle
	_current_drift_speed = _vehicle.current_speed_kmh

	var angle_valid := _current_drift_angle >= MIN_DRIFT_ANGLE and _current_drift_angle <= MAX_DRIFT_ANGLE
	var speed_valid := _current_drift_speed >= 30.0

	if angle_valid and speed_valid:
		if not _is_in_drift:
			_start_drift()
		_process_active_drift(delta)
	else:
		if _is_in_drift:
			# Check if spin-out (angle too high)
			if _current_drift_angle > MAX_DRIFT_ANGLE:
				_spin_out()
			else:
				_end_current_drift()

		# Combo grace period ticking
		if _combo_count > 0:
			_combo_grace_timer -= delta
			if _combo_grace_timer <= 0.0:
				_drop_combo()


func _start_drift() -> void:
	_is_in_drift = true
	_drift_start_time = Time.get_ticks_msec() / 1000.0
	_current_drift_duration = 0.0
	_current_drift_points = 0.0
	print("[Drift] Drift started — angle: %.1f° speed: %.0f km/h" % [_current_drift_angle, _current_drift_speed])


func _process_active_drift(delta: float) -> void:
	_current_drift_duration += delta
	total_drift_time += delta

	# Calculate raw points for this frame
	var speed_factor := _current_drift_speed / SPEED_BASELINE
	var angle_factor := _current_drift_angle / 45.0  # Normalize to ~1.0 at 45 degrees
	var raw_points := BASE_POINTS_PER_DEG_SEC * angle_factor * speed_factor * delta

	# Apply combo multiplier
	var effective_multiplier := _combo_multiplier

	# Apply zone multiplier if in a drift zone
	if _in_drift_zone:
		effective_multiplier *= _current_zone_multiplier

	var points := raw_points * effective_multiplier
	_current_drift_points += points
	_current_section_score += points
	total_score += points


func _end_current_drift() -> void:
	if not _is_in_drift:
		return

	_is_in_drift = false

	# Update records
	if _current_drift_duration > longest_drift_duration:
		longest_drift_duration = _current_drift_duration
	if _current_drift_points > highest_single_drift:
		highest_single_drift = _current_drift_points

	# Advance combo
	_combo_count += 1
	_combo_multiplier = minf(1.0 + (_combo_count - 1) * 0.5, MAX_COMBO_MULTIPLIER)
	_combo_grace_timer = COMBO_GRACE_PERIOD
	_combo_total_points += _current_drift_points

	EventBus.drift_combo_updated.emit(_combo_count, _combo_multiplier, _combo_total_points)

	print("[Drift] Drift ended — %.0f pts (combo x%d = %.1fx) duration: %.1fs" % [
		_current_drift_points, _combo_count, _combo_multiplier, _current_drift_duration
	])


func _spin_out() -> void:
	_is_in_drift = false
	_current_drift_points = 0.0
	print("[Drift] SPIN OUT — combo lost!")
	_drop_combo()


func _drop_combo() -> void:
	if _combo_count > 0:
		print("[Drift] Combo dropped (was x%d = %.0f pts)" % [_combo_count, _combo_total_points])
		EventBus.drift_combo_dropped.emit()
	_combo_count = 0
	_combo_multiplier = 1.0
	_combo_total_points = 0.0
	_combo_grace_timer = 0.0


# ---------------------------------------------------------------------------
# Zone Handling
# ---------------------------------------------------------------------------

## Called when player enters a designated drift zone Area3D.
func on_drift_zone_entered(zone_name: String, multiplier: float = DEFAULT_ZONE_MULTIPLIER) -> void:
	_in_drift_zone = true
	_current_zone_name = zone_name
	_current_zone_multiplier = multiplier
	EventBus.drift_zone_entered.emit(zone_name, multiplier)
	print("[Drift] Entered drift zone: %s (x%.1f)" % [zone_name, multiplier])


## Called when player exits a designated drift zone Area3D.
func on_drift_zone_exited(zone_name: String) -> void:
	if _current_zone_name == zone_name:
		_in_drift_zone = false
		_current_zone_name = ""
		_current_zone_multiplier = 1.0
		EventBus.drift_zone_exited.emit(zone_name)
		print("[Drift] Exited drift zone: %s" % zone_name)


# ---------------------------------------------------------------------------
# Section Scoring
# ---------------------------------------------------------------------------

## Call when the player crosses a section boundary (Area3D trigger).
func advance_section() -> void:
	_finalize_current_section()
	_current_section_index += 1
	_current_section_score = 0.0
	print("[Drift] Starting section %d" % _current_section_index)


func _finalize_current_section() -> void:
	var score := _current_section_score
	var rank := _calculate_rank(score)
	section_scores.append(score)
	section_ranks.append(rank)
	EventBus.drift_section_scored.emit(_current_section_index, score, rank)
	print("[Drift] Section %d complete — %.0f pts — Rank: %s" % [_current_section_index, score, rank])


func _calculate_rank(score: float) -> String:
	if score >= RANK_THRESHOLDS["S"]:
		return "S"
	elif score >= RANK_THRESHOLDS["A"]:
		return "A"
	elif score >= RANK_THRESHOLDS["B"]:
		return "B"
	elif score >= RANK_THRESHOLDS["C"]:
		return "C"
	else:
		return "D"


# ---------------------------------------------------------------------------
# Near-Miss Wall Detection
# ---------------------------------------------------------------------------

func _setup_wall_raycasts() -> void:
	# Create raycasts on both sides of the vehicle for wall proximity
	for old_ray in _wall_raycast_origins:
		old_ray.queue_free()
	_wall_raycast_origins.clear()

	var directions := [Vector3.RIGHT, Vector3.LEFT]
	var offsets := [Vector3(1.0, 0.5, 0.0), Vector3(-1.0, 0.5, 0.0)]

	for i in range(directions.size()):
		var ray := RayCast3D.new()
		ray.target_position = directions[i] * NEAR_MISS_DISTANCE
		ray.position = offsets[i]
		ray.collision_mask = 2  # Environment/wall layer
		ray.enabled = true
		_vehicle.add_child(ray)
		_wall_raycast_origins.append(ray)


func _check_wall_proximity() -> void:
	if not _is_in_drift or _near_miss_cooldown > 0.0:
		return

	for ray in _wall_raycast_origins:
		if ray.is_colliding():
			var collision_point := ray.get_collision_point()
			var distance := ray.global_position.distance_to(collision_point)

			if distance <= NEAR_MISS_DISTANCE:
				_register_near_miss(distance)
				break  # One near-miss per check cycle


func _register_near_miss(distance: float) -> void:
	_near_miss_cooldown = NEAR_MISS_COOLDOWN_TIME
	total_near_misses += 1

	# Closer = more points (inverse scaling)
	var closeness_factor := 1.0 - (distance / NEAR_MISS_DISTANCE)
	# Extra bonus for being really close
	if distance <= NEAR_MISS_PERFECT_DISTANCE:
		closeness_factor = 2.0

	var bonus := NEAR_MISS_BONUS * closeness_factor * _combo_multiplier

	if _in_drift_zone:
		bonus *= _current_zone_multiplier

	_current_drift_points += bonus
	_current_section_score += bonus
	total_score += bonus

	EventBus.drift_near_miss.emit(distance, bonus)
	print("[Drift] NEAR MISS! Distance: %.2fm — +%.0f pts" % [distance, bonus])


func _update_near_miss_cooldown(delta: float) -> void:
	if _near_miss_cooldown > 0.0:
		_near_miss_cooldown = maxf(_near_miss_cooldown - delta, 0.0)


# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

## Build the final results breakdown dictionary.
func get_results() -> Dictionary:
	var overall_rank := _calculate_overall_rank()

	var breakdown := {
		"total_score": total_score,
		"overall_rank": overall_rank,
		"section_scores": section_scores.duplicate(),
		"section_ranks": section_ranks.duplicate(),
		"total_drift_time": total_drift_time,
		"longest_drift": longest_drift_duration,
		"highest_single_drift": highest_single_drift,
		"total_near_misses": total_near_misses,
		"max_combo": _combo_count,
	}

	EventBus.drift_total_scored.emit(total_score, overall_rank, breakdown)
	return breakdown


func _calculate_overall_rank() -> String:
	# Overall rank based on total score scaled by number of sections
	var section_count := maxi(section_scores.size(), 1)
	var normalized := total_score / float(section_count)
	return _calculate_rank(normalized)


# ---------------------------------------------------------------------------
# Inner Data Class
# ---------------------------------------------------------------------------

## Data class describing a drift section on the track.
class DriftSection:
	var section_name: String = ""
	var section_index: int = 0
	var start_marker: Marker3D = null
	var end_marker: Marker3D = null
	var par_score: float = 10000.0  # Expected "good" score for this section
