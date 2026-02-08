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

	var line: Dictionary = _current_lines[_current_line_index]
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

	# Check conditions — supports both single-type "condition" and multi-key "conditions"
	if line.has("conditions"):
		if not _check_conditions(line.conditions):
			_current_line_index += 1
			_advance()
			return
	elif line.has("condition"):
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
			# Filter choices by conditions (supports both "condition" and "conditions")
			var available := choices.filter(func(c):
				if c.has("conditions"):
					return _check_conditions(c.conditions)
				elif c.has("condition"):
					return _check_condition(c.condition)
				return true
			)
			choices_displayed.emit(available)
			EventBus.dialogue_choice_presented.emit(available)

		"narration":
			var text: String = line.get("text", "")
			dialogue_line_displayed.emit("", text, "")

		"cinematic":
			# Cinematic scene descriptions — displayed like narration
			# but can be styled differently by the UI (e.g. centered,
			# uppercase, letterboxed)
			var text: String = line.get("text", "")
			dialogue_line_displayed.emit("__cinematic__", text, "")

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

	# Restore game state BEFORE emitting signals so that handlers
	# (e.g. auto-triggering the next story dialogue) can safely set
	# a new state without it being clobbered afterwards.
	GameManager.change_state(GameManager.previous_state)

	dialogue_completed.emit(id)
	EventBus.dialogue_ended.emit(id)


func _apply_choice_consequences(choice: Dictionary) -> void:
	# Relationship changes
	var rel_changes: Dictionary = choice.get("relationship_changes", {})
	for char_id in rel_changes:
		GameManager.relationships.change_affinity(char_id, rel_changes[char_id])

	# Moral alignment — route through MoralTracker if available
	var moral: float = choice.get("moral_shift", 0.0)
	if moral != 0.0:
		if GameManager.has_node("MoralTracker"):
			var tracker: MoralTracker = GameManager.get_node("MoralTracker")
			var reason: String = choice.get("choice_id", _current_dialogue_id)
			tracker.shift_alignment(moral, reason)
		else:
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

	# Delayed consequences — register through ConsequenceManager if available
	var delayed: Array = choice.get("delayed_consequences", [])
	if not delayed.is_empty() and GameManager.has_node("ConsequenceManager"):
		var cm: ConsequenceManager = GameManager.get_node("ConsequenceManager")
		var choice_id: String = choice.get("choice_id", _current_dialogue_id)
		for dc in delayed:
			cm.register_delayed(
				dc.get("trigger_mission", ""),
				dc.get("consequence", {}),
				choice_id
			)


