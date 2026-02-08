## Solo racing mode where the player races against their personal best ghost.
## Provides real-time delta display, sector split times, and new record
## celebration. Designed to be added as a child of the race scene.
class_name TimeTrialMode
extends Node

# ═══════════════════════════════════════════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

## Colour constants for the delta display (green = ahead, red = behind).
const DELTA_COLOR_AHEAD: Color = Color(0.2, 1.0, 0.3)
const DELTA_COLOR_BEHIND: Color = Color(1.0, 0.25, 0.2)
const DELTA_COLOR_NEUTRAL: Color = Color(1.0, 1.0, 1.0)
## Minimum delta (seconds) before colour changes from neutral.
const DELTA_DEADZONE: float = 0.05

# ═══════════════════════════════════════════════════════════════════════════════
#  STATE
# ═══════════════════════════════════════════════════════════════════════════════

var _track_id: String = ""
var _vehicle_id: String = ""
var _running: bool = false
var _elapsed: float = 0.0
var _ghost_data: GhostData = null
var _ghost_player: GhostPlayer = null

## Sector tracking — populated from checkpoint events.
var _sector_times: Array = []          # Array of float — player sector finish times
var _ghost_sector_times: Array = []    # Array of float — ghost sector finish times
var _current_sector: int = 0
var _sector_start_time: float = 0.0

## Best lap tracking (for circuit tracks with multiple laps).
var _best_lap_time: float = INF
var _current_lap_start: float = 0.0
var _current_lap: int = 0

## Player vehicle reference (for position comparison).
var _player_vehicle: VehicleController = null


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	set_process(false)
	EventBus.race_started.connect(_on_race_started)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.lap_completed.connect(_on_lap_completed)
	print("[Ghost] TimeTrialMode ready.")


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func start_time_trial(track_id: String, vehicle_id: String,
		player_vehicle: VehicleController = null,
		parent_3d: Node3D = null) -> void:
	## Initialises and starts a time trial session.
	## Loads the best ghost (if one exists) and spawns a ghost player.
	_track_id = track_id
	_vehicle_id = vehicle_id
	_player_vehicle = player_vehicle
	_elapsed = 0.0
	_sector_times.clear()
	_ghost_sector_times.clear()
	_current_sector = 0
	_sector_start_time = 0.0
	_best_lap_time = INF
	_current_lap_start = 0.0
	_current_lap = 0

	# Load best ghost for comparison
	var ghost_mgr: GhostManager = _get_ghost_manager()
	if ghost_mgr:
		_ghost_data = ghost_mgr.load_ghost(track_id, vehicle_id)
		if _ghost_data == null:
			_ghost_data = ghost_mgr.load_best_ghost(track_id)

		if _ghost_data != null:
			var target_parent: Node3D = parent_3d if parent_3d else null
			_ghost_player = ghost_mgr.spawn_ghost_player(_ghost_data, target_parent)
			_precompute_ghost_sectors()
			print("[Ghost] Time trial ghost loaded — PB: %.2fs" % _ghost_data.total_time)
		else:
			print("[Ghost] No ghost found for track: %s — racing without ghost." % track_id)

		# Set up the recorder on the player vehicle
		if player_vehicle:
			ghost_mgr.recorder.set_vehicle(player_vehicle)

	_running = true
	set_process(true)
	print("[Ghost] Time trial started — track: %s, vehicle: %s" % [track_id, vehicle_id])


func get_current_delta() -> float:
	## Returns the time delta between the player and the ghost.
	## Negative = player is ahead. Positive = player is behind.
	if _ghost_data == null or _player_vehicle == null:
		return 0.0

	# Get the ghost's position at the current elapsed time
	var ghost_frame: GhostData.GhostFrame = _ghost_data.get_frame_at_time(_elapsed)

	# Simple distance-based delta estimate:
	# Compare how far along the track each entity is.
	# A more accurate approach would use track progress, but for now we
	# use the ghost's recorded time at a comparable position.
	return _estimate_time_delta()


