## Manages the player's chosen backstory origin and applies origin-specific
## stat bonuses. The origin is selected during the prologue when Maya asks
## the player why they are in Nova Pacifica.
##
## FALLEN:       Former promising driver, sabotaged. +5% driving skill multiplier.
##               Characters recognize you.
## OUTSIDER:     Blue collar worker, discovered racing by accident.
##               -10% repair costs, +5% part knowledge.
## GHOST_ORIGIN: Mysterious, backstory revealed slowly.
##               Balanced +3% all stats. Characters project assumptions.
class_name OriginSystem
extends Node

# --- Origin stat modifier tables ---
const ORIGIN_BONUSES := {
	"fallen": {
		"driving_skill_multiplier": 0.05,
		"repair_cost_modifier": 0.0,
		"part_knowledge_bonus": 0.0,
		"all_stats_bonus": 0.0,
		"description": "Once a rising star. Sabotaged, disgraced, hungry for redemption.",
	},
	"outsider": {
		"driving_skill_multiplier": 0.0,
		"repair_cost_modifier": -0.10,
		"part_knowledge_bonus": 0.05,
		"all_stats_bonus": 0.0,
		"description": "Blue collar. No pedigree. Just raw hunger and calloused hands.",
	},
	"ghost_origin": {
		"driving_skill_multiplier": 0.0,
		"repair_cost_modifier": 0.0,
		"part_knowledge_bonus": 0.0,
		"all_stats_bonus": 0.03,
		"description": "No past. No name. Just a shadow behind the wheel.",
	},
}

var _origin_id: String = ""
var _origin_set: bool = false


func _ready() -> void:
	EventBus.choice_made.connect(_on_choice_made)
	print("[Origin] OriginSystem initialized.")


func set_origin(origin: PlayerData.Origin) -> void:
	## Set the player's origin and apply bonuses. Should only be called once.
	GameManager.player_data.set_origin(origin)
	_origin_id = GameManager.player_data.origin_id
	_origin_set = true
	_apply_origin_bonuses()
	EventBus.origin_chosen.emit(_origin_id)
	print("[Origin] Origin chosen: %s" % _origin_id)


func get_origin_id() -> String:
	return _origin_id


func is_origin(check_id: String) -> bool:
	## Check if the current origin matches the given id.
	## Used for conditional dialogue checks.
	return _origin_id == check_id


func is_origin_set() -> bool:
	return _origin_set


func get_bonus(stat_name: String) -> float:
	## Get a specific origin bonus value by stat name.
	if _origin_id.is_empty():
		return 0.0
	var bonuses: Dictionary = ORIGIN_BONUSES.get(_origin_id, {})
	return bonuses.get(stat_name, 0.0)


func get_driving_skill_multiplier() -> float:
	## Returns the driving skill bonus (0.05 for Fallen, 0.03 for Ghost, 0 for Outsider).
	if _origin_id == "ghost_origin":
		return ORIGIN_BONUSES["ghost_origin"]["all_stats_bonus"]
	return get_bonus("driving_skill_multiplier")


func get_repair_cost_modifier() -> float:
	## Returns repair cost modifier (-0.10 for Outsider, -0.03 for Ghost, 0 for Fallen).
	if _origin_id == "ghost_origin":
		return -ORIGIN_BONUSES["ghost_origin"]["all_stats_bonus"]
	return get_bonus("repair_cost_modifier")


func get_part_knowledge_bonus() -> float:
	## Returns part knowledge bonus (0.05 for Outsider, 0.03 for Ghost, 0 for Fallen).
	if _origin_id == "ghost_origin":
		return ORIGIN_BONUSES["ghost_origin"]["all_stats_bonus"]
	return get_bonus("part_knowledge_bonus")


func get_origin_description() -> String:
	if _origin_id.is_empty():
		return ""
	return ORIGIN_BONUSES.get(_origin_id, {}).get("description", "")


func _apply_origin_bonuses() -> void:
	## Apply origin-specific stat bonuses through the relevant subsystems.
	## Bonuses are applied as persistent modifiers, not one-time changes.
	match _origin_id:
		"fallen":
			# Better driving skills — characters recognize you
			GameManager.player_data.set_choice_flag("fallen_origin", true)
			GameManager.player_data.set_choice_flag("origin_recognized", true)
			print("[Origin] Applied FALLEN bonuses: +5%% driving skill")

		"outsider":
			# Better mechanical knowledge, cheaper repairs
			GameManager.player_data.set_choice_flag("outsider_origin", true)
			GameManager.player_data.set_choice_flag("origin_mechanical", true)
			print("[Origin] Applied OUTSIDER bonuses: -10%% repair costs, +5%% part knowledge")

		"ghost_origin":
			# Balanced stats, mysterious background
			GameManager.player_data.set_choice_flag("ghost_origin", true)
			GameManager.player_data.set_choice_flag("origin_mysterious", true)
			print("[Origin] Applied GHOST bonuses: +3%% all stats")


func _on_choice_made(choice_id: String, _option_index: int, option_data: Dictionary) -> void:
	## Listen for origin choice from the prologue dialogue.
	match choice_id:
		"origin_fallen":
			set_origin(PlayerData.Origin.FALLEN)
		"origin_outsider":
			set_origin(PlayerData.Origin.OUTSIDER)
		"origin_ghost":
			set_origin(PlayerData.Origin.GHOST_ORIGIN)


func serialize() -> Dictionary:
	return {
		"origin_id": _origin_id,
		"origin_set": _origin_set,
	}


func deserialize(data: Dictionary) -> void:
	_origin_id = data.get("origin_id", "")
	_origin_set = data.get("origin_set", false)
	if _origin_set and not _origin_id.is_empty():
		# Restore origin on player_data without re-applying bonuses
		match _origin_id:
			"fallen":
				GameManager.player_data.origin = PlayerData.Origin.FALLEN
				GameManager.player_data.origin_id = "fallen"
			"outsider":
				GameManager.player_data.origin = PlayerData.Origin.OUTSIDER
				GameManager.player_data.origin_id = "outsider"
			"ghost_origin":
				GameManager.player_data.origin = PlayerData.Origin.GHOST_ORIGIN
				GameManager.player_data.origin_id = "ghost_origin"
		print("[Origin] Restored origin from save: %s" % _origin_id)