func _check_conditions(conditions: Dictionary) -> bool:
	## Evaluate a multi-key conditions dictionary. ALL conditions must be true.
	## Supports:
	##   "origin": "fallen"                   — only if player chose Fallen origin
	##   "moral_min": 20                      — only if moral alignment >= 20
	##   "moral_max": -10                     — only if moral alignment <= -10
	##   "path": "corporate"                  — only in corporate path
	##   "flag": "nikko_saved"                — only if specific choice flag is set
	##   "flag_equals": {"flag": "x", "value": "y"} — flag equals specific value
	##   "relationship_min": {"diesel": 40}   — character affinity minimums
	##   "relationship_level_min": {"maya": 3} — character level minimums
	##   "rep_tier_min": 3                    — reputation tier minimum
	##   "cash_min": 1000                     — cash minimum
	##   "zero_awareness_min": 2              — zero awareness minimum
	##   "mission_completed": "first_blood"   — specific mission must be completed
	##   "act_min": 2                         — must be at or past this act
	##   "choice_made": "sabotage_accept"     — specific choice recorded in ChoiceSystem

	# Origin check
	if conditions.has("origin"):
		var required_origin: String = conditions["origin"]
		if GameManager.player_data.get_origin_id() != required_origin:
			return false

	# Moral alignment minimum
	if conditions.has("moral_min"):
		var min_moral: float = conditions["moral_min"]
		var current_moral := _get_moral_alignment()
		if current_moral < min_moral:
			return false

	# Moral alignment maximum
	if conditions.has("moral_max"):
		var max_moral: float = conditions["moral_max"]
		var current_moral := _get_moral_alignment()
		if current_moral > max_moral:
			return false

	# Path check
	if conditions.has("path"):
		var required_path: String = conditions["path"]
		if GameManager.story.chosen_path != required_path:
			return false

	# Flag check (boolean — flag must exist and be truthy)
	if conditions.has("flag"):
		var flag_id: String = conditions["flag"]
		if not GameManager.player_data.has_choice_flag(flag_id):
			return false

	# Flag equals check
	if conditions.has("flag_equals"):
		var flag_check: Dictionary = conditions["flag_equals"]
		var flag_id: String = flag_check.get("flag", "")
		var expected_value: Variant = flag_check.get("value", true)
		if GameManager.player_data.get_choice_flag(flag_id) != expected_value:
			return false

	# Relationship affinity minimums (Dictionary: character_id -> min_affinity)
	if conditions.has("relationship_min"):
		var rel_mins: Dictionary = conditions["relationship_min"]
		for char_id in rel_mins:
			if GameManager.relationships.get_affinity(char_id) < rel_mins[char_id]:
				return false

	# Relationship level minimums (Dictionary: character_id -> min_level)
	if conditions.has("relationship_level_min"):
		var level_mins: Dictionary = conditions["relationship_level_min"]
		for char_id in level_mins:
			if GameManager.relationships.get_level(char_id) < level_mins[char_id]:
				return false

	# Reputation tier minimum
	if conditions.has("rep_tier_min"):
		var min_tier: int = conditions["rep_tier_min"]
		if GameManager.reputation.get_tier() < min_tier:
			return false

	# Cash minimum
	if conditions.has("cash_min"):
		var min_cash: int = conditions["cash_min"]
		if GameManager.economy.cash < min_cash:
			return false

	# Zero awareness minimum
	if conditions.has("zero_awareness_min"):
		var min_awareness: int = conditions["zero_awareness_min"]
		var current_awareness := _get_zero_awareness()
		if current_awareness < min_awareness:
			return false

	# Mission completed check
	if conditions.has("mission_completed"):
		var mission_id: String = conditions["mission_completed"]
		if not GameManager.story.is_mission_completed(mission_id):
			return false

	# Act minimum check
	if conditions.has("act_min"):
		var min_act: int = conditions["act_min"]
		if GameManager.story.current_act < min_act:
			return false

	# Choice made check (via ChoiceSystem)
	if conditions.has("choice_made"):
		var choice_id: String = conditions["choice_made"]
		if GameManager.has_node("ChoiceSystem"):
			var cs: ChoiceSystem = GameManager.get_node("ChoiceSystem")
			if not cs.has_made_choice(choice_id):
				return false
		else:
			# Fall back to player_data flags
			if not GameManager.player_data.has_choice_flag(choice_id):
				return false

	return true


func _check_condition(condition: Dictionary) -> bool:
	## Evaluate a single-type condition dictionary.
	## Supports relationship, flag, rep, cash, origin, moral, path checks.
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
			return _get_zero_awareness() >= min_level

		"origin":
			var required_origin: String = condition.get("origin", "")
			return GameManager.player_data.get_origin_id() == required_origin

		"moral_min":
			var min_moral: float = condition.get("value", 0.0)
			return _get_moral_alignment() >= min_moral

		"moral_max":
			var max_moral: float = condition.get("value", 0.0)
			return _get_moral_alignment() <= max_moral

		"path":
			var required_path: String = condition.get("path", "")
			return GameManager.story.chosen_path == required_path

		"mission_completed":
			var mission_id: String = condition.get("mission", "")
			return GameManager.story.is_mission_completed(mission_id)

		"choice_made":
			var choice_id: String = condition.get("choice", "")
			if GameManager.has_node("ChoiceSystem"):
				var cs: ChoiceSystem = GameManager.get_node("ChoiceSystem")
				return cs.has_made_choice(choice_id)
			return GameManager.player_data.has_choice_flag(choice_id)

	return true # Unknown conditions pass


func _get_moral_alignment() -> float:
	## Get moral alignment from MoralTracker if available, otherwise from player_data.
	if GameManager.has_node("MoralTracker"):
		var tracker: MoralTracker = GameManager.get_node("MoralTracker")
		return tracker.get_alignment()
	return GameManager.player_data._moral_alignment


func _get_zero_awareness() -> int:
	## Get zero awareness from MoralTracker if available, otherwise from player_data.
	if GameManager.has_node("MoralTracker"):
		var tracker: MoralTracker = GameManager.get_node("MoralTracker")
		return tracker.get_zero_awareness()
	return GameManager.player_data._zero_awareness


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
