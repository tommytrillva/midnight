## Multi-lap circuit race controller.
## Handles lap counting, split times, best-lap tracking, real-time leaderboard,
## optional rubber-band AI difficulty, optional pit stops, and DNF timeout.
class_name CircuitRace
extends Node

# --- Configuration ---
## Seconds behind the leader before DNF warning fires.
const DNF_WARNING_THRESHOLD := 30.0
## Seconds behind the leader before automatic DNF.
const DNF_TIMEOUT_SECONDS := 60.0
## Pit stop duration base (seconds). Modified by damage amount.
const PIT_STOP_BASE_DURATION := 5.0
## Maximum pit stop duration.
const PIT_STOP_MAX_DURATION := 12.0
## Nitro refill amount per pit stop.
const PIT_NITRO_REFILL := 100.0
## Damage repaired per pit stop (0-100 scale).
const PIT_REPAIR_AMOUNT := 50.0
## Rubber-band strength scaling (0 = off, 1 = full).
const RUBBER_BAND_BASE_STRENGTH := 0.15

enum CircuitState { IDLE, RACING, FINISHED }

# --- State ---
var state: CircuitState = CircuitState.IDLE
var total_laps: int = 3
var pit_stops_enabled: bool = false
var rubber_band_enabled: bool = true
var rubber_band_difficulty: float = 0.5  # 0-1, scales rubber band intensity

# --- Racer Tracking ---
## Per-racer lap data, keyed by racer_id.
var racer_laps: Dictionary = {}  # racer_id -> RacerLapData
var leaderboard: Array[Dictionary] = []  # Sorted position list

# --- References ---
var _track: RaceTrack = null
var _player_vehicle: VehicleController = null
var _race_manager: RaceManager = null

# --- Pit Stop State ---
var _pit_area: Area3D = null
var _player_in_pit: bool = false
var _pit_timer: float = 0.0
var _pit_active: bool = false

# --- DNF Tracking ---
var _dnf_warned: Dictionary = {}  # racer_id -> bool


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Initialize circuit race. Call after vehicles are spawned.
func activate(
	track: RaceTrack,
	player_vehicle: VehicleController,
	laps: int,
	enable_pits: bool = false,
	enable_rubber_band: bool = true,
	difficulty: float = 0.5,
	pit_area: Area3D = null,
) -> void:
	_track = track
	_player_vehicle = player_vehicle
	_race_manager = GameManager.race_manager
	total_laps = laps
	pit_stops_enabled = enable_pits
	rubber_band_enabled = enable_rubber_band
	rubber_band_difficulty = difficulty
	_pit_area = pit_area

	# Initialize lap data for all racers
	racer_laps.clear()
	leaderboard.clear()
	_dnf_warned.clear()

	for racer in _race_manager.racers:
		var lap_data := RacerLapData.new()
		lap_data.racer_id = racer.racer_id
		lap_data.display_name = racer.display_name
		lap_data.is_player = racer.is_player
		racer_laps[racer.racer_id] = lap_data

	# Wire pit stop area if available
	if _pit_area and pit_stops_enabled:
		_pit_area.body_entered.connect(_on_pit_area_entered)
		_pit_area.body_exited.connect(_on_pit_area_exited)

	# Wire lap and checkpoint signals
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)

	state = CircuitState.RACING
	set_process(true)
	set_physics_process(true)

	print("[Circuit] Race activated — %d laps | Pits: %s | Rubber band: %s (%.1f)" % [
		total_laps,
		"ON" if pit_stops_enabled else "OFF",
		"ON" if rubber_band_enabled else "OFF",
		rubber_band_difficulty,
	])


func deactivate() -> void:
	state = CircuitState.IDLE
	set_process(false)
	set_physics_process(false)

	# Disconnect signals safely
	if EventBus.lap_completed.is_connected(_on_lap_completed):
		EventBus.lap_completed.disconnect(_on_lap_completed)
	if EventBus.checkpoint_reached.is_connected(_on_checkpoint_reached):
		EventBus.checkpoint_reached.disconnect(_on_checkpoint_reached)
	if _pit_area:
		if _pit_area.body_entered.is_connected(_on_pit_area_entered):
			_pit_area.body_entered.disconnect(_on_pit_area_entered)
		if _pit_area.body_exited.is_connected(_on_pit_area_exited):
			_pit_area.body_exited.disconnect(_on_pit_area_exited)

	print("[Circuit] Race deactivated")


