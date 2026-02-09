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
var origin: OriginSystem = null
var choice_system: ChoiceSystem = null
var consequence_manager: ConsequenceManager = null
var moral_tracker: MoralTracker = null
var ending_calculator: EndingCalculator = null
var ending_system: EndingSystem = null
var ambient_dialogue: AmbientDialogue = null
var housing: HousingSystem = null
var phone: PhoneSystem = null
var radio: RadioSystem = null
var pink_slip: PinkSlipSystem = null
var vehicle_acquisition: VehicleAcquisition = null

# --- Debug ---
var debug_mode: bool = false


func _ready() -> void:
	print("[GameManager] Initializing...")
	player_data = PlayerData.new()
	print("[GameManager] ✓ PlayerData created")
	reputation = ReputationSystem.new()
	print("[GameManager] ✓ ReputationSystem created")
	economy = EconomySystem.new()
	print("[GameManager] ✓ EconomySystem created")
	relationships = RelationshipSystem.new()
	print("[GameManager] ✓ RelationshipSystem created")
	skills = SkillTreeSystem.new()
	print("[GameManager] ✓ SkillTreeSystem created")
	story = StoryManager.new()
	print("[GameManager] ✓ StoryManager created")
	race_manager = RaceManager.new()
	print("[GameManager] ✓ RaceManager created")
	police = PoliceSystem.new()
	print("[GameManager] ✓ PoliceSystem created")
	world_time = WorldTimeSystem.new()
	print("[GameManager] ✓ WorldTimeSystem created")
	garage = GarageSystem.new()
	print("[GameManager] ✓ GarageSystem created")
	origin = OriginSystem.new()
	print("[GameManager] ✓ OriginSystem created")
	choice_system = ChoiceSystem.new()
	choice_system.name = "ChoiceSystem"
	print("[GameManager] ✓ ChoiceSystem created")
	consequence_manager = ConsequenceManager.new()
	consequence_manager.name = "ConsequenceManager"
	print("[GameManager] ✓ ConsequenceManager created")
	moral_tracker = MoralTracker.new()
	moral_tracker.name = "MoralTracker"
	print("[GameManager] ✓ MoralTracker created")
	ending_calculator = EndingCalculator.new()
	ending_calculator.name = "EndingCalculator"
	print("[GameManager] ✓ EndingCalculator created")
	ending_system = EndingSystem.new()
	ending_system.name = "EndingSystem"
	print("[GameManager] ✓ EndingSystem created")
	ambient_dialogue = AmbientDialogue.new()
	ambient_dialogue.name = "AmbientDialogue"
	print("[GameManager] ✓ AmbientDialogue created")
	housing = HousingSystem.new()
	housing.name = "HousingSystem"
	print("[GameManager] ✓ HousingSystem created")
	phone = PhoneSystem.new()
	phone.name = "PhoneSystem"
	print("[GameManager] ✓ PhoneSystem created")
	radio = RadioSystem.new()
	radio.name = "RadioSystem"
	print("[GameManager] ✓ RadioSystem created")
	pink_slip = PinkSlipSystem.new()
	pink_slip.name = "PinkSlipSystem"
	print("[GameManager] ✓ PinkSlipSystem created")
	vehicle_acquisition = VehicleAcquisition.new()
	vehicle_acquisition.name = "VehicleAcquisition"
	print("[GameManager] ✓ VehicleAcquisition created")

	print("[GameManager] Adding subsystems as children...")
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
	add_child(origin)
	add_child(choice_system)
	add_child(consequence_manager)
	add_child(moral_tracker)
	add_child(ending_calculator)
	add_child(ending_system)
	add_child(ambient_dialogue)
	add_child(housing)
	add_child(phone)
	add_child(radio)
	add_child(pink_slip)
	add_child(vehicle_acquisition)

	print("[GameManager] Setting initial values...")
	# Initialize with default state
	economy.set_cash(500) # Starting cash per GDD
	reputation.set_rep(0)

	print("[GameManager] ✓✓✓ All subsystems initialized successfully!")


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
	police.reset()
	garage.reset()
	choice_system.deserialize({})  # Reset to empty state
	consequence_manager.deserialize({})  # Reset to empty state
	moral_tracker.deserialize({})  # Reset to empty state
	ambient_dialogue.clear_recent_events()
	housing.deserialize({})  # Reset to CAR (starting housing)
	phone.deserialize({})  # Reset phone messages
	radio.deserialize({})  # Reset radio state
	pink_slip.deserialize({})  # Reset pink slip state
	vehicle_acquisition.deserialize({})  # Reset acquisition log
	world_time.deserialize({})  # Reset time/weather
	origin.deserialize({})  # Reset origin
	ending_system.deserialize({})  # Reset ending state
	# Start in CUTSCENE state for the prologue; story.start_new_story()
	# will auto-trigger the prologue_opening mission
	change_state(GameState.CUTSCENE)
	story.start_new_story()
	EventBus.story_chapter_started.emit(1, 1)
	print("[GameManager] New game started — Prologue: The Spark")


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
	housing.trigger_fall_housing()
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
		"origin": origin.serialize(),
		"choice_system": choice_system.serialize(),
		"consequence_manager": consequence_manager.serialize(),
		"moral_tracker": moral_tracker.serialize(),
		# EndingCalculator is calculated on demand, no persistence needed
		"ending_system": ending_system.serialize(),
		"ambient_dialogue": ambient_dialogue.serialize(),
		"housing": housing.serialize(),
		"phone": phone.serialize(),
		"radio": radio.serialize(),
		"pink_slip": pink_slip.serialize(),
		"vehicle_acquisition": vehicle_acquisition.serialize(),
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
	origin.deserialize(data.get("origin", {}))
	choice_system.deserialize(data.get("choice_system", {}))
	consequence_manager.deserialize(data.get("consequence_manager", {}))
	moral_tracker.deserialize(data.get("moral_tracker", {}))
	ending_system.deserialize(data.get("ending_system", {}))
	ambient_dialogue.deserialize(data.get("ambient_dialogue", {}))
	housing.deserialize(data.get("housing", {}))
	phone.deserialize(data.get("phone", {}))
	radio.deserialize(data.get("radio", {}))
	pink_slip.deserialize(data.get("pink_slip", {}))
	vehicle_acquisition.deserialize(data.get("vehicle_acquisition", {}))
	print("[GameManager] Save data loaded.")
