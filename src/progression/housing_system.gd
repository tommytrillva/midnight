## Manages the player's housing progression from sleeping in the CRX
## through Maya's couch, apartments, the penthouse, The Fall, and rebuilding.
## Housing level determines rest bonus (skill XP), vehicle storage, and monthly rent.
## Per GDD: CRX -> Maya's Couch -> Studio -> Apartment -> Penthouse -> Back to CRX -> Rebuild.
class_name HousingSystem
extends Node

# Housing level enum — progression order matches the GDD housing arc
enum Level {
	CAR,            # 0 — Sleeping in the CRX. Starting state.
	COUCH,          # 1 — Maya's couch above the garage.
	STUDIO,         # 2 — Cheap studio apartment near the docks.
	APARTMENT,      # 3 — Nice downtown apartment.
	PENTHOUSE,      # 4 — Luxury penthouse, top of the world.
	BACK_TO_CAR,    # 5 — Post-Fall, back in the CRX.
	REBUILD_STUDIO, # 6 — Rebuilding, modest fresh-start studio.
}

# Maps Level enum values to housing_data.json "id" strings
const LEVEL_TO_ID := {
	Level.CAR: "car",
	Level.COUCH: "couch",
	Level.STUDIO: "studio",
	Level.APARTMENT: "apartment",
	Level.PENTHOUSE: "penthouse",
	Level.BACK_TO_CAR: "back_to_car",
	Level.REBUILD_STUDIO: "rebuild_studio",
}

# Maps rep tier names to numeric tier values for condition checking
const REP_TIER_MAP := {
	"UNKNOWN": 0,
	"NEWCOMER": 1,
	"KNOWN": 2,
	"RESPECTED": 3,
	"FEARED": 4,
	"LEGENDARY": 5,
}

# --- State ---
var current_level: int = Level.CAR
var months_rent_missed: int = 0

# --- Data ---
var _housing_data: Array = []  # Loaded from JSON
var _dialogue_map: Dictionary = {}  # level -> dialogue file id


func _ready() -> void:
	_load_housing_data()
	_setup_dialogue_map()

	# Listen for month ticks to handle rent
	EventBus.time_period_changed.connect(_on_time_period_changed)

	print("[Housing] System initialized. Current: %s" % _get_level_name())


# =============================================================================
# DATA LOADING
# =============================================================================

func _load_housing_data() -> void:
	var path := "res://data/housing/housing_data.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				_housing_data = json.data.get("levels", [])
				file.close()
				print("[Housing] Loaded %d housing levels from JSON." % _housing_data.size())
				return
			file.close()

	# Fallback — build minimal data inline
	push_warning("[Housing] Could not load housing_data.json, using fallback.")
	_housing_data = _build_fallback_data()


func _build_fallback_data() -> Array:
	return [
		{"id": "car", "name": "Your Car", "description": "The backseat of your beater.", "rest_bonus": 0.0, "vehicle_storage": 0, "monthly_rent": 0, "flavor": "", "unlock": "default"},
		{"id": "couch", "name": "Maya's Couch", "description": "A lumpy couch above Torres Automotive.", "rest_bonus": 0.05, "vehicle_storage": 0, "monthly_rent": 0, "flavor": "", "unlock": {"flag": "maya_offered_couch"}},
		{"id": "studio", "name": "Harbor Studio", "description": "A tiny studio near the docks.", "rest_bonus": 0.1, "vehicle_storage": 1, "monthly_rent": 500, "flavor": "", "unlock": {"cash_min": 2000, "rep_tier": "NEWCOMER"}},
		{"id": "apartment", "name": "Downtown Apartment", "description": "Two bedrooms, a view of the neon signs.", "rest_bonus": 0.2, "vehicle_storage": 3, "monthly_rent": 2000, "flavor": "", "unlock": {"cash_min": 10000, "rep_tier": "KNOWN"}},
		{"id": "penthouse", "name": "Skyline Penthouse", "description": "Top floor. Full city view.", "rest_bonus": 0.3, "vehicle_storage": 8, "monthly_rent": 10000, "flavor": "", "unlock": {"cash_min": 100000, "rep_tier": "FEARED"}},
		{"id": "back_to_car", "name": "Your Car (Again)", "description": "Full circle. The backseat.", "rest_bonus": 0.0, "vehicle_storage": 0, "monthly_rent": 0, "flavor": "", "unlock": {"flag": "the_fall_triggered"}},
		{"id": "rebuild_studio", "name": "Fresh Start Studio", "description": "Different building, same sized room.", "rest_bonus": 0.1, "vehicle_storage": 1, "monthly_rent": 500, "flavor": "", "unlock": {"flag": "rebuilding_started", "cash_min": 2000}},
	]


