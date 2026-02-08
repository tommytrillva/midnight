extends Area3D

# Race Trigger - Detects player entry and launches races
# Handles race initialization, requirements checking, and scene loading
#
# USAGE:
# 1. Add an Area3D node to your scene with "race_trigger" group
# 2. Attach this script to the Area3D
# 3. Configure the exported properties in the inspector:
#    - race_id: Unique identifier for this race
#    - race_name: Display name shown to player
#    - race_type: Circuit, Sprint, Drift, Drag, or Time Attack
#    - minimum_reputation: Rep required to unlock
#    - entry_fee: Cash required to enter
#    - race_scene_path: Path to the race scene .tscn file
#    - prize_money: Cash reward for winning
#    - reputation_reward: Rep gained for winning
#    - total_laps: Number of laps (for circuit races)
#    - ai_count: Number of AI opponents
# 4. The trigger will automatically create a 3D label prompt when player enters
# 5. Press E or Enter to start the race when in trigger zone
#
# INTEGRATION:
# - Requires GameManager autoload for player data and scene management
# - Checks player reputation and cash before allowing race start
# - Stores race data in GameManager.current_race_data for race scene
# - Tracks completed races in GameManager.player_data.completed_races

signal race_available(trigger)
signal race_unavailable(trigger)

# Race Properties
@export var race_id: String = "intro_race_01"
@export var race_name: String = "First Blood"
@export_enum("Circuit", "Sprint", "Drift", "Drag", "Time Attack") var race_type: String = "Sprint"
@export var minimum_reputation: int = 0
@export var entry_fee: int = 0
@export var race_scene_path: String = "res://scenes/races/intro_race.tscn"

# Race Details
@export_group("Race Info")
@export var race_description: String = "Your first street race in the city"
@export var prize_money: int = 500
@export var reputation_reward: int = 100
@export var total_laps: int = 3
@export var ai_count: int = 3

# UI Elements
@export_group("UI")
@export var prompt_key: String = "E"
@export var show_prompt_distance: float = 5.0

# Internal state
var player_in_trigger: bool = false
var player_vehicle = null
var is_race_active: bool = false
var can_race: bool = false
var prompt_label: Label = null

func _ready():
	# Connect Area3D signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create UI prompt
	create_prompt_ui()

	# Validate race data
	validate_race_config()

	print("Race Trigger initialized: ", race_name, " [", race_id, "]")

func validate_race_config():
	"""Validate race configuration"""
	if race_id.is_empty():
		push_warning("Race trigger missing race_id!")

	if race_scene_path.is_empty():
		push_warning("Race trigger missing race_scene_path!")

	if prize_money < 0:
		push_warning("Race trigger has negative prize money!")

func create_prompt_ui():
	"""Create the on-screen prompt for race activation"""
	# Create a Label3D for world-space UI
	var label_3d = Label3D.new()
	label_3d.name = "RacePromptLabel3D"
	label_3d.text = ""
	label_3d.pixel_size = 0.002
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.outline_size = 8
	label_3d.outline_modulate = Color.BLACK
	label_3d.font_size = 32
	label_3d.position = Vector3(0, 2.5, 0)  # Float above trigger
	label_3d.visible = false
	add_child(label_3d)
	prompt_label = label_3d

func _process(_delta):
	"""Handle per-frame updates"""
	if player_in_trigger and player_vehicle:
		update_prompt_visibility()

		# Check for race activation input
		if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_E):
			attempt_start_race()

func update_prompt_visibility():
	"""Update prompt based on player distance and requirements"""
	if not prompt_label:
		return

	# Check requirements
	can_race = check_race_requirements()

	if can_race:
		prompt_label.text = "Press [%s] to start %s\n%s - $%d Prize" % [prompt_key, race_name, race_type, prize_money]
		prompt_label.modulate = Color.GREEN_YELLOW
	else:
		var reason = get_unavailable_reason()
		prompt_label.text = "Race Locked: %s" % reason
		prompt_label.modulate = Color.INDIAN_RED

	prompt_label.visible = true

