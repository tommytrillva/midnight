## Manages relationships with all major characters.
## Per GDD Section 7.2: 0-100 affinity with 5 levels per character.
## Relationships gate missions, dialogue, story outcomes, and endings.
class_name RelationshipSystem
extends Node

# Relationship level thresholds from GDD
const LEVEL_THRESHOLDS := [0, 21, 41, 61, 81]
const LEVEL_NAMES := ["Stranger", "Acquaintance", "Friend", "Close", "Family"]

# Character-specific level names
const CHARACTER_LEVEL_NAMES := {
	"maya": ["Stranger", "Client", "Friend", "Close", "Romance/Family"],
	"diesel": ["Observed", "Tested", "Mentored", "Trusted", "Redeemed"],
	"nikko": ["Rival", "Enemy", "Understood", "Respect", "Brother"],
	"jade": ["Business", "Investment", "Conflicted", "Ally", "Free"],
	"zero": ["Unknown", "Aware", "Contacted", "Entangled", "Resolution"],
}

# All tracked characters
var relationships: Dictionary = {} # character_id -> { affinity, level, events }


func _ready() -> void:
	_init_characters()


func _init_characters() -> void:
	for char_id in ["maya", "diesel", "nikko", "jade", "zero"]:
		relationships[char_id] = {
			"affinity": 0,
			"level": 1,
			"interactions": 0,
			"flags": {},
		}


func change_affinity(character_id: String, amount: int) -> void:
	if not relationships.has(character_id):
		push_error("[Relationships] Unknown character: %s" % character_id)
		return

	var char_data: Dictionary = relationships[character_id]
	var old_value: int = char_data.affinity
	char_data.affinity = clampi(old_value + amount, 0, 100)
	char_data.interactions += 1

	var new_level := _calculate_level(char_data.affinity)
	var old_level: int = char_data.level

	if new_level != old_level:
		char_data.level = new_level
		if new_level > old_level:
			EventBus.relationship_level_up.emit(character_id, new_level)
			print("[Relationships] %s level UP: %s (%d)" % [
				character_id,
				get_level_name(character_id, new_level),
				new_level
			])
		else:
			EventBus.relationship_level_down.emit(character_id, new_level)

	EventBus.relationship_changed.emit(character_id, old_value, char_data.affinity)


func get_affinity(character_id: String) -> int:
	if not relationships.has(character_id):
		return 0
	return relationships[character_id].affinity


func get_level(character_id: String) -> int:
	if not relationships.has(character_id):
		return 1
	return relationships[character_id].level


func get_level_name(character_id: String, level: int = -1) -> String:
	if level == -1:
		level = get_level(character_id)
	if CHARACTER_LEVEL_NAMES.has(character_id):
		var names: Array = CHARACTER_LEVEL_NAMES[character_id]
		return names[clampi(level - 1, 0, names.size() - 1)]
	return LEVEL_NAMES[clampi(level - 1, 0, LEVEL_NAMES.size() - 1)]


func get_highest_affinity_character() -> String:
	## Returns the character with highest affinity. Used for Act 3/4 logic.
	var best_id := ""
	var best_value := -1
	for char_id in relationships:
		if char_id == "zero": # Zero is not a friend
			continue
		var aff: int = relationships[char_id].affinity
		if aff > best_value:
			best_value = aff
			best_id = char_id
	return best_id


func get_characters_at_level(min_level: int) -> Array[String]:
	## Returns character IDs at or above the specified level.
	## Used for Act 4 — who returns to help.
	var result: Array[String] = []
	for char_id in relationships:
		if char_id == "zero":
			continue
		if relationships[char_id].level >= min_level:
			result.append(char_id)
	return result


func set_character_flag(character_id: String, flag: String, value: Variant = true) -> void:
	if relationships.has(character_id):
		relationships[character_id].flags[flag] = value


func get_character_flag(character_id: String, flag: String, default: Variant = null) -> Variant:
	if not relationships.has(character_id):
		return default
	return relationships[character_id].flags.get(flag, default)


func apply_fall_strain() -> void:
	## Act 3: The Fall — strain all relationships.
	## Highest affinity character loses least, others lose more.
	var best := get_highest_affinity_character()
	for char_id in relationships:
		if char_id == "zero":
			continue
		if char_id == best:
			change_affinity(char_id, -10) # Slight decrease for closest ally
		else:
			change_affinity(char_id, -30) # Major decrease for others
	print("[Relationships] Act 3 Fall strain applied. Closest ally: %s" % best)


func reset_all() -> void:
	_init_characters()


func _calculate_level(affinity: int) -> int:
	for i in range(LEVEL_THRESHOLDS.size() - 1, -1, -1):
		if affinity >= LEVEL_THRESHOLDS[i]:
			return i + 1
	return 1


func serialize() -> Dictionary:
	return {"relationships": relationships}


func deserialize(data: Dictionary) -> void:
	relationships = data.get("relationships", {})
	if relationships.is_empty():
		_init_characters()
