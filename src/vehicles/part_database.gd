## Singleton-style database for all vehicle parts.
## Loads part definitions from JSON data files.
## Access via PartDatabase.get_part(id).
class_name PartDatabase
extends RefCounted

# Part tier constants matching GDD
const TIER_STOCK := 1
const TIER_STREET := 2
const TIER_SPORT := 3
const TIER_RACE := 4
const TIER_ELITE := 5
const TIER_LEGENDARY := 6

# Slot types
const SLOTS := [
	"engine_internals", "turbo", "exhaust", "intake", "ecu",
	"transmission", "clutch", "differential", "suspension",
	"brakes", "tires", "wheels", "body_kit", "spoiler",
	"roll_cage", "nitrous",
]

static var _parts_cache: Dictionary = {}
static var _loaded: bool = false


static func load_parts() -> void:
	if _loaded:
		return
	# Load from JSON data files
	var dir := DirAccess.open("res://data/parts/")
	if dir == null:
		push_warning("[PartDatabase] No parts data directory found. Using defaults.")
		_load_default_parts()
		_loaded = true
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path := "res://data/parts/" + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var parts_array: Array = json.data
					for part_data in parts_array:
						_parts_cache[part_data.id] = part_data
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()
	_loaded = true
	print("[PartDatabase] Loaded %d parts." % _parts_cache.size())


static func get_part(part_id: String) -> Dictionary:
	if not _loaded:
		load_parts()
	return _parts_cache.get(part_id, {})


static func get_parts_for_slot(slot: String, max_tier: int = TIER_LEGENDARY) -> Array:
	if not _loaded:
		load_parts()
	var results: Array = []
	for part_id in _parts_cache:
		var part: Dictionary = _parts_cache[part_id]
		if part.get("slot", "") == slot and part.get("tier", 1) <= max_tier:
			results.append(part)
	results.sort_custom(func(a, b): return a.get("tier", 1) < b.get("tier", 1))
	return results


static func get_parts_by_tier(tier: int) -> Array:
	if not _loaded:
		load_parts()
	var results: Array = []
	for part_id in _parts_cache:
		var part: Dictionary = _parts_cache[part_id]
		if part.get("tier", 1) == tier:
			results.append(part)
	return results


static func get_compatible_parts(vehicle_id: String, slot: String) -> Array:
	## Returns parts compatible with a specific vehicle and slot.
	var all_slot_parts := get_parts_for_slot(slot)
	return all_slot_parts.filter(func(part):
		var compat: Array = part.get("compatible_vehicles", [])
		return compat.is_empty() or vehicle_id in compat
	)


