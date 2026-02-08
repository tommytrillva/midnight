## Manages incoming text messages from NPCs between missions.
## Characters text the player with story updates, ambient flavor, and
## reply-driven consequences that feed into relationships and flags.
## Per GDD: Maya (car updates), Nikko (trash talk), Diesel (cryptic wisdom),
## Jade (corporate updates), Echo (Zero's messages).
class_name PhoneSystem
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Character display names used in the UI.
const CHARACTER_NAMES := {
	"maya": "Maya Torres",
	"nikko": "Nikko Tanaka",
	"diesel": "Diesel",
	"jade": "Jade Chen",
	"echo": "Echo",
	"zero": "Zero",
	"unknown": "Unknown Number",
}

## Every message ever delivered, keyed by id.
var messages: Dictionary = {}

## Per-character ordered lists of message ids (chronological).
var conversations: Dictionary = {}

## Queue of pending messages: Array of { sender, text, reply_options,
## consequences, delay_remaining, trigger }.
var _queue: Array = []

## Loaded trigger-based story messages (from JSON).
var _story_messages: Array = []

## Loaded ambient messages (from JSON).
var _ambient_pools: Dictionary = {}

## Cooldown per character for ambient messages (seconds).
var _ambient_cooldowns: Dictionary = {}

## Global ambient check timer.
var _ambient_timer: float = 0.0

## Auto-increment counter for generating unique message ids.
var _next_id: int = 1

## Already-fired story trigger ids (so we don't re-send).
var _fired_triggers: Array = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_story_messages()
	_load_ambient_messages()
	_connect_signals()
	print("[Phone] PhoneSystem ready. %d story triggers, %d ambient pools loaded." % [
		_story_messages.size(), _ambient_pools.size()])


func _process(delta: float) -> void:
	_process_queue(delta)
	_process_ambient(delta)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func send_message(sender: String, text: String, reply_options: Array = [],
		consequences: Dictionary = {}) -> String:
	## Immediately deliver a message. Returns the message id.
	var msg_id := _generate_id()
	var msg := {
		"id": msg_id,
		"sender": sender,
		"text": text,
		"timestamp": _get_game_timestamp(),
		"read": false,
		"reply_options": reply_options,
		"consequences": consequences,
		"replied": false,
		"reply_index": -1,
	}
	messages[msg_id] = msg

	if not conversations.has(sender):
		conversations[sender] = []
	conversations[sender].append(msg_id)

	EventBus.message_received.emit(sender, msg_id)
	print("[Phone] Message from %s: \"%s\"" % [sender, text.substr(0, 60)])
	return msg_id


func queue_message(sender: String, text: String, delay: float,
		reply_options: Array = [], consequences: Dictionary = {}) -> void:
	## Enqueue a message that will be delivered after `delay` seconds.
	_queue.append({
		"sender": sender,
		"text": text,
		"delay_remaining": delay,
		"reply_options": reply_options,
		"consequences": consequences,
	})


func get_unread_count() -> int:
	var count: int = 0
	for msg_id in messages:
		if not messages[msg_id].read:
			count += 1
	return count


func get_unread_count_for(sender: String) -> int:
	var count: int = 0
	if not conversations.has(sender):
		return 0
	for msg_id in conversations[sender]:
		if not messages[msg_id].read:
			count += 1
	return count


func get_conversation(sender: String) -> Array:
	## Returns an ordered array of full message dictionaries for the sender.
	var result: Array = []
	if not conversations.has(sender):
		return result
	for msg_id in conversations[sender]:
		if messages.has(msg_id):
			result.append(messages[msg_id])
	return result


func get_contacts_with_messages() -> Array:
	## Returns sender ids that have at least one message, sorted with most
	## recent activity first.
	var contacts: Array = []
	var latest_times: Dictionary = {}
	for sender in conversations:
		if conversations[sender].size() > 0:
			contacts.append(sender)
			var last_id: String = conversations[sender].back()
			latest_times[sender] = messages[last_id].timestamp
	contacts.sort_custom(func(a: String, b: String) -> bool:
		return latest_times.get(a, 0) > latest_times.get(b, 0))
	return contacts


func mark_read(message_id: String) -> void:
	if messages.has(message_id) and not messages[message_id].read:
		messages[message_id].read = true
		EventBus.message_read.emit(message_id)


func mark_conversation_read(sender: String) -> void:
	if not conversations.has(sender):
		return
	for msg_id in conversations[sender]:
		if messages.has(msg_id) and not messages[msg_id].read:
			messages[msg_id].read = true
			EventBus.message_read.emit(msg_id)


