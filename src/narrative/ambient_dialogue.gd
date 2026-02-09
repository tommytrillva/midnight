## Manages background NPC chatter that plays in the world.
## Selects lines from pools based on district, story progress,
## reputation, recent events, time of day, and player origin.
## Displays as floating text or subtitle overlay (not full dialogue UI).
class_name AmbientDialogue
extends Node

# --- Configuration ---
const COOLDOWN_MIN: float = 30.0
const COOLDOWN_MAX: float = 60.0
const EXCHANGE_LINE_DELAY: float = 2.5 # Seconds between lines in a multi-line exchange
const LINE_DISPLAY_DURATION: float = 4.0 # How long a single line stays visible

# --- State ---
var _dialogue_pools: Dictionary = {} # pool_id -> parsed JSON data
var _cooldown_timer: float = 0.0
var _is_on_cooldown: bool = false
var _is_playing: bool = false
var _active_group_id: String = ""
var _played_line_ids: Dictionary = {} # pool_id -> Array of played line indices (to reduce repeats)
var _recent_events: Array[String] = [] # Tracks recent events for contextual lines
var _registered_groups: Dictionary = {} # group_id -> {position: Vector3, district: String}
var _exchange_queue: Array = [] # Queue of lines in a multi-line exchange
var _exchange_timer: float = 0.0

# --- Recent event tracking ---
const MAX_RECENT_EVENTS: int = 10
const RECENT_EVENT_EXPIRY: float = 300.0 # 5 minutes
var _event_timestamps: Dictionary = {} # event_name -> timestamp


func _ready() -> void:
	_preload_all_pools()
	_connect_event_signals()
	print("[AmbientDialogue] System initialized. Loaded %d dialogue pools." % _dialogue_pools.size())


func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.MENU:
		return
	if GameManager.current_state == GameManager.GameState.PAUSED:
		return
	if GameManager.current_state == GameManager.GameState.DIALOGUE:
		return

	# Handle cooldown
	if _is_on_cooldown:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_is_on_cooldown = false

	# Handle exchange playback (multi-line conversations)
	if _is_playing and not _exchange_queue.is_empty():
		_exchange_timer -= delta
		if _exchange_timer <= 0.0:
			_play_next_exchange_line()

	# Expire old recent events
	_expire_old_events()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func get_ambient_line(context: Dictionary) -> Dictionary:
	## Select a random ambient line appropriate for the given context.
	## Context keys: district, act, chapter, rep_tier, time_period, origin_id,
	##               recent_events (Array), weather
	## Returns a Dictionary with: speakers, exchange, pool_id, line_index
	## Returns empty Dictionary if no suitable line found.

	var candidates: Array[Dictionary] = []
	var district: String = context.get("district", "downtown")
	var act: int = context.get("act", 1)
	var chapter: int = context.get("chapter", 1)
	var rep_tier: int = context.get("rep_tier", 0)
	var time_period: String = context.get("time_period", "night")
	var origin_id: String = context.get("origin_id", "outsider")
	var ctx_recent_events: Array = context.get("recent_events", [])
	var weather: String = context.get("weather", "clear")

	# Determine which pools to draw from based on context
	var pool_ids := _get_relevant_pools(district, act, chapter, rep_tier)

	for pool_id in pool_ids:
		if not _dialogue_pools.has(pool_id):
			continue
		var pool: Dictionary = _dialogue_pools[pool_id]
		var lines: Array = pool.get("lines", [])

		for i in range(lines.size()):
			var line: Dictionary = lines[i]

			# Check conditions
			if not _check_line_conditions(line, context):
				continue

			# Reduce weight for recently played lines
			var weight: float = line.get("weight", 1.0)
			if _has_been_played_recently(pool_id, i):
				weight *= 0.1

			# Apply time-of-day weight bonus
			var preferred_time: String = line.get("preferred_time", "")
			if not preferred_time.is_empty() and preferred_time == time_period:
				weight *= 1.5

			# Apply weather weight bonus
			var preferred_weather: String = line.get("preferred_weather", "")
			if not preferred_weather.is_empty() and preferred_weather == weather:
				weight *= 1.5

			candidates.append({
				"pool_id": pool_id,
				"line_index": i,
				"line_data": line,
				"weight": weight,
			})

	if candidates.is_empty():
		return {}

	# Weighted random selection
	var selected := _weighted_random_select(candidates)
	_mark_as_played(selected.pool_id, selected.line_index)

	return {
		"speakers": selected.line_data.get("speakers", []),
		"exchange": selected.line_data.get("exchange", []),
		"pool_id": selected.pool_id,
		"line_index": selected.line_index,
		"tags": selected.line_data.get("tags", []),
	}