func _setup_dialogue_map() -> void:
	_dialogue_map = {
		Level.COUCH: "housing_upgrade_couch",
		Level.STUDIO: "housing_upgrade_studio",
		Level.APARTMENT: "housing_upgrade_apartment",
		Level.PENTHOUSE: "housing_upgrade_penthouse",
		Level.BACK_TO_CAR: "housing_fall",
	}


# =============================================================================
# QUERIES
# =============================================================================

func get_current_housing() -> Dictionary:
	## Returns the full data dictionary for the current housing level.
	if current_level >= 0 and current_level < _housing_data.size():
		var data: Dictionary = _housing_data[current_level].duplicate()
		data["level"] = current_level
		return data
	return {"id": "car", "name": "Your Car", "level": Level.CAR, "rest_bonus": 0.0, "vehicle_storage": 0, "monthly_rent": 0}


func get_housing_at_level(level: int) -> Dictionary:
	## Returns the data dictionary for a specific housing level.
	if level >= 0 and level < _housing_data.size():
		var data: Dictionary = _housing_data[level].duplicate()
		data["level"] = level
		return data
	return {}


func get_rest_bonus() -> float:
	## Returns the current rest bonus for skill XP calculations.
	var data := get_current_housing()
	return data.get("rest_bonus", 0.0)


func get_vehicle_storage() -> int:
	## Returns the number of extra garage slots from current housing.
	var data := get_current_housing()
	return data.get("vehicle_storage", 0)


func get_monthly_rent() -> int:
	## Returns the monthly rent cost for current housing.
	var data := get_current_housing()
	return data.get("monthly_rent", 0)


func can_afford_rent() -> bool:
	## Checks whether the player can pay this month's rent.
	var rent := get_monthly_rent()
	if rent <= 0:
		return true
	return GameManager.economy.can_afford(rent)


func get_available_upgrades() -> Array:
	## Returns an array of housing levels the player can currently upgrade to.
	## Only considers "forward" progression — not Fall/Rebuild levels unless
	## the corresponding story flags are set.
	var upgrades: Array = []
	for level_idx in range(_housing_data.size()):
		if level_idx == current_level:
			continue
		if not _can_unlock(level_idx):
			continue
		# During normal play (pre-Fall), only show levels 0-4
		# During post-Fall, show BACK_TO_CAR and REBUILD_STUDIO
		if current_level < Level.BACK_TO_CAR:
			# Normal progression — only show levels above current, up to PENTHOUSE
			if level_idx <= current_level or level_idx > Level.PENTHOUSE:
				continue
		else:
			# Post-Fall — only show REBUILD_STUDIO
			if level_idx != Level.REBUILD_STUDIO:
				continue
		var data: Dictionary = _housing_data[level_idx].duplicate()
		data["level"] = level_idx
		upgrades.append(data)
	return upgrades


# =============================================================================
# UPGRADE / DOWNGRADE
# =============================================================================

func upgrade_housing(level: int) -> bool:
	## Attempts to upgrade to the given housing level. Returns true on success.
	if level == current_level:
		print("[Housing] Already at level %d." % level)
		return false

	if not _can_unlock(level):
		print("[Housing] Cannot unlock level %d — conditions not met." % level)
		return false

	var old_level := current_level
	current_level = level
	months_rent_missed = 0

	var housing := get_current_housing()
	EventBus.housing_upgraded.emit(old_level, current_level, housing)

	# Trigger transition dialogue if one exists
	_trigger_transition_dialogue(current_level)

	print("[Housing] Upgraded: %s -> %s" % [
		LEVEL_TO_ID.get(old_level, "unknown"),
		LEVEL_TO_ID.get(current_level, "unknown"),
	])
	return true


func downgrade_housing(level: int) -> void:
	## Forces a downgrade to the given housing level (used by story events).
	var old_level := current_level
	current_level = level
	months_rent_missed = 0

	var housing := get_current_housing()
	EventBus.housing_downgraded.emit(old_level, current_level, housing)

	# Trigger transition dialogue if one exists
	_trigger_transition_dialogue(current_level)

	print("[Housing] Downgraded: %s -> %s" % [
		LEVEL_TO_ID.get(old_level, "unknown"),
		LEVEL_TO_ID.get(current_level, "unknown"),
	])


