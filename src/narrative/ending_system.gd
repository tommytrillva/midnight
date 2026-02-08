## Orchestrates the game's 7 endings, credits sequences, and post-game unlocks.
## Connects to DialogueSystem for ending dialogue playback and emits
## EventBus signals for ending lifecycle events.
## Per GDD Section 4.4: 6 standard endings + 1 secret ending.
class_name EndingSystem
extends Node

# --- Ending Definitions ---
const ENDINGS := {
	"legend": {
		"id": "legend",
		"title": "The Legend Never Dies",
		"dialogue_id": "ending_a_legend",
		"music": "ost_ending_legend",
		"credits_theme": "credits_legend",
		"priority": 50,
		"unlocks": ["new_game_plus", "legend_mode", "vehicle_legend_livery"],
	},
	"empire": {
		"id": "empire",
		"title": "The Empire",
		"dialogue_id": "ending_b_empire",
		"music": "ost_ending_empire",
		"credits_theme": "credits_empire",
		"priority": 40,
		"unlocks": ["new_game_plus", "owner_mode", "vehicle_empire_fleet"],
	},
	"family": {
		"id": "family",
		"title": "The Family",
		"dialogue_id": "ending_c_family",
		"music": "ost_ending_family",
		"credits_theme": "credits_family",
		"priority": 45,
		"unlocks": ["new_game_plus", "family_garage_hub", "vehicle_restored_crx"],
	},
	"ghost": {
		"id": "ghost",
		"title": "The Ghost",
		"dialogue_id": "ending_d_ghost",
		"music": "ost_ending_ghost",
		"credits_theme": "credits_ghost",
		"priority": 90,
		"unlocks": ["new_game_plus", "ghost_mode", "vehicle_ghost_spec"],
	},
	"contradiction": {
		"id": "contradiction",
		"title": "The Contradiction",
		"dialogue_id": "ending_e_contradiction",
		"music": "ost_ending_contradiction",
		"credits_theme": "credits_contradiction",
		"priority": 30,
		"unlocks": ["new_game_plus", "documentary_mode"],
	},
	"price": {
		"id": "price",
		"title": "The Price",
		"dialogue_id": "ending_f_price",
		"music": "ost_ending_price",
		"credits_theme": "credits_price",
		"priority": 35,
		"unlocks": ["new_game_plus", "cathedral_garage", "vehicle_zero_collection"],
	},
	"secret_beginning": {
		"id": "secret_beginning",
		"title": "The Beginning",
		"dialogue_id": "ending_secret_beginning",
		"music": "ost_ending_secret",
		"credits_theme": "credits_secret",
		"priority": 100,
		"unlocks": ["new_game_plus", "legend_mode", "ghost_mode", "ghost_origin",
					"vehicle_all_unlocked", "true_ending_flag"],
	},
}

# --- State ---
var _dialogue_system: DialogueSystem = null
var _current_ending_id: String = ""
var _ending_phase: String = "" # "dialogue", "credits", "post_game", ""
var _completed_endings: Array[String] = []


