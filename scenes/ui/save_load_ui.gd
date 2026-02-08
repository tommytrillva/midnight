## Save/Load screen UI. Displays save slots with metadata and handles
## save, load, and delete operations with confirmation dialogs.
class_name SaveLoadUI
extends CanvasLayer

signal save_completed(slot: int)
signal load_completed(slot: int)
signal closed()

enum Mode { SAVE, LOAD }

const SLOT_COUNT := 5
const AUTOSAVE_SLOT := 0

# --- Style Constants (PS1/PS2 retro aesthetic) ---
const COLOR_BG_PANEL := Color(0.05, 0.05, 0.1, 0.95)
const COLOR_BG_SLOT := Color(0.06, 0.06, 0.12, 0.9)
const COLOR_BG_SLOT_SELECTED := Color(0.08, 0.12, 0.18, 0.95)
const COLOR_ACCENT_CYAN := Color(0.0, 1.0, 1.0)
const COLOR_ACCENT_PINK := Color(1.0, 0.2, 0.6)
const COLOR_TEXT := Color(1.0, 1.0, 1.0)
const COLOR_TEXT_DIM := Color(0.6, 0.6, 0.7)
const COLOR_EMPTY := Color(0.3, 0.3, 0.4)
const COLOR_BORDER_DIM := Color(0.15, 0.15, 0.25, 0.5)
const COLOR_BORDER_SELECTED := Color(0.0, 1.0, 1.0, 0.8)
const COLOR_THUMB_EMPTY := Color(0.08, 0.08, 0.12)
const COLOR_THUMB_USED := Color(0.15, 0.1, 0.2)

# --- State ---
var current_mode: Mode = Mode.LOAD
var _selected_slot: int = -1
var _slot_panels: Array[PanelContainer] = []
var _confirm_action: StringName = &""
var _is_open: bool = false

# --- Node References ---
@onready var _root: Control = $Root
@onready var _title_label: Label = $Root/Content/MainPanel/VBox/TitleLabel
@onready var _slots_container: VBoxContainer = $Root/Content/MainPanel/VBox/SlotsScroll/SlotsContainer
@onready var _back_btn: Button = $Root/Content/MainPanel/VBox/BottomBar/BackBtn
@onready var _delete_btn: Button = $Root/Content/MainPanel/VBox/BottomBar/DeleteBtn
@onready var _action_btn: Button = $Root/Content/MainPanel/VBox/BottomBar/ActionBtn
@onready var _confirm_dialog: PanelContainer = $Root/ConfirmDialog
@onready var _confirm_overlay: ColorRect = $Root/ConfirmOverlay
@onready var _confirm_label: Label = $Root/ConfirmDialog/VBox/ConfirmLabel
@onready var _confirm_yes: Button = $Root/ConfirmDialog/VBox/ButtonBar/ConfirmYes
@onready var _confirm_no: Button = $Root/ConfirmDialog/VBox/ButtonBar/ConfirmNo


func _ready() -> void:
	_back_btn.pressed.connect(_on_back)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_action_btn.pressed.connect(_on_action_pressed)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	_confirm_no.pressed.connect(_on_confirm_no)

	_apply_styles()

	visible = false
	_confirm_dialog.visible = false
	_confirm_overlay.visible = false
	_delete_btn.disabled = true
	_action_btn.disabled = true

	EventBus.save_failed.connect(_on_save_failed)

	print("[SaveUI] Initialized.")


# ==========================================================================
# Public API
# ==========================================================================

func open(mode: Mode) -> void:
	current_mode = mode
	_selected_slot = -1
	_is_open = true

	_title_label.text = "SAVE GAME" if mode == Mode.SAVE else "LOAD GAME"
	_action_btn.text = "SAVE" if mode == Mode.SAVE else "LOAD"
	_delete_btn.disabled = true
	_action_btn.disabled = true
	_confirm_dialog.visible = false
	_confirm_overlay.visible = false

	_refresh_slots()

	# Fade in
	_root.modulate.a = 0.0
	visible = true
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)

	# Focus the first slot for controller/keyboard navigation
	if _slot_panels.size() > 0:
		await get_tree().process_frame
		_slot_panels[0].grab_focus()

	print("[SaveUI] Opened in %s mode." % ("SAVE" if mode == Mode.SAVE else "LOAD"))


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		visible = false
		closed.emit()
	)
	print("[SaveUI] Closed.")


func is_open() -> bool:
	return _is_open


# ==========================================================================
# Slot Management
# ==========================================================================

