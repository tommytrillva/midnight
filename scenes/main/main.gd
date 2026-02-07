## Main scene controller. Manages scene transitions, menu state,
## and top-level game flow.
extends Node

@onready var main_menu: Control = $UI/MainMenu
@onready var new_game_btn: Button = $UI/MainMenu/VBox/NewGame
@onready var continue_btn: Button = $UI/MainMenu/VBox/Continue
@onready var quit_btn: Button = $UI/MainMenu/VBox/Quit
@onready var fade_overlay: ColorRect = $UI/FadeOverlay


func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	quit_btn.pressed.connect(_on_quit)

	# Check if save exists
	continue_btn.disabled = not SaveManager.has_save(0)

	# Connect to events
	EventBus.screen_fade_in.connect(_fade_in)
	EventBus.screen_fade_out.connect(_fade_out)

	GameManager.change_state(GameManager.GameState.MENU)
	print("[Main] MIDNIGHT GRIND v0.1.0 initialized.")


func _on_new_game() -> void:
	print("[Main] Starting new game...")
	_fade_out(0.5)
	await get_tree().create_timer(0.5).timeout
	GameManager.start_new_game()
	_transition_to_game()


func _on_continue() -> void:
	if SaveManager.load_game(0):
		print("[Main] Loading save...")
		_fade_out(0.5)
		await get_tree().create_timer(0.5).timeout
		_transition_to_game()
	else:
		print("[Main] No save data found.")


func _on_quit() -> void:
	get_tree().quit()


func _transition_to_game() -> void:
	main_menu.visible = false
	# Load the free roam / game world scene
	# For MVP, start the story mission sequence
	GameManager.story.start_mission("arrival")
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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if GameManager.current_state == GameManager.GameState.PAUSED:
			GameManager.change_state(GameManager.previous_state)
			get_tree().paused = false
		elif GameManager.current_state != GameManager.GameState.MENU:
			GameManager.change_state(GameManager.GameState.PAUSED)
			get_tree().paused = true
