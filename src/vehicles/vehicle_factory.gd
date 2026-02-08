## Factory for creating VehicleData instances from JSON data files.
## Bridges the data layer (JSON) to the runtime layer (VehicleData Resource).
## Supports the full 100-car roster with validation and template caching.
class_name VehicleFactory
extends RefCounted

# Cached vehicle templates keyed by vehicle_id — avoids re-reading JSON
static var _template_cache: Dictionary = {}
static var _all_vehicle_ids: Array[String] = []
static var _catalog_loaded: bool = false

# Required fields that every vehicle JSON must have
const REQUIRED_FIELDS := ["vehicle_id", "display_name", "manufacturer"]


# ---------------------------------------------------------------------------
# Template Cache & Catalog
# ---------------------------------------------------------------------------

static func load_vehicle_catalog() -> void:
	## Scans the vehicles data directory and caches all vehicle IDs.
	if _catalog_loaded:
		return
	_all_vehicle_ids.clear()
	var dir := DirAccess.open("res://data/vehicles/")
	if dir == null:
		push_warning("[Vehicle] No vehicles directory found at res://data/vehicles/")
		_catalog_loaded = true
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var vid := file_name.get_basename()
			_all_vehicle_ids.append(vid)
		file_name = dir.get_next()
	dir.list_dir_end()
	_all_vehicle_ids.sort()
	_catalog_loaded = true
	print("[Vehicle] Catalog loaded: %d vehicle definitions found." % _all_vehicle_ids.size())


static func get_all_vehicle_ids() -> Array[String]:
	## Returns all known vehicle IDs from the data directory.
	load_vehicle_catalog()
	return _all_vehicle_ids


static func get_cached_template(vehicle_id: String) -> VehicleData:
	## Returns a cached vehicle template (read-only reference).
	## Use create_from_json() if you need a mutable instance.
	if _template_cache.has(vehicle_id):
		return _template_cache[vehicle_id]
	var vehicle := create_from_json(vehicle_id)
	if vehicle:
		_template_cache[vehicle_id] = vehicle
	return vehicle


static func clear_cache() -> void:
	## Clears all cached templates. Useful for hot-reloading data.
	_template_cache.clear()
	_all_vehicle_ids.clear()
	_catalog_loaded = false
	print("[Vehicle] Template cache cleared.")


# ---------------------------------------------------------------------------
# Vehicle Creation
# ---------------------------------------------------------------------------

static func create_from_json(vehicle_id: String) -> VehicleData:
	var path := "res://data/vehicles/%s.json" % vehicle_id
	if not FileAccess.file_exists(path):
		push_error("[Vehicle] Vehicle data not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[Vehicle] Failed to parse: %s — %s" % [path, json.get_error_message()])
		return null
	file.close()

	var data: Dictionary = json.data

	# Validate required fields
	if not _validate_json(data, vehicle_id):
		return null

	return create_from_dict(data)


static func create_from_dict(data: Dictionary) -> VehicleData:
	var v := VehicleData.new()

	# --- Identity ---
	v.vehicle_id = data.get("vehicle_id", "")
	v.display_name = data.get("display_name", "Unknown")
	v.manufacturer = data.get("manufacturer", "")
	v.year = data.get("year", 1995)
	v.body_style = data.get("body_style", "")
	v.culture = data.get("culture", "jdm")
	v.description = data.get("description", "")

	# --- New Roster Fields ---
	v.tier = clampi(data.get("tier", 1), 1, 7)
	v.category = data.get("category", "JDM")
	v.acquisition_method = data.get("acquisition_method", "purchase")
	v.engine_config = data.get("engine_config", data.get("engine_type", "I4"))
	v.aspiration = data.get("aspiration", "NA")
	v.special_traits = _to_string_array(data.get("special_traits", []))
	v.lore = data.get("lore", "")
	v.rarity = data.get("rarity", _tier_to_rarity(v.tier))
	v.is_story_locked = data.get("is_story_locked", false)

	# --- Base Stats ---
	v.base_speed = data.get("base_speed", 50.0)
	v.base_acceleration = data.get("base_acceleration", 50.0)
	v.base_handling = data.get("base_handling", 50.0)
	v.base_braking = data.get("base_braking", 50.0)
	v.base_durability = data.get("base_durability", 100.0)

	# --- Engine Specs ---
	v.engine_type = data.get("engine_type", "i4")
	v.displacement_cc = data.get("displacement_cc", 2000)
	v.stock_hp = data.get("stock_hp", 150.0)
	v.stock_torque = data.get("stock_torque", 140.0)
	v.redline_rpm = data.get("redline_rpm", 7000)
	v.weight_kg = data.get("weight_kg", 1200.0)
	v.drivetrain = data.get("drivetrain", "RWD")

	# --- Dynamic State Defaults ---
	v.current_hp = v.stock_hp
	v.current_torque = v.stock_torque
	v.estimated_value = data.get("starting_value", data.get("price", 500))
	v.wear_percentage = data.get("starting_wear", 0.0)
	v.damage_percentage = data.get("starting_damage", 0.0)

	# --- Upgrade Tier Tracking ---
	v.engine_upgrade_tier = data.get("engine_upgrade_tier", 0)
	v.aero_upgrade_tier = data.get("aero_upgrade_tier", 0)
	v.suspension_upgrade_tier = data.get("suspension_upgrade_tier", 0)

	return v


