## Manages the overall narrative progression through the 4-act Harmon Circle structure.
## Tracks current act/chapter, mission states, and narrative flags.
## Full 67-mission arc spanning ~200 hours across Prologue + 4 Acts.
## Per GDD Section 4 and Section 9.
class_name StoryManager
extends Node

enum Act { ACT_1, ACT_2, ACT_3, ACT_4 }

const ACT_NAMES := ["The Come-Up", "The Rise", "The Fall", "The Redemption"]
const CHAPTERS_PER_ACT := [4, 4, 4, 4] # Max sub-chapter index per act (Act 1 also has ch 0 = prologue)

var current_act: int = 1
var current_chapter: int = 0 # 0 = prologue (Act 1 only), 1-4 = normal sub-chapters
var active_missions: Array[String] = []
var completed_missions: Array[String] = []
var failed_missions: Array[String] = []
var available_missions: Array[String] = []
var story_flags: Dictionary = {} # Persistent story state

# Path divergence tracking (Act 2)
var chosen_path: String = "" # "corporate" or "underground" or ""

# Mission definitions (loaded from JSON or defined inline for full arc)
var _mission_data: Dictionary = {}
var _dialogue_system: DialogueSystem = null


func _ready() -> void:
	_dialogue_system = DialogueSystem.new()
	add_child(_dialogue_system)
	_load_mission_data()

	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.choice_made.connect(_on_choice_made)
	EventBus.dialogue_ended.connect(_on_story_dialogue_ended)


# =============================================================================
# MISSION LIFECYCLE
# =============================================================================

func start_new_story() -> void:
	current_act = 1
	current_chapter = 0
	active_missions.clear()
	completed_missions.clear()
	failed_missions.clear()
	available_missions.clear()
	story_flags.clear()
	chosen_path = ""
	_refresh_available_missions()

	# Auto-start the opening cinematic on new game
	if "prologue_opening" in available_missions:
		start_mission("prologue_opening")


func start_mission(mission_id: String) -> void:
	if mission_id in active_missions:
		return
	if mission_id in completed_missions:
		return

	var mission := get_mission(mission_id)
	if mission.is_empty():
		push_error("[Story] Unknown mission: %s" % mission_id)
		return

	active_missions.append(mission_id)
	if mission_id in available_missions:
		available_missions.erase(mission_id)

	EventBus.mission_started.emit(mission_id)
	print("[Story] Mission started: %s — %s" % [mission_id, mission.get("title", "")])

	# Start pre-mission dialogue if it exists
	var pre_dialogue: String = mission.get("dialogue_pre", "")
	if not pre_dialogue.is_empty():
		_dialogue_system.start_dialogue(pre_dialogue)


func complete_mission(mission_id: String, outcome: Dictionary = {}) -> void:
	if mission_id not in active_missions:
		return

	active_missions.erase(mission_id)
	completed_missions.append(mission_id)

	# Set flags defined on the mission
	var mission := get_mission(mission_id)
	var flags_to_set: Array = mission.get("flags_set_on_complete", [])
	for flag in flags_to_set:
		set_story_flag(flag)

	EventBus.mission_completed.emit(mission_id, outcome)
	print("[Story] Mission completed: %s" % mission_id)

	# Apply mission-defined rewards (cash, rep, relationships)
	_apply_mission_rewards(mission_id, outcome)

	# Check for chapter/act progression
	_check_progression()
	_refresh_available_missions()


func fail_mission(mission_id: String, reason: String = "") -> void:
	if mission_id not in active_missions:
		return

	active_missions.erase(mission_id)
	failed_missions.append(mission_id)

	EventBus.mission_failed.emit(mission_id, reason)
	print("[Story] Mission failed: %s — %s" % [mission_id, reason])
	_refresh_available_missions()


# =============================================================================
# PROGRESSION
# =============================================================================

func advance_chapter() -> void:
	if current_chapter < CHAPTERS_PER_ACT[current_act - 1]:
		current_chapter += 1
	else:
		advance_act()
		return
	EventBus.story_chapter_started.emit(current_act, current_chapter)
	print("[Story] Chapter %d.%d: %s" % [current_act, current_chapter, _get_chapter_name()])
	_refresh_available_missions()


func advance_act() -> void:
	if current_act >= 4:
		print("[Story] Story complete!")
		EventBus.hud_message.emit("Your legend is complete.", 8.0)
		return

	current_act += 1
	current_chapter = 1

	# Special handling for Act 3 transition — The Fall
	if current_act == 3:
		trigger_the_fall()

	EventBus.story_chapter_started.emit(current_act, current_chapter)
	print("[Story] ACT %d: %s" % [current_act, ACT_NAMES[current_act - 1]])
	_refresh_available_missions()


# =============================================================================
# PATH / FLAGS
# =============================================================================

func set_path(path: String) -> void:
	## Set the Act 2 path divergence. "corporate" or "underground".
	chosen_path = path
	story_flags["chosen_path"] = path
	EventBus.hud_message.emit("Path chosen: %s" % path.capitalize(), 3.0)
	print("[Story] Path chosen: %s" % path)


func set_story_flag(flag: String, value: Variant = true) -> void:
	story_flags[flag] = value


func get_story_flag(flag: String, default: Variant = null) -> Variant:
	return story_flags.get(flag, default)


func trigger_the_fall() -> void:
	## Initiates the Act 3 Fall sequence. Strips the player of almost everything.
	## Per GDD: lose all vehicles except beater, lose 90% REP, money near-zero.
	## Skill tree progress is KEPT (by design).
	set_story_flag("the_fall_triggered")
	GameManager.trigger_the_fall()
	print("[Story] THE FALL has been triggered.")


func check_path_divergence() -> String:
	## Returns the chosen path: "corporate", "underground", or "" if not yet chosen.
	return chosen_path


# =============================================================================
# QUERY METHODS
# =============================================================================

func get_mission(mission_id: String) -> Dictionary:
	return _mission_data.get(mission_id, {})


func is_mission_completed(mission_id: String) -> bool:
	return mission_id in completed_missions


func is_mission_active(mission_id: String) -> bool:
	return mission_id in active_missions


func get_current_act() -> int:
	return current_act


func get_current_act_name() -> String:
	return ACT_NAMES[current_act - 1]


func get_missions_for_act(act: int) -> Array:
	## Returns all missions belonging to the given act number (1-4).
	var result: Array = []
	for mission_id in _mission_data:
		var m: Dictionary = _mission_data[mission_id]
		if m.get("act", 0) == act:
			result.append(m)
	return result


func get_missions_for_chapter(chapter: float) -> Array:
	## Returns all missions with the given chapter value (e.g. 1.0, 1.1, 2.3).
	## Chapter float format: integer part = act, decimal part = sub-chapter.
	var result: Array = []
	var target_act: int = int(chapter)
	var target_sub: int = _get_subchapter(chapter)
	for mission_id in _mission_data:
		var m: Dictionary = _mission_data[mission_id]
		if m.get("act", 0) == target_act and _get_subchapter(m.get("chapter", 0.0)) == target_sub:
			result.append(m)
	return result


