## Manages delayed and cumulative consequences from player choices.
## Consequences can fire immediately, on a future mission start,
## accumulate toward a threshold, or only matter at the ending.
class_name ConsequenceManager
extends Node

# Consequence types
const TYPE_IMMEDIATE := "immediate"   # Applied right away
const TYPE_DELAYED := "delayed"       # Applied when a specific mission starts
const TYPE_CUMULATIVE := "cumulative" # Tracked counter, triggers at threshold
const TYPE_FINAL := "final"           # Only evaluated at ending determination

# Pending delayed consequences: triggers when a specific mission starts
var pending_consequences: Array = []
# Each: { trigger_mission: String, consequence: Dictionary, source_choice: String }

# Cumulative counters: counter_id -> { value: int, threshold: int, consequence: Dictionary, triggered: bool }
var cumulative_counters: Dictionary = {}

# Final consequences: evaluated only during ending calculation
var final_consequences: Array = []
# Each: { condition: Dictionary, effect: Dictionary, source_choice: String }

# Log of all applied consequences for debugging/narrative tracking
var _applied_log: Array = []


func _ready() -> void:
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.choice_made.connect(_on_choice_made)
	_register_key_consequences()
	print("[Consequence] ConsequenceManager initialized.")


func register_delayed(trigger_mission: String, consequence: Dictionary, source_choice: String) -> void:
	## Register a consequence that fires when a specific mission starts.
	pending_consequences.append({
		"trigger_mission": trigger_mission,
		"consequence": consequence,
		"source_choice": source_choice,
	})
	print("[Consequence] Delayed registered: %s -> triggers on mission '%s'" % [source_choice, trigger_mission])


func register_cumulative(counter_id: String, threshold: int, consequence: Dictionary) -> void:
	## Register a cumulative counter. When the counter reaches the threshold, the consequence fires.
	if not cumulative_counters.has(counter_id):
		cumulative_counters[counter_id] = {
			"value": 0,
			"threshold": threshold,
			"consequence": consequence,
			"triggered": false,
		}


func increment_cumulative(counter_id: String, amount: int = 1) -> void:
	## Increment a cumulative counter and check if it triggers.
	if not cumulative_counters.has(counter_id):
		return
	var counter: Dictionary = cumulative_counters[counter_id]
	if counter.triggered:
		return
	counter.value += amount
	print("[Consequence] Cumulative '%s': %d / %d" % [counter_id, counter.value, counter.threshold])
	if counter.value >= counter.threshold:
		counter.triggered = true
		EventBus.cumulative_threshold_reached.emit(counter_id)
		apply_consequence(counter.consequence)
		print("[Consequence] Cumulative '%s' threshold reached! Consequence fired." % counter_id)


func register_final(condition: Dictionary, effect: Dictionary, source_choice: String) -> void:
	## Register a consequence that only matters at ending determination.
	final_consequences.append({
		"condition": condition,
		"effect": effect,
		"source_choice": source_choice,
	})


func check_pending_consequences(mission_id: String) -> void:
	## Check and fire any delayed consequences triggered by the given mission.
	var remaining: Array = []
	for pc in pending_consequences:
		if pc.trigger_mission == mission_id:
			EventBus.delayed_consequence_fired.emit(mission_id, pc.source_choice)
			print("[Consequence] Delayed consequence fired for mission '%s' (source: %s)" % [
				mission_id, pc.source_choice
			])
			apply_consequence(pc.consequence)
		else:
			remaining.append(pc)
	pending_consequences = remaining