func reply(message_id: String, reply_index: int) -> void:
	## Player selects a reply option. Applies consequences and records choice.
	if not messages.has(message_id):
		push_error("[Phone] Unknown message id: %s" % message_id)
		return

	var msg: Dictionary = messages[message_id]
	if msg.replied:
		return
	if reply_index < 0 or reply_index >= msg.reply_options.size():
		push_error("[Phone] Invalid reply index %d for message %s" % [reply_index, message_id])
		return

	msg.replied = true
	msg.reply_index = reply_index

	var option: Dictionary = msg.reply_options[reply_index]
	var reply_text: String = option.get("text", "...")

	# Record the player's reply as a message in the conversation.
	var reply_id := _generate_id()
	var reply_msg := {
		"id": reply_id,
		"sender": "player",
		"text": reply_text,
		"timestamp": _get_game_timestamp(),
		"read": true,
		"reply_options": [],
		"consequences": {},
		"replied": false,
		"reply_index": -1,
	}
	messages[reply_id] = reply_msg
	if conversations.has(msg.sender):
		conversations[msg.sender].append(reply_id)

	# Apply consequences
	_apply_consequences(option)

	EventBus.message_replied.emit(message_id, reply_index)
	print("[Phone] Player replied to %s (option %d): \"%s\"" % [
		msg.sender, reply_index, reply_text.substr(0, 60)])

	# Some replies trigger follow-up messages
	var followup: Dictionary = option.get("followup", {})
	if not followup.is_empty():
		var fu_delay: float = followup.get("delay", 15.0)
		var fu_text: String = followup.get("text", "")
		if not fu_text.is_empty():
			queue_message(msg.sender, fu_text, fu_delay)


func has_pending_reply(message_id: String) -> bool:
	if not messages.has(message_id):
		return false
	var msg: Dictionary = messages[message_id]
	return msg.reply_options.size() > 0 and not msg.replied

# ---------------------------------------------------------------------------
# Queue Processing
# ---------------------------------------------------------------------------

func _process_queue(delta: float) -> void:
	var i: int = _queue.size() - 1
	while i >= 0:
		_queue[i].delay_remaining -= delta
		if _queue[i].delay_remaining <= 0.0:
			var entry: Dictionary = _queue[i]
			send_message(entry.sender, entry.text, entry.reply_options,
				entry.consequences)
			_queue.remove_at(i)
		i -= 1

# ---------------------------------------------------------------------------
# Ambient Message System
# ---------------------------------------------------------------------------

func _process_ambient(delta: float) -> void:
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	# Check every 120-300 seconds
	_ambient_timer = randf_range(120.0, 300.0)

	# Only send ambient messages during free roam
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return

	# Pick a random character from available ambient pools
	var eligible: Array = []
	for sender in _ambient_pools:
		if _ambient_pools[sender].size() == 0:
			continue
		var cooldown: float = _ambient_cooldowns.get(sender, 0.0)
		if cooldown <= 0.0:
			# Check relationship: must have met the character (affinity > 0 or specific flag)
			if _is_character_available(sender):
				eligible.append(sender)

	if eligible.is_empty():
		return

	var sender: String = eligible[randi() % eligible.size()]
	var pool: Array = _ambient_pools[sender]
	var entry: Dictionary = pool[randi() % pool.size()]

	var text: String = entry.get("text", "")
	var replies: Array = entry.get("replies", [])
	var conditions: Dictionary = entry.get("conditions", {})

	# Check conditions
	if not _check_ambient_conditions(conditions):
		return

	queue_message(sender, text, randf_range(5.0, 30.0), replies)
	_ambient_cooldowns[sender] = randf_range(600.0, 1200.0)


func _is_character_available(sender: String) -> bool:
	## Returns true if the player has met this character and they can text.
	match sender:
		"maya":
			return GameManager.story.get_story_flag("met_maya", false) != false
		"nikko":
			return GameManager.story.get_story_flag("met_nikko", false) != false
		"diesel":
			return GameManager.story.get_story_flag("met_diesel", false) != false
		"jade":
			return GameManager.story.get_story_flag("met_jade", false) != false
		"echo", "zero":
			return GameManager.story.get_story_flag("met_zero", false) != false
		"unknown":
			return GameManager.story.get_story_flag("prologue_complete", false) != false
	return false


func _check_ambient_conditions(conditions: Dictionary) -> bool:
	if conditions.is_empty():
		return true

	# Check minimum relationship level
	var min_level: Dictionary = conditions.get("min_level", {})
	for char_id in min_level:
		if GameManager.relationships.get_level(char_id) < min_level[char_id]:
			return false

	# Check required flags
	var flags_required: Array = conditions.get("flags_required", [])
	for flag in flags_required:
		if GameManager.story.get_story_flag(flag, false) == false:
			return false

	# Check act requirement
	var min_act: int = conditions.get("min_act", 0)
	if min_act > 0 and GameManager.story.current_act < min_act:
		return false

	return true

# ---------------------------------------------------------------------------
# Story Trigger Handling
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.story_chapter_started.connect(_on_chapter_started)
	EventBus.relationship_level_up.connect(_on_relationship_level_up)
	EventBus.relationship_level_down.connect(_on_relationship_level_down)
	EventBus.race_finished.connect(_on_race_finished)


