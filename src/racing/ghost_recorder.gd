## Records player vehicle state during a race for ghost replay playback.
## Captures snapshots at a fixed interval (default 20 fps) to balance
## file size with playback smoothness (interpolation fills the gaps).
class_name GhostRecorder
extends Node

## Recording interval in seconds. 1/20 = 20 fps capture rate.
const RECORD_INTERVAL: float = 1.0 / 20.0

## Maximum recording duration in seconds (safety cap: 30 minutes).
const MAX_RECORD_DURATION: float = 1800.0

# ── State ────────────────────────────────────────────────────────────────────
var _recording: bool = false
var _track_id: String = ""
var _vehicle_id: String = ""
var _vehicle_name: String = ""
var _vehicle: VehicleController = null
var _frames: Array = []  # Array of GhostData.GhostFrame
var _elapsed: float = 0.0
var _record_accumulator: float = 0.0


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	set_process(false)
	EventBus.race_started.connect(_on_race_started)
	EventBus.race_finished.connect(_on_race_finished)
	print("[Ghost] GhostRecorder ready.")


func _process(delta: float) -> void:
	if not _recording or _vehicle == null:
		return

	_elapsed += delta
	_record_accumulator += delta

	# Safety cap: stop recording absurdly long sessions
	if _elapsed >= MAX_RECORD_DURATION:
		push_warning("[Ghost] Recording hit maximum duration (%.0fs). Stopping." % MAX_RECORD_DURATION)
		stop_recording()
		return

	# Record at fixed interval (20 fps)
	while _record_accumulator >= RECORD_INTERVAL:
		_record_accumulator -= RECORD_INTERVAL
		record_frame(_vehicle)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func start_recording(track_id: String, vehicle_id: String, vehicle: VehicleController = null) -> void:
	## Begin recording ghost data for the specified track and vehicle.
	if _recording:
		push_warning("[Ghost] Already recording — stopping previous session.")
		stop_recording()

	_track_id = track_id
	_vehicle_id = vehicle_id
	_vehicle = vehicle
	_vehicle_name = ""

	if _vehicle and _vehicle.vehicle_data:
		_vehicle_name = _vehicle.vehicle_data.display_name if _vehicle.vehicle_data.get("display_name") else vehicle_id

	_frames.clear()
	_elapsed = 0.0
	_record_accumulator = 0.0
	_recording = true
	set_process(true)

	EventBus.ghost_recording_started.emit(_track_id)
	print("[Ghost] Recording started — track: %s, vehicle: %s" % [_track_id, _vehicle_id])


func stop_recording() -> GhostData:
	## Stops recording and returns the completed GhostData resource.
	## Returns null if no frames were captured.
	if not _recording:
		return null

	_recording = false
	set_process(false)

	if _frames.is_empty():
		print("[Ghost] Recording stopped with no frames captured.")
		EventBus.ghost_recording_stopped.emit(_track_id, 0.0)
		return null

	var ghost := GhostData.new()
	ghost.track_id = _track_id
	ghost.vehicle_id = _vehicle_id
	ghost.vehicle_name = _vehicle_name
	ghost.total_time = _elapsed
	ghost.frames = _frames.duplicate()
	ghost.recorded_date = Time.get_datetime_string_from_system()
	ghost.player_name = _get_player_name()
	ghost.act_recorded = _get_current_act()

	EventBus.ghost_recording_stopped.emit(_track_id, _elapsed)
	print("[Ghost] Recording stopped — %.2fs, %d frames captured." % [_elapsed, _frames.size()])

	return ghost


func record_frame(vehicle: VehicleController) -> void:
	## Captures a single snapshot of the vehicle's current state.
	if vehicle == null:
		return

	var frame := GhostData.GhostFrame.new()
	frame.timestamp = _elapsed
	frame.position = vehicle.global_transform.origin
	frame.rotation = vehicle.global_transform.basis.get_euler()
	frame.rotation = Vector3(
		rad_to_deg(frame.rotation.x),
		rad_to_deg(frame.rotation.y),
		rad_to_deg(frame.rotation.z)
	)
	frame.speed = vehicle.current_speed_kmh
	frame.steering = vehicle.input_steer
	frame.drifting = vehicle.is_drifting
	frame.nitro = vehicle.nitro_active
	frame.braking = vehicle.input_brake > 0.1 or vehicle.is_handbraking
	frame.gear = vehicle.current_gear

	_frames.append(frame)


func is_recording() -> bool:
	return _recording


func set_vehicle(vehicle: VehicleController) -> void:
	## Assign or reassign the vehicle to record. Can be called before
	## or during recording if the reference changes.
	_vehicle = vehicle
	if _vehicle and _vehicle.vehicle_data:
		_vehicle_name = _vehicle.vehicle_data.display_name if _vehicle.vehicle_data.get("display_name") else _vehicle_id


func get_elapsed_time() -> float:
	return _elapsed


func get_frame_count() -> int:
	return _frames.size()


# ═══════════════════════════════════════════════════════════════════════════════
#  RACE EVENT HOOKS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_race_started(race_data: Dictionary) -> void:
	## Auto-start recording when a race begins (if a vehicle is assigned).
	if _vehicle == null:
		print("[Ghost] Race started but no vehicle assigned — skipping auto-record.")
		return

	var track: String = race_data.get("track_id", "unknown_track")
	var vid: String = race_data.get("vehicle_id", "")
	if vid.is_empty() and _vehicle_id.is_empty():
		vid = "unknown_vehicle"
	elif vid.is_empty():
		vid = _vehicle_id

	start_recording(track, vid, _vehicle)


func _on_race_finished(_results: Dictionary) -> void:
	## Auto-stop recording when the race ends.
	if _recording:
		stop_recording()


# ═══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _get_player_name() -> String:
	if GameManager and GameManager.player_data:
		return GameManager.player_data.player_name
	return "Player"


func _get_current_act() -> int:
	if GameManager and GameManager.story:
		return GameManager.story.current_act
	return 1
