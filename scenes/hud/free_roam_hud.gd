## Free-roam HUD showing time, weather, cash, REP, heat level,
## current district, minimap, waypoint indicators, and in-car radio.
## Visible during exploration.
extends CanvasLayer

signal skills_button_pressed

const MinimapScene := preload("res://scenes/ui/minimap.tscn")
const RadioHUDScene := preload("res://scenes/ui/radio_hud.tscn")
const PhoneUIScene := preload("res://scenes/ui/phone_ui.tscn")

@onready var time_label: Label = $HUD/TopBar/Time
@onready var weather_label: Label = $HUD/TopBar/Weather
@onready var cash_label: Label = $HUD/TopBar/Cash
@onready var rep_label: Label = $HUD/TopBar/REP
@onready var rep_bar: ProgressBar = $HUD/TopBar/REPBar
@onready var heat_indicator: Label = $HUD/BottomBar/Heat
@onready var district_label: Label = $HUD/BottomBar/District
@onready var speed_label: Label = $HUD/BottomBar/Speed
@onready var skills_button: Button = $HUD/TopBar/SkillsBtn
@onready var notification: Label = $HUD/Notification
@onready var waypoint_overlay: Control = $HUD/WaypointOverlay

var _notif_timer: float = 0.0

## Minimap reference (instantiated at runtime)
var minimap: Minimap = null
var _minimap_container: Control = null

## Waypoint system for navigation indicators
var waypoint_system: WaypointSystem = null

## World map overlay (full-screen)
var world_map: WorldMapUI = null

## Radio HUD display
var radio_hud: RadioHUD = null

## Phone UI overlay
var phone_ui: PhoneUI = null

## Phone notification badge on the HUD
var _phone_badge: Label = null

const HEAT_COLORS := {
	0: Color(0.3, 0.8, 0.3), # Green - clean
	1: Color(0.9, 0.9, 0.2), # Yellow - noticed
	2: Color(1.0, 0.5, 0.0), # Orange - wanted
	3: Color(1.0, 0.2, 0.2), # Red - pursuit
	4: Color(1.0, 0.0, 0.0), # Bright red - manhunt
}


func _ready() -> void:
	EventBus.cash_changed.connect(_on_cash_changed)
	EventBus.rep_changed.connect(_on_rep_changed)
	EventBus.rep_tier_changed.connect(_on_rep_tier_changed)
	EventBus.heat_level_changed.connect(_on_heat_changed)
	EventBus.time_period_changed.connect(_on_time_changed)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.district_entered.connect(_on_district_entered)
	EventBus.hud_message.connect(show_notification)
	EventBus.notification_popup.connect(_on_notification)

	# Skills button
	if skills_button:
		skills_button.pressed.connect(_on_skills_pressed)

	notification.visible = false

	# Initialize minimap
	_setup_minimap()

	# Initialize waypoint system
	_setup_waypoint_system()

	# Initialize world map
	_setup_world_map()

	# Initialize radio HUD
	_setup_radio_hud()

	# Initialize phone UI
	_setup_phone()

	_refresh_all()


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return

	# Update time display
	time_label.text = GameManager.world_time.get_display_time()

	# Notification timer
	if _notif_timer > 0:
		_notif_timer -= delta
		if _notif_timer <= 0:
			notification.visible = false

	# Update waypoint overlay indicators
	if waypoint_system and waypoint_overlay and waypoint_overlay.visible:
		waypoint_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return

	# Toggle world map with M key or toggle_map action
	if event.is_action_pressed("toggle_map") or \
		(event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M):
		_toggle_world_map()
		get_viewport().set_input_as_handled()
		return

	# Toggle phone with P key or phone action
	if event.is_action_pressed("phone") or \
		(event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P):
		_toggle_phone()
		get_viewport().set_input_as_handled()
		return

	# Radio station switching: [ and ] keys or radio actions
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETLEFT:
				if radio_hud and radio_hud._radio:
					radio_hud._radio.prev_station()
					get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				if radio_hud and radio_hud._radio:
					radio_hud._radio.next_station()
					get_viewport().set_input_as_handled()
			KEY_BACKSLASH:
				if radio_hud and radio_hud._radio:
					radio_hud._radio.toggle_radio()
					get_viewport().set_input_as_handled()

	# Forward radio input actions to RadioHUD
	if radio_hud:
		radio_hud.handle_input(event)


