## Main scene controller. Manages scene transitions, menu state,
## and top-level game flow. Includes animated menu polish.
extends Node

const LoadingScreenScene := preload("res://scenes/ui/loading_screen.tscn")

@onready var main_menu: Control = $UI/MainMenu
@onready var title_label: Label = $UI/MainMenu/VBox/Title
@onready var subtitle_label: Label = $UI/MainMenu/VBox/Subtitle
@onready var new_game_btn: Button = $UI/MainMenu/VBox/NewGame
@onready var continue_btn: Button = $UI/MainMenu/VBox/Continue
@onready var quit_btn: Button = $UI/MainMenu/VBox/Quit
@onready var fade_overlay: ColorRect = $UI/FadeOverlay
@onready var save_load_ui: SaveLoadUI = $SaveLoadUI

# --- Transition & Loading ---
var screen_transition: ScreenTransition = null
var loading_screen: LoadingScreen = null

# --- Animation State ---
var _menu_animated: bool = false
var _btn_tweens: Dictionary = {}

# --- Style Constants ---
const COLOR_NEON_CYAN := Color(0.0, 1.0, 1.0)
const COLOR_NEON_PINK := Color(1.0, 0.0, 0.6)
const COLOR_WHITE := Color(1.0, 1.0, 1.0)


func _ready() -> void:
	# Create transition systems
	screen_transition = ScreenTransition.new()
	add_child(screen_transition)

	loading_screen = LoadingScreenScene.instantiate()
	add_child(loading_screen)

	# Connect buttons
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

	# Style menu buttons with retro neon look
	_style_menu_buttons()

	# Connect hover/press animations on buttons
	_connect_button_animations()

	# Play entrance animation
	_animate_menu_entrance()

	print("[Main] MIDNIGHT GRIND v0.1.0 initialized.")


# ------------------------------------------------------------------
# Menu Entrance Animation
# ------------------------------------------------------------------

func _animate_menu_entrance() -> void:
	if _menu_animated:
		return
	_menu_animated = true

	# Hide everything initially
	title_label.modulate.a = 0.0
	title_label.position.y -= 30.0
	subtitle_label.modulate.a = 0.0

	var buttons: Array[Button] = [new_game_btn, continue_btn, quit_btn]
	for btn in buttons:
		btn.modulate.a = 0.0
		btn.position.x -= 80.0

	# Animate title: fade + slide in
	var title_tween := create_tween()
	title_tween.set_parallel(true)
	title_tween.tween_property(title_label, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	title_tween.tween_property(title_label, "position:y", title_label.position.y + 30.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await title_tween.finished

	# Animate subtitle fade
	var sub_tween := create_tween()
	sub_tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)
	await sub_tween.finished

	# Stagger-animate buttons from the left
	for i in range(buttons.size()):
		var btn := buttons[i]
		var btn_tween := create_tween()
		btn_tween.set_parallel(true)
		btn_tween.tween_property(btn, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT).set_delay(i * 0.1)
		btn_tween.tween_property(btn, "position:x", btn.position.x + 80.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(i * 0.1)

	# Wait for the last button
	await get_tree().create_timer(0.1 * buttons.size() + 0.4).timeout
	new_game_btn.grab_focus()


# ------------------------------------------------------------------
# Button Animation Hooks
# ------------------------------------------------------------------

func _connect_button_animations() -> void:
	var buttons: Array[Button] = [new_game_btn, continue_btn, quit_btn]
	for btn in buttons:
		btn.mouse_entered.connect(_on_btn_hover_start.bind(btn))
		btn.mouse_exited.connect(_on_btn_hover_end.bind(btn))
		btn.focus_entered.connect(_on_btn_hover_start.bind(btn))
		btn.focus_exited.connect(_on_btn_hover_end.bind(btn))
		btn.button_down.connect(_on_btn_press.bind(btn))


func _on_btn_hover_start(btn: Button) -> void:
	# Kill any existing tween on this button
	_kill_btn_tween(btn)

	# Scale up slightly + neon glow pulse
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.15).set_ease(Tween.EASE_OUT)

	# Pulsing glow via self_modulate
	var glow_tween := create_tween()
	glow_tween.set_loops()
	glow_tween.tween_property(btn, "self_modulate", Color(1.4, 1.4, 1.4, 1.0), 0.4).set_ease(Tween.EASE_IN_OUT)
	glow_tween.tween_property(btn, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4).set_ease(Tween.EASE_IN_OUT)

	_btn_tweens[btn] = [tween, glow_tween]


func _on_btn_hover_end(btn: Button) -> void:
	_kill_btn_tween(btn)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "self_modulate", Color.WHITE, 0.1)


