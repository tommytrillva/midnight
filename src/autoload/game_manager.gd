## Central game state manager. Holds references to all subsystems
## and manages the overall game lifecycle.
extends Node

# --- Game State ---
enum GameState { MENU, FREE_ROAM, RACING, GARAGE, DIALOGUE, CUTSCENE, PAUSED, LOADING }

var current_state: GameState = GameState.MENU
var previous_state: GameState = GameState.MENU

# --- Player Data ---
var player_data: PlayerData = null

# --- Subsystem References (set during _ready) ---
var reputation: ReputationSystem = null
var economy: EconomySystem = null
var relationships: RelationshipSystem = null
var skills: SkillTreeSystem = null
var story: StoryManager = null
var race_manager: RaceManager = null
var police: PoliceSystem = null
var world_time: WorldTimeSystem = null
var garage: GarageSystem = null

# --- Debug ---
var debug_mode: bool = false


func _ready() -> void:
	player_data = PlayerData.new()
	reputation = ReputationSystem.new()
	economy = EconomySystem.new()
	relationships = RelationshipSystem.new()
	skills = SkillTreeSystem.new()
	story = StoryManager.new()
	race_manager = RaceManager.new()
	police = PoliceSystem.new()
	world_time = WorldTimeSystem.new()
	garage = GarageSystem.new()

	# Add subsystems as children so they process
	add_child(reputation)
	add_child(economy)
	add_child(relationships)
	add_child(skills)
	add_child(story)
	add_child(race_manager)
	add_child(police)
	add_child(world_time)
	add_child(garage)

	# Initialize with default state
	economy.set_cash(500) # Starting cash per GDD
	reputation.set_rep(0)

	print("[GameManager] All subsystems initialized.")


func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	previous_state = current_state
	current_state = new_state
	print("[GameManager] State: %s -> %s" % [GameState.keys()[previous_state], GameState.keys()[new_state]])


func start_new_game() -> void:
	player_data = PlayerData.new()
	economy.set_cash(500)
	reputation.set_rep(0)
	relationships.reset_all()
	skills.reset_all()
	story.start_new_story()
	police.reset()
	garage.reset()
	change_state(GameState.FREE_ROAM)
	EventBus.story_chapter_started.emit(1, 1)
	print("[GameManager] New game started — Act 1, Chapter 1: Arrival")


func trigger_the_fall() -> void:
	## Act 3: The Fall — strip the player of (almost) everything.
	## Per GDD: lose all vehicles except beater, lose 90% REP, money near-zero.
	## Skill tree progress is KEPT.
	var kept_vehicle_id := garage.get_worst_vehicle_id()
	garage.seize_all_except(kept_vehicle_id)
	economy.set_cash(50)
	reputation.apply_fall_penalty() # -90% REP
	police.reset()
	relationships.apply_fall_strain()
	EventBus.story_chapter_started.emit(3, 1)
	EventBus.hud_message.emit("Everything is gone.", 5.0)
	print("[GameManager] ACT 3: THE FALL triggered.")


func get_save_data() -> Dictionary:
	return {
		"version": "0.1.0",
		"state": current_state,
		"player": player_data.serialize(),
		"economy": economy.serialize(),
		"reputation": reputation.serialize(),
		"relationships": relationships.serialize(),
		"skills": skills.serialize(),
		"story": story.serialize(),
		"police": police.serialize(),
		"world_time": world_time.serialize(),
		"garage": garage.serialize(),
	}


func load_save_data(data: Dictionary) -> void:
	player_data.deserialize(data.get("player", {}))
	economy.deserialize(data.get("economy", {}))
	reputation.deserialize(data.get("reputation", {}))
	relationships.deserialize(data.get("relationships", {}))
	skills.deserialize(data.get("skills", {}))
	story.deserialize(data.get("story", {}))
	police.deserialize(data.get("police", {}))
	world_time.deserialize(data.get("world_time", {}))
	garage.deserialize(data.get("garage", {}))
	print("[GameManager] Save data loaded.")