func trigger_fall_housing() -> void:
	## Called during Act 3: The Fall. Drops the player to BACK_TO_CAR.
	## Everything is gone. This is the emotional gut-punch moment.
	print("[Housing] THE FALL — losing everything.")
	downgrade_housing(Level.BACK_TO_CAR)
	EventBus.hud_message.emit("You're back in the car.", 5.0)


# =============================================================================
# RENT
# =============================================================================

func pay_rent() -> void:
	## Attempts to pay monthly rent. Called on month ticks.
	var rent := get_monthly_rent()
	if rent <= 0:
		return  # Free housing, no rent needed

	var housing_id: String = LEVEL_TO_ID.get(current_level, "unknown")

	if GameManager.economy.spend(rent, "rent_%s" % housing_id):
		months_rent_missed = 0
		EventBus.rent_paid.emit(rent, housing_id)
		print("[Housing] Rent paid: $%d for %s" % [rent, housing_id])
	else:
		months_rent_missed += 1
		EventBus.rent_missed.emit(rent, housing_id)
		print("[Housing] RENT MISSED (%d months): $%d for %s" % [months_rent_missed, rent, housing_id])
		_handle_missed_rent()


func _handle_missed_rent() -> void:
	## Consequences for missing rent. Escalates with each missed month.
	if months_rent_missed == 1:
		EventBus.hud_message.emit("Rent is overdue. Find some cash.", 4.0)
	elif months_rent_missed == 2:
		EventBus.hud_message.emit("Second month without rent. Eviction warning.", 5.0)
		# Small rep hit — word gets around
		GameManager.reputation.lose_rep(100, "missed_rent")
	elif months_rent_missed >= 3:
		# Eviction — forced downgrade
		EventBus.hud_message.emit("Evicted. Back to the car.", 6.0)
		GameManager.reputation.lose_rep(300, "eviction")
		if current_level <= Level.PENTHOUSE:
			downgrade_housing(Level.CAR)
		else:
			downgrade_housing(Level.BACK_TO_CAR)


# =============================================================================
# CONDITION CHECKING
# =============================================================================

func _can_unlock(level: int) -> bool:
	## Checks whether the player meets all unlock conditions for a housing level.
	if level < 0 or level >= _housing_data.size():
		return false

	var data: Dictionary = _housing_data[level]
	var unlock = data.get("unlock", "default")

	# Default — always available (starting housing)
	if unlock is String and unlock == "default":
		return true

	if not unlock is Dictionary:
		return false

	var unlock_dict: Dictionary = unlock

	# Check story flag requirement
	if unlock_dict.has("flag"):
		var flag: String = unlock_dict["flag"]
		if not GameManager.story.story_flags.get(flag, false):
			return false

	# Check cash minimum
	if unlock_dict.has("cash_min"):
		var cash_min: int = unlock_dict["cash_min"]
		if GameManager.economy.cash < cash_min:
			return false

	# Check reputation tier
	if unlock_dict.has("rep_tier"):
		var required_tier_name: String = unlock_dict["rep_tier"]
		var required_tier: int = REP_TIER_MAP.get(required_tier_name, 0)
		if GameManager.reputation.get_tier() < required_tier:
			return false

	return true


func _get_level_name() -> String:
	var data := get_current_housing()
	return data.get("name", "Unknown")


func _trigger_transition_dialogue(level: int) -> void:
	## Triggers the housing transition dialogue for the given level, if one exists.
	if _dialogue_map.has(level):
		var dialogue_id: String = _dialogue_map[level]
		EventBus.dialogue_started.emit(dialogue_id)


# =============================================================================
# TIME
# =============================================================================

func _on_time_period_changed(period: String) -> void:
	## Listen for month changes to trigger rent payment.
	## The WorldTimeSystem emits "month_start" at each new month.
	if period == "month_start":
		pay_rent()


# =============================================================================
# SERIALIZATION
# =============================================================================

func serialize() -> Dictionary:
	return {
		"current_level": current_level,
		"months_rent_missed": months_rent_missed,
	}


func deserialize(data: Dictionary) -> void:
	current_level = data.get("current_level", Level.CAR)
	months_rent_missed = data.get("months_rent_missed", 0)
	print("[Housing] Deserialized — level: %s, missed rent: %d" % [_get_level_name(), months_rent_missed])