func _refresh_slots() -> void:
	# Clear existing slot panels
	for panel in _slot_panels:
		if is_instance_valid(panel):
			panel.queue_free()
	_slot_panels.clear()

	# Autosave slot shown only in LOAD mode
	var start_slot := AUTOSAVE_SLOT if current_mode == Mode.LOAD else 1

	for slot_idx in range(start_slot, SLOT_COUNT + 1):
		var info := SaveManager.get_save_info(slot_idx)
		var panel := _build_slot_panel(slot_idx, info)
		_slots_container.add_child(panel)
		_slot_panels.append(panel)


func _build_slot_panel(slot: int, info: Dictionary) -> PanelContainer:
	var has_data := not info.is_empty()
	var is_autosave := (slot == AUTOSAVE_SLOT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 76)
	panel.focus_mode = Control.FOCUS_ALL
	panel.set_meta("slot_index", slot)
	panel.add_theme_stylebox_override("panel", _make_slot_stylebox(false))

	# Inner margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(hbox)

	# --- Thumbnail placeholder ---
	var thumb := ColorRect.new()
	thumb.custom_minimum_size = Vector2(64, 48)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.color = COLOR_THUMB_USED if has_data else COLOR_THUMB_EMPTY
	if is_autosave and has_data:
		thumb.color = Color(0.1, 0.15, 0.2)
	hbox.add_child(thumb)

	# --- Info column ---
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)

	# Slot label + player name
	var name_label := Label.new()
	if is_autosave:
		name_label.text = "AUTOSAVE"
		if has_data:
			name_label.text += " - %s" % info.get("player_name", "Racer")
	elif has_data:
		name_label.text = "SLOT %d - %s" % [slot, info.get("player_name", "Racer")]
	else:
		name_label.text = "SLOT %d - Empty Slot" % slot
	name_label.add_theme_color_override("font_color", COLOR_TEXT if has_data else COLOR_EMPTY)
	info_vbox.add_child(name_label)

	# Chapter/Act progress
	var progress_label := Label.new()
	if has_data:
		var act: int = info.get("story_act", 1)
		var chapter: int = info.get("story_chapter", 1)
		progress_label.text = "Act %d - Chapter %d" % [act, chapter]
	else:
		progress_label.text = "No save data"
	progress_label.add_theme_color_override(
		"font_color", COLOR_ACCENT_CYAN if has_data else COLOR_EMPTY
	)
	progress_label.add_theme_font_size_override("font_size", 13)
	info_vbox.add_child(progress_label)

	# Stats line: cash, REP, vehicle
	var stats_label := Label.new()
	if has_data:
		var cash: int = info.get("cash", 0)
		var rep: int = info.get("rep", 0)
		var vehicle: String = info.get("vehicle_name", "No Vehicle")
		stats_label.text = "$%s  |  REP %s  |  %s" % [
			_format_number(cash), _format_number(rep), vehicle
		]
	else:
		stats_label.text = ""
	stats_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	stats_label.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(stats_label)

	hbox.add_child(info_vbox)

	# --- Right column: date + play time ---
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_vbox.add_theme_constant_override("separation", 4)

	var date_label := Label.new()
	if has_data:
		date_label.text = _format_timestamp(info.get("timestamp", ""))
	else:
		date_label.text = ""
	date_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	date_label.add_theme_font_size_override("font_size", 12)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_vbox.add_child(date_label)

	var time_label := Label.new()
	if has_data:
		time_label.text = _format_play_time(info.get("play_time_seconds", 0.0))
	else:
		time_label.text = ""
	time_label.add_theme_color_override("font_color", COLOR_ACCENT_PINK)
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_vbox.add_child(time_label)

	hbox.add_child(right_vbox)

	# --- Input connections ---
	panel.gui_input.connect(func(event: InputEvent): _on_slot_gui_input(event, panel))
	panel.focus_entered.connect(func(): _on_slot_focus_entered(panel))
	panel.mouse_entered.connect(func(): _on_slot_mouse_entered(panel))

	return panel


# ==========================================================================
# Slot Selection & Activation
# ==========================================================================

func _select_slot(panel: PanelContainer) -> void:
	var slot: int = panel.get_meta("slot_index")

	# Deselect previous panel
	if _selected_slot >= 0:
		for p in _slot_panels:
			if is_instance_valid(p) and p.get_meta("slot_index") == _selected_slot:
				p.add_theme_stylebox_override("panel", _make_slot_stylebox(false))
				break

	_selected_slot = slot
	panel.add_theme_stylebox_override("panel", _make_slot_stylebox(true))

	# Update bottom bar button states
	var info := SaveManager.get_save_info(slot)
	var has_data := not info.is_empty()
	var is_autosave := (slot == AUTOSAVE_SLOT)
	_delete_btn.disabled = not has_data or is_autosave

	if current_mode == Mode.SAVE:
		_action_btn.disabled = is_autosave
	else:
		_action_btn.disabled = not has_data

	print("[SaveUI] Selected slot %d." % slot)