# ---------------------------------------------------------------------------
# Main Loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if state != CircuitState.RACING:
		return
	_update_pit_stop(delta)


func _physics_process(delta: float) -> void:
	if state != CircuitState.RACING:
		return
	_update_leaderboard()
	_check_dnf_timeouts()
	if rubber_band_enabled:
		_apply_rubber_banding()


# ---------------------------------------------------------------------------
# Lap & Checkpoint Tracking
# ---------------------------------------------------------------------------

func _on_lap_completed(racer_id: int, lap: int, race_time: float) -> void:
	if not racer_laps.has(racer_id):
		return

	var data: RacerLapData = racer_laps[racer_id]
	var lap_time: float = race_time - data.last_lap_timestamp
	data.last_lap_timestamp = race_time
	data.lap_times.append(lap_time)
	data.current_lap = lap

	# Track best lap
	if lap_time < data.best_lap_time or data.best_lap_time <= 0.0:
		data.best_lap_time = lap_time
		data.best_lap_number = lap
		EventBus.circuit_best_lap.emit(racer_id, lap, lap_time)
		if data.is_player:
			print("[Circuit] NEW BEST LAP! Lap %d — %s" % [lap, _format_time(lap_time)])

	EventBus.circuit_lap_time.emit(racer_id, lap, lap_time)

	var name_str := data.display_name
	print("[Circuit] %s completed lap %d/%d — %s (best: %s)" % [
		name_str, lap, total_laps, _format_time(lap_time), _format_time(data.best_lap_time)
	])

	# Check if this racer has finished all laps
	if lap >= total_laps:
		data.finished = true
		data.finish_time = race_time
		_race_manager.report_finish(racer_id)
		print("[Circuit] %s FINISHED — Total: %s" % [name_str, _format_time(race_time)])
		_check_all_finished()


func _on_checkpoint_reached(racer_id: int, checkpoint_index: int) -> void:
	if not racer_laps.has(racer_id):
		return

	var data: RacerLapData = racer_laps[racer_id]
	var split_time := _race_manager.race_timer
	data.checkpoint_splits.append({
		"checkpoint": checkpoint_index,
		"time": split_time,
		"lap": data.current_lap,
	})


# ---------------------------------------------------------------------------
# Leaderboard
# ---------------------------------------------------------------------------

func _update_leaderboard() -> void:
	leaderboard.clear()

	for racer_id in racer_laps:
		var data: RacerLapData = racer_laps[racer_id]
		var racer_state: RaceManager.RacerState = null
		for r in _race_manager.racers:
			if r.racer_id == racer_id:
				racer_state = r
				break

		leaderboard.append({
			"racer_id": racer_id,
			"name": data.display_name,
			"is_player": data.is_player,
			"current_lap": data.current_lap,
			"progress": racer_state.progress if racer_state else 0.0,
			"best_lap": data.best_lap_time,
			"finished": data.finished,
			"dnf": data.dnf,
		})

	# Sort: finished first (by finish time), then by (lap desc, progress desc)
	leaderboard.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.finished and not b.finished:
			return true
		if b.finished and not a.finished:
			return false
		if a.finished and b.finished:
			var data_a: RacerLapData = racer_laps[a.racer_id]
			var data_b: RacerLapData = racer_laps[b.racer_id]
			return data_a.finish_time < data_b.finish_time
		# Both still racing — sort by lap then progress
		if a.current_lap != b.current_lap:
			return a.current_lap > b.current_lap
		return a.progress > b.progress
	)

	# Assign positions
	for i in range(leaderboard.size()):
		leaderboard[i]["position"] = i + 1

	EventBus.circuit_leaderboard_updated.emit(leaderboard)


## Get the current leaderboard for HUD display.
func get_leaderboard() -> Array[Dictionary]:
	return leaderboard


