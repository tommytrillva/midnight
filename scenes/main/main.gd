## Main scene controller. Manages scene transitions, menu state,
## and top-level game flow.
extends Node

@onready var main_menu: Control = $UI/MainMenu
@onready var new_game_btn: Button = $UI/MainMenu/VBox/NewGame
@onready var continue_btn: Button = $UI/MainMenu/VBox/Continue
@onready var quit_btn: Button = $UI/MainMenu/VBox/Quit
@onready var fade_overlay: ColorRect = $UI/FadeOverlay
@onready var save_load_ui: SaveLoadUI = $SaveLoadUI


func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	quit_btn.pressed.connect(_on_quit)

	# Enable Continue if any save exists across all slots
	continue_btn.disabled = not SaveManager.has_any_save()

	# Connect to events
	EventBus.screen_fade_in.connect(_fade_in)
	EventBus.screen_fade_out.connect(_fade_out)

	# Save/Load UI signals
	save_load_ui.load_completed.connect(_on_load_completed)
	save_load_ui.save_completed.connect(_on_save_completed)
	save_load_ui.closed.connect(_on_save_load_closed)

	# Allow any system (pause menu, etc.) to request save/load screens
	EventBus.save_screen_requested.connect(_open_save_screen)
	EventBus.load_screen_requested.connect(_open_load_screen)

	GameManager.change_state(GameManager.GameState.MENU)
	print("[Main] MIDNIGHT GRIND v0.1.0 initialized.")


func _on_new_game() -> void:
	print("[Main] Starting new game...")
	_fade_out(0.5)
	await get_tree().create_timer(0.5).timeout
	GameManager.start_new_game()
	_transition_to_game()


func _on_continue() -> void:
	# Open the save/load UI in LOAD mode so the player can pick a slot
	save_load_ui.open(SaveLoadUI.Mode.LOAD)


func _on_quit() -> void:
	get_tree().quit()


func _on_load_completed(_slot: int) -> void:
	## Called when the player loads a save from the save/load UI.
	GameManager.change_state(GameManager.GameState.LOADING)
	main_menu.visible = false
	print("[Main] Loading save from slot %d..." % _slot)
	_fade_out(0.5)
	await get_tree().create_timer(0.5).timeout
	_transition_to_game()


func _on_save_completed(_slot: int) -> void:
	## Called when the player saves from the save/load UI.
	# Re-check continue button in case this was the first save
	continue_btn.disabled = not SaveManager.has_any_save()
	print("[Main] Save completed to slot %d." % _slot)


func _on_save_load_closed() -> void:
	## Called when the save/load UI is dismissed.
	if GameManager.current_state == GameManager.GameState.MENU:
		# Ensure main menu is visible when returning from load screen
		main_menu.visible = true
	elif GameManager.current_state == GameManager.GameState.PAUSED:
		# Return to paused state — a future pause menu can re-show itself here
		pass


func _open_save_screen() -> void:
	## Opens the save screen. Can be called from pause menu via EventBus.
	save_load_ui.open(SaveLoadUI.Mode.SAVE)


func _open_load_screen() -> void:
	## Opens the load screen. Can be called from pause menu via EventBus.
	save_load_ui.open(SaveLoadUI.Mode.LOAD)


func _transition_to_game() -> void:
	main_menu.visible = false

	# Give the player their starter vehicle if they don't have one
	if GameManager.garage.get_vehicle_count() == 0:
		var starter := VehicleFactory.create_from_json("starter_beater")
		if starter:
			GameManager.garage.add_vehicle(starter, "story")
			GameManager.player_data.current_vehicle_id = "starter_beater"

	# Load the free roam world
	var free_roam_scene := load("res://scenes/world/free_roam.tscn")
	if free_roam_scene:
		var free_roam := free_roam_scene.instantiate()
		add_child(free_roam)
		# Start the arrival story mission
		GameManager.story.start_mission("arrival")
	else:
		push_error("[Main] Failed to load free_roam.tscn")

	_fade_in(1.0)


func _fade_in(duration: float) -> void:
	fade_overlay.visible = true
	fade_overlay.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, duration)
	tween.tween_callback(func(): fade_overlay.visible = false)


func _fade_out(duration: float) -> void:
	fade_overlay.visible = true
	fade_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, duration)


## Pause input is handled by the PauseMenu (instanced in free_roam and race_session).
## main.gd no longer manages pause toggling directly.