func play_ambient_line(line: Dictionary) -> void:
	## Play an ambient line (or multi-line exchange) through the subtitle/bubble system.
	## Emits signals for the UI layer to pick up and display.
	if line.is_empty():
		return
	if _is_playing:
		return

	var exchange: Array = line.get("exchange", [])
	if exchange.is_empty():
		return

	_is_playing = true
	_active_group_id = line.get("group_id", "")
	_exchange_queue = exchange.duplicate()
	_exchange_timer = 0.0 # Play first line immediately

	EventBus.ambient_exchange_started.emit(_active_group_id, line)


func register_npc_group(group_id: String, position: Vector3, district: String = "") -> void:
	## Register an NPC group location for ambient dialogue triggering.
	_registered_groups[group_id] = {
		"position": position,
		"district": district,
	}


func unregister_npc_group(group_id: String) -> void:
	_registered_groups.erase(group_id)


func trigger_for_group(group_id: String) -> void:
	## Called when a player enters an NPC group's detection range.
	## Attempts to play an ambient line if not on cooldown.
	if _is_on_cooldown or _is_playing:
		return
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return

	EventBus.npc_group_entered.emit(group_id)

	var context := _build_current_context(group_id)
	var line := get_ambient_line(context)
	if line.is_empty():
		return

	line["group_id"] = group_id
	play_ambient_line(line)


func add_recent_event(event_name: String) -> void:
	## Track a recent event for contextual line selection.
	if event_name not in _recent_events:
		_recent_events.append(event_name)
		if _recent_events.size() > MAX_RECENT_EVENTS:
			var oldest: String = _recent_events[0]
			_recent_events.remove_at(0)
			_event_timestamps.erase(oldest)
	_event_timestamps[event_name] = Time.get_ticks_msec() / 1000.0


func get_recent_events() -> Array[String]:
	return _recent_events


func clear_recent_events() -> void:
	_recent_events.clear()
	_event_timestamps.clear()


# ---------------------------------------------------------------------------
# Internal — Pool Loading
# ---------------------------------------------------------------------------

func _preload_all_pools() -> void:
	var pool_files := [
		"ambient_pit_early",
		"ambient_pit_mid",
		"ambient_pit_late",
		"ambient_downtown",
		"ambient_harbor",
		"ambient_industrial",
		"ambient_hillside",
		"ambient_act3_fall",
		"ambient_act4_legend",
	]
	for pool_id in pool_files:
		var data := _load_pool(pool_id)
		if not data.is_empty():
			_dialogue_pools[pool_id] = data


func _load_pool(pool_id: String) -> Dictionary:
	var path := "res://data/dialogue/%s.json" % pool_id
	if not FileAccess.file_exists(path):
		push_warning("[AmbientDialogue] Pool file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[AmbientDialogue] Failed to parse: %s" % path)
		return {}
	file.close()

	return json.data


# ---------------------------------------------------------------------------
# Internal — Pool Selection
# ---------------------------------------------------------------------------

func _get_relevant_pools(district: String, act: int, _chapter: int, rep_tier: int) -> Array[String]:
	## Determine which ambient dialogue pools are relevant for the current context.
	var pools: Array[String] = []

	# Act 3 Fall override — this plays everywhere during The Fall
	if act == 3:
		pools.append("ambient_act3_fall")

	# Act 4 Legend overlay — plays in addition to district pools
	if act == 4:
		pools.append("ambient_act4_legend")

	# District-specific pools
	match district:
		"downtown":
			pools.append("ambient_downtown")
			# The Pit is in Downtown — select early/mid/late based on progression
			if act == 1 and rep_tier <= 1:
				pools.append("ambient_pit_early")
			elif act <= 2 and rep_tier >= 2:
				pools.append("ambient_pit_mid")
			elif rep_tier >= 4:
				pools.append("ambient_pit_late")
			elif act >= 2:
				pools.append("ambient_pit_mid")
			else:
				pools.append("ambient_pit_early")

		"harbor":
			pools.append("ambient_harbor")
			# Harbor gets The Pit overflow at mid/late game
			if rep_tier >= 3:
				pools.append("ambient_pit_mid")

		"industrial":
			pools.append("ambient_industrial")

		"hillside":
			pools.append("ambient_hillside")

	return pools


# ---------------------------------------------------------------------------
# Internal — Condition Checking
# ---------------------------------------------------------------------------