func _on_mission_completed(mission_id: String, _outcome: Dictionary) -> void:
	_check_story_triggers("mission_complete:%s" % mission_id)


func _on_mission_started(mission_id: String) -> void:
	_check_story_triggers("mission_start:%s" % mission_id)


func _on_chapter_started(act: int, chapter: int) -> void:
	_check_story_triggers("chapter:%d.%d" % [act, chapter])


func _on_relationship_level_up(character_id: String, new_level: int) -> void:
	_check_story_triggers("relationship_up:%s:%d" % [character_id, new_level])


func _on_relationship_level_down(character_id: String, new_level: int) -> void:
	_check_story_triggers("relationship_down:%s:%d" % [character_id, new_level])


func _on_race_finished(results: Dictionary) -> void:
	if results.get("player_won", false):
		_check_story_triggers("race_won")
	else:
		_check_story_triggers("race_lost")


func _check_story_triggers(trigger: String) -> void:
	for entry in _story_messages:
		var msg_trigger: String = entry.get("trigger", "")
		if msg_trigger != trigger:
			continue
		var msg_id_key: String = entry.get("id", msg_trigger)
		if msg_id_key in _fired_triggers:
			continue

		# Check additional conditions
		var conditions: Dictionary = entry.get("conditions", {})
		if not _check_ambient_conditions(conditions):
			continue

		_fired_triggers.append(msg_id_key)

		var sender: String = entry.get("sender", "unknown")
		var text: String = entry.get("text", "")
		var delay: float = entry.get("delay", 30.0)
		var replies: Array = entry.get("replies", [])
		var consequences: Dictionary = entry.get("consequences", {})

		queue_message(sender, text, delay, replies, consequences)

# ---------------------------------------------------------------------------
# Consequence Application
# ---------------------------------------------------------------------------

func _apply_consequences(option: Dictionary) -> void:
	# Relationship changes
	var rel: Dictionary = option.get("relationship", {})
	for char_id in rel:
		GameManager.relationships.change_affinity(char_id, rel[char_id])

	# Story flags
	var flags: Array = option.get("set_flags", [])
	for flag in flags:
		GameManager.story.set_story_flag(flag)

	# Mission unlocks
	var unlock: String = option.get("unlock_mission", "")
	if not unlock.is_empty():
		GameManager.story.set_story_flag("phone_unlock_%s" % unlock)
		print("[Phone] Unlocked flag for mission: %s" % unlock)

	# Cash reward/cost
	var cash: int = option.get("cash", 0)
	if cash > 0:
		GameManager.economy.earn(cash, "phone_reply")
	elif cash < 0:
		GameManager.economy.spend(-cash, "phone_reply")

# ---------------------------------------------------------------------------
# Data Loading
# ---------------------------------------------------------------------------

func _load_story_messages() -> void:
	var path := "res://data/messages/story_messages.json"
	if not FileAccess.file_exists(path):
		print("[Phone] No story_messages.json found at %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[Phone] Failed to open %s" % path)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data: Dictionary = json.data
		_story_messages = data.get("messages", [])
		print("[Phone] Loaded %d story messages." % _story_messages.size())
	else:
		push_error("[Phone] JSON parse error in story_messages.json: %s" % json.get_error_message())
	file.close()


func _load_ambient_messages() -> void:
	var path := "res://data/messages/ambient_messages.json"
	if not FileAccess.file_exists(path):
		print("[Phone] No ambient_messages.json found at %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[Phone] Failed to open %s" % path)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data: Dictionary = json.data
		_ambient_pools = data.get("pools", {})
		print("[Phone] Loaded ambient pools for: %s" % str(_ambient_pools.keys()))
	else:
		push_error("[Phone] JSON parse error in ambient_messages.json: %s" % json.get_error_message())
	file.close()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _generate_id() -> String:
	var id := "msg_%d" % _next_id
	_next_id += 1
	return id


func _get_game_timestamp() -> float:
	## Returns the in-game time as a float for ordering. Falls back to OS time.
	if GameManager.world_time:
		return GameManager.world_time.get_total_minutes()
	return Time.get_unix_time_from_system()

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"messages": messages,
		"conversations": conversations,
		"next_id": _next_id,
		"fired_triggers": _fired_triggers,
		"ambient_cooldowns": _ambient_cooldowns,
	}


func deserialize(data: Dictionary) -> void:
	messages = data.get("messages", {})
	conversations = data.get("conversations", {})
	_next_id = data.get("next_id", 1)
	_fired_triggers = data.get("fired_triggers", [])
	_ambient_cooldowns = data.get("ambient_cooldowns", {})
	print("[Phone] Deserialized %d messages across %d conversations." % [
		messages.size(), conversations.size()])
