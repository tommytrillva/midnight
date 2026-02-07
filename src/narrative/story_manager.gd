## Manages the overall narrative progression through the 4-act Harmon Circle structure.
## Tracks current act/chapter, mission states, and narrative flags.
## Per GDD Section 4 and Section 9.
class_name StoryManager
extends Node

enum Act { ACT_1, ACT_2, ACT_3, ACT_4 }

const ACT_NAMES := ["The Come-Up", "The Rise", "The Fall", "The Redemption"]
const CHAPTERS_PER_ACT := [4, 4, 4, 4]

var current_act: int = 1
var current_chapter: int = 1
var active_missions: Array[String] = []
var completed_missions: Array[String] = []
var failed_missions: Array[String] = []
var available_missions: Array[String] = []
var story_flags: Dictionary = {} # Persistent story state

# Path divergence tracking (Act 2)
var chosen_path: String = "" # "corporate" or "underground" or ""

# Mission definitions (loaded from data or defined here for MVP)
var _mission_data: Dictionary = {}
var _dialogue_system: DialogueSystem = null


func _ready() -> void:
	_dialogue_system = DialogueSystem.new()
	add_child(_dialogue_system)
	_load_mission_data()

	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.choice_made.connect(_on_choice_made)


func start_new_story() -> void:
	current_act = 1
	current_chapter = 1
	active_missions.clear()
	completed_missions.clear()
	failed_missions.clear()
	available_missions.clear()
	story_flags.clear()
	chosen_path = ""
	_refresh_available_missions()


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
	print("[Story] Mission started: %s — %s" % [mission_id, mission.get("name", "")])

	# Start pre-race dialogue if it exists
	var pre_dialogue: String = mission.get("pre_dialogue", "")
	if not pre_dialogue.is_empty():
		_dialogue_system.start_dialogue(pre_dialogue)


func complete_mission(mission_id: String, outcome: Dictionary = {}) -> void:
	if mission_id not in active_missions:
		return

	active_missions.erase(mission_id)
	completed_missions.append(mission_id)

	EventBus.mission_completed.emit(mission_id, outcome)
	print("[Story] Mission completed: %s" % mission_id)

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
		return

	current_act += 1
	current_chapter = 1

	# Special handling for Act 3 transition
	if current_act == 3:
		GameManager.trigger_the_fall()

	EventBus.story_chapter_started.emit(current_act, current_chapter)
	print("[Story] ACT %d: %s" % [current_act, ACT_NAMES[current_act - 1]])
	_refresh_available_missions()


func set_path(path: String) -> void:
	## Set the Act 2 path divergence. "corporate" or "underground".
	chosen_path = path
	story_flags["chosen_path"] = path
	print("[Story] Path chosen: %s" % path)


func get_mission(mission_id: String) -> Dictionary:
	return _mission_data.get(mission_id, {})


func is_mission_completed(mission_id: String) -> bool:
	return mission_id in completed_missions


func is_mission_active(mission_id: String) -> bool:
	return mission_id in active_missions


func set_story_flag(flag: String, value: Variant = true) -> void:
	story_flags[flag] = value


func get_story_flag(flag: String, default: Variant = null) -> Variant:
	return story_flags.get(flag, default)


func get_current_act_name() -> String:
	return ACT_NAMES[current_act - 1]


func determine_ending() -> String:
	## Determine which of the 6+ endings the player gets based on cumulative choices.
	## Per GDD Section 4.4.
	var maya_level := GameManager.relationships.get_level("maya")
	var diesel_level := GameManager.relationships.get_level("diesel")
	var jade_level := GameManager.relationships.get_level("jade")
	var nikko_level := GameManager.relationships.get_level("nikko")
	var moral := GameManager.player_data._moral_alignment
	var zero_awareness := GameManager.player_data._zero_awareness
	var beat_ghost := story_flags.get("beat_ghost", false)
	var accepted_zero_offer := story_flags.get("accepted_zero_offer", false)

	# The Ghost ending (secret, highest priority)
	if beat_ghost and story_flags.get("ghost_secret_conditions", false):
		return "the_ghost"

	# Become Zero
	if accepted_zero_offer and moral < -30:
		return "become_zero"

	# Destroy Zero
	if zero_awareness >= 4 and diesel_level >= 4 and not accepted_zero_offer:
		return "destroy_zero"

	# The Escape
	if maya_level >= 5 and abs(moral) < 30:
		return "the_escape"

	# The Professional
	if chosen_path == "corporate" and jade_level >= 4:
		return "the_professional"

	# Default: Legend of the Streets
	return "legend_of_the_streets"