func _check_line_conditions(line: Dictionary, context: Dictionary) -> bool:
	## Check if a line's conditions are satisfied by the current context.
	var conditions: Dictionary = line.get("conditions", {})
	if conditions.is_empty():
		return true

	# Act requirement
	if conditions.has("min_act"):
		if context.get("act", 1) < conditions.min_act:
			return false
	if conditions.has("max_act"):
		if context.get("act", 1) > conditions.max_act:
			return false
	if conditions.has("act"):
		if context.get("act", 1) != conditions.act:
			return false

	# Chapter requirement
	if conditions.has("min_chapter"):
		if context.get("chapter", 1) < conditions.min_chapter:
			return false

	# Reputation tier
	if conditions.has("min_rep_tier"):
		if context.get("rep_tier", 0) < conditions.min_rep_tier:
			return false
	if conditions.has("max_rep_tier"):
		if context.get("rep_tier", 0) > conditions.max_rep_tier:
			return false

	# Origin requirement
	if conditions.has("origin"):
		if context.get("origin_id", "") != conditions.origin:
			return false

	# Time of day
	if conditions.has("time_period"):
		if context.get("time_period", "") != conditions.time_period:
			return false

	# Weather
	if conditions.has("weather"):
		if context.get("weather", "") != conditions.weather:
			return false

	# Recent events
	if conditions.has("recent_event"):
		if conditions.recent_event not in _recent_events:
			return false
	if conditions.has("no_recent_event"):
		if conditions.no_recent_event in _recent_events:
			return false

	# Win streak
	if conditions.has("min_wins"):
		var total_wins: int = context.get("total_wins", 0)
		if total_wins < conditions.min_wins:
			return false

	# Choice flags (delegates to PlayerData)
	if conditions.has("has_flag"):
		if not GameManager.player_data.has_choice_flag(conditions.has_flag):
			return false
	if conditions.has("flag_equals"):
		var flag_check: Dictionary = conditions.flag_equals
		var flag_id: String = flag_check.get("flag", "")
		var expected_value: Variant = flag_check.get("value", true)
		if GameManager.player_data.get_choice_flag(flag_id) != expected_value:
			return false

	# Story flags
	if conditions.has("story_flag"):
		if not GameManager.story.story_flags.has(conditions.story_flag):
			return false
	if conditions.has("story_flag_equals"):
		var sf_check: Dictionary = conditions.story_flag_equals
		var sf_id: String = sf_check.get("flag", "")
		var sf_val: Variant = sf_check.get("value", true)
		if GameManager.story.get_story_flag(sf_id) != sf_val:
			return false

	# Mission completed checks
	if conditions.has("mission_completed"):
		if not GameManager.story.is_mission_completed(conditions.mission_completed):
			return false

	# Moral alignment range
	if conditions.has("min_moral"):
		if GameManager.player_data._moral_alignment < conditions.min_moral:
			return false
	if conditions.has("max_moral"):
		if GameManager.player_data._moral_alignment > conditions.max_moral:
			return false

	return true


# ---------------------------------------------------------------------------
# Internal — Context Building
# ---------------------------------------------------------------------------

func _build_current_context(group_id: String = "") -> Dictionary:
	## Build a context dictionary from current game state.
	var district: String = GameManager.player_data.current_district
	if _registered_groups.has(group_id):
		var group_data: Dictionary = _registered_groups[group_id]
		if not group_data.get("district", "").is_empty():
			district = group_data.district

	return {
		"district": district,
		"act": GameManager.story.current_act,
		"chapter": GameManager.story.current_chapter,
		"rep_tier": GameManager.reputation.get_tier(),
		"time_period": GameManager.world_time.current_period,
		"origin_id": GameManager.player_data.get_origin_id(),
		"recent_events": _recent_events.duplicate(),
		"weather": GameManager.world_time.current_weather,
		"total_wins": GameManager.player_data.total_wins,
		"total_races": GameManager.player_data.total_races,
		"moral_alignment": GameManager.player_data._moral_alignment,
		"group_id": group_id,
	}


# ---------------------------------------------------------------------------
# Internal — Exchange Playback
# ---------------------------------------------------------------------------

func _play_next_exchange_line() -> void:
	if _exchange_queue.is_empty():
		_finish_exchange()
		return

	var line_entry: Dictionary = _exchange_queue[0]
	_exchange_queue.remove_at(0)

	var speaker_index: int = line_entry.get("speaker", 0)
	var text: String = line_entry.get("text", "")
	var speaker_tag: String = line_entry.get("speaker_tag", "NPC %d" % (speaker_index + 1))

	EventBus.ambient_line_started.emit(_active_group_id, {
		"speaker_index": speaker_index,
		"speaker_tag": speaker_tag,
		"text": text,
	})

	# Set timer for next line or for finishing
	if _exchange_queue.is_empty():
		_exchange_timer = LINE_DISPLAY_DURATION
	else:
		_exchange_timer = EXCHANGE_LINE_DELAY


