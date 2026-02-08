## Singleton-style database for all vehicle parts and part combos.
## Loads part definitions and combo data from JSON files in data/parts/.
## Access via PartDatabase.get_part(id), PartDatabase.get_combo(id), etc.
class_name PartDatabase
extends RefCounted

# Part tier constants — 0 (Stock) through 5 (Legendary)
const TIER_STOCK := 0
const TIER_STREET := 1
const TIER_SPORT := 2
const TIER_RACE := 3
const TIER_ELITE := 4
const TIER_LEGENDARY := 5

const TIER_NAMES := {
	0: "Stock",
	1: "Street",
	2: "Sport",
	3: "Race",
	4: "Elite",
	5: "Legendary",
}

const RARITY_NAMES := ["common", "uncommon", "rare", "epic", "legendary"]

# Slot types — matches VehicleData.installed_parts keys
const SLOTS := [
	"engine_internals", "turbo", "exhaust", "intake", "ecu",
	"transmission", "clutch", "differential", "suspension",
	"brakes", "tires", "wheels", "body_kit", "spoiler",
	"roll_cage", "nitrous",
]

# Category groupings for shop UI
const CATEGORIES := [
	"exhaust", "intake", "turbo", "suspension", "brakes", "tires",
	"transmission", "ecu", "nitrous", "engine_internals", "drivetrain",
	"weight_reduction", "cooling", "aero", "cosmetic",
]

static var _parts_cache: Dictionary = {}
static var _combos_cache: Dictionary = {}
static var _loaded: bool = false
static var _combos_loaded: bool = false


# ---------------------------------------------------------------------------
# Part Loading
# ---------------------------------------------------------------------------

static func load_parts() -> void:
	if _loaded:
		return
	# Attempt to load from the primary catalog JSON
	var catalog_path := "res://data/parts/parts_catalog.json"
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			var parts_array: Array = data.get("parts", [])
			for part_data in parts_array:
				_normalize_part(part_data)
				_parts_cache[part_data.id] = part_data
			print("[Parts] Loaded %d parts from parts_catalog.json." % _parts_cache.size())
		else:
			push_error("[Parts] Failed to parse parts_catalog.json: %s" % json.get_error_message())
			_load_default_parts()
		file.close()
	else:
		push_warning("[Parts] parts_catalog.json not found. Using hardcoded defaults.")
		_load_default_parts()
	_loaded = true


