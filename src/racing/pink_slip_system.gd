## Manages pink slip race challenges, vehicle wagering, and ownership transfers.
## Supports story-protected, voluntary, and NPC-challenged pink slip types.
## Validates value fairness, enforces safety rules (cannot wager last car),
## and handles REP consequences for declining challenges.
class_name PinkSlipSystem
extends Node

enum ChallengeType { STORY, VOLUNTARY, CHALLENGED }
enum ChallengeState { PENDING, ACCEPTED, DECLINED, IN_RACE, WON, LOST, EXPIRED }

## Fairness threshold — vehicles must be within this percentage of each other's value.
const FAIRNESS_THRESHOLD := 0.30
## REP penalty for declining an NPC challenge.
const DECLINE_REP_PENALTY := 250
## Bonus REP multiplier when wagering a higher-value car.
const VALUE_UNDERDOG_REP_MULT := 1.5

var active_challenges: Dictionary = {} # challenge_id -> Dictionary
var completed_challenges: Array[String] = []
var _challenge_data_cache: Array = []


func _ready() -> void:
	_load_challenge_data()
	EventBus.race_finished.connect(_on_race_finished)
	print("[PinkSlip] System initialized")


# ---------------------------------------------------------------------------
# Challenge Data Loading
# ---------------------------------------------------------------------------

func _load_challenge_data() -> void:
	var path := "res://data/pink_slips/challenges.json"
	if not FileAccess.file_exists(path):
		push_warning("[PinkSlip] No challenge data found at: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[PinkSlip] Failed to open: %s" % path)
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[PinkSlip] Failed to parse: %s" % path)
		return
	file.close()

	var data: Dictionary = json.data
	_challenge_data_cache = data.get("challenges", [])
	print("[PinkSlip] Loaded %d challenge definitions" % _challenge_data_cache.size())


# ---------------------------------------------------------------------------
# Challenge Creation & Validation
# ---------------------------------------------------------------------------

func create_challenge(
	player_vehicle: VehicleData,
	opponent_vehicle: VehicleData,
	race_config: Dictionary
) -> Dictionary:
	## Build a new pink slip challenge dictionary.
	## race_config expects: type (string), race_data (RaceData), opponent_name, challenge_def_id (optional).
	var challenge_id: String = "ps_%s_%d" % [
		opponent_vehicle.vehicle_id,
		Time.get_ticks_msec()
	]

	var player_value := get_vehicle_value(player_vehicle)
	var opponent_value := get_vehicle_value(opponent_vehicle)
	var fairness := _calculate_fairness(player_value, opponent_value)
	var challenge_type_str: String = race_config.get("type", "voluntary")
	var challenge_type: ChallengeType = _parse_challenge_type(challenge_type_str)

	var challenge := {
		"challenge_id": challenge_id,
		"challenge_type": challenge_type,
		"challenge_type_name": ChallengeType.keys()[challenge_type],
		"state": ChallengeState.PENDING,
		"player_vehicle_id": player_vehicle.vehicle_id,
		"player_vehicle_name": player_vehicle.display_name,
		"player_vehicle_value": player_value,
		"opponent_vehicle_id": opponent_vehicle.vehicle_id,
		"opponent_vehicle_name": opponent_vehicle.display_name,
		"opponent_vehicle_value": opponent_value,
		"opponent_name": race_config.get("opponent_name", "Unknown"),
		"race_data": race_config.get("race_data", null),
		"fairness_ratio": fairness,
		"fairness_label": _get_fairness_label(fairness),
		"story_protected": race_config.get("story_protected", false),
		"challenge_def_id": race_config.get("challenge_def_id", ""),
		"opponent_dialogue_pre": race_config.get("opponent_dialogue_pre", ""),
		"opponent_dialogue_win": race_config.get("opponent_dialogue_win", ""),
		"opponent_dialogue_lose": race_config.get("opponent_dialogue_lose", ""),
		"created_at": Time.get_datetime_string_from_system(),
	}

	active_challenges[challenge_id] = challenge
	print("[PinkSlip] Challenge created: %s vs %s (fairness: %s)" % [
		player_vehicle.display_name,
		opponent_vehicle.display_name,
		challenge["fairness_label"],
	])

	return challenge