func check_race_requirements() -> bool:
	"""Check if player meets race requirements"""
	if not GameManager:
		return false

	# Check if race already completed
	if race_id in GameManager.player_data.completed_races:
		return false

	# Check reputation requirement
	if GameManager.player_data.reputation < minimum_reputation:
		return false

	# Check cash for entry fee
	if GameManager.player_data.cash < entry_fee:
		return false

	return true

func get_unavailable_reason() -> String:
	"""Get reason why race is unavailable"""
	if not GameManager:
		return "Game not initialized"

	if race_id in GameManager.player_data.completed_races:
		return "Already Completed"

	if GameManager.player_data.reputation < minimum_reputation:
		return "Need %d Rep (Have %d)" % [minimum_reputation, GameManager.player_data.reputation]

	if GameManager.player_data.cash < entry_fee:
		return "Need $%d Entry Fee" % entry_fee

	return "Unknown"

func attempt_start_race():
	"""Attempt to start the race"""
	if not can_race:
		print("Cannot start race: ", get_unavailable_reason())
		show_error_feedback()
		return

	if is_race_active:
		print("Race already active!")
		return

	# Charge entry fee
	if entry_fee > 0:
		if not GameManager.spend_cash(entry_fee):
			print("Failed to charge entry fee!")
			return

	# Start race
	start_race()

func start_race():
	"""Initialize and load the race"""
	is_race_active = true

	print("=== RACE STARTING ===")
	print("Race: ", race_name)
	print("Type: ", race_type)
	print("Prize: $", prize_money)
	print("Rep Reward: +", reputation_reward)

	# Store race data for the race scene to access
	if GameManager:
		GameManager.current_race_data = {
			"race_id": race_id,
			"race_name": race_name,
			"race_type": race_type,
			"prize_money": prize_money,
			"reputation_reward": reputation_reward,
			"total_laps": total_laps,
			"ai_count": ai_count,
			"entry_fee": entry_fee
		}

	# Load race scene
	load_race_scene()

func load_race_scene():
	"""Load the race scene"""
	if race_scene_path.is_empty():
		push_error("No race scene path configured for race: ", race_id)
		is_race_active = false
		return

	# Check if scene exists
	if not ResourceLoader.exists(race_scene_path):
		push_error("Race scene not found: ", race_scene_path)
		is_race_active = false
		return

	# Load scene
	print("Loading race scene: ", race_scene_path)
	GameManager.load_scene(race_scene_path)

func show_error_feedback():
	"""Show visual feedback for error"""
	if prompt_label:
		var original_color = prompt_label.modulate
		prompt_label.modulate = Color.RED
		await get_tree().create_timer(0.2).timeout
		if prompt_label:
			prompt_label.modulate = original_color

func _on_body_entered(body):
	"""Handle body entering trigger zone"""
	# Check if it's the player vehicle
	if body.is_in_group("player_vehicle"):
		player_in_trigger = true
		player_vehicle = body
		race_available.emit(self)
		print("Player entered race trigger: ", race_name)

func _on_body_exited(body):
	"""Handle body exiting trigger zone"""
	# Check if it's the player vehicle
	if body.is_in_group("player_vehicle"):
		player_in_trigger = false
		player_vehicle = null
		race_unavailable.emit(self)

		# Hide prompt
		if prompt_label:
			prompt_label.visible = false

		print("Player exited race trigger: ", race_name)

func get_race_info() -> Dictionary:
	"""Get race information as a dictionary"""
	return {
		"race_id": race_id,
		"race_name": race_name,
		"race_type": race_type,
		"minimum_reputation": minimum_reputation,
		"entry_fee": entry_fee,
		"prize_money": prize_money,
		"reputation_reward": reputation_reward,
		"total_laps": total_laps,
		"ai_count": ai_count,
		"description": race_description,
		"is_completed": GameManager and race_id in GameManager.player_data.completed_races
	}

func mark_race_completed():
	"""Mark this race as completed (called by race manager)"""
	if GameManager and race_id not in GameManager.player_data.completed_races:
		GameManager.player_data.completed_races.append(race_id)
		print("Race completed and saved: ", race_id)