func get_available_missions_for_path(path: String) -> Array:
	## Returns currently available missions filtered by the given path.
	## Pass "" to get path-neutral missions only, or "corporate"/"underground".
	var result: Array = []
	for mission_id in available_missions:
		var m: Dictionary = get_mission(mission_id)
		var m_path: String = m.get("path", "")
		if m_path.is_empty() or m_path == path:
			result.append(m)
	return result


func determine_ending() -> String:
	## Determine which of the 7 endings the player gets based on cumulative choices.
	## Per GDD Section 4.4. Delegates to EndingSystem for the full evaluation.
	## Returns the ending_id that can be passed to EndingSystem.trigger_ending().
	if GameManager.ending_system:
		return GameManager.ending_system.determine_ending()

	# Fallback if EndingSystem is not yet initialized
	return "legend"


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _get_subchapter(chapter: float) -> int:
	## Extracts the sub-chapter index from a chapter float.
	## e.g. 1.3 -> 3, 2.0 -> 0, 4.4 -> 4.
	return int(round(fmod(chapter, 1.0) * 10))


func _check_progression() -> void:
	## Check if completing missions should advance the chapter/act.
	var chapter_missions := _get_missions_for_current_chapter()
	var required_missions := chapter_missions.filter(func(m: Dictionary) -> bool:
		return m.get("is_story_critical", false)
	)
	var all_required_done := required_missions.all(func(m: Dictionary) -> bool:
		return m.get("id", "") in completed_missions
	)
	if all_required_done and not required_missions.is_empty():
		advance_chapter()


func _get_missions_for_current_chapter() -> Array:
	## Returns all missions for the current act + sub-chapter, respecting path filter.
	var result: Array = []
	for mission_id in _mission_data:
		var m: Dictionary = _mission_data[mission_id]
		if m.get("act", 0) != current_act:
			continue
		if _get_subchapter(m.get("chapter", 0.0)) != current_chapter:
			continue
		# Filter by path if the mission belongs to a specific path
		var m_path: String = m.get("path", "")
		if not m_path.is_empty() and m_path != chosen_path:
			continue
		result.append(m)
	return result


func _refresh_available_missions() -> void:
	available_missions.clear()
	for mission_id in _mission_data:
		if mission_id in completed_missions:
			continue
		if mission_id in active_missions:
			continue
		if mission_id in failed_missions:
			continue
		var m: Dictionary = _mission_data[mission_id]
		if m.get("act", 0) != current_act:
			continue
		if _get_subchapter(m.get("chapter", 0.0)) != current_chapter:
			continue
		# Path filter — skip missions belonging to the other path
		var m_path: String = m.get("path", "")
		if not m_path.is_empty() and m_path != chosen_path:
			continue
		# Check prerequisites
		var prereqs: Array = m.get("prerequisites", [])
		var all_prereqs_met := prereqs.all(func(p: String) -> bool:
			return p in completed_missions
		)
		if not all_prereqs_met:
			continue
		# Check required flags
		var flags_req: Array = m.get("flags_required", [])
		var all_flags_met := flags_req.all(func(f: String) -> bool:
			return story_flags.get(f, false) != false
		)
		if not all_flags_met:
			continue
		available_missions.append(mission_id)


func _apply_mission_rewards(mission_id: String, _outcome: Dictionary) -> void:
	## Apply cash, rep, and relationship rewards defined on the mission.
	var mission := get_mission(mission_id)
	var rewards: Dictionary = mission.get("rewards", {})
	if rewards.is_empty():
		return

	var cash: int = rewards.get("cash", 0)
	if cash > 0:
		GameManager.economy.earn(cash, "mission_%s" % mission_id)

	var rep: int = rewards.get("rep", 0)
	if rep > 0:
		GameManager.reputation.earn_rep(rep, "mission_%s" % mission_id)

	var rel: Dictionary = rewards.get("relationship", {})
	for char_id in rel:
		GameManager.relationships.change_affinity(char_id, rel[char_id])

	print("[Story] Rewards applied for %s — cash: %d, rep: %d" % [mission_id, cash, rep])


func check_auto_trigger_missions() -> void:
	## Start any available missions that have auto_trigger set.
	## Called after dialogue ends or when returning to free roam after a race.
	if _dialogue_system._current_dialogue_id != "":
		return # A dialogue is already active, wait for it to finish
	for mid in available_missions.duplicate():
		var m := get_mission(mid)
		if m.get("auto_trigger", false):
			start_mission(mid)
			break # One at a time


func _get_chapter_name() -> String:
	var names := {
		"1_0": "Prologue",
		"1_1": "Zero",
		"1_2": "The Pit",
		"1_3": "Blood in the Water",
		"1_4": "Underground King",
		"2_1": "New Horizons",
		"2_2": "Double Life",
		"2_3": "Rising Stakes",
		"2_4": "The Precipice",
		"3_1": "Inner Circle",
		"3_2": "The Summit",
		"3_3": "The Fall",
		"3_4": "Ashes",
		"4_1": "The Return",
		"4_2": "Building Legacy",
		"4_3": "Final Challenges",
		"4_4": "Legend",
	}
	return names.get("%d_%d" % [current_act, current_chapter], "Unknown")


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_mission_completed(_mission_id: String, _outcome: Dictionary) -> void:
	pass # Already handled in complete_mission


func _on_story_dialogue_ended(dialogue_id: String) -> void:
	## When a dialogue ends, check if it completes a story/scripted mission.
	## Then check for any auto-trigger missions that should start.
	for mid in active_missions.duplicate():
		var m := get_mission(mid)
		if m.get("dialogue_pre", "") == dialogue_id:
			var mtype: String = m.get("race_type", "")
			if mtype in ["story", "none"]:
				complete_mission(mid)
				break

	# After any dialogue ends, check for auto-trigger missions
	check_auto_trigger_missions()


func _on_race_finished(results: Dictionary) -> void:
	if results.get("is_story_mission", false):
		var mission_id: String = results.get("mission_id", "")
		if mission_id.is_empty():
			return
		if results.get("player_won", false):
			complete_mission(mission_id, results)
		else:
			# Some story races can be failed, others just have consequences
			var mission := get_mission(mission_id)
			if mission.get("fail_on_loss", false):
				fail_mission(mission_id, "race_lost")
			else:
				complete_mission(mission_id, results)


func _on_choice_made(choice_id: String, _option_index: int, option_data: Dictionary) -> void:
	# Track path divergence specifically
	if choice_id == "the_fork":
		var path: String = option_data.get("path", "")
		if not path.is_empty():
			set_path(path)


# =============================================================================
# DATA LOADING
# =============================================================================

func _load_mission_data() -> void:
	# Load from JSON if available, otherwise use built-in definitions
	var path := "res://data/missions/missions.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var missions: Array = json.data
				for m in missions:
					_mission_data[m.id] = m
				file.close()
				return
			file.close()

	# Fallback: built-in full 4-act mission definitions
	_load_default_missions()