func validate_challenge(challenge: Dictionary) -> bool:
	## Returns true if the challenge is valid and safe to accept.
	## Checks: player has >1 vehicle, vehicle exists, not story-protected from loss.
	var player_vid: String = challenge.get("player_vehicle_id", "")
	var garage: GarageSystem = GameManager.garage

	# Cannot wager your only vehicle
	if garage.get_vehicle_count() <= 1:
		print("[PinkSlip] BLOCKED: Cannot wager only vehicle")
		return false

	# Player vehicle must still exist in garage
	if garage.get_vehicle(player_vid) == null:
		print("[PinkSlip] BLOCKED: Player vehicle not found: %s" % player_vid)
		return false

	# Check if player vehicle has wager protection (story-critical)
	var vehicle := garage.get_vehicle(player_vid)
	if vehicle and vehicle.acquired_method == "story_protected":
		print("[PinkSlip] BLOCKED: Vehicle has story wager protection: %s" % player_vid)
		return false

	return true


func accept_challenge(challenge_id: String) -> void:
	## Accept a pink slip challenge and prepare for the race.
	if not active_challenges.has(challenge_id):
		push_error("[PinkSlip] Challenge not found: %s" % challenge_id)
		return

	var challenge: Dictionary = active_challenges[challenge_id]

	if not validate_challenge(challenge):
		push_warning("[PinkSlip] Challenge validation failed: %s" % challenge_id)
		return

	challenge["state"] = ChallengeState.ACCEPTED
	active_challenges[challenge_id] = challenge

	EventBus.pink_slip_accepted.emit({
		"challenge_id": challenge_id,
		"player_vehicle_id": challenge.get("player_vehicle_id", ""),
		"opponent_vehicle_id": challenge.get("opponent_vehicle_id", ""),
		"opponent_name": challenge.get("opponent_name", ""),
	})

	print("[PinkSlip] Challenge accepted: %s" % challenge_id)


func decline_challenge(challenge_id: String) -> void:
	## Decline a pink slip challenge. Costs REP for CHALLENGED types.
	if not active_challenges.has(challenge_id):
		push_error("[PinkSlip] Challenge not found: %s" % challenge_id)
		return

	var challenge: Dictionary = active_challenges[challenge_id]
	challenge["state"] = ChallengeState.DECLINED
	active_challenges[challenge_id] = challenge

	# REP penalty for declining an NPC challenge
	var rep_cost := 0
	if challenge.get("challenge_type", ChallengeType.VOLUNTARY) == ChallengeType.CHALLENGED:
		rep_cost = DECLINE_REP_PENALTY
		GameManager.reputation.lose_rep(rep_cost, "pink_slip_declined")
		print("[PinkSlip] Challenge declined — lost %d REP" % rep_cost)
	else:
		print("[PinkSlip] Challenge declined (no penalty)")

	EventBus.pink_slip_declined.emit({
		"challenge_id": challenge_id,
		"opponent_name": challenge.get("opponent_name", ""),
		"rep_cost": rep_cost,
	})

	# Move to completed
	completed_challenges.append(challenge_id)


func resolve_pink_slip(challenge_id: String, player_won: bool) -> void:
	## Resolve a pink slip race — transfer vehicle ownership.
	if not active_challenges.has(challenge_id):
		push_error("[PinkSlip] Cannot resolve — challenge not found: %s" % challenge_id)
		return

	var challenge: Dictionary = active_challenges[challenge_id]
	var garage: GarageSystem = GameManager.garage

	if player_won:
		challenge["state"] = ChallengeState.WON
		active_challenges[challenge_id] = challenge

		# Player wins opponent's vehicle
		var opponent_data := {
			"vehicle_id": challenge.get("opponent_vehicle_id", ""),
			"display_name": challenge.get("opponent_vehicle_name", "Unknown"),
		}
		EventBus.pink_slip_won.emit(opponent_data)

		# Bonus REP for pink slip win, scaled by value difference
		var player_val: int = challenge.get("player_vehicle_value", 0)
		var opponent_val: int = challenge.get("opponent_vehicle_value", 0)
		var rep_bonus := 500
		if player_val < opponent_val:
			rep_bonus = int(rep_bonus * VALUE_UNDERDOG_REP_MULT)
		GameManager.reputation.earn_rep(rep_bonus, "pink_slip_win")

		print("[PinkSlip] PLAYER WON: Gained %s" % challenge.get("opponent_vehicle_name", ""))

	else:
		# Story-protected challenges prevent vehicle loss
		if challenge.get("story_protected", false):
			challenge["state"] = ChallengeState.LOST
			active_challenges[challenge_id] = challenge
			print("[PinkSlip] Story protection — player keeps vehicle despite loss")
		else:
			challenge["state"] = ChallengeState.LOST
			active_challenges[challenge_id] = challenge

			# Player loses their wagered vehicle
			var lost_data := {
				"vehicle_id": challenge.get("player_vehicle_id", ""),
				"display_name": challenge.get("player_vehicle_name", "Unknown"),
			}
			EventBus.pink_slip_lost.emit(lost_data)

			# REP loss for losing a pink slip
			GameManager.reputation.lose_rep(300, "pink_slip_loss")

			print("[PinkSlip] PLAYER LOST: Lost %s" % challenge.get("player_vehicle_name", ""))

	# Move to completed
	completed_challenges.append(challenge_id)