# ---------------------------------------------------------------------------
# Batch Loading
# ---------------------------------------------------------------------------

static func load_all_vehicles() -> Array[VehicleData]:
	## Loads and returns all vehicles from the data directory.
	var vehicles: Array[VehicleData] = []
	for vid in get_all_vehicle_ids():
		var vehicle := get_cached_template(vid)
		if vehicle:
			vehicles.append(vehicle)
	print("[Vehicle] Loaded all %d vehicles." % vehicles.size())
	return vehicles


static func load_vehicles_by_tier(target_tier: int) -> Array[VehicleData]:
	## Returns all vehicles matching a specific tier.
	var vehicles: Array[VehicleData] = []
	for vid in get_all_vehicle_ids():
		var vehicle := get_cached_template(vid)
		if vehicle and vehicle.tier == target_tier:
			vehicles.append(vehicle)
	return vehicles


static func load_vehicles_by_category(target_category: String) -> Array[VehicleData]:
	## Returns all vehicles matching a specific category.
	var vehicles: Array[VehicleData] = []
	for vid in get_all_vehicle_ids():
		var vehicle := get_cached_template(vid)
		if vehicle and vehicle.category == target_category:
			vehicles.append(vehicle)
	return vehicles


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

static func _validate_json(data: Dictionary, vehicle_id: String) -> bool:
	## Validates that JSON data has required fields and valid values.
	var valid := true

	# Check required fields
	for field in REQUIRED_FIELDS:
		if not data.has(field) or str(data[field]).is_empty():
			push_error("[Vehicle] Missing required field '%s' in %s" % [field, vehicle_id])
			valid = false

	# Validate tier range
	var tier_val: int = data.get("tier", 1)
	if tier_val < 1 or tier_val > 7:
		push_warning("[Vehicle] Invalid tier %d in %s, clamping to 1-7" % [tier_val, vehicle_id])

	# Validate category
	var cat: String = data.get("category", "")
	if not cat.is_empty() and cat not in VehicleData.VALID_CATEGORIES:
		push_warning("[Vehicle] Unknown category '%s' in %s" % [cat, vehicle_id])

	# Validate engine config
	var ec: String = data.get("engine_config", "")
	if not ec.is_empty() and ec not in VehicleData.VALID_ENGINE_CONFIGS:
		push_warning("[Vehicle] Unknown engine_config '%s' in %s" % [ec, vehicle_id])

	# Validate aspiration
	var asp: String = data.get("aspiration", "")
	if not asp.is_empty() and asp not in VehicleData.VALID_ASPIRATIONS:
		push_warning("[Vehicle] Unknown aspiration '%s' in %s" % [asp, vehicle_id])

	# Validate drivetrain
	var dt: String = data.get("drivetrain", "")
	if not dt.is_empty() and dt not in VehicleData.VALID_DRIVETRAINS:
		push_warning("[Vehicle] Unknown drivetrain '%s' in %s" % [dt, vehicle_id])

	# Validate rarity
	var rar: String = data.get("rarity", "")
	if not rar.is_empty() and rar not in VehicleData.VALID_RARITIES:
		push_warning("[Vehicle] Unknown rarity '%s' in %s" % [rar, vehicle_id])

	# Validate acquisition method
	var acq: String = data.get("acquisition_method", "")
	if not acq.is_empty() and acq not in VehicleData.VALID_ACQUISITION_METHODS:
		push_warning("[Vehicle] Unknown acquisition_method '%s' in %s" % [acq, vehicle_id])

	return valid


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

static func _tier_to_rarity(tier_val: int) -> String:
	## Auto-assign rarity based on vehicle tier if not explicitly set.
	match tier_val:
		1: return "common"
		2: return "common"
		3: return "uncommon"
		4: return "rare"
		5: return "epic"
		6: return "legendary"
		7: return "legendary"
		_: return "common"


static func _to_string_array(source: Array) -> Array[String]:
	## Converts a generic Array to Array[String].
	var result: Array[String] = []
	for item in source:
		result.append(str(item))
	return result
