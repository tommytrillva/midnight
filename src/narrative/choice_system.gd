## Tracks all player choices with categorization and consequence logging.
## Choices are categorized by type and logged with timestamps for the
## consequence system, moral tracker, and ending calculator to query.
class_name ChoiceSystem
extends Node

# Choice categories
const TYPE_RELATIONSHIP := "relationship" # Affects character feelings
const TYPE_REPUTATION := "reputation"     # Affects world perception
const TYPE_MORAL := "moral"               # Affects hidden moral alignment
const TYPE_STRATEGIC := "strategic"       # Affects resources/capabilities

# All recorded choices: choice_id -> { id, category, timestamp, consequence_applied, data }
var _choices: Dictionary = {}

# Quick lookup by category
var _choices_by_category: Dictionary = {
	TYPE_RELATIONSHIP: [],
	TYPE_REPUTATION: [],
	TYPE_MORAL: [],
	TYPE_STRATEGIC: [],
}


func _ready() -> void:
	EventBus.choice_made.connect(_on_choice_made)
	print("[Choice] ChoiceSystem initialized.")


func record_choice(choice_id: String, category: String, data: Dictionary = {}) -> void:
	## Record a player choice with its category and associated data.
	var choice_record := {
		"id": choice_id,
		"category": category,
		"timestamp": GameManager.player_data.play_time_seconds,
		"consequence_applied": false,
		"data": data,
	}
	_choices[choice_id] = choice_record

	# Index by category
	if _choices_by_category.has(category):
		if choice_id not in _choices_by_category[category]:
			_choices_by_category[category].append(choice_id)
	else:
		_choices_by_category[category] = [choice_id]

	EventBus.choice_recorded.emit(choice_id, category)
	print("[Choice] Recorded: %s (category: %s)" % [choice_id, category])


func has_made_choice(choice_id: String) -> bool:
	## Check if a specific choice has been made.
	return _choices.has(choice_id)


func get_choice_data(choice_id: String) -> Dictionary:
	## Get the full record for a specific choice.
	return _choices.get(choice_id, {})


func get_choices_by_category(category: String) -> Array:
	## Get all choice IDs in a given category.
	var ids: Array = _choices_by_category.get(category, [])
	var result: Array = []
	for choice_id in ids:
		if _choices.has(choice_id):
			result.append(_choices[choice_id])
	return result


func mark_consequence_applied(choice_id: String) -> void:
	## Mark that a choice's consequence has been applied.
	if _choices.has(choice_id):
		_choices[choice_id].consequence_applied = true


func get_moral_alignment() -> float:
	## Returns the hidden moral alignment from -100 to +100.
	## This value is NEVER shown to the player.
	return GameManager.player_data._moral_alignment


func get_story_path() -> String:
	## Returns the player's chosen path: "corporate" or "underground".
	## Returns empty string if The Fork hasn't been reached yet.
	return GameManager.story.chosen_path


func evaluate_ending_conditions() -> String:
	## Determines which ending the player gets based on all cumulative choices.
	## Delegates to EndingCalculator if available, otherwise uses StoryManager.
	if GameManager.has_node("EndingCalculator"):
		var calc: EndingCalculator = GameManager.get_node("EndingCalculator")
		return calc.calculate_ending()
	return GameManager.story.determine_ending()


func get_total_choices() -> int:
	## Returns the total number of choices the player has made.
	return _choices.size()


func get_total_by_category(category: String) -> int:
	## Returns the count of choices in a specific category.
	return _choices_by_category.get(category, []).size()


func _on_choice_made(choice_id: String, _option_index: int, option_data: Dictionary) -> void:
	## Auto-record choices emitted through the EventBus.
	## Determine category from the option data or default to strategic.
	var category: String = option_data.get("category", TYPE_STRATEGIC)

	# Auto-categorize based on known choice effects
	if option_data.has("moral_shift") and option_data.moral_shift != 0.0:
		category = TYPE_MORAL
	elif option_data.has("relationship_changes") and not option_data.relationship_changes.is_empty():
		category = TYPE_RELATIONSHIP
	elif option_data.has("rep") and option_data.rep != 0:
		category = TYPE_REPUTATION

	record_choice(choice_id, category, option_data)


func serialize() -> Dictionary:
	return {
		"choices": _choices,
		"choices_by_category": _choices_by_category,
	}


func deserialize(data: Dictionary) -> void:
	_choices = data.get("choices", {})
	_choices_by_category = data.get("choices_by_category", {
		TYPE_RELATIONSHIP: [],
		TYPE_REPUTATION: [],
		TYPE_MORAL: [],
		TYPE_STRATEGIC: [],
	})
	# Ensure all categories exist
	for cat in [TYPE_RELATIONSHIP, TYPE_REPUTATION, TYPE_MORAL, TYPE_STRATEGIC]:
		if not _choices_by_category.has(cat):
			_choices_by_category[cat] = []
	print("[Choice] Deserialized %d choices." % _choices.size())
