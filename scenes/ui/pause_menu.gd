## Pause menu with settings, save/load, and quit options.
## PS1/PS2 retro aesthetic with neon pink/cyan accents.
## process_mode is WHEN_PAUSED — the parent scene opens the menu
## and pauses the tree, then this node handles all input while paused.
class_name PauseMenu
extends CanvasLayer

# --- Node References (main panel) ---
@onready var overlay: ColorRect = $Overlay
@onready var main_panel: PanelContainer = $MainPanel
@onready var menu_buttons: VBoxContainer = $MainPanel/MainVBox/MenuButtons
@onready var resume_btn: Button = $MainPanel/MainVBox/MenuButtons/ResumeBtn
@onready var save_btn: Button = $MainPanel/MainVBox/MenuButtons/SaveBtn
@onready var load_btn: Button = $MainPanel/MainVBox/MenuButtons/LoadBtn
@onready var settings_btn: Button = $MainPanel/MainVBox/MenuButtons/SettingsBtn
@onready var quit_menu_btn: Button = $MainPanel/MainVBox/MenuButtons/QuitMenuBtn
@onready var quit_game_btn: Button = $MainPanel/MainVBox/MenuButtons/QuitGameBtn

# --- Node References (settings panel) ---
@onready var settings_panel: PanelContainer = $SettingsPanel
@onready var settings_content: VBoxContainer = $SettingsPanel/SettingsVBox/SettingsScroll/SettingsContent
@onready var settings_back_btn: Button = $SettingsPanel/SettingsVBox/SettingsBackBtn

# --- Node References (confirm dialog) ---
@onready var confirm_dialog: PanelContainer = $ConfirmDialog
@onready var confirm_text: Label = $ConfirmDialog/ConfirmVBox/ConfirmText
@onready var confirm_yes_btn: Button = $ConfirmDialog/ConfirmVBox/ConfirmButtons/ConfirmYes
@onready var confirm_no_btn: Button = $ConfirmDialog/ConfirmVBox/ConfirmButtons/ConfirmNo

# --- Settings Controls (created dynamically in _build_settings_ui) ---
var _master_vol_slider: HSlider
var _music_vol_slider: HSlider
var _sfx_vol_slider: HSlider
var _engine_vol_slider: HSlider
var _camera_sens_slider: HSlider
var _psx_shader_slider: HSlider
var _fps_toggle: CheckButton
var _vsync_toggle: CheckButton
var _fullscreen_toggle: CheckButton

# --- Internal State ---
var _is_open: bool = false
var _in_settings: bool = false
var _in_confirm: bool = false
var _previous_state: int = GameManager.GameState.FREE_ROAM
var _confirm_action: Callable
var _pulse_tween: Tween = null
var _current_focus_btn: Button = null

## When true, disables Save button (used during races).
var race_mode: bool = false

# --- Style Constants ---
const COLOR_NEON_PINK := Color(1.0, 0.0, 0.6)
const COLOR_CYAN := Color(0.0, 1.0, 1.0)
const COLOR_PANEL_BG := Color(0.03, 0.02, 0.10, 0.95)
const COLOR_BTN_NORMAL := Color(0.06, 0.04, 0.12, 0.8)
const COLOR_BTN_HOVER := Color(1.0, 0.0, 0.6, 0.15)
const COLOR_BTN_PRESSED := Color(0.0, 1.0, 1.0, 0.2)
const COLOR_WHITE := Color(1.0, 1.0, 1.0)


func _ready() -> void:
	visible = false
	_connect_buttons()
	_build_settings_ui()
	_apply_retro_style()
	settings_panel.visible = false
	confirm_dialog.visible = false
	print("[Pause] Pause menu initialized.")


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _in_confirm:
			_hide_confirm()
		elif _in_settings:
			_close_settings()
		else:
			close_menu()


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

## Opens the pause menu and pauses the game tree.
func open_menu() -> void:
	if _is_open:
		return
	if GameManager.current_state in [
		GameManager.GameState.MENU,
		GameManager.GameState.LOADING,
		GameManager.GameState.PAUSED,
	]:
		return

	_previous_state = GameManager.current_state
	GameManager.change_state(GameManager.GameState.PAUSED)
	get_tree().paused = true

	# Disable save during races
	save_btn.disabled = race_mode
	save_btn.tooltip_text = "Cannot save during a race" if race_mode else ""

	visible = true
	_is_open = true
	_show_main_panel()
	resume_btn.grab_focus()
	print("[Pause] Menu opened. Previous state: %s" % GameManager.GameState.keys()[_previous_state])