func _refresh_all() -> void:
	cash_label.text = "$%s" % _format_number(GameManager.economy.cash)
	rep_label.text = "%s — %s" % [
		GameManager.reputation.get_tier_name(),
		_format_number(GameManager.reputation.current_rep)
	]
	rep_bar.value = GameManager.reputation.get_tier_progress() * 100.0
	_update_heat(GameManager.police.heat_level)
	district_label.text = GameManager.player_data.current_district.capitalize()
	weather_label.text = GameManager.world_time.current_weather.replace("_", " ").capitalize()


func show_notification(text: String, duration: float = 3.0) -> void:
	notification.text = text
	notification.visible = true
	_notif_timer = duration


func _on_cash_changed(_old: int, new_val: int) -> void:
	cash_label.text = "$%s" % _format_number(new_val)


func _on_rep_changed(_old: int, new_val: int) -> void:
	rep_label.text = "%s — %s" % [
		GameManager.reputation.get_tier_name(),
		_format_number(new_val)
	]
	rep_bar.value = GameManager.reputation.get_tier_progress() * 100.0


func _on_rep_tier_changed(_old: int, _new: int) -> void:
	show_notification("REP TIER UP: %s" % GameManager.reputation.get_tier_name(), 5.0)


func _on_heat_changed(_old: int, new_level: int) -> void:
	_update_heat(new_level)


func _update_heat(level: int) -> void:
	heat_indicator.text = GameManager.police.get_heat_name().to_upper()
	heat_indicator.modulate = HEAT_COLORS.get(level, Color.WHITE)
	heat_indicator.visible = level > 0


func _on_time_changed(period: String) -> void:
	show_notification(period.replace("_", " ").capitalize(), 2.0)


func _on_weather_changed(condition: String) -> void:
	weather_label.text = condition.replace("_", " ").capitalize()


func _on_district_entered(district_id: String) -> void:
	district_label.text = district_id.capitalize()
	show_notification("Entering: %s" % district_id.replace("_", " ").capitalize(), 2.0)


func _on_notification(title: String, body: String, _icon: String) -> void:
	show_notification("%s: %s" % [title, body], 4.0)


func _on_skills_pressed() -> void:
	skills_button_pressed.emit()


func _format_number(num: int) -> String:
	var s := str(num)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i > 0:
			result = "," + result
	return result


# ---------------------------------------------------------------------------
# Minimap
# ---------------------------------------------------------------------------

func _setup_minimap() -> void:
	## Instantiates the minimap scene and adds it to the HUD.
	_minimap_container = MinimapScene.instantiate() as Control
	if _minimap_container == null:
		print("[Minimap] WARNING: Could not instantiate minimap scene.")
		return

	var hud := $HUD as Control
	if hud:
		hud.add_child(_minimap_container)

	minimap = _minimap_container.get_node_or_null("Minimap") as Minimap
	print("[Minimap] Minimap added to HUD.")


# ---------------------------------------------------------------------------
# Waypoint System
# ---------------------------------------------------------------------------

func _setup_waypoint_system() -> void:
	## Creates the WaypointSystem node and adds it as a child.
	waypoint_system = WaypointSystem.new()
	waypoint_system.name = "WaypointSystem"
	add_child(waypoint_system)

	# Connect the overlay's draw signal for rendering waypoint indicators
	if waypoint_overlay:
		waypoint_overlay.draw.connect(_on_waypoint_overlay_draw)
		waypoint_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[Waypoint] WaypointSystem added to HUD.")