## Get a specific racer's lap data.
func get_racer_data(racer_id: int) -> RacerLapData:
	return racer_laps.get(racer_id, null)


# ---------------------------------------------------------------------------
# DNF Timeout
# ---------------------------------------------------------------------------

func _check_dnf_timeouts() -> void:
	# Find the leader's race time as reference
	var leader_time := _race_manager.race_timer
	var leader_progress := 0.0
	for entry in leaderboard:
		if entry.position == 1:
			leader_progress = entry.progress
			break

	# Check each non-finished racer
	for racer_id in racer_laps:
		var data: RacerLapData = racer_laps[racer_id]
		if data.finished or data.dnf:
			continue

		# Estimate time behind leader using progress difference
		var racer_progress := 0.0
		for entry in leaderboard:
			if entry.racer_id == racer_id:
				racer_progress = entry.progress
				break

		var progress_diff: float = leader_progress - racer_progress
		if progress_diff <= 0.0:
			continue

		# Very rough time estimate based on progress gap
		var estimated_gap: float = progress_diff * _race_manager.race_timer
		if estimated_gap <= 0.0:
			continue

		# DNF warning
		if estimated_gap >= DNF_WARNING_THRESHOLD and not _dnf_warned.get(racer_id, false):
			_dnf_warned[racer_id] = true
			EventBus.circuit_dnf_warning.emit(racer_id, estimated_gap)
			if data.is_player:
				print("[Circuit] DNF WARNING — %.0fs behind leader!" % estimated_gap)

		# DNF timeout
		if estimated_gap >= DNF_TIMEOUT_SECONDS:
			data.dnf = true
			data.finished = true
			_race_manager.report_dnf(racer_id)
			EventBus.circuit_dnf_timeout.emit(racer_id)
			print("[Circuit] %s DNF — too far behind" % data.display_name)


# ---------------------------------------------------------------------------
# Rubber Banding
# ---------------------------------------------------------------------------

func _apply_rubber_banding() -> void:
	## Adjust AI difficulty based on player position to keep races competitive.
	## Only applies when rubber_band_enabled is true.
	if leaderboard.size() < 2:
		return

	var player_position := 0
	var total := leaderboard.size()

	for entry in leaderboard:
		if entry.is_player:
			player_position = entry.position
			break

	if player_position == 0:
		return

	# If player is behind, AI slows slightly. If player is ahead, AI speeds up slightly.
	var position_ratio: float = float(player_position - 1) / float(maxi(total - 1, 1))
	var band_strength: float = RUBBER_BAND_BASE_STRENGTH * rubber_band_difficulty

	# Apply to RaceAI instances via their difficulty property
	for racer_id in racer_laps:
		var data: RacerLapData = racer_laps[racer_id]
		if data.is_player:
			continue

		# Find the AI node in the scene tree
		for racer in _race_manager.racers:
			if racer.racer_id == racer_id:
				# Adjust the racer's effective speed via progress reporting
				# AI that is ahead of player gets slightly slower, behind gets faster
				var ai_position := 0
				for entry in leaderboard:
					if entry.racer_id == racer_id:
						ai_position = entry.position
						break
				# No direct modification — rubber banding is handled in RaceAI._update_rubber_band()
				break


# ---------------------------------------------------------------------------
# Pit Stops
# ---------------------------------------------------------------------------

func _on_pit_area_entered(body: Node3D) -> void:
	if body != _player_vehicle or not pit_stops_enabled:
		return
	if _pit_active:
		return

	_player_in_pit = true
	print("[Circuit] Entered pit lane")


func _on_pit_area_exited(body: Node3D) -> void:
	if body != _player_vehicle:
		return
	_player_in_pit = false
	if _pit_active:
		_cancel_pit_stop()