## Closes the pause menu and unpauses the game tree.
func close_menu() -> void:
	if not _is_open:
		return

	GameManager.change_state(_previous_state)
	get_tree().paused = false

	visible = false
	_is_open = false
	_in_settings = false
	_in_confirm = false
	_stop_pulse()
	print("[Pause] Menu closed. Restored state: %s" % GameManager.GameState.keys()[_previous_state])


## Returns true when the pause menu is currently shown.
func is_open() -> bool:
	return _is_open


# ------------------------------------------------------------------
# Button Connections
# ------------------------------------------------------------------

func _connect_buttons() -> void:
	resume_btn.pressed.connect(_on_resume)
	save_btn.pressed.connect(_on_save)
	load_btn.pressed.connect(_on_load)
	settings_btn.pressed.connect(_on_settings)
	quit_menu_btn.pressed.connect(_on_quit_menu)
	quit_game_btn.pressed.connect(_on_quit_game)
	settings_back_btn.pressed.connect(_close_settings)
	confirm_yes_btn.pressed.connect(_on_confirm_yes)
	confirm_no_btn.pressed.connect(_on_confirm_no)

	# Pulse animation tracking on menu buttons
	for btn in menu_buttons.get_children():
		if btn is Button:
			btn.focus_entered.connect(_on_button_focus_entered.bind(btn))
			btn.focus_exited.connect(_on_button_focus_exited.bind(btn))


func _on_resume() -> void:
	close_menu()


func _on_save() -> void:
	if race_mode:
		return
	# Open the save/load UI in SAVE mode via EventBus (handled by main.gd SaveLoadUI)
	if EventBus.has_signal("save_screen_requested"):
		EventBus.save_screen_requested.emit()
	else:
		# Fallback: direct save to slot 1
		var success := SaveManager.save_game(1)
		if success:
			EventBus.hud_message.emit("Game saved.", 2.0)
			close_menu()
		else:
			EventBus.hud_message.emit("Save failed!", 2.0)


func _on_load() -> void:
	# Open the save/load UI in LOAD mode via EventBus (handled by main.gd SaveLoadUI)
	if EventBus.has_signal("load_screen_requested"):
		EventBus.load_screen_requested.emit()
	else:
		# Fallback: load most recent save
		if not SaveManager.has_save(1) and not SaveManager.has_save(0):
			EventBus.hud_message.emit("No save data found.", 2.0)
			return
		_show_confirm("Load last save? Unsaved progress will be lost.", func():
			get_tree().paused = false
			_is_open = false
			visible = false
			var slot := 1 if SaveManager.has_save(1) else 0
			SaveManager.load_game(slot)
			GameManager.change_state(GameManager.GameState.FREE_ROAM)
		)


func _on_settings() -> void:
	_open_settings()


func _on_quit_menu() -> void:
	_show_confirm("Quit to main menu? Unsaved progress will be lost.", func():
		get_tree().paused = false
		_is_open = false
		visible = false
		GameManager.change_state(GameManager.GameState.MENU)
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	)


func _on_quit_game() -> void:
	_show_confirm("Quit game? Unsaved progress will be lost.", func():
		get_tree().quit()
	)


# ------------------------------------------------------------------
# Settings Panel
# ------------------------------------------------------------------

func _open_settings() -> void:
	_in_settings = true
	main_panel.visible = false
	settings_panel.visible = true
	_load_settings_values()
	settings_back_btn.grab_focus()


func _close_settings() -> void:
	_in_settings = false
	SettingsManager.save_settings()
	settings_panel.visible = false
	main_panel.visible = true
	settings_btn.grab_focus()


func _load_settings_values() -> void:
	_master_vol_slider.value = SettingsManager.master_volume
	_music_vol_slider.value = SettingsManager.music_volume
	_sfx_vol_slider.value = SettingsManager.sfx_volume
	_engine_vol_slider.value = SettingsManager.engine_volume
	_camera_sens_slider.value = SettingsManager.camera_sensitivity
	_psx_shader_slider.value = SettingsManager.psx_shader_intensity
	_fps_toggle.button_pressed = SettingsManager.show_fps
	_vsync_toggle.button_pressed = SettingsManager.vsync
	_fullscreen_toggle.button_pressed = SettingsManager.fullscreen