func _on_waypoint_overlay_draw() -> void:
	## Draws waypoint indicators on the overlay control.
	if waypoint_system == null or waypoint_system.get_waypoint_count() == 0:
		return

	# Get player position
	var player_pos := Vector3.ZERO
	var free_roam := _find_free_roam()
	if free_roam and free_roam.player_vehicle and is_instance_valid(free_roam.player_vehicle):
		player_pos = free_roam.player_vehicle.global_transform.origin

	var indicators := waypoint_system.get_indicators(player_pos)
	var font := ThemeDB.fallback_font

	for indicator in indicators:
		var color: Color = indicator.color
		var is_primary: bool = indicator.is_primary
		var distance: float = indicator.distance
		var label: String = indicator.label

		if indicator.is_on_screen:
			# Draw marker above the waypoint position on-screen
			var pos: Vector2 = indicator.screen_pos
			var marker_size := 8.0 if is_primary else 5.0

			# Diamond marker
			var diamond := PackedVector2Array([
				pos + Vector2(0, -marker_size),
				pos + Vector2(marker_size, 0),
				pos + Vector2(0, marker_size),
				pos + Vector2(-marker_size, 0),
			])
			waypoint_overlay.draw_colored_polygon(diamond, color)

			# Distance text
			if font:
				var dist_text := "%dm" % int(distance)
				waypoint_overlay.draw_string(font, pos + Vector2(-15, marker_size + 14),
					dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, color)

			# Label text
			if font and not label.is_empty() and is_primary:
				waypoint_overlay.draw_string(font, pos + Vector2(-40, -marker_size - 6),
					label, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, color)
		else:
			# Draw edge arrow pointing toward off-screen waypoint
			var edge_pos: Vector2 = indicator.edge_pos
			var angle: float = indicator.angle
			var arrow_size := 12.0 if is_primary else 8.0

			# Chevron/arrow pointing in the direction
			var dir := Vector2(cos(angle), sin(angle))
			var perp := Vector2(-dir.y, dir.x)
			var tip := edge_pos
			var left_pt := tip - dir * arrow_size + perp * arrow_size * 0.5
			var right_pt := tip - dir * arrow_size - perp * arrow_size * 0.5

			var arrow := PackedVector2Array([tip, left_pt, right_pt])
			waypoint_overlay.draw_colored_polygon(arrow, color)

			# Distance text near the arrow
			if font:
				var dist_text := "%dm" % int(distance)
				var text_offset := -dir * (arrow_size + 14)
				waypoint_overlay.draw_string(font, edge_pos + text_offset + Vector2(-12, 4),
					dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, color)


# ---------------------------------------------------------------------------
# World Map
# ---------------------------------------------------------------------------

func _setup_world_map() -> void:
	## Creates the WorldMapUI overlay.
	world_map = WorldMapUI.new()
	world_map.name = "WorldMapUI"
	# Add to the parent (FreeRoam) so it can find the scene tree
	# We defer this to ensure the scene tree is ready
	call_deferred("_add_world_map_deferred")


func _add_world_map_deferred() -> void:
	var parent := get_parent()
	if parent:
		parent.add_child(world_map)
	else:
		add_child(world_map)
	print("[Map] WorldMapUI added.")


func _toggle_world_map() -> void:
	if world_map == null:
		return
	if world_map.is_open():
		world_map.close_map()
	else:
		world_map.open_map()


func _find_free_roam() -> Node:
	## Walk up the tree to find FreeRoam.
	var node := get_parent()
	while node:
		if "player_vehicle" in node:
			return node
		node = node.get_parent()
	return null


# ---------------------------------------------------------------------------
# Phone System
# ---------------------------------------------------------------------------

