## Central handler for all vehicle acquisition methods.
## Tracks how every vehicle was obtained for story consequences and stats.
## Logs acquisition history and emits EventBus signals.
class_name VehicleAcquisition
extends Node

# Acquisition history: Array of { vehicle_id, method, source, timestamp }
var _acquisition_log: Array[Dictionary] = []

# Track Zero's gifts separately for story consequence checks
var _zero_gifts: Dictionary = {} # vehicle_id -> { source, timestamp }


func _ready() -> void:
	EventBus.pink_slip_won.connect(_on_pink_slip_won)
	EventBus.barn_find_discovered.connect(_on_barn_find_discovered)


# ---------------------------------------------------------------------------
# Primary Acquisition Entry Point
# ---------------------------------------------------------------------------

func acquire_vehicle(vehicle_id: String, method: String, source: String = "") -> void:
	## Acquires a vehicle via any method. Creates it from JSON and adds to garage.
	## method: "purchase", "pink_slip", "zero_gift", "story_unlock", "barn_find", "tournament_reward"
	var vehicle := VehicleFactory.create_from_json(vehicle_id)
	if vehicle == null:
		push_error("[Acquisition] Failed to load vehicle data for: %s" % vehicle_id)
		return

	vehicle.acquisition_method = method
	vehicle.acquired_method = method
	vehicle.acquired_timestamp = Time.get_datetime_string_from_system()

	# Mark story-locked if it came from story or Zero
	if method == "story_unlock" or method == "zero_gift":
		vehicle.is_story_locked = true

	# Log the acquisition
	var log_entry := {
		"vehicle_id": vehicle_id,
		"method": method,
		"source": source,
		"timestamp": vehicle.acquired_timestamp,
		"display_name": vehicle.display_name,
	}
	_acquisition_log.append(log_entry)

	# Track Zero gifts specially
	if method == "zero_gift":
		_zero_gifts[vehicle_id] = {
			"source": source,
			"timestamp": vehicle.acquired_timestamp,
		}
		EventBus.zero_gift_received.emit(vehicle_id)
		print("[Acquisition] Zero's gift received: %s (strings attached)" % vehicle.display_name)

	# Add to player's garage (also emits vehicle_acquired signal)
	GameManager.garage.add_vehicle(vehicle, method)

	# Method-specific signals
	match method:
		"purchase":
			print("[Acquisition] Purchased: %s" % vehicle.display_name)
		"pink_slip":
			print("[Acquisition] Won pink slip: %s" % vehicle.display_name)
		"story_unlock":
			print("[Acquisition] Story unlock: %s (source: %s)" % [vehicle.display_name, source])
		"barn_find":
			# Barn finds start with extra wear
			vehicle.wear_percentage = randf_range(40.0, 80.0)
			vehicle.damage_percentage = randf_range(10.0, 40.0)
			print("[Acquisition] Barn find discovered: %s" % vehicle.display_name)
		"tournament_reward":
			print("[Acquisition] Tournament reward: %s (source: %s)" % [vehicle.display_name, source])
		_:
			print("[Acquisition] Vehicle acquired: %s via %s" % [vehicle.display_name, method])


# ---------------------------------------------------------------------------
# History Queries
# ---------------------------------------------------------------------------

func get_acquisition_history() -> Array:
	## Returns the full acquisition history log.
	return _acquisition_log.duplicate()


func get_acquisitions_by_method(method: String) -> Array:
	## Returns all acquisitions matching a specific method.
	var results: Array = []
	for entry in _acquisition_log:
		if entry.get("method", "") == method:
			results.append(entry)
	return results


func was_gifted_by_zero(vehicle_id: String) -> bool:
	## Checks if a vehicle was gifted by Zero — has story consequences.
	## Zero's gifts come with strings attached and may affect endings.
	return _zero_gifts.has(vehicle_id)


func get_zero_gift_count() -> int:
	## Returns how many gifts have been accepted from Zero.
	return _zero_gifts.size()


func get_total_acquisitions() -> int:
	return _acquisition_log.size()


func get_vehicles_by_source(source: String) -> Array:
	## Returns all vehicles acquired from a specific source (mission, event, etc.).
	var results: Array = []
	for entry in _acquisition_log:
		if entry.get("source", "") == source:
			results.append(entry)
	return results


# ---------------------------------------------------------------------------
# Event Handlers
# ---------------------------------------------------------------------------

func _on_pink_slip_won(won_vehicle_data: Dictionary) -> void:
	## When a pink slip race is won, acquire the vehicle through this system.
	var vid: String = won_vehicle_data.get("vehicle_id", "")
	if not vid.is_empty():
		acquire_vehicle(vid, "pink_slip", "pink_slip_race")


func _on_barn_find_discovered(barn_id: String, vehicle_id: String) -> void:
	## When a barn find is discovered in the open world.
	acquire_vehicle(vehicle_id, "barn_find", barn_id)


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"acquisition_log": _acquisition_log,
		"zero_gifts": _zero_gifts,
	}


func deserialize(data: Dictionary) -> void:
	_acquisition_log.clear()
	_zero_gifts.clear()
	var log_data: Array = data.get("acquisition_log", [])
	for entry in log_data:
		_acquisition_log.append(entry)
	_zero_gifts = data.get("zero_gifts", {})