func apply_consequence(consequence: Dictionary) -> void:
	## Apply a consequence dictionary to the game state.
	## Supports: relationship_changes, moral_shift, cash, rep, set_flags,
	## hud_message, reputation_tag, zero_awareness.

	# Relationship changes
	var rel_changes: Dictionary = consequence.get("relationship_changes", {})
	for char_id in rel_changes:
		GameManager.relationships.change_affinity(char_id, rel_changes[char_id])

	# Moral alignment shift
	var moral: float = consequence.get("moral_shift", 0.0)
	if moral != 0.0:
		if GameManager.has_node("MoralTracker"):
			var tracker: MoralTracker = GameManager.get_node("MoralTracker")
			tracker.shift_alignment(moral, consequence.get("moral_reason", "consequence"))
		else:
			GameManager.player_data.shift_moral_alignment(moral)

	# Cash
	var cash: int = consequence.get("cash", 0)
	if cash > 0:
		GameManager.economy.earn(cash, "consequence")
	elif cash < 0:
		GameManager.economy.spend(-cash, "consequence")

	# Reputation
	var rep: int = consequence.get("rep", 0)
	if rep > 0:
		GameManager.reputation.earn_rep(rep, "consequence")
	elif rep < 0:
		GameManager.reputation.lose_rep(-rep, "consequence")

	# Set flags
	var flags: Dictionary = consequence.get("set_flags", {})
	for flag_id in flags:
		GameManager.player_data.set_choice_flag(flag_id, flags[flag_id])

	# Story flags
	var story_flags: Dictionary = consequence.get("story_flags", {})
	for flag_id in story_flags:
		GameManager.story.set_story_flag(flag_id, story_flags[flag_id])

	# Zero awareness
	var zero_awareness: int = consequence.get("zero_awareness", 0)
	if zero_awareness > 0:
		if GameManager.has_node("MoralTracker"):
			var tracker: MoralTracker = GameManager.get_node("MoralTracker")
			for i in range(zero_awareness):
				tracker.increment_zero_awareness()
		else:
			var current: int = GameManager.player_data._zero_awareness
			GameManager.player_data.set_zero_awareness(current + zero_awareness)

	# HUD message
	var message: String = consequence.get("hud_message", "")
	if not message.is_empty():
		var duration: float = consequence.get("message_duration", 3.0)
		EventBus.hud_message.emit(message, duration)

	# Log and emit
	_applied_log.append({
		"consequence": consequence,
		"timestamp": GameManager.player_data.play_time_seconds,
	})
	EventBus.consequence_applied.emit(consequence, consequence.get("source", "unknown"))


func get_final_consequences() -> Array:
	## Returns all final consequences for the ending calculator to evaluate.
	return final_consequences


func get_applied_log() -> Array:
	## Returns the log of all applied consequences.
	return _applied_log


func _on_mission_started(mission_id: String) -> void:
	check_pending_consequences(mission_id)


func _on_choice_made(choice_id: String, _option_index: int, option_data: Dictionary) -> void:
	## Handle key story choices by registering their delayed consequences.
	var delayed: Array = option_data.get("delayed_consequences", [])
	for dc in delayed:
		register_delayed(
			dc.get("trigger_mission", ""),
			dc.get("consequence", {}),
			choice_id
		)

	# Handle immediate consequences embedded in option data beyond what
	# dialogue_system already handles (e.g., cumulative counters)
	var cumulative_id: String = option_data.get("cumulative_counter", "")
	if not cumulative_id.is_empty():
		var amount: int = option_data.get("cumulative_amount", 1)
		increment_cumulative(cumulative_id, amount)


func _register_key_consequences() -> void:
	## Pre-register the key delayed consequences described in the GDD.
	## These are set up so that when a player makes one of these choices,
	## the consequence fires at the right moment later.

	# Cumulative counters
	register_cumulative("cheater_reputation", 3, {
		"rep": -500,
		"set_flags": {"cheater_exposed": true},
		"hud_message": "Word gets around... they're calling you a cheater.",
		"message_duration": 5.0,
	})

	register_cumulative("underground_loyalty", 5, {
		"rep": 300,
		"set_flags": {"underground_respected": true},
		"hud_message": "The underground knows your name. Respect.",
		"message_duration": 4.0,
	})

	register_cumulative("corporate_connections", 5, {
		"rep": 200,
		"set_flags": {"corporate_networked": true},
		"hud_message": "Your corporate network is paying dividends.",
		"message_duration": 4.0,
	})

	register_cumulative("ruthless_choices", 5, {
		"set_flags": {"reputation_ruthless": true},
		"hud_message": "People are starting to fear you.",
		"message_duration": 4.0,
	})

	register_cumulative("compassionate_choices", 5, {
		"set_flags": {"reputation_compassionate": true},
		"hud_message": "People trust you. That means something.",
		"message_duration": 4.0,
	})


func serialize() -> Dictionary:
	return {
		"pending_consequences": pending_consequences,
		"cumulative_counters": cumulative_counters,
		"final_consequences": final_consequences,
		"applied_log": _applied_log,
	}


func deserialize(data: Dictionary) -> void:
	pending_consequences = data.get("pending_consequences", [])
	cumulative_counters = data.get("cumulative_counters", {})
	final_consequences = data.get("final_consequences", [])
	_applied_log = data.get("applied_log", [])
	print("[Consequence] Deserialized: %d pending, %d cumulative, %d final." % [
		pending_consequences.size(),
		cumulative_counters.size(),
		final_consequences.size(),
	])