func get_delta_color() -> Color:
	## Returns the appropriate colour for the delta display.
	var delta: float = get_current_delta()
	if absf(delta) < DELTA_DEADZONE:
		return DELTA_COLOR_NEUTRAL
	elif delta < 0.0:
		return DELTA_COLOR_AHEAD
	else:
		return DELTA_COLOR_BEHIND


func get_delta_text() -> String:
	## Returns a formatted string for the delta display (e.g., "+1.23" or "-0.45").
	var delta: float = get_current_delta()
	if absf(delta) < DELTA_DEADZONE:
		return "0.00"
	var sign_str: String = "+" if delta > 0.0 else ""
	return "%s%.2f" % [sign_str, delta]


func get_sector_times() -> Array:
	return _sector_times.duplicate()


func get_ghost_sector_times() -> Array:
	return _ghost_sector_times.duplicate()


func get_sector_delta(sector_index: int) -> float:
	## Returns the delta for a specific completed sector.
	if sector_index >= _sector_times.size() or sector_index >= _ghost_sector_times.size():
		return 0.0
	return _sector_times[sector_index] - _ghost_sector_times[sector_index]


func get_best_lap_time() -> float:
	return _best_lap_time


func get_current_lap() -> int:
	return _current_lap


func get_elapsed_time() -> float:
	return _elapsed


func is_running() -> bool:
	return _running


func has_ghost() -> bool:
	return _ghost_data != null


func get_ghost_total_time() -> float:
	if _ghost_data != null:
		return _ghost_data.total_time
	return 0.0


# ═══════════════════════════════════════════════════════════════════════════════
#  HUD DATA (for the race HUD to query)
# ═══════════════════════════════════════════════════════════════════════════════

func get_hud_data() -> Dictionary:
	## Returns a dictionary of all time trial HUD data for easy UI binding.
	return {
		"elapsed": _elapsed,
		"delta": get_current_delta(),
		"delta_text": get_delta_text(),
		"delta_color": get_delta_color(),
		"current_sector": _current_sector,
		"sector_times": _sector_times,
		"ghost_sector_times": _ghost_sector_times,
		"best_lap": _best_lap_time,
		"current_lap": _current_lap,
		"has_ghost": _ghost_data != null,
		"ghost_time": get_ghost_total_time(),
		"running": _running,
	}


# ═══════════════════════════════════════════════════════════════════════════════
#  EVENT HOOKS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_race_started(_race_data: Dictionary) -> void:
	if _running and _ghost_player:
		_ghost_player.start_playback()


func _on_race_finished(results: Dictionary) -> void:
	if not _running:
		return

	_running = false
	set_process(false)

	var player_time: float = _elapsed
	var player_dnf: bool = results.get("player_dnf", false)

	if player_dnf:
		print("[Ghost] Time trial ended — DNF.")
		EventBus.hud_message.emit("DNF - No record set", 3.0)
		_cleanup_ghost_player()
		return

	# Check for new record
	var is_new_record: bool = false
	if _ghost_data != null:
		if player_time < _ghost_data.total_time:
			is_new_record = true
			var improvement: float = _ghost_data.total_time - player_time
			print("[Ghost] NEW RECORD! %.2fs (improved by %.2fs)" % [player_time, improvement])
			EventBus.hud_message.emit("NEW RECORD! %.2fs" % player_time, 5.0)
			EventBus.notification_popup.emit(
				"New Personal Best!",
				"Track: %s\nTime: %.2fs\nImproved by: %.2fs" % [_track_id, player_time, improvement],
				"trophy"
			)
		else:
			var gap: float = player_time - _ghost_data.total_time
			print("[Ghost] Time trial finished: %.2fs (%.2fs behind PB)" % [player_time, gap])
	else:
		# First ever run on this track
		is_new_record = true
		print("[Ghost] First time trial recorded: %.2fs" % player_time)
		EventBus.hud_message.emit("First Record Set! %.2fs" % player_time, 5.0)

	_cleanup_ghost_player()