static func _load_default_parts() -> void:
	## Fallback: create minimal default parts for MVP testing.
	var defaults := [
		# --- Exhaust ---
		{"id": "exhaust_stock", "name": "Stock Exhaust", "slot": "exhaust", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "exhaust_street", "name": "Street Cat-Back Exhaust", "slot": "exhaust", "tier": 2, "price": 800, "stat_bonuses": {"speed": 3, "acceleration": 2}, "weight_delta": -2},
		{"id": "exhaust_sport", "name": "Sport Header + Exhaust", "slot": "exhaust", "tier": 3, "price": 2500, "stat_bonuses": {"speed": 7, "acceleration": 5}, "weight_delta": -5},
		# --- Intake ---
		{"id": "intake_stock", "name": "Stock Intake", "slot": "intake", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "intake_street", "name": "Cold Air Intake", "slot": "intake", "tier": 2, "price": 400, "stat_bonuses": {"acceleration": 3}, "weight_delta": -1},
		{"id": "intake_sport", "name": "Ram Air Intake System", "slot": "intake", "tier": 3, "price": 1200, "stat_bonuses": {"speed": 3, "acceleration": 5}, "weight_delta": -2},
		# --- Turbo ---
		{"id": "turbo_none", "name": "No Turbo", "slot": "turbo", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "turbo_street", "name": "Small Frame Turbo", "slot": "turbo", "tier": 2, "price": 3000, "stat_bonuses": {"speed": 8, "acceleration": 6}, "weight_delta": 10, "requires": ["intake_street"]},
		{"id": "turbo_sport", "name": "Ball Bearing Turbo Kit", "slot": "turbo", "tier": 3, "price": 7500, "stat_bonuses": {"speed": 18, "acceleration": 14}, "weight_delta": 12, "requires": ["intake_sport", "exhaust_street"]},
		# --- Suspension ---
		{"id": "suspension_stock", "name": "Stock Suspension", "slot": "suspension", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "suspension_street", "name": "Lowering Springs + Shocks", "slot": "suspension", "tier": 2, "price": 600, "stat_bonuses": {"handling": 5}, "weight_delta": -2},
		{"id": "suspension_sport", "name": "Coilover Kit", "slot": "suspension", "tier": 3, "price": 2000, "stat_bonuses": {"handling": 12, "braking": 3}, "weight_delta": -3},
		# --- Brakes ---
		{"id": "brakes_stock", "name": "Stock Brakes", "slot": "brakes", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "brakes_street", "name": "Slotted Rotors + Pads", "slot": "brakes", "tier": 2, "price": 500, "stat_bonuses": {"braking": 5}, "weight_delta": -1},
		{"id": "brakes_sport", "name": "Big Brake Kit", "slot": "brakes", "tier": 3, "price": 2200, "stat_bonuses": {"braking": 12}, "weight_delta": 2},
		# --- Tires ---
		{"id": "tires_stock", "name": "Stock Tires", "slot": "tires", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "tires_street", "name": "Performance Street Tires", "slot": "tires", "tier": 2, "price": 400, "stat_bonuses": {"handling": 4, "braking": 2}, "weight_delta": 0},
		{"id": "tires_sport", "name": "Semi-Slick Tires", "slot": "tires", "tier": 3, "price": 1000, "stat_bonuses": {"handling": 8, "braking": 5, "acceleration": 2}, "weight_delta": 0},
		# --- Transmission ---
		{"id": "transmission_stock", "name": "Stock Transmission", "slot": "transmission", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "transmission_street", "name": "Short Shift Kit", "slot": "transmission", "tier": 2, "price": 300, "stat_bonuses": {"acceleration": 3}, "weight_delta": 0},
		{"id": "transmission_sport", "name": "Close-Ratio Gearbox", "slot": "transmission", "tier": 3, "price": 3500, "stat_bonuses": {"acceleration": 8, "speed": 4}, "weight_delta": -3},
		# --- ECU ---
		{"id": "ecu_stock", "name": "Stock ECU", "slot": "ecu", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "ecu_street", "name": "Piggyback ECU Tune", "slot": "ecu", "tier": 2, "price": 500, "stat_bonuses": {"speed": 3, "acceleration": 3}, "weight_delta": 0},
		{"id": "ecu_sport", "name": "Standalone ECU + Dyno Tune", "slot": "ecu", "tier": 3, "price": 2000, "stat_bonuses": {"speed": 8, "acceleration": 6}, "weight_delta": 0},
		# --- Nitrous ---
		{"id": "nitrous_none", "name": "No Nitrous", "slot": "nitrous", "tier": 1, "price": 0, "stat_bonuses": {}, "weight_delta": 0},
		{"id": "nitrous_street", "name": "Wet Shot Kit (50hp)", "slot": "nitrous", "tier": 2, "price": 1500, "stat_bonuses": {"acceleration": 10}, "weight_delta": 15},
		{"id": "nitrous_sport", "name": "Direct Port Kit (100hp)", "slot": "nitrous", "tier": 3, "price": 4000, "stat_bonuses": {"acceleration": 20, "speed": 5}, "weight_delta": 18},
	]
	for part in defaults:
		_parts_cache[part.id] = part
	print("[PartDatabase] Loaded %d default parts." % _parts_cache.size())