func _on_btn_press(btn: Button) -> void:
	# Flash white briefly + shake
	var flash_tween := create_tween()
	flash_tween.tween_property(btn, "self_modulate", Color(2.0, 2.0, 2.0, 1.0), 0.05)
	flash_tween.tween_property(btn, "self_modulate", Color.WHITE, 0.15)

	# Quick shake
	var orig_x := btn.position.x
	var shake_tween := create_tween()
	shake_tween.tween_property(btn, "position:x", orig_x + 4.0, 0.03)
	shake_tween.tween_property(btn, "position:x", orig_x - 3.0, 0.03)
	shake_tween.tween_property(btn, "position:x", orig_x + 2.0, 0.03)
	shake_tween.tween_property(btn, "position:x", orig_x, 0.03)


func _kill_btn_tween(btn: Button) -> void:
	if _btn_tweens.has(btn):
		for tw in _btn_tweens[btn]:
			if tw is Tween and tw.is_valid():
				tw.kill()
		_btn_tweens.erase(btn)
	btn.self_modulate = Color.WHITE


# ------------------------------------------------------------------
# Button Styling (retro neon)
# ------------------------------------------------------------------

func _style_menu_buttons() -> void:
	# Style title
	title_label.add_theme_color_override("font_color", COLOR_NEON_CYAN)
	title_label.add_theme_font_size_override("font_size", 40)

	# Style subtitle
	subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 0.8))
	subtitle_label.add_theme_font_size_override("font_size", 16)

	# Style each button
	var buttons: Array[Button] = [new_game_btn, continue_btn, quit_btn]
	for btn in buttons:
		_style_single_button(btn)


func _style_single_button(btn: Button) -> void:
	# Normal
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.04, 0.12, 0.8)
	normal.border_width_bottom = 1
	normal.border_color = Color(COLOR_NEON_PINK, 0.3)
	normal.content_margin_left = 24.0
	normal.content_margin_right = 24.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("normal", normal)

	# Hover
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(COLOR_NEON_PINK, 0.15)
	hover.border_width_bottom = 2
	hover.border_width_left = 3
	hover.border_color = COLOR_NEON_PINK
	hover.content_margin_left = 24.0
	hover.content_margin_right = 24.0
	hover.content_margin_top = 10.0
	hover.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(COLOR_NEON_CYAN, 0.2)
	pressed.border_width_bottom = 2
	pressed.border_color = COLOR_NEON_CYAN
	pressed.content_margin_left = 24.0
	pressed.content_margin_right = 24.0
	pressed.content_margin_top = 10.0
	pressed.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("pressed", pressed)

	# Focus
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(COLOR_NEON_PINK, 0.12)
	focus.border_width_left = 3
	focus.border_width_bottom = 2
	focus.border_color = COLOR_NEON_PINK
	focus.content_margin_left = 24.0
	focus.content_margin_right = 24.0
	focus.content_margin_top = 10.0
	focus.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("focus", focus)

	# Disabled
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.04, 0.03, 0.08, 0.5)
	disabled.content_margin_left = 24.0
	disabled.content_margin_right = 24.0
	disabled.content_margin_top = 10.0
	disabled.content_margin_bottom = 10.0
	btn.add_theme_stylebox_override("disabled", disabled)

	# Font colors
	btn.add_theme_color_override("font_color", COLOR_WHITE)
	btn.add_theme_color_override("font_hover_color", COLOR_NEON_PINK)
	btn.add_theme_color_override("font_focus_color", COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_NEON_CYAN)
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))
	btn.add_theme_font_size_override("font_size", 18)


# ------------------------------------------------------------------
# Game Actions
# ------------------------------------------------------------------

func _on_new_game() -> void:
	print("[Main] Starting new game...")
	GameManager.start_new_game()

	# Pixelate transition to game
	screen_transition.transition_midpoint.connect(_transition_to_game, CONNECT_ONE_SHOT)
	screen_transition.pixelate(1.2)


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

	# Fade to black then transition to game
	screen_transition.transition_midpoint.connect(_transition_to_game, CONNECT_ONE_SHOT)
	screen_transition.fade_black(1.0)


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
		var starter := VehicleFactory.create_from_json("honda_crx_si")
		if starter:
			GameManager.garage.add_vehicle(starter, "story")
			GameManager.player_data.current_vehicle_id = "honda_crx_si"

	# Load the free roam world
	var free_roam_scene := load("res://scenes/world/free_roam.tscn")
	if free_roam_scene:
		var free_roam := free_roam_scene.instantiate()
		add_child(free_roam)
		# The prologue missions auto-trigger via story.start_new_story()
		# which was called in GameManager.start_new_game(). The chain is:
		# prologue_opening -> prologue_maya_meeting -> prologue_first_day
		# -> prologue_underground -> arrival
		# If the prologue is already done (loaded save), check for auto-triggers
		if GameManager.story.is_mission_completed("prologue_opening"):
			GameManager.story.check_auto_trigger_missions()
	else:
		push_error("[Main] Failed to load free_roam.tscn")


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