func begin_pit_stop() -> void:
	## Player initiates a pit stop (press action while in pit area).
	if not _player_in_pit or _pit_active or not pit_stops_enabled:
		return

	_pit_active = true
	var vehicle_data := _player_vehicle.vehicle_data
	var damage := 0.0
	if vehicle_data:
		damage = 100.0 - vehicle_data.condition  # condition is 0-100

	# Duration scales with damage
	var duration: float = PIT_STOP_BASE_DURATION + (damage / 100.0) * (PIT_STOP_MAX_DURATION - PIT_STOP_BASE_DURATION)
	_pit_timer = duration

	EventBus.circuit_pit_entered.emit(0)
	print("[Circuit] PIT STOP — Duration: %.1fs (damage: %.0f%%)" % [duration, damage])

	# Freeze player vehicle during pit stop
	if _player_vehicle:
		_player_vehicle.engine_force = 0.0
		_player_vehicle.brake = _player_vehicle.max_brake_force
		_player_vehicle.set_physics_process(false)


func _update_pit_stop(delta: float) -> void:
	if not _pit_active:
		return

	_pit_timer -= delta
	if _pit_timer <= 0.0:
		_complete_pit_stop()


func _complete_pit_stop() -> void:
	_pit_active = false

	var repairs := {}

	# Repair vehicle
	if _player_vehicle and _player_vehicle.vehicle_data:
		var old_condition := _player_vehicle.vehicle_data.condition
		_player_vehicle.vehicle_data.condition = minf(
			_player_vehicle.vehicle_data.condition + PIT_REPAIR_AMOUNT, 100.0
		)
		repairs["condition_restored"] = _player_vehicle.vehicle_data.condition - old_condition

	# Refill nitro
	if _player_vehicle:
		var old_nitro := _player_vehicle.nitro_amount
		_player_vehicle.nitro_amount = minf(_player_vehicle.nitro_amount + PIT_NITRO_REFILL, _player_vehicle.nitro_max)
		repairs["nitro_refilled"] = _player_vehicle.nitro_amount - old_nitro
		# Unfreeze
		_player_vehicle.set_physics_process(true)

	EventBus.circuit_pit_exited.emit(0, repairs)
	print("[Circuit] Pit stop complete — Repairs: %s" % str(repairs))


func _cancel_pit_stop() -> void:
	_pit_active = false
	_pit_timer = 0.0
	if _player_vehicle:
		_player_vehicle.set_physics_process(true)
	print("[Circuit] Pit stop cancelled — left pit area")


# ---------------------------------------------------------------------------
# Finish
# ---------------------------------------------------------------------------

func _check_all_finished() -> void:
	var all_done := true
	for racer_id in racer_laps:
		var data: RacerLapData = racer_laps[racer_id]
		if not data.finished and not data.dnf:
			all_done = false
			break

	if all_done:
		state = CircuitState.FINISHED
		print("[Circuit] All racers finished or DNF")


## Build results for integration with RaceManager.
func get_results() -> Dictionary:
	var lap_data := {}
	for racer_id in racer_laps:
		var data: RacerLapData = racer_laps[racer_id]
		lap_data[racer_id] = {
			"lap_times": data.lap_times.duplicate(),
			"best_lap_time": data.best_lap_time,
			"best_lap_number": data.best_lap_number,
			"total_laps": data.current_lap,
			"finished": data.finished,
			"dnf": data.dnf,
			"finish_time": data.finish_time,
		}

	return {
		"race_type": "circuit",
		"total_laps": total_laps,
		"leaderboard": leaderboard.duplicate(),
		"racer_lap_data": lap_data,
	}


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--.---"
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	var ms: int = int((seconds - int(seconds)) * 1000)
	return "%d:%02d.%03d" % [mins, secs, ms]


# ---------------------------------------------------------------------------
# Inner Data Class
# ---------------------------------------------------------------------------

## Per-racer lap tracking data for circuit races.
class RacerLapData:
	var racer_id: int = 0
	var display_name: String = ""
	var is_player: bool = false
	var current_lap: int = 0
	var lap_times: Array[float] = []
	var best_lap_time: float = 0.0
	var best_lap_number: int = 0
	var last_lap_timestamp: float = 0.0
	var checkpoint_splits: Array[Dictionary] = []
	var finished: bool = false
	var dnf: bool = false
	var finish_time: float = 0.0
	var pit_stops: int = 0
