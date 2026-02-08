## Core player data container. Tracks all persistent player state
## across sessions. Serializable for save/load.
class_name PlayerData
extends RefCounted

# --- Origin System ---
enum Origin { FALLEN, OUTSIDER, GHOST_ORIGIN }
var origin: Origin = Origin.OUTSIDER
var origin_id: String = "outsider"  # For dialogue condition checking

var player_name: String = "Racer"
var current_vehicle_id: String = ""
var owned_vehicle_ids: Array[String] = []
var current_district: String = "downtown"
var total_races: int = 0
var total_wins: int = 0
var total_losses: int = 0
var total_dnfs: int = 0
var total_pink_slips_won: int = 0
var total_pink_slips_lost: int = 0
var play_time_seconds: float = 0.0

# Hidden moral tracking (never shown to player per GDD)
var _moral_alignment: float = 0.0 # -100 (ruthless) to +100 (honorable)
var _zero_awareness: int = 0 # 0-5, tracks knowledge of Zero
var _choice_flags: Dictionary = {} # Tracks specific narrative decisions


func set_origin(new_origin: Origin) -> void:
	origin = new_origin
	match origin:
		Origin.FALLEN:
			origin_id = "fallen"
		Origin.OUTSIDER:
			origin_id = "outsider"
		Origin.GHOST_ORIGIN:
			origin_id = "ghost_origin"
	print("[PlayerData] Origin set: %s" % origin_id)


func get_origin_id() -> String:
	return origin_id


func record_race_result(won: bool, dnf: bool = false) -> void:
	total_races += 1
	if dnf:
		total_dnfs += 1
	elif won:
		total_wins += 1
	else:
		total_losses += 1


func record_pink_slip(won: bool) -> void:
	if won:
		total_pink_slips_won += 1
	else:
		total_pink_slips_lost += 1


func get_win_rate() -> float:
	if total_races == 0:
		return 0.0
	return float(total_wins) / float(total_races)


func shift_moral_alignment(amount: float) -> void:
	_moral_alignment = clampf(_moral_alignment + amount, -100.0, 100.0)


func set_choice_flag(flag_id: String, value: Variant = true) -> void:
	_choice_flags[flag_id] = value


func get_choice_flag(flag_id: String, default: Variant = null) -> Variant:
	return _choice_flags.get(flag_id, default)


func has_choice_flag(flag_id: String) -> bool:
	return _choice_flags.has(flag_id)


func set_zero_awareness(level: int) -> void:
	_zero_awareness = clampi(level, 0, 5)


func serialize() -> Dictionary:
	return {
		"player_name": player_name,
		"origin": origin,
		"origin_id": origin_id,
		"current_vehicle_id": current_vehicle_id,
		"owned_vehicle_ids": owned_vehicle_ids,
		"current_district": current_district,
		"total_races": total_races,
		"total_wins": total_wins,
		"total_losses": total_losses,
		"total_dnfs": total_dnfs,
		"total_pink_slips_won": total_pink_slips_won,
		"total_pink_slips_lost": total_pink_slips_lost,
		"play_time_seconds": play_time_seconds,
		"_moral_alignment": _moral_alignment,
		"_zero_awareness": _zero_awareness,
		"_choice_flags": _choice_flags,
	}


func deserialize(data: Dictionary) -> void:
	player_name = data.get("player_name", "Racer")
	origin = data.get("origin", Origin.OUTSIDER)
	origin_id = data.get("origin_id", "outsider")
	current_vehicle_id = data.get("current_vehicle_id", "")
	owned_vehicle_ids.assign(data.get("owned_vehicle_ids", []))
	current_district = data.get("current_district", "downtown")
	total_races = data.get("total_races", 0)
	total_wins = data.get("total_wins", 0)
	total_losses = data.get("total_losses", 0)
	total_dnfs = data.get("total_dnfs", 0)
	total_pink_slips_won = data.get("total_pink_slips_won", 0)
	total_pink_slips_lost = data.get("total_pink_slips_lost", 0)
	play_time_seconds = data.get("play_time_seconds", 0.0)
	_moral_alignment = data.get("_moral_alignment", 0.0)
	_zero_awareness = data.get("_zero_awareness", 0)
	_choice_flags = data.get("_choice_flags", {})
