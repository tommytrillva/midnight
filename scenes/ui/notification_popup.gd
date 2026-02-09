## Toast notification system. Displays small popups that slide in from the
## top-right corner with neon-bordered styling. Multiple notifications stack
## vertically and auto-dismiss after a configurable duration.
## Listens to EventBus.notification_popup for incoming notifications.
class_name NotificationPopup
extends CanvasLayer

# --- Configuration ---
const DEFAULT_DURATION: float = 3.0
const SLIDE_IN_TIME: float = 0.3
const SLIDE_OUT_TIME: float = 0.25
const NOTIFICATION_SPACING: float = 8.0
const MAX_VISIBLE: int = 5
const NOTIFICATION_WIDTH: float = 320.0
const NOTIFICATION_HEIGHT: float = 56.0
const MARGIN_RIGHT: float = 16.0
const MARGIN_TOP: float = 16.0

# --- Style Constants ---
const COLOR_PANEL_BG := Color(0.03, 0.02, 0.10, 0.92)
const COLOR_BORDER_CYAN := Color(0.0, 1.0, 1.0, 0.7)
const COLOR_BORDER_PINK := Color(1.0, 0.0, 0.6, 0.7)
const COLOR_TEXT_WHITE := Color(1.0, 1.0, 1.0)
const COLOR_TEXT_CYAN := Color(0.0, 1.0, 1.0)
const COLOR_ICON_CYAN := Color(0.0, 1.0, 1.0, 0.8)

# --- Internal ---
var _queue: Array[Dictionary] = []
var _active_notifications: Array[Control] = []
var _container: Control = null
var _is_processing_queue: bool = false


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "NotificationPopup"

	# Create a root control for positioning
	_container = Control.new()
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	# Listen for notification events
	if EventBus.has_signal("notification_popup"):
		EventBus.notification_popup.connect(_on_notification_requested)

	# Also listen for common game events to auto-generate notifications
	EventBus.district_unlocked.connect(_on_district_unlocked)
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.rep_tier_changed.connect(_on_rep_tier_changed)
	EventBus.relationship_level_up.connect(_on_relationship_level_up)
	EventBus.vehicle_acquired.connect(_on_vehicle_acquired)
	EventBus.skill_unlocked.connect(_on_skill_unlocked)

	print("[NotificationPopup] Initialized.")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Queue a notification with title text, optional body text, and icon hint.
func notify(title: String, body: String = "", icon: String = "info", duration: float = DEFAULT_DURATION) -> void:
	_queue.append({
		"title": title,
		"body": body,
		"icon": icon,
		"duration": duration,
	})
	_process_queue()


# ---------------------------------------------------------------------------
# Queue Processing
# ---------------------------------------------------------------------------

func _process_queue() -> void:
	if _is_processing_queue:
		return
	_is_processing_queue = true

	while _queue.size() > 0 and _active_notifications.size() < MAX_VISIBLE:
		var data: Dictionary = _queue.pop_front()
		_spawn_notification(data)
		# Brief delay between spawning multiple
		await get_tree().create_timer(0.1).timeout

	_is_processing_queue = false


func _spawn_notification(data: Dictionary) -> void:
	var panel := _create_notification_panel(data)
	_container.add_child(panel)
	_active_notifications.append(panel)

	# Position: start offscreen to the right
	var target_y := MARGIN_TOP + (_active_notifications.size() - 1) * (NOTIFICATION_HEIGHT + NOTIFICATION_SPACING)
	var viewport_width := _container.get_viewport_rect().size.x
	var target_x := viewport_width - NOTIFICATION_WIDTH - MARGIN_RIGHT
	var start_x := viewport_width + 20.0

	panel.position = Vector2(start_x, target_y)
	panel.modulate.a = 0.0

	# Slide in
	var tween := _container.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "position:x", target_x, SLIDE_IN_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 1.0, SLIDE_IN_TIME * 0.7)

	# Auto-dismiss after duration
	var duration: float = data.get("duration", DEFAULT_DURATION)
	await get_tree().create_timer(duration).timeout
	_dismiss_notification(panel)


