extends Control

# Main Menu

@onready var new_game_button = $VBoxContainer/NewGameButton
@onready var load_game_button = $VBoxContainer/LoadGameButton
@onready var quit_button = $VBoxContainer/QuitButton

func _ready():
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_new_game_pressed():
	print("Starting new game...")
	GameManager.start_new_game()

func _on_load_game_pressed():
	print("Loading game...")
	# TODO: Implement load game

func _on_quit_pressed():
	get_tree().quit()