func _setup_phone() -> void:
	## Instantiates the PhoneUI scene and adds the HUD notification badge.
	# Create phone badge on the top bar
	_phone_badge = Label.new()
	_phone_badge.name = "PhoneBadge"
	_phone_badge.text = ""
	_phone_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_badge.add_theme_font_size_override("font_size", 12)
	_phone_badge.add_theme_color_override("font_color", Color(0.0, 0.85, 0.85))
	_phone_badge.custom_minimum_size = Vector2(40, 0)
	_phone_badge.visible = false

	var top_bar := $HUD/TopBar as Control
	if top_bar:
		top_bar.add_child(_phone_badge)

	# Instantiate PhoneUI as a sibling CanvasLayer
	var phone_instance := PhoneUIScene.instantiate()
	if phone_instance:
		call_deferred("_add_phone_deferred", phone_instance)

	# Connect phone signals for badge updates
	EventBus.message_received.connect(_on_phone_message_received)
	EventBus.message_read.connect(_on_phone_message_read)
	EventBus.phone_opened.connect(_on_phone_opened)
	EventBus.phone_closed.connect(_on_phone_closed)

	_update_phone_badge()
	print("[Phone] Phone badge and UI added to HUD.")


func _add_phone_deferred(phone_instance: Node) -> void:
	var parent := get_parent()
	if parent:
		parent.add_child(phone_instance)
	else:
		add_child(phone_instance)
	phone_ui = phone_instance as PhoneUI


func _toggle_phone() -> void:
	if phone_ui == null:
		return
	if phone_ui._is_open:
		phone_ui.close_phone()
	else:
		phone_ui.open_phone()


func _update_phone_badge() -> void:
	if _phone_badge == null:
		return
	var phone: PhoneSystem = GameManager.phone
	if not phone:
		_phone_badge.visible = false
		return
	var count: int = phone.get_unread_count()
	if count > 0:
		_phone_badge.text = "[%d]" % count
		_phone_badge.visible = true
	else:
		_phone_badge.text = ""
		_phone_badge.visible = false


func _on_phone_message_received(_sender: String, _message_id: String) -> void:
	_update_phone_badge()
	# Brief HUD notification
	show_notification("New message", 2.0)


func _on_phone_message_read(_message_id: String) -> void:
	_update_phone_badge()


func _on_phone_opened() -> void:
	_update_phone_badge()


func _on_phone_closed() -> void:
	_update_phone_badge()


# ---------------------------------------------------------------------------
# Radio HUD
# ---------------------------------------------------------------------------

func _setup_radio_hud() -> void:
	## Instantiates the RadioHUD scene and links it to the RadioSystem.
	var radio_hud_instance: Control = RadioHUDScene.instantiate()
	if radio_hud_instance == null:
		print("[Radio] WARNING: Could not instantiate RadioHUD scene.")
		return

	var hud := $HUD as Control
	if hud:
		hud.add_child(radio_hud_instance)

	radio_hud = radio_hud_instance as RadioHUD
	if radio_hud == null:
		print("[Radio] WARNING: RadioHUD scene root is not a RadioHUD.")
		return

	# Find the RadioSystem — it should be a child of GameManager
	var radio_system: RadioSystem = _find_radio_system()
	if radio_system:
		radio_hud.set_radio_system(radio_system)
	else:
		print("[Radio] WARNING: RadioSystem not found. Radio HUD will have limited functionality.")

	print("[Radio] RadioHUD added to free-roam HUD.")


func _find_radio_system() -> RadioSystem:
	## Locate the RadioSystem node in the scene tree.
	## It should be a child of GameManager or AudioManager.
	if GameManager.has_node("RadioSystem"):
		return GameManager.get_node("RadioSystem") as RadioSystem

	# Search children of GameManager
	for child: Node in GameManager.get_children():
		if child is RadioSystem:
			return child as RadioSystem

	# Try AudioManager
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr:
		for child: Node in audio_mgr.get_children():
			if child is RadioSystem:
				return child as RadioSystem

	# Fallback: search the tree
	return _find_node_by_class(get_tree().root, "RadioSystem") as RadioSystem


func _find_node_by_class(node: Node, class_string: String) -> Node:
	## Recursively search for a node by class_name (limited depth).
	if node.get_class() == class_string or (node is RadioSystem):
		return node
	for child: Node in node.get_children():
		var found := _find_node_by_class(child, class_string)
		if found:
			return found
	return null