func _ready() -> void:
	_dialogue_system = DialogueSystem.new()
	add_child(_dialogue_system)
	_dialogue_system.dialogue_completed.connect(_on_ending_dialogue_completed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func trigger_ending(ending_id: String) -> void:
	## Start the ending sequence for the given ending_id.
	## Validates the ending exists, transitions game state, plays dialogue.
	if not ENDINGS.has(ending_id):
		push_error("[EndingSystem] Unknown ending: %s" % ending_id)
		return

	if not _current_ending_id.is_empty():
		push_warning("[EndingSystem] Ending already in progress: %s" % _current_ending_id)
		return

	_current_ending_id = ending_id
	_ending_phase = "dialogue"
	var ending: Dictionary = ENDINGS[ending_id]

	print("[EndingSystem] Triggering ending: %s — \"%s\"" % [ending_id, ending.title])

	# Transition game state
	GameManager.change_state(GameManager.GameState.CUTSCENE)

	# Record which ending was reached
	GameManager.player_data.set_choice_flag("ending_reached", ending_id)
	GameManager.story.set_story_flag("ending_id", ending_id)
	GameManager.story.set_story_flag("ending_title", ending.title)

	# Signal the start
	EventBus.ending_started.emit(ending_id, ending.title)

	# Start ending-specific music
	EventBus.music_track_changed.emit(ending.music, "Midnight Grind OST")

	# Fade in and start dialogue
	EventBus.screen_fade_in.emit(2.0)
	_dialogue_system.start_dialogue(ending.dialogue_id)


func play_credits(ending_id: String) -> void:
	## Play the credits sequence with ending-specific theming.
	## Called automatically after ending dialogue finishes, but can be
	## invoked directly for testing.
	if not ENDINGS.has(ending_id):
		push_error("[EndingSystem] Unknown ending for credits: %s" % ending_id)
		return

	_ending_phase = "credits"
	var ending: Dictionary = ENDINGS[ending_id]

	print("[EndingSystem] Playing credits for: %s" % ending_id)

	# Switch to credits music
	EventBus.music_track_changed.emit(ending.credits_theme, "Midnight Grind OST")

	# Emit credits signal — the UI layer picks this up to render the
	# scrolling credits with ending-specific visuals and colour palette.
	EventBus.credits_started.emit(ending_id, ending.title)

	# For the secret ending, credits will reverse mid-scroll — that
	# behaviour is handled by the credits UI scene listening for the
	# ending_id == "secret_beginning" case.

	# Credits duration is handled by the credits scene itself.
	# When the scene finishes it calls _on_credits_finished().


func unlock_post_game(ending_id: String) -> void:
	## Unlock New Game+, special modes, and vehicles based on ending.
	## Called after credits complete.
	if not ENDINGS.has(ending_id):
		push_error("[EndingSystem] Unknown ending for unlocks: %s" % ending_id)
		return

	var ending: Dictionary = ENDINGS[ending_id]
	var unlocks: Array = ending.get("unlocks", [])

	print("[EndingSystem] Unlocking post-game content for: %s" % ending_id)

	# Track this ending as completed
	if ending_id not in _completed_endings:
		_completed_endings.append(ending_id)

	# Apply each unlock
	for unlock_id in unlocks:
		_apply_unlock(unlock_id)
		print("[EndingSystem]   Unlocked: %s" % unlock_id)

	# Set persistent flags
	GameManager.player_data.set_choice_flag("ending_completed_%s" % ending_id, true)
	GameManager.player_data.set_choice_flag("post_game_unlocked", true)
	GameManager.player_data.set_choice_flag("new_game_plus_available", true)

	# Track total endings completed
	GameManager.player_data.set_choice_flag(
		"total_endings_completed", _completed_endings.size()
	)

	# Enable free roam with full map access
	_enable_free_roam()

	# Signal completion
	_ending_phase = ""
	_current_ending_id = ""
	EventBus.ending_completed.emit(ending_id, ending.title)

	print("[EndingSystem] Ending complete. Free roam enabled. %d/7 endings seen." %
		_completed_endings.size())


func get_ending_data(ending_id: String) -> Dictionary:
	## Return the definition dictionary for an ending.
	return ENDINGS.get(ending_id, {})


func is_ending_completed(ending_id: String) -> bool:
	return ending_id in _completed_endings


func get_completed_endings() -> Array[String]:
	return _completed_endings


func get_current_ending() -> String:
	return _current_ending_id


func is_ending_active() -> bool:
	return not _current_ending_id.is_empty()


func determine_ending() -> String:
	## Evaluate all game state to determine which ending the player earns.
	## Checks are ordered by priority (secret > ghost > specific > default).
	## Returns the ending_id string.
	var maya_level := GameManager.relationships.get_level("maya")
	var diesel_level := GameManager.relationships.get_level("diesel")
	var nikko_level := GameManager.relationships.get_level("nikko")
	var jade_level := GameManager.relationships.get_level("jade")
	var maya_aff := GameManager.relationships.get_affinity("maya")
	var diesel_aff := GameManager.relationships.get_affinity("diesel")
	var nikko_aff := GameManager.relationships.get_affinity("nikko")
	var moral := GameManager.player_data._moral_alignment
	var zero_awareness := GameManager.player_data._zero_awareness
	var play_time := GameManager.player_data.play_time_seconds
	var flags := GameManager.player_data._choice_flags
	var story_flags := GameManager.story.story_flags

	var beat_ghost: bool = story_flags.get("beat_ghost", false)
	var accepted_zero: bool = story_flags.get("accepted_zero_offer", false)

	# --- Secret Ending: The Beginning ---
	# Under 120 hours, all high relationships, selfless choices,
	# beat Ghost with every car type.
	var play_hours := play_time / 3600.0
	var all_high_rel := (maya_level >= 4 and diesel_level >= 4 and
						nikko_level >= 4 and jade_level >= 4)
	var selfless := moral >= 50.0
	var beat_ghost_all_types: bool = flags.get("beat_ghost_sedan", false) and \
		flags.get("beat_ghost_coupe", false) and \
		flags.get("beat_ghost_hatch", false) and \
		flags.get("beat_ghost_muscle", false)

	if (play_hours < 120.0 and all_high_rel and selfless and
		beat_ghost and beat_ghost_all_types):
		return "secret_beginning"

	# --- Ending D: The Ghost ---
	# Beat Ghost in Act 4 + specific ghost-related choices
	if beat_ghost and story_flags.get("ghost_secret_conditions", false):
		return "ghost"

	# --- Ending F: The Price ---
	# Accepted Zero's offer, morally compromised
	if accepted_zero and moral < -30.0:
		return "price"

	# --- Ending C: The Family ---
	# Maya, Nikko, Diesel all at affinity 60+
	if maya_aff >= 60 and nikko_aff >= 60 and diesel_aff >= 60:
		return "family"

	# --- Ending B: The Empire ---
	# Owner path chosen, business success flags
	var owner_path: bool = (story_flags.get("chosen_path", "") == "corporate" or
		flags.get("owner_path", false))
	var business_success: bool = flags.get("business_established", false)
	if owner_path and business_success:
		return "empire"

	# --- Ending E: The Contradiction ---
	# Mixed choices, balanced moral alignment, no dominant path
	var balanced_moral: bool = abs(moral) < 25.0
	var mixed_paths: bool = flags.get("made_corporate_choices", false) and \
		flags.get("made_underground_choices", false)
	if balanced_moral and mixed_paths:
		return "contradiction"

	# --- Ending A: The Legend Never Dies (Default) ---
	# High overall relationships and general legend status
	return "legend"


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _on_ending_dialogue_completed(dialogue_id: String) -> void:
	## Called when the ending dialogue sequence finishes.
	## Automatically transitions to credits.
	if _current_ending_id.is_empty():
		return

	var ending: Dictionary = ENDINGS.get(_current_ending_id, {})
	if ending.is_empty():
		return

	if dialogue_id == ending.get("dialogue_id", ""):
		print("[EndingSystem] Ending dialogue complete. Transitioning to credits.")
		EventBus.screen_fade_out.emit(1.5)
		# Small delay before credits via a timer
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(func(): play_credits(_current_ending_id))


func on_credits_finished() -> void:
	## Called by the credits UI scene when the scroll completes.
	## Transitions to post-game unlocks and free roam.
	if _current_ending_id.is_empty():
		return

	print("[EndingSystem] Credits finished.")
	EventBus.credits_finished.emit(_current_ending_id)
	unlock_post_game(_current_ending_id)


func _apply_unlock(unlock_id: String) -> void:
	## Apply a specific post-game unlock.
	GameManager.player_data.set_choice_flag("unlock_%s" % unlock_id, true)

	match unlock_id:
		"new_game_plus":
			GameManager.player_data.set_choice_flag("new_game_plus_available", true)

		"legend_mode":
			# All races available, increased difficulty, legendary AI opponents
			GameManager.player_data.set_choice_flag("legend_mode_unlocked", true)

		"ghost_mode":
			# Race as The Ghost — no HUD, no headlights, perfect handling
			GameManager.player_data.set_choice_flag("ghost_mode_unlocked", true)

		"owner_mode":
			# Team management post-game — hire drivers, manage garage empire
			GameManager.player_data.set_choice_flag("owner_mode_unlocked", true)

		"ghost_origin":
			# New origin story: start as a Ghost disciple
			GameManager.player_data.set_choice_flag("ghost_origin_unlocked", true)

		"documentary_mode":
			# Replay the story with interview-style commentary overlays
			GameManager.player_data.set_choice_flag("documentary_mode_unlocked", true)

		"cathedral_garage":
			# Zero's car cathedral becomes available as a free-roam garage
			GameManager.player_data.set_choice_flag("cathedral_garage_unlocked", true)

		"family_garage_hub":
			# Maya's original garage becomes a social hub in free roam
			GameManager.player_data.set_choice_flag("family_garage_hub_unlocked", true)

		"vehicle_legend_livery":
			GameManager.player_data.set_choice_flag("legend_livery_unlocked", true)

		"vehicle_empire_fleet":
			GameManager.player_data.set_choice_flag("empire_fleet_unlocked", true)

		"vehicle_restored_crx":
			GameManager.player_data.set_choice_flag("restored_crx_unlocked", true)

		"vehicle_ghost_spec":
			GameManager.player_data.set_choice_flag("ghost_spec_unlocked", true)

		"vehicle_zero_collection":
			GameManager.player_data.set_choice_flag("zero_collection_unlocked", true)

		"vehicle_all_unlocked":
			GameManager.player_data.set_choice_flag("all_vehicles_unlocked", true)

		"true_ending_flag":
			GameManager.player_data.set_choice_flag("true_ending_seen", true)


func _enable_free_roam() -> void:
	## After an ending, enable free roam with full district access.
	GameManager.change_state(GameManager.GameState.FREE_ROAM)
	GameManager.player_data.set_choice_flag("free_roam_full_access", true)

	# Unlock all districts
	for district_id in ["downtown", "harbor", "industrial", "highlands",
						"neon_mile", "route_9", "outskirts"]:
		EventBus.district_unlocked.emit(district_id)

	EventBus.hud_message.emit("Free Roam unlocked. All districts accessible.", 5.0)
	print("[EndingSystem] Free roam enabled — all districts unlocked.")


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"completed_endings": _completed_endings,
		"current_ending_id": _current_ending_id,
		"ending_phase": _ending_phase,
	}


func deserialize(data: Dictionary) -> void:
	_completed_endings.assign(data.get("completed_endings", []))
	_current_ending_id = data.get("current_ending_id", "")
	_ending_phase = data.get("ending_phase", "")