func _finish_exchange() -> void:
	EventBus.ambient_exchange_finished.emit(_active_group_id)
	EventBus.ambient_line_finished.emit(_active_group_id)
	_is_playing = false
	_active_group_id = ""
	_exchange_queue.clear()
	_start_cooldown()


func _start_cooldown() -> void:
	_cooldown_timer = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	_is_on_cooldown = true


# ---------------------------------------------------------------------------
# Internal — Weighted Selection & Repeat Tracking
# ---------------------------------------------------------------------------

func _weighted_random_select(candidates: Array[Dictionary]) -> Dictionary:
	var total_weight: float = 0.0
	for c in candidates:
		total_weight += c.weight

	var roll := randf() * total_weight
	var cumulative: float = 0.0
	for c in candidates:
		cumulative += c.weight
		if roll <= cumulative:
			return c

	return candidates[candidates.size() - 1]


func _has_been_played_recently(pool_id: String, line_index: int) -> bool:
	if not _played_line_ids.has(pool_id):
		return false
	return line_index in _played_line_ids[pool_id]


func _mark_as_played(pool_id: String, line_index: int) -> void:
	if not _played_line_ids.has(pool_id):
		_played_line_ids[pool_id] = []

	var played: Array = _played_line_ids[pool_id]
	played.append(line_index)

	# Only remember a limited window to allow repeats eventually
	var pool_size := 0
	if _dialogue_pools.has(pool_id):
		pool_size = _dialogue_pools[pool_id].get("lines", []).size()
	var max_memory := maxi(pool_size / 2, 3)
	while played.size() > max_memory:
		played.remove_at(0)


# ---------------------------------------------------------------------------
# Internal — Event Signal Connections
# ---------------------------------------------------------------------------

func _connect_event_signals() -> void:
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.race_started.connect(_on_race_started)
	EventBus.pink_slip_won.connect(_on_pink_slip_won)
	EventBus.pink_slip_lost.connect(_on_pink_slip_lost)
	EventBus.busted.connect(_on_busted)
	EventBus.pursuit_escaped.connect(_on_pursuit_escaped)
	EventBus.rep_tier_changed.connect(_on_rep_tier_changed)
	EventBus.vehicle_totaled.connect(_on_vehicle_totaled)
	EventBus.district_entered.connect(_on_district_entered)
	EventBus.drift_total_scored.connect(_on_drift_scored)


func _on_race_finished(results: Dictionary) -> void:
	if results.get("player_won", false):
		add_recent_event("race_won")
		if GameManager.player_data.total_wins >= 6:
			add_recent_event("win_streak")
	else:
		add_recent_event("race_lost")


func _on_race_started(_race_data: Dictionary) -> void:
	add_recent_event("race_active")


func _on_pink_slip_won(_vehicle: Dictionary) -> void:
	add_recent_event("pink_slip_won")


func _on_pink_slip_lost(_vehicle: Dictionary) -> void:
	add_recent_event("pink_slip_lost")


func _on_busted(_fine: int) -> void:
	add_recent_event("busted")


func _on_pursuit_escaped() -> void:
	add_recent_event("escaped_cops")


func _on_rep_tier_changed(_old_tier: int, new_tier: int) -> void:
	add_recent_event("tier_up_%d" % new_tier)


func _on_vehicle_totaled(_vehicle_id: String) -> void:
	add_recent_event("vehicle_totaled")


func _on_district_entered(district_id: String) -> void:
	# Clear played lines when changing districts for variety
	_played_line_ids.clear()
	GameManager.player_data.current_district = district_id


func _on_drift_scored(total_score: float, rank: String, _breakdown: Dictionary) -> void:
	if rank in ["S", "A"]:
		add_recent_event("sick_drift")


# ---------------------------------------------------------------------------
# Internal — Event Expiry
# ---------------------------------------------------------------------------

func _expire_old_events() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var expired: Array[String] = []
	for event_name in _event_timestamps:
		if now - _event_timestamps[event_name] > RECENT_EVENT_EXPIRY:
			expired.append(event_name)
	for event_name in expired:
		_recent_events.erase(event_name)
		_event_timestamps.erase(event_name)


# ---------------------------------------------------------------------------
# Serialization (only recent events + cooldown state matter)
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"recent_events": _recent_events,
		"played_pools": _played_line_ids,
	}


func deserialize(data: Dictionary) -> void:
	var events: Array = data.get("recent_events", [])
	_recent_events.clear()
	for e in events:
		_recent_events.append(e)
	_played_line_ids = data.get("played_pools", {})