func _on_checkpoint_reached(racer_id: int, checkpoint_index: int) -> void:
	## Record sector split time when the player hits a checkpoint.
	if not _running or racer_id != 0:
		return

	var sector_time: float = _elapsed - _sector_start_time
	_sector_times.append(sector_time)
	_current_sector = checkpoint_index + 1
	_sector_start_time = _elapsed

	# Log sector comparison
	if checkpoint_index < _ghost_sector_times.size():
		var ghost_sector: float = _ghost_sector_times[checkpoint_index]
		var sector_delta: float = sector_time - ghost_sector
		var delta_str: String = "%+.2f" % sector_delta
		print("[Ghost] Sector %d: %.2fs (ghost: %.2fs, delta: %s)" % [
			checkpoint_index + 1, sector_time, ghost_sector, delta_str])
	else:
		print("[Ghost] Sector %d: %.2fs (no ghost comparison)" % [
			checkpoint_index + 1, sector_time])


func _on_lap_completed(racer_id: int, lap: int, _time: float) -> void:
	if not _running or racer_id != 0:
		return

	var lap_time: float = _elapsed - _current_lap_start
	_current_lap = lap
	_current_lap_start = _elapsed

	if lap_time < _best_lap_time:
		_best_lap_time = lap_time
		print("[Ghost] Best lap: %.2fs (lap %d)" % [lap_time, lap])
	else:
		print("[Ghost] Lap %d: %.2fs (best: %.2fs)" % [lap, lap_time, _best_lap_time])


# ═══════════════════════════════════════════════════════════════════════════════
#  DELTA ESTIMATION
# ═══════════════════════════════════════════════════════════════════════════════

func _estimate_time_delta() -> float:
	## Estimates the time difference between the player and the ghost.
	## Uses position-based comparison: finds the ghost timestamp where
	## the ghost was closest to the player's current position, then
	## returns (elapsed - ghost_timestamp).
	if _ghost_data == null or _player_vehicle == null:
		return 0.0

	var player_pos: Vector3 = _player_vehicle.global_transform.origin

	# Find the ghost frame closest to the player's current position
	# (search around the current elapsed time to avoid full-scan cost)
	var search_window: float = 10.0  # seconds to search around current time
	var best_dist: float = INF
	var best_time: float = _elapsed

	var start_time: float = maxf(0.0, _elapsed - search_window)
	var end_time: float = minf(_ghost_data.total_time, _elapsed + search_window)
	var step: float = GhostRecorder.RECORD_INTERVAL

	var t: float = start_time
	while t <= end_time:
		var frame: GhostData.GhostFrame = _ghost_data.get_frame_at_time(t)
		var dist: float = player_pos.distance_squared_to(frame.position)
		if dist < best_dist:
			best_dist = dist
			best_time = t
		t += step

	# Delta = how far ahead/behind the player is in time
	# Negative = player reached this point sooner (ahead)
	# Positive = ghost reached this point sooner (behind)
	return _elapsed - best_time


# ═══════════════════════════════════════════════════════════════════════════════
#  GHOST SECTOR PRECOMPUTATION
# ═══════════════════════════════════════════════════════════════════════════════

func _precompute_ghost_sectors() -> void:
	## Pre-computes the ghost's sector times by simulating checkpoint crossings.
	## This is a simplified approach: in a full implementation, the ghost
	## recording would store checkpoint timestamps directly.
	_ghost_sector_times.clear()
	# Without access to the track's checkpoint positions at this point,
	# we store empty sector times. The GhostRecorder could be enhanced
	# to record checkpoint events directly for precise sector comparison.
	print("[Ghost] Ghost sector precomputation deferred (requires track checkpoint data).")


# ═══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _get_ghost_manager() -> GhostManager:
	## Retrieves the GhostManager from the GameManager autoload.
	if GameManager and GameManager.has_node("GhostManager"):
		return GameManager.get_node("GhostManager") as GhostManager
	# Fallback: look in scene tree
	var manager := get_node_or_null("/root/GhostManager")
	if manager is GhostManager:
		return manager as GhostManager
	push_warning("[Ghost] GhostManager not found in GameManager or scene tree.")
	return null


func _cleanup_ghost_player() -> void:
	if _ghost_player and is_instance_valid(_ghost_player):
		_ghost_player.stop_playback()
		# Don't free it here — GhostManager owns ghost players.
		_ghost_player = null
