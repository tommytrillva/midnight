## Manages dialogue presentation and player choices.
## Loads dialogue from JSON data files and handles branching
## based on relationship levels, choice flags, and story state.
class_name DialogueSystem
extends Node

signal dialogue_line_displayed(speaker: String, text: String, portrait: String)
signal choices_displayed(choices: Array)
signal dialogue_completed(dialogue_id: String)

var _current_dialogue_id: String = ""
var _current_lines: Array = []
var _current_line_index: int = 0
var _waiting_for_choice: bool = false
var _dialogue_cache: Dictionary = {}


func start_dialogue(dialogue_id: String) -> void:
	var dialogue := _load_dialogue(dialogue_id)
	if dialogue.is_empty():
		push_error("[Dialogue] Dialogue not found: %s" % dialogue_id)
		return

	_current_dialogue_id = dialogue_id
	_current_lines = dialogue.get("lines", [])
	_current_line_index = 0
	_waiting_for_choice = false

	EventBus.dialogue_started.emit(dialogue_id)
	GameManager.change_state(GameManager.GameState.DIALOGUE)
	_advance()


func advance() -> void:
	## Called when player clicks/presses to advance dialogue.
	if _waiting_for_choice:
		return # Must select a choice
	_current_line_index += 1
	_advance()


func select_choice(choice_index: int) -> void:
	if not _waiting_for_choice:
		return

	var line := _current_lines[_current_line_index]
	var choices: Array = line.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return

	var choice: Dictionary = choices[choice_index]
	_waiting_for_choice = false

	# Apply choice consequences
	_apply_choice_consequences(choice)

	# Record the choice
	EventBus.choice_made.emit(
		choice.get("choice_id", _current_dialogue_id + "_" + str(_current_line_index)),
		choice_index,
		choice
	)

	# Jump to next line or specified target
	var jump_to: String = choice.get("jump_to", "")
	if not jump_to.is_empty():
		_jump_to_label(jump_to)
	else:
		_current_line_index += 1
	_advance()


func _advance() -> void:
	if _current_line_index >= _current_lines.size():
		_end_dialogue()
		return

	var line: Dictionary = _current_lines[_current_line_index]

	# Check conditions
	if line.has("condition"):
		if not _check_condition(line.condition):
			_current_line_index += 1
			_advance()
			return

	# Handle different line types
	var line_type: String = line.get("type", "dialogue")

	match line_type:
		"dialogue":
			var speaker: String = line.get("speaker", "")
			var text: String = line.get("text", "")
			var portrait: String = line.get("portrait", "")
			dialogue_line_displayed.emit(speaker, text, portrait)

		"choice":
			_waiting_for_choice = true
			var choices: Array = line.get("choices", [])
			# Filter choices by conditions
			var available := choices.filter(func(c):
				return not c.has("condition") or _check_condition(c.condition)
			)
			choices_displayed.emit(available)
			EventBus.dialogue_choice_presented.emit(available)

		"narration":
			var text: String = line.get("text", "")
			dialogue_line_displayed.emit("", text, "")

		"action":
			_execute_action(line.get("action", {}))
			_current_line_index += 1
			_advance()


func _end_dialogue() -> void:
	var id := _current_dialogue_id
	_current_dialogue_id = ""
	_current_lines = []
	_current_line_index = 0
	_waiting_for_choice = false

	dialogue_completed.emit(id)
	EventBus.dialogue_ended.emit(id)
	GameManager.change_state(GameManager.previous_state)


func _apply_choice_consequences(choice: Dictionary) -> void:
	# Relationship changes
	var rel_changes: Dictionary = choice.get("relationship_changes", {})
	for char_id in rel_changes:
		GameManager.relationships.change_affinity(char_id, rel_changes[char_id])

	# Moral alignment
	var moral: float = choice.get("moral_shift", 0.0)
	if moral != 0.0:
		GameManager.player_data.shift_moral_alignment(moral)

	# Set flags
	var flags: Dictionary = choice.get("set_flags", {})
	for flag_id in flags:
		GameManager.player_data.set_choice_flag(flag_id, flags[flag_id])

	# Cash reward/cost
	var cash: int = choice.get("cash", 0)
	if cash > 0:
		GameManager.economy.earn(cash, "dialogue_choice")
	elif cash < 0:
		GameManager.economy.spend(-cash, "dialogue_choice")

	# REP
	var rep: int = choice.get("rep", 0)
	if rep > 0:
		GameManager.reputation.earn_rep(rep, "dialogue_choice")
	elif rep < 0:
		GameManager.reputation.lose_rep(-rep, "dialogue_choice")


func _check_condition(condition: Dictionary) -> bool:
	## Evaluate a condition dictionary. Supports relationship, flag, rep, and cash checks.
	var cond_type: String = condition.get("type", "")

	match cond_type:
		"relationship_min":
			var char_id: String = condition.get("character", "")
			var min_level: int = condition.get("level", 1)
			return GameManager.relationships.get_level(char_id) >= min_level

		"relationship_affinity_min":
			var char_id: String = condition.get("character", "")
			var min_val: int = condition.get("value", 0)
			return GameManager.relationships.get_affinity(char_id) >= min_val

		"has_flag":
			var flag_id: String = condition.get("flag", "")
			return GameManager.player_data.has_choice_flag(flag_id)

		"flag_equals":
			var flag_id: String = condition.get("flag", "")
			var value: Variant = condition.get("value", true)
			return GameManager.player_data.get_choice_flag(flag_id) == value

		"rep_tier_min":
			var min_tier: int = condition.get("tier", 0)
			return GameManager.reputation.get_tier() >= min_tier

		"cash_min":
			var min_cash: int = condition.get("amount", 0)
			return GameManager.economy.cash >= min_cash

		"zero_awareness_min":
			var min_level: int = condition.get("level", 0)
			return GameManager.player_data._zero_awareness >= min_level

	return true # Unknown conditions pass


func _execute_action(action: Dictionary) -> void:
	var action_type: String = action.get("type", "")
	match action_type:
		"give_cash":
			GameManager.economy.earn(action.get("amount", 0), "dialogue_action")
		"give_rep":
			GameManager.reputation.earn_rep(action.get("amount", 0), "dialogue_action")
		"change_relationship":
			GameManager.relationships.change_affinity(
				action.get("character", ""),
				action.get("amount", 0)
			)
		"set_flag":
			GameManager.player_data.set_choice_flag(
				action.get("flag", ""),
				action.get("value", true)
			)
		"set_zero_awareness":
			GameManager.player_data.set_zero_awareness(action.get("level", 0))
		"start_mission":
			GameManager.story.start_mission(action.get("mission_id", ""))


func _jump_to_label(label: String) -> void:
	for i in range(_current_lines.size()):
		if _current_lines[i].get("label", "") == label:
			_current_line_index = i
			return
	push_warning("[Dialogue] Label not found: %s" % label)
	_current_line_index += 1


func _load_dialogue(dialogue_id: String) -> Dictionary:
	if _dialogue_cache.has(dialogue_id):
		return _dialogue_cache[dialogue_id]

	var path := "res://data/dialogue/%s.json" % dialogue_id
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[Dialogue] Failed to parse: %s" % path)
		return {}
	file.close()

	var data: Dictionary = json.data
	_dialogue_cache[dialogue_id] = data
	return data
