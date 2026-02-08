## Hidden moral alignment tracker. NEVER displayed to the player.
## Ranges from -100 (ruthless) to +100 (compassionate).
## Also tracks "zero_awareness" — how much the player knows about Zero's true nature.
## Per GDD Section 4.4 and Section 9.
class_name MoralTracker
extends Node

# Alignment boundaries for categorization
const COMPASSIONATE_THRESHOLD := 30.0
const RUTHLESS_THRESHOLD := -30.0

# Known moral shift values for key choices (for reference and validation)
const KNOWN_SHIFTS := {
	"nikko_stop": 25.0,            # Stopping for Nikko's crash
	"nikko_continue": -20.0,       # Keeping racing past crash
	"sabotage_refuse": 10.0,       # Refusing sabotage
	"sabotage_accept": -15.0,      # Accepting sabotage
	"zero_gift_refuse": 5.0,       # Refusing Zero's gift
	"zero_gift_accept": -5.0,      # Accepting Zero's gift
	"nikko_help_debts": 15.0,      # Helping Nikko with debts
	"nikko_reveal_secret": -10.0,  # Revealing Nikko's secret to Maya
	"press_honest": 10.0,          # Being honest at press conference
	"press_aggressive": -5.0,      # Being aggressive at press conference
}

# Hidden alignment value: -100 (ruthless) to +100 (compassionate)
var _alignment: float = 0.0

# Zero awareness: 0-5, how much the player knows about Zero's true nature
var _zero_awareness: int = 0

# History of all moral shifts for debugging and narrative tracking
var _shift_history: Array = []


func _ready() -> void:
	# Sync with player_data's existing values
	_alignment = GameManager.player_data._moral_alignment
	_zero_awareness = GameManager.player_data._zero_awareness
	EventBus.choice_made.connect(_on_choice_made)
	print("[Moral] MoralTracker initialized. Alignment: %.1f, Zero awareness: %d" % [_alignment, _zero_awareness])


func shift_alignment(amount: float, reason: String = "") -> void:
	## Shift the moral alignment by the given amount.
	## Positive values move toward compassionate, negative toward ruthless.
	var old_value := _alignment
	_alignment = clampf(_alignment + amount, -100.0, 100.0)

	# Keep player_data in sync
	GameManager.player_data._moral_alignment = _alignment

	_shift_history.append({
		"amount": amount,
		"reason": reason,
		"old_value": old_value,
		"new_value": _alignment,
		"timestamp": GameManager.player_data.play_time_seconds,
	})

	EventBus.moral_alignment_shifted.emit(old_value, _alignment, reason)

	var direction := "+" if amount > 0 else ""
	print("[Moral] Alignment shifted %s%.1f (%s): %.1f -> %.1f [%s]" % [
		direction, amount, reason, old_value, _alignment, get_alignment_category()
	])

	# Update cumulative counters in ConsequenceManager if available
	if amount < -5.0:
		if GameManager.has_node("ConsequenceManager"):
			var cm: ConsequenceManager = GameManager.get_node("ConsequenceManager")
			cm.increment_cumulative("ruthless_choices")
	elif amount > 5.0:
		if GameManager.has_node("ConsequenceManager"):
			var cm: ConsequenceManager = GameManager.get_node("ConsequenceManager")
			cm.increment_cumulative("compassionate_choices")


func get_alignment() -> float:
	## Returns the current moral alignment value (-100 to +100).
	return _alignment


func get_alignment_category() -> String:
	## Returns a category string based on current alignment.
	## "compassionate" / "pragmatic" / "ruthless"
	if _alignment >= COMPASSIONATE_THRESHOLD:
		return "compassionate"
	elif _alignment <= RUTHLESS_THRESHOLD:
		return "ruthless"
	else:
		return "pragmatic"


func increment_zero_awareness() -> void:
	## Increase zero awareness by 1, capped at 5.
	if _zero_awareness >= 5:
		return
	var old_level := _zero_awareness
	_zero_awareness += 1
	GameManager.player_data.set_zero_awareness(_zero_awareness)
	EventBus.zero_awareness_changed.emit(old_level, _zero_awareness)
	print("[Moral] Zero awareness increased to %d/5" % _zero_awareness)

	# Emit HUD hints at key awareness levels (subtle, never explains what Zero is)
	match _zero_awareness:
		2:
			EventBus.hud_message.emit("Something doesn't add up...", 3.0)
		4:
			EventBus.hud_message.emit("You're starting to see the pattern.", 4.0)
		5:
			EventBus.hud_message.emit("Now you understand.", 5.0)


func get_zero_awareness() -> int:
	## Returns the current zero awareness level (0-5).
	return _zero_awareness


func get_shift_history() -> Array:
	## Returns the full history of moral shifts.
	return _shift_history


func _on_choice_made(choice_id: String, _option_index: int, option_data: Dictionary) -> void:
	## Auto-apply moral shifts from known choices.
	## Choices can specify moral_shift in their data, or we recognize known choice IDs.

	# Check for explicit moral_shift in option data (already handled by dialogue_system
	# writing to player_data, but we need to sync and log)
	var explicit_shift: float = option_data.get("moral_shift", 0.0)
	if explicit_shift != 0.0:
		# Dialogue system already applied to player_data, so sync our value
		_alignment = GameManager.player_data._moral_alignment
		_shift_history.append({
			"amount": explicit_shift,
			"reason": "choice_%s" % choice_id,
			"old_value": _alignment - explicit_shift,
			"new_value": _alignment,
			"timestamp": GameManager.player_data.play_time_seconds,
		})
		return

	# Handle well-known choices by ID if they didn't have explicit moral_shift data
	if KNOWN_SHIFTS.has(choice_id):
		shift_alignment(KNOWN_SHIFTS[choice_id], choice_id)

	# Handle zero awareness increments from specific choices
	var zero_increment: int = option_data.get("zero_awareness", 0)
	if zero_increment > 0:
		for i in range(zero_increment):
			increment_zero_awareness()


func serialize() -> Dictionary:
	return {
		"alignment": _alignment,
		"zero_awareness": _zero_awareness,
		"shift_history": _shift_history,
	}


func deserialize(data: Dictionary) -> void:
	_alignment = data.get("alignment", 0.0)
	_zero_awareness = data.get("zero_awareness", 0)
	_shift_history = data.get("shift_history", [])

	# Sync with player_data
	GameManager.player_data._moral_alignment = _alignment
	GameManager.player_data.set_zero_awareness(_zero_awareness)

	print("[Moral] Deserialized. Alignment: %.1f [%s], Zero awareness: %d" % [
		_alignment, get_alignment_category(), _zero_awareness
	])
