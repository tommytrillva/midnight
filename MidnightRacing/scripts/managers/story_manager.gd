extends Node

# Story Manager - Handles story progression, missions, and character interactions

signal mission_started(mission_id: String)
signal mission_completed(mission_id: String)
signal dialogue_triggered(character: String)
signal phone_notification(message: Dictionary)

var current_mission = null
var mission_flags = {}
var dialogue_history = []

var missions = {
	"intro_race": {
		"id": "intro_race",
		"title": "Welcome to Midnight",
		"description": "Win your first race to prove yourself",
		"type": "race",
		"requirements": {},
		"rewards": {
			"cash": 1000,
			"reputation": 50
		},
		"completed": false,
		"triggered": false
	},
	"meet_maya": {
		"id": "meet_maya",
		"title": "Street Connections",
		"description": "Meet Maya at the garage",
		"type": "story",
		"requirements": {"completed_missions": ["intro_race"]},
		"rewards": {
			"cash": 0,
			"reputation": 25,
			"unlock": "garage_upgrades"
		},
		"completed": false,
		"triggered": false,
		"location": Vector3(100, 0, 50),  # Maya's location in downtown
		"character": "Maya"
	},
	"first_upgrade": {
		"id": "first_upgrade",
		"title": "Power Up",
		"description": "Install your first performance upgrade",
		"type": "garage",
		"requirements": {"completed_missions": ["meet_maya"]},
		"rewards": {
			"cash": 500,
			"reputation": 25
		},
		"completed": false,
		"triggered": false
	},
	"diesel_challenge": {
		"id": "diesel_challenge",
		"title": "Diesel's Challenge",
		"description": "Beat Diesel in a one-on-one race",
		"type": "race",
		"requirements": {"reputation": 100},
		"rewards": {
			"cash": 2500,
			"reputation": 100,
			"unlock": "industrial_district"
		},
		"completed": false,
		"triggered": false,
		"location": Vector3(-200, 0, 150),  # Diesel's location
		"character": "Diesel"
	}
}

var characters = {
	"Maya": {
		"name": "Maya",
		"role": "Mechanic",
		"description": "Your go-to mechanic and friend in the underground scene",
		"location": Vector3(100, 0, 50),
		"met": false
	},
	"Diesel": {
		"name": "Diesel",
		"role": "Rival Racer",
		"description": "A tough competitor with a reputation to match",
		"location": Vector3(-200, 0, 150),
		"met": false
	},
	"Razor": {
		"name": "Razor",
		"role": "Crew Leader",
		"description": "Leader of the city's most notorious racing crew",
		"location": Vector3(0, 0, -300),
		"met": false
	}
}

func _ready():
	# Initialize mission system
	print("Story Manager initialized")

func check_mission_triggers():
	"""Check if any missions should be triggered"""
	for mission_id in missions:
		var mission = missions[mission_id]
		if not mission.triggered and not mission.completed:
			if check_requirements(mission.requirements):
				trigger_mission(mission_id)

func check_requirements(requirements: Dictionary) -> bool:
	"""Check if mission requirements are met"""
	if requirements.is_empty():
		return true

	# Check completed missions requirement
	if requirements.has("completed_missions"):
		for req_mission in requirements.completed_missions:
			if not missions[req_mission].completed:
				return false

	# Check reputation requirement
	if requirements.has("reputation"):
		if GameManager.player_data.reputation < requirements.reputation:
			return false

	# Check cash requirement
	if requirements.has("cash"):
		if GameManager.player_data.cash < requirements.cash:
			return false

	return true

func trigger_mission(mission_id: String):
	"""Trigger a mission"""
	if mission_id in missions:
		var mission = missions[mission_id]
		mission.triggered = true
		print("Mission triggered: ", mission.title)

		# Send phone notification
		send_phone_notification({
			"title": "New Mission",
			"message": mission.title,
			"description": mission.description,
			"type": "mission"
		})

		mission_started.emit(mission_id)

func start_mission(mission_id: String):
	"""Start a mission"""
	if mission_id in missions:
		current_mission = mission_id
		var mission = missions[mission_id]
		print("Mission started: ", mission.title)

func complete_mission(mission_id: String):
	"""Complete a mission and give rewards"""
	if mission_id in missions:
		var mission = missions[mission_id]
		mission.completed = true
		current_mission = null

		# Give rewards
		if mission.rewards.has("cash"):
			GameManager.add_cash(mission.rewards.cash)
		if mission.rewards.has("reputation"):
			GameManager.add_reputation(mission.rewards.reputation)
		if mission.rewards.has("unlock"):
			handle_unlock(mission.rewards.unlock)

		print("Mission completed: ", mission.title)
		mission_completed.emit(mission_id)

		# Check for new missions
		check_mission_triggers()

func handle_unlock(unlock_type: String):
	"""Handle various unlock types"""
	match unlock_type:
		"garage_upgrades":
			print("Garage upgrades unlocked!")
		"industrial_district":
			GameManager.unlock_district("industrial")
			send_phone_notification({
				"title": "New District",
				"message": "Industrial District Unlocked",
				"description": "New races and opportunities await",
				"type": "unlock"
			})
		_:
			print("Unknown unlock type: ", unlock_type)

func trigger_dialogue(character_name: String, location: Vector3):
	"""Trigger dialogue with a character"""
	if character_name in characters:
		var character = characters[character_name]
		character.met = true
		dialogue_history.append({
			"character": character_name,
			"time": Time.get_ticks_msec()
		})
		print("Dialogue triggered with: ", character_name)
		dialogue_triggered.emit(character_name)

func send_phone_notification(notification: Dictionary):
	"""Send a phone notification to the player"""
	print("📱 Phone notification: ", notification.title, " - ", notification.message)
	phone_notification.emit(notification)

func get_mission(mission_id: String) -> Dictionary:
	"""Get mission data"""
	if mission_id in missions:
		return missions[mission_id]
	return {}

func is_mission_available(mission_id: String) -> bool:
	"""Check if a mission is available to start"""
	if mission_id in missions:
		var mission = missions[mission_id]
		return mission.triggered and not mission.completed
	return false