func _check_progression() -> void:
	## Check if completing missions should advance the chapter/act.
	var chapter_missions := _get_missions_for_chapter(current_act, current_chapter)
	var required_missions := chapter_missions.filter(func(m):
		return m.get("required", false)
	)
	var all_required_done := required_missions.all(func(m):
		return m.get("id", "") in completed_missions
	)
	if all_required_done and not required_missions.is_empty():
		advance_chapter()


func _get_missions_for_chapter(act: int, chapter: int) -> Array:
	var result: Array = []
	for mission_id in _mission_data:
		var m: Dictionary = _mission_data[mission_id]
		if m.get("act", 0) == act and m.get("chapter", 0) == chapter:
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
		if m.get("chapter", 0) != current_chapter:
			continue
		# Check prerequisites
		var prereqs: Array = m.get("prerequisites", [])
		var all_met := prereqs.all(func(p): return p in completed_missions)
		if all_met:
			available_missions.append(mission_id)


func _on_mission_completed(mission_id: String, _outcome: Dictionary) -> void:
	pass # Already handled in complete_mission


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


func _get_chapter_name() -> String:
	var names := {
		"1_1": "Arrival", "1_2": "Proving Ground",
		"1_3": "The Undercard", "1_4": "Rising Heat",
		"2_1": "New Levels", "2_2": "The Fork",
		"2_3": "Empire Building", "2_4": "The Summit",
		"3_1": "Cracks", "3_2": "The Betrayal",
		"3_3": "Rock Bottom", "3_4": "The Spark",
		"4_1": "From the Ashes", "4_2": "Gathering Storm",
		"4_3": "The Reckoning", "4_4": "Legacy",
	}
	return names.get("%d_%d" % [current_act, current_chapter], "Unknown")


func _load_mission_data() -> void:
	# Load from JSON if available, otherwise use built-in Act 1 definitions
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

	# Fallback: built-in Act 1 Ch. 1-2 missions for MVP
	_load_default_missions()


func _load_default_missions() -> void:
	var missions := [
		{
			"id": "arrival", "name": "Arrival", "act": 1, "chapter": 1,
			"type": "scripted", "required": true,
			"description": "Arrive in Nova Pacifica. A new beginning.",
			"pre_dialogue": "arrival_intro",
			"prerequisites": [],
		},
		{
			"id": "first_blood", "name": "First Blood", "act": 1, "chapter": 1,
			"type": "street_sprint", "required": true,
			"description": "Your first race — prove you belong.",
			"pre_dialogue": "first_blood_pre",
			"post_win_dialogue": "first_blood_win",
			"post_lose_dialogue": "first_blood_lose",
			"fail_on_loss": false,
			"prerequisites": ["arrival"],
			"rewards": {"cash": 300, "rep": 100},
		},
		{
			"id": "torres_garage", "name": "Torres Garage", "act": 1, "chapter": 1,
			"type": "story", "required": true,
			"description": "Meet Maya, tour the garage, get your first upgrade.",
			"pre_dialogue": "torres_garage_intro",
			"prerequisites": ["first_blood"],
			"rewards": {"relationship": {"maya": 10}},
		},
		{
			"id": "the_watcher", "name": "The Watcher", "act": 1, "chapter": 2,
			"type": "story", "required": true,
			"description": "Diesel observes your race from the shadows.",
			"pre_dialogue": "the_watcher",
			"prerequisites": ["torres_garage"],
			"rewards": {"relationship": {"diesel": 5}},
		},
		{
			"id": "proving_grounds", "name": "Proving Grounds", "act": 1, "chapter": 2,
			"type": "circuit", "required": true,
			"description": "First organized event — beat local regulars.",
			"pre_dialogue": "proving_grounds_pre",
			"prerequisites": ["the_watcher"],
			"rewards": {"cash": 800, "rep": 300},
		},
		{
			"id": "diesels_test", "name": "Diesel's Test", "act": 1, "chapter": 2,
			"type": "touge", "required": false,
			"description": "Diesel challenges you — not to win, but to see your heart.",
			"pre_dialogue": "diesels_test_pre",
			"post_win_dialogue": "diesels_test_win",
			"post_lose_dialogue": "diesels_test_lose",
			"prerequisites": ["proving_grounds"],
			"fail_on_loss": false,
			"rewards": {"relationship": {"diesel": 15}, "rep": 200},
		},
	]
	for m in missions:
		_mission_data[m.id] = m
	print("[Story] Loaded %d default missions (MVP Act 1 Ch. 1-2)" % missions.size())


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
	current_chapter = data.get("current_chapter", 1)
	active_missions.assign(data.get("active_missions", []))
	completed_missions.assign(data.get("completed_missions", []))
	failed_missions.assign(data.get("failed_missions", []))
	story_flags = data.get("story_flags", {})
	chosen_path = data.get("chosen_path", "")
	_refresh_available_missions()