func _activate_slot(panel: PanelContainer) -> void:
	var slot: int = panel.get_meta("slot_index")
	var info := SaveManager.get_save_info(slot)
	var has_data := not info.is_empty()
	var is_autosave := (slot == AUTOSAVE_SLOT)

	if current_mode == Mode.SAVE:
		if is_autosave:
			return  # Cannot manually save to autosave
		if has_data:
			_show_confirm("Overwrite existing save in Slot %d?" % slot, &"save")
		else:
			_do_save(slot)
	else:  # LOAD
		if has_data:
			_show_confirm("Load this save? Unsaved progress will be lost.", &"load")


# ==========================================================================
# Save / Load / Delete Operations
# ==========================================================================

func _do_save(slot: int) -> void:
	print("[SaveUI] Saving to slot %d..." % slot)
	var success := SaveManager.save_game(slot)
	if success:
		save_completed.emit(slot)
		EventBus.hud_message.emit("Game saved to Slot %d." % slot, 3.0)
		_refresh_slots()
	else:
		EventBus.hud_message.emit("Save failed! Check disk space.", 3.0)


func _do_load(slot: int) -> void:
	print("[SaveUI] Loading from slot %d..." % slot)
	var success := SaveManager.load_game(slot)
	if success:
		load_completed.emit(slot)
		close()
	else:
		EventBus.hud_message.emit("Failed to load save. File may be corrupt.", 3.0)


func _do_delete(slot: int) -> void:
	print("[SaveUI] Deleting slot %d..." % slot)
	var success := SaveManager.delete_save(slot)
	if success:
		EventBus.hud_message.emit("Save deleted.", 2.0)
		_selected_slot = -1
		_delete_btn.disabled = true
		_action_btn.disabled = true
		_refresh_slots()
	else:
		EventBus.hud_message.emit("Failed to delete save.", 2.0)


# ==========================================================================
# Confirmation Dialog
# ==========================================================================

func _show_confirm(message: String, action: StringName) -> void:
	_confirm_action = action
	_confirm_label.text = message
	_confirm_overlay.visible = true
	_confirm_dialog.visible = true
	_confirm_no.grab_focus()


func _hide_confirm() -> void:
	_confirm_dialog.visible = false
	_confirm_overlay.visible = false
	_confirm_action = &""
	# Return focus to the selected slot panel
	for p in _slot_panels:
		if is_instance_valid(p) and p.get_meta("slot_index") == _selected_slot:
			p.grab_focus()
			break


func _on_confirm_yes() -> void:
	var action := _confirm_action
	var slot := _selected_slot
	_hide_confirm()

	match action:
		&"save":
			_do_save(slot)
		&"load":
			_do_load(slot)
		&"delete":
			_do_delete(slot)


func _on_confirm_no() -> void:
	_hide_confirm()


# ==========================================================================
# Input Handlers
# ==========================================================================

func _on_slot_gui_input(event: InputEvent, panel: PanelContainer) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select_slot(panel)
			if event.double_click:
				_activate_slot(panel)
	elif event.is_action_pressed("ui_accept"):
		if _selected_slot == panel.get_meta("slot_index"):
			_activate_slot(panel)
		else:
			_select_slot(panel)


func _on_slot_focus_entered(panel: PanelContainer) -> void:
	_select_slot(panel)


func _on_slot_mouse_entered(panel: PanelContainer) -> void:
	if not _confirm_dialog.visible:
		panel.grab_focus()


func _on_back() -> void:
	close()


func _on_delete_pressed() -> void:
	if _selected_slot < 1:  # Cannot delete autosave or if nothing selected
		return
	var info := SaveManager.get_save_info(_selected_slot)
	if info.is_empty():
		return
	_show_confirm(
		"Delete save in Slot %d? This cannot be undone." % _selected_slot, &"delete"
	)


func _on_action_pressed() -> void:
	if _selected_slot < 0:
		return
	for panel in _slot_panels:
		if is_instance_valid(panel) and panel.get_meta("slot_index") == _selected_slot:
			_activate_slot(panel)
			break


func _on_save_failed(reason: String) -> void:
	push_error("[SaveUI] Save failed: %s" % reason)
	EventBus.hud_message.emit("Save failed: %s" % reason, 4.0)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	if _confirm_dialog.visible:
		if event.is_action_pressed("ui_cancel"):
			_hide_confirm()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ==========================================================================