static func load_combos() -> void:
	if _combos_loaded:
		return
	var combo_path := "res://data/parts/part_combos.json"
	var file := FileAccess.open(combo_path, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data: Dictionary = json.data
			var combos_array: Array = data.get("combos", [])
			for combo_data in combos_array:
				_combos_cache[combo_data.id] = combo_data
			print("[Parts] Loaded %d part combos from part_combos.json." % _combos_cache.size())
		else:
			push_error("[Parts] Failed to parse part_combos.json: %s" % json.get_error_message())
		file.close()
	else:
		push_warning("[Parts] part_combos.json not found. No combos available.")
	_combos_loaded = true


static func _ensure_loaded() -> void:
	if not _loaded:
		load_parts()
	if not _combos_loaded:
		load_combos()


static func _normalize_part(part: Dictionary) -> void:
	## Ensure all parts have consistent fields regardless of JSON source.
	if not part.has("display_name") and part.has("name"):
		part["display_name"] = part["name"]
	if not part.has("stat_modifiers") and part.has("stat_bonuses"):
		part["stat_modifiers"] = part["stat_bonuses"]
	if not part.has("stat_bonuses") and part.has("stat_modifiers"):
		part["stat_bonuses"] = part["stat_modifiers"]
	if not part.has("prerequisites"):
		part["prerequisites"] = part.get("requires", [])
	if not part.has("requires"):
		part["requires"] = part.get("prerequisites", [])
	if not part.has("compatible_drivetrains"):
		part["compatible_drivetrains"] = []
	if not part.has("rarity"):
		part["rarity"] = _tier_to_rarity(part.get("tier", 0))
	if not part.has("weight_delta"):
		part["weight_delta"] = 0
	if not part.has("category"):
		part["category"] = part.get("slot", "unknown")


# ---------------------------------------------------------------------------
# Part Queries
# ---------------------------------------------------------------------------

static func get_part(part_id: String) -> Dictionary:
	_ensure_loaded()
	return _parts_cache.get(part_id, {})


static func get_all_parts() -> Array:
	_ensure_loaded()
	return _parts_cache.values()


static func get_part_count() -> int:
	_ensure_loaded()
	return _parts_cache.size()


static func get_parts_for_slot(slot: String, max_tier: int = TIER_LEGENDARY) -> Array:
	_ensure_loaded()
	var results: Array = []
	for part_id in _parts_cache:
		var part: Dictionary = _parts_cache[part_id]
		if part.get("slot", "") == slot and part.get("tier", 0) <= max_tier:
			results.append(part)
	results.sort_custom(func(a, b): return a.get("tier", 0) < b.get("tier", 0))
	return results


static func get_parts_by_category(category: String, max_tier: int = TIER_LEGENDARY) -> Array:
	_ensure_loaded()
	var results: Array = []
	for part_id in _parts_cache:
		var part: Dictionary = _parts_cache[part_id]
		if part.get("category", "") == category and part.get("tier", 0) <= max_tier:
			results.append(part)
	results.sort_custom(func(a, b): return a.get("tier", 0) < b.get("tier", 0))
	return results


static func get_parts_by_tier(tier: int) -> Array:
	_ensure_loaded()
	var results: Array = []
	for part_id in _parts_cache:
		var part: Dictionary = _parts_cache[part_id]
		if part.get("tier", 0) == tier:
			results.append(part)
	return results


static func get_parts_by_rarity(rarity: String) -> Array:
	_ensure_loaded()
	var results: Array = []
	for part_id in _parts_cache:
		var part: Dictionary = _parts_cache[part_id]
		if part.get("rarity", "common") == rarity:
			results.append(part)
	return results


static func get_compatible_parts(vehicle_id: String, slot: String) -> Array:
	## Returns parts compatible with a specific vehicle and slot.
	var all_slot_parts := get_parts_for_slot(slot)
	return all_slot_parts.filter(func(part):
		var compat: Array = part.get("compatible_vehicles", [])
		return compat.is_empty() or vehicle_id in compat
	)


static func get_compatible_parts_for_drivetrain(slot: String, drivetrain: String) -> Array:
	## Returns parts in a slot that are compatible with a given drivetrain (RWD, FWD, AWD).
	var all_slot_parts := get_parts_for_slot(slot)
	var dt_upper := drivetrain.to_upper()
	return all_slot_parts.filter(func(part):
		var compat: Array = part.get("compatible_drivetrains", [])
		return compat.is_empty() or dt_upper in compat
	)


static func check_prerequisites(part_id: String, installed_parts: Dictionary) -> bool:
	## Returns true if all prerequisites for the given part are installed on the vehicle.
	var part := get_part(part_id)
	if part.is_empty():
		return false
	var reqs: Array = part.get("prerequisites", [])
	if reqs.is_empty():
		return true
	var installed_ids: Array = []
	for slot in installed_parts:
		var pid: String = installed_parts[slot]
		if not pid.is_empty():
			installed_ids.append(pid)
	for req_id in reqs:
		if req_id not in installed_ids:
			return false
	return true


static func get_tier_name(tier: int) -> String:
	return TIER_NAMES.get(tier, "Unknown")


# ---------------------------------------------------------------------------
# Combo Queries
# ---------------------------------------------------------------------------

static func get_combo(combo_id: String) -> Dictionary:
	_ensure_loaded()
	return _combos_cache.get(combo_id, {})


static func get_all_combos() -> Array:
	_ensure_loaded()
	return _combos_cache.values()


static func get_active_combos(installed_parts: Dictionary) -> Array:
	## Returns all combos that are fully satisfied by the installed parts.
	_ensure_loaded()
	var installed_ids: Array = []
	for slot in installed_parts:
		var pid: String = installed_parts[slot]
		if not pid.is_empty():
			installed_ids.append(pid)

	var active: Array = []
	for combo_id in _combos_cache:
		var combo: Dictionary = _combos_cache[combo_id]
		var combo_parts: Array = combo.get("parts", [])
		var all_present := true
		for required_part in combo_parts:
			if required_part not in installed_ids:
				all_present = false
				break
		if all_present:
			active.append(combo)
	return active


static func get_combo_bonus_totals(installed_parts: Dictionary) -> Dictionary:
	## Returns the sum of all active combo bonuses as a single Dictionary.
	var active := get_active_combos(installed_parts)
	var totals: Dictionary = {}
	for combo in active:
		var bonus: Dictionary = combo.get("bonus", {})
		for stat in bonus:
			totals[stat] = totals.get(stat, 0.0) + bonus[stat]
	return totals


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

static func _tier_to_rarity(tier: int) -> String:
	match tier:
		0: return "common"
		1: return "common"
		2: return "uncommon"
		3: return "rare"
		4: return "epic"
		5: return "legendary"
		_: return "common"


static func reload() -> void:
	## Force reload all data from JSON files. Useful for development.
	_parts_cache.clear()
	_combos_cache.clear()
	_loaded = false
	_combos_loaded = false
	_ensure_loaded()
	print("[Parts] Database reloaded: %d parts, %d combos." % [_parts_cache.size(), _combos_cache.size()])


# ---------------------------------------------------------------------------
# Hardcoded Fallback (MVP defaults — used when JSON files are missing)
# ---------------------------------------------------------------------------

static func _load_default_parts() -> void:
	## Fallback: create minimal default parts for MVP testing.
	## These use the legacy field names for backward compatibility.
	var defaults := [
		# --- Exhaust ---
		{"id": "stock_exhaust", "name": "Stock Exhaust", "slot": "exhaust", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "exhaust"},
		{"id": "street_exhaust", "name": "Street Cat-Back Exhaust", "slot": "exhaust", "tier": 1, "price": 800, "stat_bonuses": {"top_speed": 3, "acceleration": 2}, "weight_delta": -2, "category": "exhaust"},
		{"id": "sport_exhaust", "name": "Sport Header + Exhaust", "slot": "exhaust", "tier": 2, "price": 2500, "stat_bonuses": {"top_speed": 7, "acceleration": 5}, "weight_delta": -5, "category": "exhaust"},
		# --- Intake ---
		{"id": "stock_intake", "name": "Stock Intake", "slot": "intake", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "intake"},
		{"id": "cold_air_intake", "name": "Cold Air Intake", "slot": "intake", "tier": 1, "price": 400, "stat_bonuses": {"acceleration": 3}, "weight_delta": -1, "category": "intake"},
		{"id": "short_ram_intake", "name": "Short Ram Intake", "slot": "intake", "tier": 1, "price": 350, "stat_bonuses": {"acceleration": 4}, "weight_delta": -1, "category": "intake"},
		# --- Turbo ---
		{"id": "stock_none", "name": "Naturally Aspirated", "slot": "turbo", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "turbo"},
		{"id": "small_turbo", "name": "Small Frame Turbo", "slot": "turbo", "tier": 1, "price": 3000, "stat_bonuses": {"top_speed": 8, "acceleration": 6}, "weight_delta": 10, "requires": ["cold_air_intake"], "category": "turbo"},
		{"id": "medium_turbo", "name": "Medium Frame Turbo", "slot": "turbo", "tier": 2, "price": 5500, "stat_bonuses": {"top_speed": 14, "acceleration": 10}, "weight_delta": 12, "requires": ["cold_air_intake", "street_exhaust"], "category": "turbo"},
		# --- Suspension ---
		{"id": "stock_suspension", "name": "Stock Suspension", "slot": "suspension", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "suspension"},
		{"id": "lowering_springs", "name": "Lowering Springs + Shocks", "slot": "suspension", "tier": 1, "price": 600, "stat_bonuses": {"handling": 5}, "weight_delta": -2, "category": "suspension"},
		{"id": "coilovers", "name": "Coilover Kit", "slot": "suspension", "tier": 2, "price": 2000, "stat_bonuses": {"handling": 12, "braking": 3}, "weight_delta": -3, "category": "suspension"},
		# --- Brakes ---
		{"id": "stock_brakes", "name": "Stock Brakes", "slot": "brakes", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "brakes"},
		{"id": "sport_pads", "name": "Sport Brake Pads", "slot": "brakes", "tier": 1, "price": 300, "stat_bonuses": {"braking": 4}, "weight_delta": 0, "category": "brakes"},
		{"id": "slotted_rotors", "name": "Slotted Rotors + Pads", "slot": "brakes", "tier": 2, "price": 800, "stat_bonuses": {"braking": 8}, "weight_delta": -1, "category": "brakes"},
		# --- Tires ---
		{"id": "stock_tires", "name": "Stock Tires", "slot": "tires", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "tires"},
		{"id": "sport_tires", "name": "Performance Street Tires", "slot": "tires", "tier": 1, "price": 400, "stat_bonuses": {"handling": 4, "braking": 2}, "weight_delta": 0, "category": "tires"},
		{"id": "semi_slick", "name": "Semi-Slick Tires", "slot": "tires", "tier": 2, "price": 1000, "stat_bonuses": {"handling": 8, "braking": 5, "acceleration": 2}, "weight_delta": 0, "category": "tires"},
		# --- Transmission ---
		{"id": "stock_transmission", "name": "Stock Transmission", "slot": "transmission", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "transmission"},
		{"id": "short_shifter", "name": "Short Shift Kit", "slot": "transmission", "tier": 1, "price": 300, "stat_bonuses": {"acceleration": 3}, "weight_delta": 0, "category": "transmission"},
		{"id": "close_ratio_gearbox", "name": "Close-Ratio Gearbox", "slot": "transmission", "tier": 2, "price": 3500, "stat_bonuses": {"acceleration": 8, "top_speed": 4}, "weight_delta": -3, "category": "transmission"},
		# --- ECU ---
		{"id": "stock_ecu", "name": "Stock ECU", "slot": "ecu", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "ecu"},
		{"id": "piggyback_ecu", "name": "Piggyback ECU Tune", "slot": "ecu", "tier": 1, "price": 500, "stat_bonuses": {"top_speed": 3, "acceleration": 3}, "weight_delta": 0, "hp_mult": 1.05, "torque_mult": 1.05, "category": "ecu"},
		{"id": "standalone_ecu", "name": "Standalone ECU + Dyno Tune", "slot": "ecu", "tier": 2, "price": 2000, "stat_bonuses": {"top_speed": 8, "acceleration": 6}, "weight_delta": 0, "hp_mult": 1.10, "torque_mult": 1.08, "category": "ecu"},
		# --- Nitrous ---
		{"id": "no_nitrous", "name": "No Nitrous", "slot": "nitrous", "tier": 0, "price": 0, "stat_bonuses": {}, "weight_delta": 0, "category": "nitrous"},
		{"id": "wet_shot_25", "name": "Wet Shot Kit (25hp)", "slot": "nitrous", "tier": 1, "price": 800, "stat_bonuses": {"acceleration": 6}, "weight_delta": 10, "category": "nitrous"},
		{"id": "wet_shot_50", "name": "Wet Shot Kit (50hp)", "slot": "nitrous", "tier": 2, "price": 1500, "stat_bonuses": {"acceleration": 12}, "weight_delta": 14, "category": "nitrous"},
	]
	for part in defaults:
		_normalize_part(part)
		_parts_cache[part.id] = part
	print("[Parts] Loaded %d default fallback parts." % _parts_cache.size())