func _build_settings_ui() -> void:
	# --- Audio Sliders ---
	_master_vol_slider = _add_slider_row("MASTER VOLUME", 0, 100, SettingsManager.DEFAULT_MASTER_VOLUME)
	_master_vol_slider.value_changed.connect(func(val: float):
		SettingsManager.set_master_volume(int(val))
		_update_slider_label(_master_vol_slider, int(val))
	)

	_music_vol_slider = _add_slider_row("MUSIC VOLUME", 0, 100, SettingsManager.DEFAULT_MUSIC_VOLUME)
	_music_vol_slider.value_changed.connect(func(val: float):
		SettingsManager.set_music_volume(int(val))
		_update_slider_label(_music_vol_slider, int(val))
	)

	_sfx_vol_slider = _add_slider_row("SFX VOLUME", 0, 100, SettingsManager.DEFAULT_SFX_VOLUME)
	_sfx_vol_slider.value_changed.connect(func(val: float):
		SettingsManager.set_sfx_volume(int(val))
		_update_slider_label(_sfx_vol_slider, int(val))
	)

	_engine_vol_slider = _add_slider_row("ENGINE VOLUME", 0, 100, SettingsManager.DEFAULT_ENGINE_VOLUME)
	_engine_vol_slider.value_changed.connect(func(val: float):
		SettingsManager.set_engine_volume(int(val))
		_update_slider_label(_engine_vol_slider, int(val))
	)

	# --- Separator ---
	var sep1 := HSeparator.new()
	sep1.add_theme_color_override("separator", Color(COLOR_NEON_PINK, 0.3))
	settings_content.add_child(sep1)

	# --- Gameplay Sliders ---
	_camera_sens_slider = _add_slider_row("CAMERA SENSITIVITY", 0, 100, SettingsManager.DEFAULT_CAMERA_SENSITIVITY)
	_camera_sens_slider.value_changed.connect(func(val: float):
		SettingsManager.set_camera_sensitivity(int(val))
		_update_slider_label(_camera_sens_slider, int(val))
	)

	_psx_shader_slider = _add_slider_row("PSX SHADER INTENSITY", 0, 100, SettingsManager.DEFAULT_PSX_SHADER_INTENSITY)
	_psx_shader_slider.value_changed.connect(func(val: float):
		SettingsManager.set_psx_shader_intensity(int(val))
		_update_slider_label(_psx_shader_slider, int(val))
	)

	# --- Separator ---
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", Color(COLOR_NEON_PINK, 0.3))
	settings_content.add_child(sep2)

	# --- Display Toggles ---
	_fps_toggle = _add_toggle_row("SHOW FPS", SettingsManager.DEFAULT_SHOW_FPS)
	_fps_toggle.toggled.connect(func(pressed: bool):
		SettingsManager.set_show_fps(pressed)
	)

	_vsync_toggle = _add_toggle_row("VSYNC", SettingsManager.DEFAULT_VSYNC)
	_vsync_toggle.toggled.connect(func(pressed: bool):
		SettingsManager.set_vsync(pressed)
	)

	_fullscreen_toggle = _add_toggle_row("FULLSCREEN", SettingsManager.DEFAULT_FULLSCREEN)
	_fullscreen_toggle.toggled.connect(func(pressed: bool):
		SettingsManager.set_fullscreen(pressed)
	)


func _add_slider_row(label_text: String, min_val: float, max_val: float, default_val: float) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 220
	label.add_theme_color_override("font_color", COLOR_WHITE)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 1
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 180
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = str(int(default_val))
	value_label.custom_minimum_size.x = 40
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", COLOR_CYAN)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.name = "ValueLabel"
	row.add_child(value_label)

	# Store value label reference on the slider via metadata
	slider.set_meta("value_label", value_label)

	settings_content.add_child(row)
	return slider


func _add_toggle_row(label_text: String, default_val: bool) -> CheckButton:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 220
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", COLOR_WHITE)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)

	var toggle := CheckButton.new()
	toggle.button_pressed = default_val
	toggle.focus_mode = Control.FOCUS_ALL
	row.add_child(toggle)

	settings_content.add_child(row)
	return toggle


