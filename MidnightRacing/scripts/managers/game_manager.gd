extends Node

# Game Manager - Handles game state, saves, and core systems

signal game_started
signal game_paused
signal game_resumed

var player_data = {
	"name": "Player",
	"cash": 5000,
	"reputation": 0,
	"garage": [],
	"current_vehicle": null,
	"completed_races": [],
	"completed_missions": [],
	"unlocked_districts": ["downtown"]
}

var current_scene = null
var is_paused = false
var current_race_data = null  # Stores race data when launching a race

func _ready():
	# Connect to scene tree
	get_tree().get_root().child_entered_tree.connect(_on_scene_changed)

func start_new_game():
	"""Initialize a new game with starter vehicle"""
	player_data = {
		"name": "Player",
		"cash": 5000,
		"reputation": 0,
		"garage": [],
		"current_vehicle": null,
		"completed_races": [],
		"completed_missions": [],
		"unlocked_districts": ["downtown"]
	}

	# Add starter vehicle - Honda CRX Si
	var starter_vehicle = {
		"id": "honda_crx_si",
		"name": "Honda CRX Si",
		"make": "Honda",
		"model": "CRX Si",
		"year": 1991,
		"hp": 108,
		"torque": 100,
		"weight": 2200,
		"top_speed": 125,
		"acceleration": 8.5,
		"handling": 7.5,
		"parts": {
			"engine": "stock",
			"transmission": "stock",
			"suspension": "stock",
			"tires": "stock",
			"brakes": "stock",
			"body": "stock",
			"nitrous": null
		},
		"visual_mods": {
			"paint": "red",
			"vinyl": null,
			"wheels": "stock",
			"spoiler": null,
			"body_kit": null
		}
	}

	player_data.garage.append(starter_vehicle)
	player_data.current_vehicle = "honda_crx_si"

	print("New game started! Starter vehicle added: ", starter_vehicle.name)
	game_started.emit()

	# Load into free roam
	load_scene("res://scenes/districts/downtown.tscn")

func load_game(save_data: Dictionary):
	"""Load game from save data"""
	player_data = save_data
	print("Game loaded!")

func save_game():
	"""Save current game state"""
	var save_file = FileAccess.open("user://savegame.save", FileAccess.WRITE)
	save_file.store_var(player_data)
	save_file.close()
	print("Game saved!")

func load_scene(scene_path: String):
	"""Load a new scene"""
	get_tree().change_scene_to_file(scene_path)

func pause_game():
	"""Pause the game"""
	is_paused = true
	get_tree().paused = true
	game_paused.emit()

func resume_game():
	"""Resume the game"""
	is_paused = false
	get_tree().paused = false
	game_resumed.emit()

func add_cash(amount: int):
	"""Add cash to player"""
	player_data.cash += amount
	print("Cash added: $", amount, " | Total: $", player_data.cash)

func spend_cash(amount: int) -> bool:
	"""Spend cash - returns false if not enough"""
	if player_data.cash >= amount:
		player_data.cash -= amount
		print("Cash spent: $", amount, " | Remaining: $", player_data.cash)
		return true
	else:
		print("Not enough cash! Need: $", amount, " | Have: $", player_data.cash)
		return false

func add_reputation(amount: int):
	"""Add reputation points"""
	player_data.reputation += amount
	print("Reputation gained: +", amount, " | Total: ", player_data.reputation)

func get_current_vehicle():
	"""Get the current vehicle data"""
	for vehicle in player_data.garage:
		if vehicle.id == player_data.current_vehicle:
			return vehicle
	return null

func unlock_district(district_name: String):
	"""Unlock a new district"""
	if district_name not in player_data.unlocked_districts:
		player_data.unlocked_districts.append(district_name)
		print("District unlocked: ", district_name)

func _on_scene_changed(_node):
	"""Called when scene changes"""
	current_scene = get_tree().current_scene