# Styling
# ==========================================================================

func _apply_styles() -> void:
	# Main panel
	var main_panel: PanelContainer = $Root/Content/MainPanel
	var main_style := StyleBoxFlat.new()
	main_style.bg_color = COLOR_BG_PANEL
	main_style.border_color = COLOR_ACCENT_CYAN * Color(1, 1, 1, 0.3)
	main_style.set_border_width_all(1)
	main_style.set_corner_radius_all(4)
	main_style.set_content_margin_all(16)
	main_panel.add_theme_stylebox_override("panel", main_style)

	# Title label
	_title_label.add_theme_color_override("font_color", COLOR_ACCENT_CYAN)
	_title_label.add_theme_font_size_override("font_size", 24)

	# Bottom bar buttons
	_style_button(_back_btn)
	_style_button(_action_btn)

	# Delete button gets pink accent
	_style_button_pink(_delete_btn)

	# Confirm dialog panel
	var confirm_style := StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.08, 0.05, 0.12, 0.98)
	confirm_style.border_color = COLOR_ACCENT_CYAN
	confirm_style.set_border_width_all(2)
	confirm_style.set_corner_radius_all(6)
	confirm_style.set_content_margin_all(24)
	_confirm_dialog.add_theme_stylebox_override("panel", confirm_style)

	# Confirm label
	_confirm_label.add_theme_color_override("font_color", COLOR_TEXT)
	_confirm_label.add_theme_font_size_override("font_size", 16)

	# Confirm buttons
	_style_button(_confirm_yes)
	_style_button_pink(_confirm_no)


func _style_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.1, 0.18, 0.9)
	normal.border_color = COLOR_ACCENT_CYAN * Color(1, 1, 1, 0.3)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.border_color = COLOR_ACCENT_CYAN
	hover.bg_color = Color(0.12, 0.12, 0.22, 0.95)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.0, 0.15, 0.2, 0.95)
	pressed.border_color = COLOR_ACCENT_CYAN
	btn.add_theme_stylebox_override("pressed", pressed)

	var focus := normal.duplicate()
	focus.border_color = COLOR_ACCENT_CYAN
	btn.add_theme_stylebox_override("focus", focus)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.05, 0.05, 0.08, 0.5)
	disabled.border_color = Color(0.2, 0.2, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT_CYAN)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT_CYAN)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)


func _style_button_pink(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.05, 0.08, 0.9)
	normal.border_color = COLOR_ACCENT_PINK * Color(1, 1, 1, 0.3)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.border_color = COLOR_ACCENT_PINK
	hover.bg_color = Color(0.2, 0.05, 0.1, 0.95)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.25, 0.08, 0.12, 0.95)
	pressed.border_color = COLOR_ACCENT_PINK
	btn.add_theme_stylebox_override("pressed", pressed)

	var focus := normal.duplicate()
	focus.border_color = COLOR_ACCENT_PINK
	btn.add_theme_stylebox_override("focus", focus)

	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.05, 0.05, 0.08, 0.5)
	disabled.border_color = Color(0.2, 0.2, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT_PINK)
	btn.add_theme_color_override("font_pressed_color", COLOR_ACCENT_PINK)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)


func _make_slot_stylebox(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = COLOR_BG_SLOT_SELECTED
		style.border_color = COLOR_BORDER_SELECTED
		style.set_border_width_all(2)
	else:
		style.bg_color = COLOR_BG_SLOT
		style.border_color = COLOR_BORDER_DIM
		style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


# ==========================================================================
# Formatting Utilities
# ==========================================================================

func _format_number(value: int) -> String:
	## Formats an integer with comma separators (e.g., 12,500).
	var text := str(value)
	if value >= 1000:
		var parts: Array[String] = []
		while text.length() > 3:
			parts.push_front(text.substr(text.length() - 3))
			text = text.substr(0, text.length() - 3)
		parts.push_front(text)
		return ",".join(parts)
	return text


func _format_play_time(seconds: float) -> String:
	## Converts seconds into a human-readable play time string.
	var total := int(seconds)
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	return "%dh %02dm" % [hours, minutes]


func _format_timestamp(timestamp: String) -> String:
	## Formats an ISO timestamp for display.
	if timestamp.is_empty() or timestamp == "Unknown":
		return "Unknown"
	# Expected format: "2025-01-15T10:30:00"
	var parts := timestamp.split("T")
	if parts.size() >= 2:
		return "%s  %s" % [parts[0], parts[1].substr(0, 5)]
	return timestamp