func _m(id: String, title: String, act: int, chapter: float, desc: String,
		race_type: String = "story", overrides: Dictionary = {}) -> Dictionary:
	## Helper to build a mission dictionary with sensible defaults.
	## Override any field via the overrides dictionary.
	var mission := {
		"id": id,
		"title": title,
		"act": act,
		"chapter": chapter,
		"description": desc,
		"prerequisites": [] as Array,
		"dialogue_pre": id + "_pre",
		"dialogue_win": "",
		"dialogue_lose": "",
		"race_type": race_type,
		"race_config": {} as Dictionary,
		"rewards": {} as Dictionary,
		"flags_required": [] as Array,
		"flags_set_on_complete": [] as Array,
		"is_story_critical": false,
		"path": "",
		"auto_trigger": false,
		"fail_on_loss": false,
	}
	mission.merge(overrides, true)
	return mission


func _load_default_missions() -> void:
	var missions: Array = []

	# =========================================================================
	# PROLOGUE — Hours 0-2 — Chapter 1.0
	# The player arrives in Nova Pacifica and discovers the underground scene.
	# =========================================================================

	missions.append(_m("prologue_opening", "Opening Cinematic", 1, 1.0,
		"The neon skyline of Nova Pacifica stretches before you. A new city. A new life.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"dialogue_pre": "prologue_opening_cinematic",
			"flags_set_on_complete": ["prologue_started"],
		}))

	missions.append(_m("prologue_maya_meeting", "Meet Maya Torres", 1, 1.0,
		"A chance encounter at Torres Garage. Maya sees something in you — or in your car.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["prologue_opening"],
			"dialogue_pre": "prologue_maya_intro",
			"rewards": {"relationship": {"maya": 10}},
			"flags_set_on_complete": ["met_maya"],
		}))

	missions.append(_m("prologue_first_day", "First Day at the Shop", 1, 1.0,
		"Maya shows you the ropes. Learn the basics of tuning and the culture of the streets.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["prologue_maya_meeting"],
			"dialogue_pre": "prologue_tutorial_shop",
			"rewards": {"relationship": {"maya": 5}},
		}))

	missions.append(_m("prologue_underground", "Learn About The Pit", 1, 1.0,
		"Word of The Pit reaches you — Nova Pacifica's underground racing heart. $500 entry, everything to gain.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["prologue_first_day"],
			"dialogue_pre": "prologue_the_pit_intro",
			"flags_set_on_complete": ["prologue_complete", "the_pit_discovered"],
		}))

	# =========================================================================
	# ACT 1 — THE COME-UP
	# =========================================================================

	# --- Chapter 1.1 "Zero" — Hours 2-8 ---
	# Enter the first races. Catch the eye of legends. Diesel watches from the shadows.

	missions.append(_m("first_blood", "First Blood", 1, 1.1,
		"Your first race at The Pit. Three opponents, $500 entry. Prove you belong.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["prologue_underground"],
			"dialogue_pre": "first_blood_pre",
			"dialogue_win": "first_blood_win",
			"dialogue_lose": "first_blood_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 3,
				"ai_difficulty": 0.3,
				"tier": 1,
				"entry_fee": 500,
				"district": "downtown",
			},
			"rewards": {"cash": 500, "rep": 150},
			"flags_set_on_complete": ["first_race_done"],
		}))

	missions.append(_m("mechanics_gamble", "Mechanic's Gamble", 1, 1.1,
		"Preston talks big and bets pink slips. Beat him 1v1 and take his ride — or lose yours.",
		"sprint", {
			"prerequisites": ["first_blood"],
			"dialogue_pre": "mechanics_gamble_pre",
			"dialogue_win": "mechanics_gamble_win",
			"dialogue_lose": "mechanics_gamble_lose",
			"fail_on_loss": true,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Preston"],
				"ai_difficulty": 0.35,
				"tier": 1,
				"is_pink_slip": true,
			},
			"rewards": {"rep": 200},
			"flags_set_on_complete": ["preston_defeated"],
		}))

	missions.append(_m("diesels_test", "Diesel's Test", 1, 1.1,
		"Follow Diesel through the industrial zone. He is not racing you — he is reading you.",
		"touge", {
			"is_story_critical": true,
			"prerequisites": ["first_blood"],
			"dialogue_pre": "diesels_test_pre",
			"dialogue_win": "diesels_test_win",
			"dialogue_lose": "diesels_test_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Diesel"],
				"ai_difficulty": 0.5,
				"tier": 2,
				"district": "industrial",
			},
			"rewards": {"rep": 200, "relationship": {"diesel": 15}},
			"flags_set_on_complete": ["met_diesel", "diesel_impressed"],
		}))

	# --- Chapter 1.2 "The Pit" — Hours 8-18 ---
	# Deeper into the underground. New allies and rivals emerge.

	missions.append(_m("fresh_meat", "Fresh Meat", 1, 1.2,
		"Five-race gauntlet at The Pit. Survive the grinder and earn your name.",
		"gauntlet", {
			"is_story_critical": true,
			"prerequisites": ["diesels_test"],
			"dialogue_pre": "fresh_meat_pre",
			"dialogue_win": "fresh_meat_win",
			"dialogue_lose": "fresh_meat_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 5,
				"ai_difficulty": 0.4,
				"tier": 1,
				"race_count": 5,
				"district": "downtown",
			},
			"rewards": {"cash": 1500, "rep": 400},
		}))

	missions.append(_m("sparks_fly", "Sparks Fly", 1, 1.2,
		"Maya's equipment is being repossessed. Escape through the warehouse district with her gear.",
		"pursuit", {
			"is_story_critical": true,
			"prerequisites": ["fresh_meat"],
			"dialogue_pre": "sparks_fly_pre",
			"dialogue_win": "sparks_fly_win",
			"dialogue_lose": "sparks_fly_lose",
			"fail_on_loss": false,
			"race_config": {
				"pursuit_type": "escape",
				"ai_count": 2,
				"ai_difficulty": 0.4,
				"district": "warehouse",
			},
			"rewards": {"rep": 300, "relationship": {"maya": 20}},
			"flags_set_on_complete": ["maya_equipment_saved"],
		}))

	missions.append(_m("the_old_ways", "The Old Ways", 1, 1.2,
		"Diesel's training race. His rules, his route, his pace. Learn or be left behind.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["fresh_meat"],
			"dialogue_pre": "the_old_ways_pre",
			"dialogue_win": "the_old_ways_win",
			"dialogue_lose": "the_old_ways_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Diesel"],
				"ai_difficulty": 0.55,
				"tier": 2,
				"district": "harbor",
			},
			"rewards": {"rep": 250, "relationship": {"diesel": 10}},
		}))

	missions.append(_m("nikkos_shadow", "Nikko's Shadow", 1, 1.2,
		"Nikko Tanaka appears — your mirror, your rival. A 1v1 sprint with scripted intensity.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_old_ways"],
			"dialogue_pre": "nikkos_shadow_pre",
			"dialogue_win": "nikkos_shadow_win",
			"dialogue_lose": "nikkos_shadow_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Nikko Tanaka"],
				"ai_difficulty": 0.5,
				"tier": 2,
				"scripted_rubber_band": true,
			},
			"rewards": {"cash": 1000, "rep": 350, "relationship": {"nikko": -5}},
			"flags_set_on_complete": ["met_nikko", "nikko_rivalry_started"],
		}))

	# --- Chapter 1.3 "Blood in the Water" — Hours 18-30 ---
	# Zero takes notice. The corporate world circles. Diesel's past surfaces.

	missions.append(_m("zeros_eye", "Zero's Eye", 1, 1.3,
		"A mysterious invitation appears on your windshield. Zero has noticed you.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["nikkos_shadow"],
			"dialogue_pre": "zeros_eye_pre",
			"rewards": {"relationship": {"zero": 5}},
			"flags_set_on_complete": ["met_zero", "zero_noticed_player"],
		}))

	missions.append(_m("family_business", "Family Business", 1, 1.3,
		"High-stakes $50K race. Nikko is there too — and something is wrong with him.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["zeros_eye"],
			"dialogue_pre": "family_business_pre",
			"dialogue_win": "family_business_win",
			"dialogue_lose": "family_business_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 5,
				"ai_names": ["Nikko Tanaka", "Voss", "Drifter", "Lena", "Smoke"],
				"ai_difficulty": 0.55,
				"tier": 2,
				"entry_fee": 5000,
				"district": "downtown",
			},
			"rewards": {"cash": 50000, "rep": 600},
			"flags_set_on_complete": ["high_stakes_completed"],
		}))

	missions.append(_m("corporate_scout", "Corporate Scout", 1, 1.3,
		"Jade Chen invites you to a professional trial event. A different world entirely.",
		"circuit", {
			"prerequisites": ["zeros_eye"],
			"dialogue_pre": "corporate_scout_pre",
			"dialogue_win": "corporate_scout_win",
			"dialogue_lose": "corporate_scout_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.5,
				"tier": 2,
				"lap_count": 5,
				"district": "circuit_park",
			},
			"rewards": {"cash": 3000, "rep": 400, "relationship": {"jade": 15}},
			"flags_set_on_complete": ["met_jade", "corporate_noticed"],
		}))

	missions.append(_m("diesels_past", "Diesel's Past", 1, 1.3,
		"Diesel opens up about who he used to be. No race — just truth under streetlights.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["family_business"],
			"dialogue_pre": "diesels_past_pre",
			"rewards": {"relationship": {"diesel": 20}},
			"flags_set_on_complete": ["diesel_backstory_known"],
		}))

	# --- Chapter 1.4 "Underground King" — Hours 30-50 ---
	# The championship. Nikko's breaking. The fork in the road.

	missions.append(_m("the_gauntlet", "The Gauntlet", 1, 1.4,
		"10-race underground championship. Win at least 7 to advance to the final.",
		"tournament", {
			"is_story_critical": true,
			"prerequisites": ["diesels_past"],
			"dialogue_pre": "the_gauntlet_pre",
			"dialogue_win": "the_gauntlet_win",
			"dialogue_lose": "the_gauntlet_lose",
			"fail_on_loss": true,
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.55,
				"tier": 2,
				"race_count": 10,
				"win_requirement": 7,
				"district": "downtown",
			},
			"rewards": {"cash": 15000, "rep": 1000},
		}))

	missions.append(_m("nikkos_gambit", "Nikko's Gambit", 1, 1.4,
		"Championship semifinal. Nikko drives recklessly — do you let him crash or hold back?",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_gauntlet"],
			"dialogue_pre": "nikkos_gambit_pre",
			"dialogue_win": "nikkos_gambit_win",
			"dialogue_lose": "nikkos_gambit_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Nikko Tanaka"],
				"ai_difficulty": 0.6,
				"tier": 3,
				"scripted_crash_choice": true,
			},
			"rewards": {"cash": 5000, "rep": 500, "relationship": {"nikko": 10}},
			"flags_set_on_complete": ["nikkos_gambit_resolved"],
		}))

	missions.append(_m("the_crown", "The Crown", 1, 1.4,
		"Final championship race. Win and become the Underground King of Nova Pacifica.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["nikkos_gambit"],
			"dialogue_pre": "the_crown_pre",
			"dialogue_win": "the_crown_win",
			"dialogue_lose": "the_crown_lose",
			"fail_on_loss": true,
			"race_config": {
				"ai_count": 5,
				"ai_names": ["Voss", "Lena", "Smoke", "Drifter", "Rico"],
				"ai_difficulty": 0.6,
				"tier": 3,
				"district": "downtown",
			},
			"rewards": {"cash": 25000, "rep": 1500},
			"flags_set_on_complete": ["underground_champion"],
		}))

	missions.append(_m("the_fork", "The Fork", 1, 1.4,
		"Jade offers the corporate world. Diesel warns against it. Choose: Go Pro or Stay Underground.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["the_crown"],
			"dialogue_pre": "the_fork_choice",
			"flags_set_on_complete": ["path_chosen", "act1_complete"],
		}))

	# =========================================================================
	# ACT 2A — THE RISE (CORPORATE PATH)
	# =========================================================================

	# --- Chapter 2A.1 — Hours 50-62 ---
	# Enter the professional racing world under Jade's guidance.

	missions.append(_m("media_day", "Media Day", 2, 2.1,
		"Press conference and exhibition race. The cameras are on you now.",
		"circuit", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["the_fork"],
			"flags_required": ["path_chosen"],
			"dialogue_pre": "media_day_pre",
			"dialogue_win": "media_day_win",
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.55,
				"tier": 3,
				"lap_count": 4,
				"exhibition": true,
				"district": "circuit_park",
			},
			"rewards": {"cash": 8000, "rep": 600, "relationship": {"jade": 10}},
		}))

	missions.append(_m("the_teammate", "The Teammate", 2, 2.1,
		"Team race with Henrik Vale. Learn professional racing — and meet your new rival.",
		"circuit", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["media_day"],
			"dialogue_pre": "the_teammate_pre",
			"dialogue_win": "the_teammate_win",
			"dialogue_lose": "the_teammate_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 9,
				"ai_difficulty": 0.6,
				"tier": 3,
				"lap_count": 6,
				"team_race": true,
				"teammate": "Henrik Vale",
				"district": "circuit_park",
			},
			"rewards": {"cash": 10000, "rep": 500},
			"flags_set_on_complete": ["met_henrik"],
		}))

	missions.append(_m("circuit_initiation", "Circuit Initiation", 2, 2.1,
		"First professional race. The AI is sharper, the stakes are real, and there are rules.",
		"circuit", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["the_teammate"],
			"dialogue_pre": "circuit_initiation_pre",
			"dialogue_win": "circuit_initiation_win",
			"dialogue_lose": "circuit_initiation_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_difficulty": 0.6,
				"tier": 3,
				"lap_count": 8,
				"professional": true,
				"district": "circuit_park",
			},
			"rewards": {"cash": 15000, "rep": 800},
		}))

	missions.append(_m("jades_truth", "Jade's Truth", 2, 2.1,
		"Late night conversation with Jade. She reveals what the corporate world really costs.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["circuit_initiation"],
			"dialogue_pre": "jades_truth_pre",
			"rewards": {"relationship": {"jade": 15}},
			"flags_set_on_complete": ["jade_truth_known"],
		}))

	# --- Chapter 2A.2 — Hours 62-75 ---
	# Double life. Corporate expectations clash with underground loyalties.

	missions.append(_m("the_favor", "The Favor", 2, 2.2,
		"Maya needs help. A secret underground race while you are supposed to be corporate-clean.",
		"sprint", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["jades_truth"],
			"dialogue_pre": "the_favor_pre",
			"dialogue_win": "the_favor_win",
			"dialogue_lose": "the_favor_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 3,
				"ai_difficulty": 0.5,
				"tier": 2,
				"district": "downtown",
				"underground": true,
			},
			"rewards": {"cash": 3000, "rep": 300, "relationship": {"maya": 15}},
			"flags_set_on_complete": ["secret_race_for_maya"],
		}))

	missions.append(_m("boardroom_politics", "Boardroom Politics", 2, 2.2,
		"You discover irregularities in the racing league. Corruption runs deep.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["the_favor"],
			"dialogue_pre": "boardroom_politics_pre",
			"flags_set_on_complete": ["corruption_discovered"],
		}))

	missions.append(_m("charity_gala", "Charity Gala", 2, 2.2,
		"Social event and exhibition race. Schmooze the sponsors, then show them speed.",
		"circuit", {
			"path": "corporate",
			"prerequisites": ["boardroom_politics"],
			"dialogue_pre": "charity_gala_pre",
			"dialogue_win": "charity_gala_win",
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.55,
				"tier": 3,
				"lap_count": 3,
				"exhibition": true,
				"district": "uptown",
			},
			"rewards": {"cash": 12000, "rep": 500, "relationship": {"jade": 5}},
		}))

	missions.append(_m("henriks_challenge", "Henrik's Challenge", 2, 2.2,
		"Henrik Vale does not like sharing the spotlight. 1v1 to settle the team hierarchy.",
		"circuit", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["boardroom_politics"],
			"dialogue_pre": "henriks_challenge_pre",
			"dialogue_win": "henriks_challenge_win",
			"dialogue_lose": "henriks_challenge_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Henrik Vale"],
				"ai_difficulty": 0.65,
				"tier": 3,
				"lap_count": 5,
				"district": "circuit_park",
			},
			"rewards": {"cash": 8000, "rep": 600},
			"flags_set_on_complete": ["henrik_challenged"],
		}))

	# --- Chapter 2A.3 — Hours 75-88 ---
	# Championship chase. Old rivalries resurface. Zero beckons.

	missions.append(_m("championship_chase", "Championship Chase", 2, 2.3,
		"Five-race championship series. Consistent finishes matter more than single wins.",
		"tournament", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["henriks_challenge"],
			"dialogue_pre": "championship_chase_pre",
			"dialogue_win": "championship_chase_win",
			"dialogue_lose": "championship_chase_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_difficulty": 0.65,
				"tier": 3,
				"race_count": 5,
				"win_requirement": 3,
				"points_based": true,
				"district": "circuit_park",
			},
			"rewards": {"cash": 30000, "rep": 1200},
		}))

	missions.append(_m("nikko_returns", "Nikko Returns", 2, 2.3,
		"Nikko appears at the circuit. Different car, same fire. The rivalry reignites.",
		"circuit", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["championship_chase"],
			"dialogue_pre": "nikko_returns_pre",
			"dialogue_win": "nikko_returns_win",
			"dialogue_lose": "nikko_returns_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 7,
				"ai_names": ["Nikko Tanaka"],
				"ai_difficulty": 0.65,
				"tier": 3,
				"lap_count": 6,
				"district": "circuit_park",
			},
			"rewards": {"cash": 10000, "rep": 800, "relationship": {"nikko": 5}},
		}))

	missions.append(_m("the_offer", "The Offer", 2, 2.3,
		"A competing sponsor offers a deal. Loyalty or ambition — choose wisely.",
		"story", {
			"auto_trigger": true,
			"path": "corporate",
			"prerequisites": ["nikko_returns"],
			"dialogue_pre": "the_offer_pre",
			"flags_set_on_complete": ["sponsor_choice_made"],
		}))

	missions.append(_m("zeros_invitation", "Zero's Invitation", 2, 2.3,
		"Zero invites you to a secret elite race. Underground meets the highest level.",
		"sprint", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["nikko_returns"],
			"flags_required": ["zero_noticed_player"],
			"dialogue_pre": "zeros_invitation_pre",
			"dialogue_win": "zeros_invitation_win",
			"race_config": {
				"ai_count": 3,
				"ai_names": ["Zero's Runner", "Shadow", "Phantom"],
				"ai_difficulty": 0.7,
				"tier": 4,
				"district": "harbor",
				"underground": true,
			},
			"rewards": {"cash": 20000, "rep": 1000, "relationship": {"zero": 10}},
			"flags_set_on_complete": ["zeros_inner_circle_invited"],
		}))

	# --- Chapter 2A.4 — Hours 88-100 ---
	# The peak before the fall. Championship glory, then everything crumbles.

	missions.append(_m("championship_glory", "Championship Glory", 2, 2.4,
		"The championship final. Everything you have worked for comes down to this race.",
		"circuit", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["zeros_invitation"],
			"dialogue_pre": "championship_glory_pre",
			"dialogue_win": "championship_glory_win",
			"dialogue_lose": "championship_glory_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_names": ["Henrik Vale", "Nikko Tanaka"],
				"ai_difficulty": 0.7,
				"tier": 4,
				"lap_count": 10,
				"district": "circuit_park",
			},
			"rewards": {"cash": 50000, "rep": 2000},
			"flags_set_on_complete": ["championship_won"],
		}))

	missions.append(_m("the_celebration", "The Celebration", 2, 2.4,
		"Victory party at the top of the world. Enjoy it while it lasts.",
		"story", {
			"auto_trigger": true,
			"path": "corporate",
			"prerequisites": ["championship_glory"],
			"dialogue_pre": "the_celebration_pre",
			"rewards": {"relationship": {"jade": 10, "maya": -5}},
		}))

	missions.append(_m("the_investigation", "The Investigation", 2, 2.4,
		"A journalist has evidence of league corruption. You are tangled in it now.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["the_celebration"],
			"dialogue_pre": "the_investigation_pre",
			"flags_set_on_complete": ["investigation_started"],
		}))

	missions.append(_m("the_setup", "The Setup", 2, 2.4,
		"A race against Zero. You cannot win this one. The fall begins.",
		"sprint", {
			"is_story_critical": true,
			"path": "corporate",
			"prerequisites": ["the_investigation"],
			"dialogue_pre": "the_setup_pre",
			"dialogue_win": "the_setup_win",
			"dialogue_lose": "the_setup_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Zero"],
				"ai_difficulty": 0.95,
				"tier": 5,
				"scripted_loss": true,
				"district": "harbor",
			},
			"flags_set_on_complete": ["the_setup_complete", "corporate_fall"],
		}))

	# =========================================================================
	# ACT 2B — THE RISE (UNDERGROUND PATH)
	# =========================================================================

	# --- Chapter 2B.1 — Hours 50-62 ---

	missions.append(_m("diesels_network", "Diesel's Network", 2, 2.1,
		"Diesel reveals the full underground map. Every district, every crew, every legend.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"path": "underground",
			"prerequisites": ["the_fork"],
			"flags_required": ["path_chosen"],
			"dialogue_pre": "diesels_network_pre",
			"rewards": {"relationship": {"diesel": 15}},
			"flags_set_on_complete": ["underground_map_revealed"],
		}))

	missions.append(_m("law_encounter", "Law Encounter", 2, 2.1,
		"Detective Reyes corners you. A warning — or an opportunity disguised as a threat.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"path": "underground",
			"prerequisites": ["diesels_network"],
			"dialogue_pre": "law_encounter_pre",
			"flags_set_on_complete": ["met_reyes", "police_aware"],
		}))

	# --- Chapter 2B.2 — Hours 62-75 ---

	missions.append(_m("international_circuit", "International Circuit", 2, 2.2,
		"Underground circuit series with international racers. The world is watching in secret.",
		"tournament", {
			"is_story_critical": true,
			"path": "underground",
			"prerequisites": ["law_encounter"],
			"dialogue_pre": "international_circuit_pre",
			"dialogue_win": "international_circuit_win",
			"dialogue_lose": "international_circuit_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.6,
				"tier": 3,
				"race_count": 6,
				"win_requirement": 4,
				"district": "harbor",
			},
			"rewards": {"cash": 35000, "rep": 1500},
			"flags_set_on_complete": ["international_reputation"],
		}))

	# --- Chapter 2B.3 — Hours 75-88 ---

	missions.append(_m("underground_empire", "Underground Empire", 2, 2.3,
		"Build your territory race by race. Four districts, four kings to dethrone.",
		"sprint", {
			"is_story_critical": true,
			"path": "underground",
			"prerequisites": ["international_circuit"],
			"dialogue_pre": "underground_empire_pre",
			"dialogue_win": "underground_empire_win",
			"dialogue_lose": "underground_empire_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 3,
				"ai_difficulty": 0.65,
				"tier": 3,
				"race_count": 4,
				"district": "all",
				"territory_sprint_series": true,
			},
			"rewards": {"cash": 40000, "rep": 2000},
			"flags_set_on_complete": ["territory_claimed"],
		}))

	# --- Chapter 2B.4 — Hours 88-100 ---

	missions.append(_m("act2b_fall", "The Raid", 2, 2.4,
		"Police raid during a major race. Pursuit through the city. You cannot escape this one.",
		"pursuit", {
			"is_story_critical": true,
			"path": "underground",
			"prerequisites": ["underground_empire"],
			"dialogue_pre": "act2b_fall_pre",
			"dialogue_win": "act2b_fall_win",
			"dialogue_lose": "act2b_fall_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 4,
				"ai_difficulty": 0.8,
				"tier": 4,
				"pursuit_type": "police_raid",
				"scripted_loss": true,
				"district": "downtown",
			},
			"flags_set_on_complete": ["underground_fall", "the_setup_complete"],
		}))

	# =========================================================================
	# ACT 3 — THE FALL
	# Everything is taken. Rebuild from ashes. Uncover the truth.
	# =========================================================================

	# --- Chapter 3.1 "Inner Circle" — Hours 100-112 ---
	# Pulled into Zero's world. The elite level reveals its true nature.

	missions.append(_m("the_collection", "The Collection", 3, 3.1,
		"Zero's car cathedral. A private museum of the rarest machines on Earth.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"dialogue_pre": "the_collection_pre",
			"rewards": {"relationship": {"zero": 10}},
			"flags_set_on_complete": ["seen_zeros_collection"],
		}))

	missions.append(_m("elite_circuit", "Elite Circuit", 3, 3.1,
		"First race among the elite. Different cars, different rules, different consequences.",
		"circuit", {
			"is_story_critical": true,
			"prerequisites": ["the_collection"],
			"dialogue_pre": "elite_circuit_pre",
			"dialogue_win": "elite_circuit_win",
			"dialogue_lose": "elite_circuit_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 5,
				"ai_difficulty": 0.7,
				"tier": 4,
				"lap_count": 6,
				"elite_cars": true,
				"district": "uptown",
			},
			"rewards": {"cash": 25000, "rep": 1000},
		}))

	missions.append(_m("old_friends_stakes", "Old Friends, New Stakes", 3, 3.1,
		"Your old relationships are tested. Everyone wants something from you now.",
		"story", {
			"auto_trigger": true,
			"prerequisites": ["elite_circuit"],
			"dialogue_pre": "old_friends_stakes_pre",
			"rewards": {"relationship": {"maya": -10, "diesel": -10}},
			"flags_set_on_complete": ["relationships_strained"],
		}))

	missions.append(_m("price_of_entry", "Price of Entry", 3, 3.1,
		"Zero demands a moral compromise for full entry. A race with dark stakes.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["elite_circuit"],
			"dialogue_pre": "price_of_entry_pre",
			"dialogue_win": "price_of_entry_win",
			"dialogue_lose": "price_of_entry_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 3,
				"ai_difficulty": 0.7,
				"tier": 4,
				"dark_stakes": true,
				"district": "industrial",
			},
			"rewards": {"cash": 30000, "rep": 800, "relationship": {"zero": 15}},
			"flags_set_on_complete": ["zeros_test_passed"],
		}))

	# --- Chapter 3.2 "The Summit" — Hours 112-125 ---
	# World stage. The truth about Zero begins to surface.

	missions.append(_m("world_championship", "World Championship", 3, 3.2,
		"Eight-race global tournament. The best drivers from every continent.",
		"tournament", {
			"is_story_critical": true,
			"prerequisites": ["price_of_entry"],
			"dialogue_pre": "world_championship_pre",
			"dialogue_win": "world_championship_win",
			"dialogue_lose": "world_championship_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_difficulty": 0.75,
				"tier": 4,
				"race_count": 8,
				"win_requirement": 5,
				"global_tournament": true,
			},
			"rewards": {"cash": 75000, "rep": 3000},
		}))

	missions.append(_m("nikkos_breaking_point", "Nikko's Breaking Point", 3, 3.2,
		"Nikko is in trouble. Chase him down before he destroys himself.",
		"pursuit", {
			"is_story_critical": true,
			"prerequisites": ["world_championship"],
			"dialogue_pre": "nikkos_breaking_point_pre",
			"dialogue_win": "nikkos_breaking_point_win",
			"dialogue_lose": "nikkos_breaking_point_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Nikko Tanaka"],
				"ai_difficulty": 0.7,
				"tier": 4,
				"pursuit_type": "rescue_chase",
				"district": "harbor",
			},
			"rewards": {"relationship": {"nikko": 25}},
			"flags_set_on_complete": ["nikko_saved"],
		}))

	missions.append(_m("zero_revealed", "Zero Revealed", 3, 3.2,
		"The truth about Zero surfaces. Everything you thought you knew is wrong.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["nikkos_breaking_point"],
			"dialogue_pre": "zero_revealed_pre",
			"rewards": {"relationship": {"zero": -20}},
			"flags_set_on_complete": ["zero_truth_known"],
		}))

	missions.append(_m("the_crown_world", "The Crown: World Stage", 3, 3.2,
		"World Championship final. The entire world watches. Win, and you are immortal.",
		"circuit", {
			"is_story_critical": true,
			"prerequisites": ["zero_revealed"],
			"dialogue_pre": "the_crown_world_pre",
			"dialogue_win": "the_crown_world_win",
			"dialogue_lose": "the_crown_world_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_difficulty": 0.8,
				"tier": 5,
				"lap_count": 12,
				"world_final": true,
				"district": "circuit_park",
			},
			"rewards": {"cash": 100000, "rep": 5000},
			"flags_set_on_complete": ["world_champion"],
		}))

	# --- Chapter 3.3 "The Fall" — Hours 125-137 ---
	# Scandal. Pursuit. Rock bottom.

	missions.append(_m("the_accusation", "The Accusation", 3, 3.3,
		"The scandal breaks publicly. Your name, your career, your reputation — all under fire.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["the_crown_world"],
			"dialogue_pre": "the_accusation_pre",
			"flags_set_on_complete": ["scandal_public"],
		}))

	missions.append(_m("the_raid", "The Raid", 3, 3.3,
		"Law enforcement closes in. A desperate pursuit through the city to escape.",
		"pursuit", {
			"is_story_critical": true,
			"prerequisites": ["the_accusation"],
			"dialogue_pre": "the_raid_pre",
			"dialogue_win": "the_raid_win",
			"dialogue_lose": "the_raid_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 6,
				"ai_difficulty": 0.75,
				"tier": 4,
				"pursuit_type": "law_enforcement",
				"district": "downtown",
			},
			"flags_set_on_complete": ["escaped_raid"],
		}))

	missions.append(_m("rock_bottom", "Rock Bottom", 3, 3.3,
		"Alone in a motel room. No car. No money. No reputation. The lowest point.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["the_raid"],
			"dialogue_pre": "rock_bottom_pre",
			"flags_set_on_complete": ["rock_bottom_reached"],
		}))

	missions.append(_m("the_fire", "The Fire", 3, 3.3,
		"Someone reaches out. Who depends on the relationships you built. A spark of hope.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["rock_bottom"],
			"dialogue_pre": "the_fire_pre",
			"rewards": {"relationship": {"maya": 10, "diesel": 10}},
			"flags_set_on_complete": ["the_fire_lit"],
		}))

	# --- Chapter 3.4 "Ashes" — Hours 137-150 ---
	# Rebuild. Gather evidence. Fight back from the bottom.

	missions.append(_m("back_to_streets", "Back to the Streets", 3, 3.4,
		"Underground racing again, in a beater, with nothing to lose. Just like the beginning.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_fire"],
			"dialogue_pre": "back_to_streets_pre",
			"dialogue_win": "back_to_streets_win",
			"dialogue_lose": "back_to_streets_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 3,
				"ai_difficulty": 0.5,
				"tier": 1,
				"district": "downtown",
			},
			"rewards": {"cash": 800, "rep": 200},
			"flags_set_on_complete": ["racing_again"],
		}))

	missions.append(_m("building_the_case", "Building the Case", 3, 3.4,
		"Win races to fund the investigation. Each victory brings new evidence.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["back_to_streets"],
			"dialogue_pre": "building_the_case_pre",
			"dialogue_win": "building_the_case_win",
			"race_config": {
				"ai_count": 5,
				"ai_difficulty": 0.55,
				"tier": 2,
				"race_count": 3,
				"district": "industrial",
			},
			"rewards": {"cash": 5000, "rep": 500},
			"flags_set_on_complete": ["evidence_gathered"],
		}))

	missions.append(_m("old_debts", "Old Debts", 3, 3.4,
		"Confront those who betrayed you. Some debts are settled on the road.",
		"sprint", {
			"prerequisites": ["building_the_case"],
			"dialogue_pre": "old_debts_pre",
			"dialogue_win": "old_debts_win",
			"dialogue_lose": "old_debts_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_difficulty": 0.6,
				"tier": 3,
				"district": "harbor",
			},
			"rewards": {"cash": 3000, "rep": 400},
			"flags_set_on_complete": ["debts_settled"],
		}))

	missions.append(_m("underground_tournament", "Underground Tournament", 3, 3.4,
		"Win the underground tournament to earn the right to challenge Zero publicly.",
		"tournament", {
			"is_story_critical": true,
			"prerequisites": ["building_the_case"],
			"dialogue_pre": "underground_tournament_pre",
			"dialogue_win": "underground_tournament_win",
			"dialogue_lose": "underground_tournament_lose",
			"fail_on_loss": true,
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.65,
				"tier": 3,
				"race_count": 6,
				"win_requirement": 4,
				"district": "downtown",
			},
			"rewards": {"cash": 15000, "rep": 1500},
			"flags_set_on_complete": ["earned_challenge_right"],
		}))

	# =========================================================================
	# ACT 4 — THE REDEMPTION
	# Return, confront, build a legacy, become legend.
	# =========================================================================

	# --- Chapter 4.1 "The Return" — Hours 150-165 ---
	# Go public with the truth. Return to racing. Settle scores.

	missions.append(_m("the_press_conference", "The Press Conference", 4, 4.1,
		"Go public with the evidence against Zero and the corrupt league. No turning back.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"dialogue_pre": "the_press_conference_pre",
			"flags_set_on_complete": ["evidence_public", "zero_exposed"],
		}))

	missions.append(_m("the_challenge", "The Challenge", 4, 4.1,
		"Your first race since the fall. The crowd roars. You remember who you are.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_press_conference"],
			"dialogue_pre": "the_challenge_pre",
			"dialogue_win": "the_challenge_win",
			"dialogue_lose": "the_challenge_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 5,
				"ai_difficulty": 0.6,
				"tier": 3,
				"district": "downtown",
			},
			"rewards": {"cash": 10000, "rep": 2000},
			"flags_set_on_complete": ["comeback_started"],
		}))

	missions.append(_m("settling_accounts", "Settling Accounts", 4, 4.1,
		"Face Zero directly. Story and speed collide in the confrontation you have been building toward.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_challenge"],
			"dialogue_pre": "settling_accounts_pre",
			"dialogue_win": "settling_accounts_win",
			"dialogue_lose": "settling_accounts_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 1,
				"ai_names": ["Zero"],
				"ai_difficulty": 0.85,
				"tier": 5,
				"district": "harbor",
			},
			"rewards": {"cash": 25000, "rep": 3000, "relationship": {"zero": -10}},
			"flags_set_on_complete": ["zero_confronted"],
		}))

	missions.append(_m("the_offer_act4", "The Last Crossroad", 4, 4.1,
		"Four paths forward. The Owner, The Legend, The Mentor, or The Artist. Choose your legacy.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["settling_accounts"],
			"dialogue_pre": "the_offer_act4_pre",
			"flags_set_on_complete": ["legacy_path_chosen"],
		}))

	# --- Chapter 4.2 "Building Legacy" — Hours 165-180 ---
	# Parallel legacy paths. The player pursues their chosen future.

	missions.append(_m("legacy_path_a", "The Owner", 4, 4.2,
		"Build your own racing empire. Recruit drivers, manage crews, shape the next generation.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_offer_act4"],
			"flags_required": ["legacy_path_chosen"],
			"dialogue_pre": "legacy_path_a_pre",
			"dialogue_win": "legacy_path_a_win",
			"race_config": {
				"ai_count": 5,
				"ai_difficulty": 0.65,
				"tier": 4,
				"management_missions": true,
				"district": "all",
			},
			"rewards": {"cash": 50000, "rep": 2500},
			"flags_set_on_complete": ["legacy_owner_complete"],
		}))

	missions.append(_m("legacy_path_b", "The Legend", 4, 4.2,
		"Race on legendary tracks around the world. Cement your name in racing history.",
		"circuit", {
			"is_story_critical": true,
			"prerequisites": ["the_offer_act4"],
			"flags_required": ["legacy_path_chosen"],
			"dialogue_pre": "legacy_path_b_pre",
			"dialogue_win": "legacy_path_b_win",
			"race_config": {
				"ai_count": 11,
				"ai_difficulty": 0.8,
				"tier": 5,
				"lap_count": 8,
				"legendary_tracks": true,
			},
			"rewards": {"cash": 40000, "rep": 3000},
			"flags_set_on_complete": ["legacy_legend_complete"],
		}))

	missions.append(_m("legacy_path_c", "The Mentor", 4, 4.2,
		"Train the next generation. Story missions with teaching moments and guidance races.",
		"sprint", {
			"is_story_critical": true,
			"prerequisites": ["the_offer_act4"],
			"flags_required": ["legacy_path_chosen"],
			"dialogue_pre": "legacy_path_c_pre",
			"dialogue_win": "legacy_path_c_win",
			"race_config": {
				"ai_count": 3,
				"ai_difficulty": 0.5,
				"tier": 3,
				"teaching_race": true,
				"district": "downtown",
			},
			"rewards": {"cash": 15000, "rep": 2000, "relationship": {"maya": 10, "diesel": 10}},
			"flags_set_on_complete": ["legacy_mentor_complete"],
		}))

	missions.append(_m("legacy_path_d", "The Artist", 4, 4.2,
		"Express your passion through creative driving. Drift exhibitions, custom builds, culture.",
		"drift", {
			"is_story_critical": true,
			"prerequisites": ["the_offer_act4"],
			"flags_required": ["legacy_path_chosen"],
			"dialogue_pre": "legacy_path_d_pre",
			"dialogue_win": "legacy_path_d_win",
			"race_config": {
				"ai_count": 5,
				"ai_difficulty": 0.6,
				"tier": 4,
				"creative_mode": true,
				"district": "uptown",
			},
			"rewards": {"cash": 20000, "rep": 2500},
			"flags_set_on_complete": ["legacy_artist_complete"],
		}))

	# --- Chapter 4.3 "Final Challenges" — Hours 180-195 ---
	# The ultimate tests before the final race.

	missions.append(_m("world_remembers", "The World Remembers", 4, 4.3,
		"Exhibition races at every key location from your journey. A victory lap through memory.",
		"circuit", {
			"is_story_critical": true,
			"dialogue_pre": "world_remembers_pre",
			"dialogue_win": "world_remembers_win",
			"race_config": {
				"ai_count": 7,
				"ai_difficulty": 0.7,
				"tier": 4,
				"lap_count": 5,
				"exhibition": true,
				"multi_location": true,
			},
			"rewards": {"cash": 20000, "rep": 2000},
		}))

	missions.append(_m("ultimate_test", "The Ultimate Test", 4, 4.3,
		"24-hour endurance race. The ultimate test of skill, will, and machine.",
		"circuit", {
			"is_story_critical": true,
			"prerequisites": ["world_remembers"],
			"dialogue_pre": "ultimate_test_pre",
			"dialogue_win": "ultimate_test_win",
			"dialogue_lose": "ultimate_test_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_difficulty": 0.8,
				"tier": 5,
				"lap_count": 50,
				"endurance": true,
				"district": "circuit_park",
			},
			"rewards": {"cash": 75000, "rep": 4000},
			"flags_set_on_complete": ["endurance_complete"],
		}))

	missions.append(_m("ghosts_of_past", "Ghosts of the Past", 4, 4.3,
		"Race against your own ghost data from every major race. Can you beat who you were?",
		"time_trial", {
			"prerequisites": ["ultimate_test"],
			"dialogue_pre": "ghosts_of_past_pre",
			"dialogue_win": "ghosts_of_past_win",
			"race_config": {
				"ai_count": 0,
				"ghost_race": true,
				"district": "all",
			},
			"rewards": {"rep": 2000},
			"flags_set_on_complete": ["beat_ghost"],
		}))

	missions.append(_m("next_generation", "Next Generation", 4, 4.3,
		"A young driver approaches you, eyes full of the same fire you once had.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["ultimate_test"],
			"dialogue_pre": "next_generation_pre",
			"rewards": {"relationship": {"maya": 10, "diesel": 10, "nikko": 10}},
			"flags_set_on_complete": ["torch_ready"],
		}))

	# --- Chapter 4.4 "Legend" — Hours 195-200 ---
	# The final race. The final choice. The epilogue.

	missions.append(_m("the_final_race", "The Final Race", 4, 4.4,
		"The dream race. Everyone who matters is on the grid. One last ride under neon skies.",
		"circuit", {
			"is_story_critical": true,
			"prerequisites": ["next_generation"],
			"dialogue_pre": "the_final_race_pre",
			"dialogue_win": "the_final_race_win",
			"dialogue_lose": "the_final_race_lose",
			"fail_on_loss": false,
			"race_config": {
				"ai_count": 11,
				"ai_names": ["Nikko Tanaka", "Diesel", "Maya Torres", "Jade Chen",
					"Henrik Vale", "Zero", "Voss", "Lena", "Preston", "Rico", "Smoke"],
				"ai_difficulty": 0.85,
				"tier": 5,
				"lap_count": 15,
				"epic_finale": true,
				"district": "all",
			},
			"rewards": {"cash": 100000, "rep": 10000},
			"flags_set_on_complete": ["final_race_complete"],
		}))

	missions.append(_m("the_choice", "The Choice", 4, 4.4,
		"One last decision. Who are you? Who will you become? The ending is shaped by everything.",
		"story", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["the_final_race"],
			"dialogue_pre": "the_choice_ending",
			"flags_set_on_complete": ["ending_chosen"],
		}))

	missions.append(_m("epilogue", "Epilogue", 4, 4.4,
		"Credits drive through Nova Pacifica. The city you conquered, lost, and reclaimed.",
		"none", {
			"auto_trigger": true,
			"is_story_critical": true,
			"prerequisites": ["the_choice"],
			"dialogue_pre": "epilogue_drive",
			"race_config": {
				"freeform": true,
				"district": "all",
				"credits_overlay": true,
			},
			"flags_set_on_complete": ["story_complete"],
		}))

	# =========================================================================

	for m in missions:
		_mission_data[m.id] = m
	print("[Story] Loaded %d missions (full 4-act Harmon Circle structure)" % missions.size())


# =============================================================================
# SERIALIZATION
# =============================================================================

func serialize() -> Dictionary:
	return {
		"current_act": current_act,
		"current_chapter": current_chapter,
		"active_missions": active_missions,
		"completed_missions": completed_missions,
		"failed_missions": failed_missions,
		"story_flags": story_flags,
		"chosen_path": chosen_path,
	}


func deserialize(data: Dictionary) -> void:
	current_act = data.get("current_act", 1)
	current_chapter = data.get("current_chapter", 0)
	active_missions.assign(data.get("active_missions", []))
	completed_missions.assign(data.get("completed_missions", []))
	failed_missions.assign(data.get("failed_missions", []))
	story_flags = data.get("story_flags", {})
	chosen_path = data.get("chosen_path", "")
	_refresh_available_missions()