func _dismiss_notification(panel: Control) -> void:
	if not is_instance_valid(panel):
		return

	var viewport_width := _container.get_viewport_rect().size.x

	# Slide out
	var tween := _container.create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "position:x", viewport_width + 20.0, SLIDE_OUT_TIME).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel, "modulate:a", 0.0, SLIDE_OUT_TIME)
	await tween.finished

	# Remove from active list
	_active_notifications.erase(panel)
	panel.queue_free()

	# Reposition remaining notifications
	_reflow_notifications()

	# Process any queued notifications
	_process_queue()


func _reflow_notifications() -> void:
	## Smoothly reposition active notifications after one is removed.
	for i in range(_active_notifications.size()):
		var panel: Control = _active_notifications[i]
		if not is_instance_valid(panel):
			continue
		var target_y := MARGIN_TOP + i * (NOTIFICATION_HEIGHT + NOTIFICATION_SPACING)
		var tween := _container.create_tween()
		tween.tween_property(panel, "position:y", target_y, 0.2).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Notification Panel Construction
# ---------------------------------------------------------------------------

func _create_notification_panel(data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT)
	panel.size = Vector2(NOTIFICATION_WIDTH, NOTIFICATION_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	# Use cyan or pink border based on icon type
	var icon_type: String = data.get("icon", "info")
	var border_color := COLOR_BORDER_CYAN
	if icon_type in ["warning", "reputation", "relationship"]:
		border_color = COLOR_BORDER_PINK
	style.border_color = border_color

	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	# HBox: icon + text
	var hbox := HBoxContainer.new()
	hbox.theme_override_constants = {}
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Icon (colored square)
	var icon_rect := ColorRect.new()
	icon_rect.custom_minimum_size = Vector2(6, 6)
	icon_rect.size = Vector2(6, 6)
	icon_rect.color = border_color
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon_rect)

	# Text container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	# Title
	var title_label := Label.new()
	title_label.text = data.get("title", "")
	title_label.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_label)

	# Body (if provided)
	var body_text: String = data.get("body", "")
	if not body_text.is_empty():
		var body_label := Label.new()
		body_label.text = body_text
		body_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		body_label.add_theme_font_size_override("font_size", 12)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(body_label)

	return panel


# ---------------------------------------------------------------------------
# EventBus Signal Handlers (auto-generate notifications)
# ---------------------------------------------------------------------------

func _on_notification_requested(title: String, body: String, icon: String) -> void:
	notify(title, body, icon)


func _on_district_unlocked(district_id: String) -> void:
	var name := district_id.capitalize().replace("_", " ")
	notify("District Unlocked: %s" % name, "A new area awaits.", "district")


func _on_mission_started(mission_id: String) -> void:
	var mission := GameManager.story.get_mission(mission_id)
	var mission_name: String = mission.get("name", mission_id)
	notify("New Mission: %s" % mission_name, "", "mission")


func _on_rep_tier_changed(_old_tier: int, new_tier: int) -> void:
	var tier_names := ["UNKNOWN", "NEWCOMER", "RUNNER", "CONTENDER", "ELITE", "LEGEND"]
	var tier_name: String = tier_names[new_tier] if new_tier < tier_names.size() else "TIER %d" % new_tier
	notify("REP increased!", "Now: %s" % tier_name, "reputation")


func _on_relationship_level_up(character_id: String, new_level: int) -> void:
	var level_names := ["Stranger", "Acquaintance", "Friend", "Close Friend", "Trusted", "Bonded"]
	var level_name: String = level_names[new_level] if new_level < level_names.size() else "Level %d" % new_level
	var char_name := character_id.capitalize()
	notify("Relationship: %s" % char_name, "Now: %s" % level_name, "relationship")


func _on_vehicle_acquired(vehicle_id: String, source: String) -> void:
	notify("Vehicle Acquired!", vehicle_id.replace("_", " ").capitalize(), "vehicle")


func _on_skill_unlocked(tree: String, skill_id: String) -> void:
	var skill_name := skill_id.replace("_", " ").capitalize()
	notify("Skill Unlocked: %s" % skill_name, "Tree: %s" % tree.capitalize(), "skill")
