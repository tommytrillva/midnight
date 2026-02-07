## Manages the player's reputation (REP) which gates content access,
## story progression, and pink slip eligibility per GDD Section 6.2.
class_name ReputationSystem
extends Node

# REP tier thresholds from GDD
const TIERS := {
	0: {"name": "UNKNOWN", "min": 0, "max": 999},
	1: {"name": "NEWCOMER", "min": 1000, "max": 4999},
	2: {"name": "KNOWN", "min": 5000, "max": 14999},
	3: {"name": "RESPECTED", "min": 15000, "max": 34999},
	4: {"name": "FEARED", "min": 35000, "max": 74999},
	5: {"name": "LEGENDARY", "min": 75000, "max": 999999},
}

var current_rep: int = 0
var current_tier: int = 0
var peak_rep: int = 0 # Track highest REP for stats


func set_rep(value: int) -> void:
	var old_rep := current_rep
	current_rep = maxi(value, 0)
	if current_rep > peak_rep:
		peak_rep = current_rep
	var new_tier := _calculate_tier(current_rep)
	if new_tier != current_tier:
		var old_tier := current_tier
		current_tier = new_tier
		EventBus.rep_tier_changed.emit(old_tier, new_tier)
	if old_rep != current_rep:
		EventBus.rep_changed.emit(old_rep, current_rep)


func earn_rep(amount: int, source: String = "") -> void:
	var bonus_mult := 1.0
	# Apply bonuses per GDD
	if source == "clean_race":
		bonus_mult = 1.1
	elif source == "dominant_win":
		bonus_mult = 1.25
	elif source == "comeback_win":
		bonus_mult = 1.5

	var final_amount := int(float(amount) * bonus_mult)
	set_rep(current_rep + final_amount)
	EventBus.rep_earned.emit(final_amount, source)


func lose_rep(amount: int, source: String = "") -> void:
	set_rep(current_rep - amount)
	EventBus.rep_lost.emit(amount, source)


func apply_fall_penalty() -> void:
	## Act 3: The Fall — lose 90% of REP.
	var loss := int(current_rep * 0.9)
	lose_rep(loss, "act3_fall")
	print("[REP] The Fall: Lost %d REP (90%%)" % loss)


func get_tier() -> int:
	return current_tier


func get_tier_name() -> String:
	return TIERS[current_tier].name


func get_tier_progress() -> float:
	## Returns 0.0-1.0 progress within current tier.
	var tier_data: Dictionary = TIERS[current_tier]
	var range_size := tier_data.max - tier_data.min
	if range_size <= 0:
		return 1.0
	return clampf(float(current_rep - tier_data.min) / float(range_size), 0.0, 1.0)


func can_access_district(district_id: String) -> bool:
	## Check if player REP tier allows access to a district.
	var required_tiers := {
		"downtown": 0,
		"industrial": 1,
		"highway": 1,
		"port": 2,
		"suburbs": 2,
		"hills": 3,
	}
	return current_tier >= required_tiers.get(district_id, 0)


func can_pink_slip(vehicle_class: String) -> bool:
	## Check if player can participate in pink slip for given class.
	var required_tiers := {
		"D": 2,
		"C": 2,
		"B": 3,
		"A": 4,
		"S": 5,
	}
	return current_tier >= required_tiers.get(vehicle_class, 0)


func _calculate_tier(rep: int) -> int:
	for tier in range(5, -1, -1):
		if rep >= TIERS[tier].min:
			return tier
	return 0


func serialize() -> Dictionary:
	return {
		"current_rep": current_rep,
		"current_tier": current_tier,
		"peak_rep": peak_rep,
	}


func deserialize(data: Dictionary) -> void:
	current_rep = data.get("current_rep", 0)
	current_tier = data.get("current_tier", 0)
	peak_rep = data.get("peak_rep", 0)