# ---------------------------------------------------------------------------
# Vehicle Value Assessment
# ---------------------------------------------------------------------------

func get_vehicle_value(vehicle: VehicleData) -> int:
	## Calculate estimated market value of a vehicle (base price + installed parts).
	return vehicle.calculate_value()


func _calculate_fairness(player_value: int, opponent_value: int) -> float:
	## Returns a ratio indicating how fair the match is.
	## 1.0 = perfectly even, <1.0 = player has cheaper car, >1.0 = player has pricier car.
	if opponent_value <= 0:
		return 1.0
	return float(player_value) / float(opponent_value)


func _get_fairness_label(ratio: float) -> String:
	## Convert fairness ratio to a human-readable label.
	var diff := absf(ratio - 1.0)
	if diff <= FAIRNESS_THRESHOLD:
		return "FAIR MATCH"
	elif diff <= 0.6:
		return "RISKY"
	else:
		return "SUICIDE"


# ---------------------------------------------------------------------------
# Available Challenges Query
# ---------------------------------------------------------------------------

func get_available_challenges() -> Array:
	## Returns challenge definitions the player qualifies for and hasn't completed.
	var available: Array = []
	var current_rep: int = GameManager.reputation.current_rep

	for def in _challenge_data_cache:
		var def_id: String = def.get("id", "")

		# Skip already completed
		if def_id in completed_challenges:
			continue

		# Skip if already active
		var already_active := false
		for cid in active_challenges:
			if active_challenges[cid].get("challenge_def_id", "") == def_id:
				already_active = true
				break
		if already_active:
			continue

		# Check REP requirement
		var min_rep: int = def.get("min_rep", 0)
		if current_rep < min_rep:
			continue

		# Check story path requirement
		var required_path: String = def.get("path", "")
		if not required_path.is_empty():
			if GameManager.story.chosen_path != required_path:
				continue

		# Check mission completion requirement
		var required_mission: String = def.get("requires_mission", "")
		if not required_mission.is_empty():
			if not GameManager.story.is_mission_completed(required_mission):
				continue

		# Check act requirement
		var min_act: int = def.get("min_act", 0)
		if min_act > 0 and GameManager.story.current_act < min_act:
			continue

		available.append(def)

	return available


func get_challenge_by_id(challenge_id: String) -> Dictionary:
	## Get an active challenge by its ID.
	return active_challenges.get(challenge_id, {})


func get_active_challenge_for_race() -> Dictionary:
	## Returns the currently accepted challenge (if any) that is ready to race.
	for cid in active_challenges:
		var challenge: Dictionary = active_challenges[cid]
		if challenge.get("state", ChallengeState.PENDING) == ChallengeState.ACCEPTED:
			return challenge
	return {}


func set_challenge_in_race(challenge_id: String) -> void:
	## Mark a challenge as currently being raced.
	if active_challenges.has(challenge_id):
		active_challenges[challenge_id]["state"] = ChallengeState.IN_RACE


# ---------------------------------------------------------------------------
# NPC Challenge Trigger
# ---------------------------------------------------------------------------