func _update_slider_label(slider: HSlider, value: int) -> void:
	var label: Label = slider.get_meta("value_label", null)
	if label:
		label.text = str(value)


# ------------------------------------------------------------------
# Confirm Dialog
# ------------------------------------------------------------------

func _show_confirm(message: String, action: Callable) -> void:
	_in_confirm = true
	_confirm_action = action
	confirm_text.text = message
	confirm_dialog.visible = true
	main_panel.visible = false
	settings_panel.visible = false
	confirm_no_btn.grab_focus()


func _hide_confirm() -> void:
	_in_confirm = false
	confirm_dialog.visible = false
	if _in_settings:
		settings_panel.visible = true
		settings_back_btn.grab_focus()
	else:
		main_panel.visible = true
		resume_btn.grab_focus()


func _on_confirm_yes() -> void:
	_in_confirm = false
	confirm_dialog.visible = false
	if _confirm_action.is_valid():
		_confirm_action.call()


func _on_confirm_no() -> void:
	_hide_confirm()


# ------------------------------------------------------------------
# Panel Management
# ------------------------------------------------------------------

func _show_main_panel() -> void:
	main_panel.visible = true
	settings_panel.visible = false
	confirm_dialog.visible = false
	_in_settings = false
	_in_confirm = false


# ------------------------------------------------------------------
# Pulse Animation on Focused Button
# ------------------------------------------------------------------

func _on_button_focus_entered(btn: Button) -> void:
	_current_focus_btn = btn
	_start_pulse(btn)


func _on_button_focus_exited(btn: Button) -> void:
	_stop_pulse()
	btn.self_modulate = Color.WHITE


func _start_pulse(btn: Button) -> void:
	_stop_pulse()
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(btn, "self_modulate", Color(1.3, 1.3, 1.3, 1.0), 0.5)
	_pulse_tween.tween_property(btn, "self_modulate", Color.WHITE, 0.5)


func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	if _current_focus_btn:
		_current_focus_btn.self_modulate = Color.WHITE


# ------------------------------------------------------------------
# Retro Styling (applied programmatically for the PS1/PS2 aesthetic)
# ------------------------------------------------------------------

func _apply_retro_style() -> void:
	_style_panel(main_panel)
	_style_panel(settings_panel)
	_style_panel(confirm_dialog)

	for btn in menu_buttons.get_children():
		if btn is Button:
			_style_button(btn)

	_style_button(settings_back_btn)
	_style_button(confirm_yes_btn)
	_style_button(confirm_no_btn)


func _style_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(COLOR_NEON_PINK, 0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 24.0
	style.content_margin_top = 24.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)


func _style_button(btn: Button) -> void:
	# Normal
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BTN_NORMAL
	normal.border_width_bottom = 1
	normal.border_color = Color(COLOR_NEON_PINK, 0.3)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", normal)

	# Hover
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_BTN_HOVER
	hover.border_width_bottom = 2
	hover.border_color = Color(COLOR_NEON_PINK, 0.8)
	hover.content_margin_left = 16.0
	hover.content_margin_right = 16.0
	hover.content_margin_top = 8.0
	hover.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = COLOR_BTN_PRESSED
	pressed.border_width_bottom = 2
	pressed.border_color = Color(COLOR_CYAN, 1.0)
	pressed.content_margin_left = 16.0
	pressed.content_margin_right = 16.0
	pressed.content_margin_top = 8.0
	pressed.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("pressed", pressed)

	# Focus
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(COLOR_NEON_PINK, 0.12)
	focus.border_width_left = 3
	focus.border_width_bottom = 2
	focus.border_color = COLOR_NEON_PINK
	focus.content_margin_left = 16.0
	focus.content_margin_right = 16.0
	focus.content_margin_top = 8.0
	focus.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("focus", focus)

	# Disabled
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.04, 0.03, 0.08, 0.5)
	disabled.content_margin_left = 16.0
	disabled.content_margin_right = 16.0
	disabled.content_margin_top = 8.0
	disabled.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("disabled", disabled)

	# Font colors
	btn.add_theme_color_override("font_color", COLOR_WHITE)
	btn.add_theme_color_override("font_hover_color", COLOR_NEON_PINK)
	btn.add_theme_color_override("font_focus_color", COLOR_WHITE)
	btn.add_theme_color_override("font_pressed_color", COLOR_CYAN)
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))