func trigger_npc_challenge(challenge_def_id: String) -> Dictionary:
	## Called by story/world systems when an NPC initiates a pink slip challenge.
	## Returns the challenge dictionary for the UI to display.
	var def := {}
	for d in _challenge_data_cache:
		if d.get("id", "") == challenge_def_id:
			def = d
			break

	if def.is_empty():
		push_error("[PinkSlip] Challenge definition not found: %s" % challenge_def_id)
		return {}

	# Build opponent vehicle from database
	var opponent_vehicle := VehicleData.new()
	opponent_vehicle.vehicle_id = def.get("opponent_vehicle", "")
	opponent_vehicle.display_name = def.get("opponent_vehicle_name", "Unknown Ride")

	# Load vehicle data from vehicle database if available
	var vehicle_db_path := "res://data/vehicles/%s.json" % opponent_vehicle.vehicle_id
	if FileAccess.file_exists(vehicle_db_path):
		var vfile := FileAccess.open(vehicle_db_path, FileAccess.READ)
		if vfile:
			var vjson := JSON.new()
			if vjson.parse(vfile.get_as_text()) == OK:
				var vdata: Dictionary = vjson.data
				opponent_vehicle.display_name = vdata.get("display_name", opponent_vehicle.display_name)
				opponent_vehicle.manufacturer = vdata.get("manufacturer", "")
				opponent_vehicle.stock_hp = vdata.get("stock_hp", 200.0)
				opponent_vehicle.current_hp = opponent_vehicle.stock_hp
				opponent_vehicle.weight_kg = vdata.get("weight_kg", 1300.0)
				opponent_vehicle.base_speed = vdata.get("base_speed", 100.0)
				opponent_vehicle.base_acceleration = vdata.get("base_acceleration", 50.0)
				opponent_vehicle.base_handling = vdata.get("base_handling", 50.0)
				opponent_vehicle.estimated_value = vdata.get("estimated_value", 15000)
			vfile.close()

	# Get player's current vehicle as default wager
	var player_vid: String = GameManager.player_data.current_vehicle_id
	var player_vehicle: VehicleData = GameManager.garage.get_vehicle(player_vid)
	if player_vehicle == null:
		push_error("[PinkSlip] Player has no current vehicle")
		return {}

	var race_config := {
		"type": def.get("type", "voluntary"),
		"opponent_name": def.get("opponent_name", "Unknown"),
		"story_protected": def.get("story_protected", false),
		"challenge_def_id": challenge_def_id,
		"opponent_dialogue_pre": def.get("opponent_dialogue_pre", ""),
		"opponent_dialogue_win": def.get("opponent_dialogue_win", ""),
		"opponent_dialogue_lose": def.get("opponent_dialogue_lose", ""),
	}

	var challenge := create_challenge(player_vehicle, opponent_vehicle, race_config)

	EventBus.pink_slip_challenged.emit({
		"challenge_id": challenge.get("challenge_id", ""),
		"opponent_name": def.get("opponent_name", ""),
		"opponent_vehicle": opponent_vehicle.display_name,
		"challenge_type": def.get("type", "voluntary"),
	})

	return challenge


# ---------------------------------------------------------------------------
# Race Finish Hook
# ---------------------------------------------------------------------------

func _on_race_finished(results: Dictionary) -> void:
	## Automatically resolve pink slip if the finished race was a pink slip.
	if not results.get("is_pink_slip", false):
		return

	var challenge := get_active_challenge_for_race()
	if challenge.is_empty():
		# Check IN_RACE state challenges too
		for cid in active_challenges:
			var c: Dictionary = active_challenges[cid]
			if c.get("state", ChallengeState.PENDING) == ChallengeState.IN_RACE:
				challenge = c
				break

	if challenge.is_empty():
		print("[PinkSlip] Race finished as pink slip but no active challenge found")
		return

	var player_won: bool = results.get("player_won", false)
	resolve_pink_slip(challenge.get("challenge_id", ""), player_won)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _parse_challenge_type(type_str: String) -> ChallengeType:
	match type_str.to_lower():
		"story": return ChallengeType.STORY
		"voluntary": return ChallengeType.VOLUNTARY
		"challenged": return ChallengeType.CHALLENGED
		_: return ChallengeType.VOLUNTARY


func is_wagering_last_vehicle(vehicle_id: String) -> bool:
	## Check if wagering this vehicle would leave the player with zero cars.
	## (Player must keep at least 1.)
	var garage: GarageSystem = GameManager.garage
	return garage.get_vehicle_count() <= 1


func get_rep_cost_for_decline(challenge: Dictionary) -> int:
	## Returns how much REP declining this challenge would cost.
	if challenge.get("challenge_type", ChallengeType.VOLUNTARY) == ChallengeType.CHALLENGED:
		return DECLINE_REP_PENALTY
	return 0


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	# Only serialize completed challenge IDs — active challenges are transient
	return {
		"completed_challenges": completed_challenges.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	completed_challenges.clear()
	var saved: Array = data.get("completed_challenges", [])
	for cid in saved:
		completed_challenges.append(str(cid))
	print("[PinkSlip] Deserialized — %d completed challenges" % completed_challenges.size())
