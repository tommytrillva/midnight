## Full-screen world map overlay. Pauses the game when open.
## Shows all 4 districts, discovered POIs, mission markers, and fast travel.
## Styled with dark background, neon road lines, and glowing markers.
class_name WorldMapUI
extends CanvasLayer


## Map data files
const MAP_DATA_PATHS := {
	"downtown": "res://data/maps/downtown_map.json",
	"harbor": "res://data/maps/harbor_map.json",
	"industrial": "res://data/maps/industrial_map.json",
	"hillside": "res://data/maps/hillside_map.json",
}

## District display positions on the world map (offset from combined center).
## Each district is placed relative to a world-map grid.
const DISTRICT_OFFSETS := {
	"downtown": Vector2(0, 0),
	"harbor": Vector2(600, 100),
	"industrial": Vector2(-600, -100),
	"hillside": Vector2(0, -600),
}

## Fast travel time cost per district hop (in game minutes).
const FAST_TRAVEL_TIME_COST := 30

## Visual config
const BG_COLOR := Color(0.02, 0.02, 0.04, 0.95)
const ROAD_COLOR_DEFAULT := Color(0.0, 0.7, 0.7, 0.6)
const DISTRICT_BORDER_COLOR := Color(0.3, 0.3, 0.4, 0.4)
const LOCKED_OVERLAY := Color(0.1, 0.1, 0.1, 0.6)
const PLAYER_COLOR := Color(0.0, 1.0, 0.8, 1.0)
const TITLE_COLOR := Color(0.8, 0.8, 0.9, 1.0)
const LEGEND_COLOR := Color(0.6, 0.6, 0.7, 0.8)

## Zoom and pan
const ZOOM_MIN := 0.3
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1
const PAN_SPEED := 400.0

## State
var _is_open: bool = false
var _map_data: Dictionary = {}  # district_id -> MinimapData
var _zoom: float = 0.6
var _pan_offset: Vector2 = Vector2.ZERO
var _player_position: Vector2 = Vector2.ZERO
var _player_district: String = "downtown"
var _selected_poi: Dictionary = {}
var _hovered_poi: Dictionary = {}
var _fast_travel_target: String = ""
var _discovered_pois: Dictionary = {}  # "district_id:label" -> true

## Nodes
var _draw_control: Control = null
var _legend_panel: Control = null
var _info_panel: Control = null
var _info_label: Label = null
var _fast_travel_button: Button = null
var _close_button: Button = null


func _ready() -> void:
	layer = 10
	visible = false

	# Load map data
	for district_id in MAP_DATA_PATHS:
		_map_data[district_id] = MinimapData.load_from_json(MAP_DATA_PATHS[district_id])

	_build_ui()

	EventBus.district_entered.connect(_on_district_entered)
	print("[Map] WorldMapUI initialized.")


func _build_ui() -> void:
	## Builds the UI tree programmatically.

	# Full-screen background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Drawing surface for the map
	_draw_control = Control.new()
	_draw_control.name = "MapDraw"
	_draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_control.mouse_filter = Control.MOUSE_FILTER_PASS
	_draw_control.draw.connect(_on_draw)
	bg.add_child(_draw_control)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "NOVA PACIFICA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 20
	title.offset_left = -150
	title.offset_right = 150
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	bg.add_child(title)

	# Close button
	_close_button = Button.new()
	_close_button.name = "CloseBtn"
	_close_button.text = "CLOSE [M]"
	_close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close_button.offset_left = -120
	_close_button.offset_top = 15
	_close_button.offset_right = -15
	_close_button.offset_bottom = 45
	_close_button.pressed.connect(close_map)
	bg.add_child(_close_button)

	# Info panel (bottom-center)
	_info_panel = PanelContainer.new()
	_info_panel.name = "InfoPanel"
	_info_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_info_panel.offset_left = -200
	_info_panel.offset_right = 200
	_info_panel.offset_top = -100
	_info_panel.offset_bottom = -15
	_info_panel.visible = false
	bg.add_child(_info_panel)

	var info_vbox := VBoxContainer.new()
	_info_panel.add_child(info_vbox)

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_vbox.add_child(_info_label)

	_fast_travel_button = Button.new()
	_fast_travel_button.name = "FastTravelBtn"
	_fast_travel_button.text = "FAST TRAVEL"
	_fast_travel_button.visible = false
	_fast_travel_button.pressed.connect(_on_fast_travel_pressed)
	info_vbox.add_child(_fast_travel_button)

	# Legend (bottom-left)
	_legend_panel = PanelContainer.new()
	_legend_panel.name = "Legend"
	_legend_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend_panel.offset_left = 15
	_legend_panel.offset_right = 200
	_legend_panel.offset_top = -200
	_legend_panel.offset_bottom = -15
	bg.add_child(_legend_panel)

	var legend_vbox := VBoxContainer.new()
	_legend_panel.add_child(legend_vbox)

	var legend_title := Label.new()
	legend_title.text = "LEGEND"
	legend_title.add_theme_font_size_override("font_size", 14)
	legend_title.add_theme_color_override("font_color", TITLE_COLOR)
	legend_vbox.add_child(legend_title)

	var legend_entries := [
		["Garage", Color(1.0, 0.6, 0.0)],
		["Race Start", Color(0.2, 1.0, 0.3)],
		["Mission", Color(1.0, 1.0, 0.0)],
		["District Exit", Color(1.0, 1.0, 1.0)],
		["Contact", Color(0.7, 0.4, 1.0)],
		["Shop / Service", Color(0.0, 1.0, 1.0)],
		["Player", Color(0.0, 1.0, 0.8)],
	]
	for entry in legend_entries:
		var hbox := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = entry[1]
		hbox.add_child(swatch)
		var lbl := Label.new()
		lbl.text = "  " + entry[0]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", LEGEND_COLOR)
		hbox.add_child(lbl)
		legend_vbox.add_child(hbox)

	# Zoom controls hint (bottom-right)
	var zoom_hint := Label.new()
	zoom_hint.name = "ZoomHint"
	zoom_hint.text = "Scroll: Zoom | Drag: Pan | Click: Select"
	zoom_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	zoom_hint.offset_left = -280
	zoom_hint.offset_right = -15
	zoom_hint.offset_top = -30
	zoom_hint.offset_bottom = -10
	zoom_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_hint.add_theme_font_size_override("font_size", 10)
	zoom_hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 0.6))
	bg.add_child(zoom_hint)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	# Close with M or Escape
	if event.is_action_pressed("toggle_map") or event.is_action_pressed("ui_cancel") or \
		(event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M):
		close_map()
		get_viewport().set_input_as_handled()
		return

	# Zoom with scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_draw_control.queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_draw_control.queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
			get_viewport().set_input_as_handled()

	# Pan with mouse drag
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_pan_offset += event.relative
		_draw_control.queue_redraw()
		get_viewport().set_input_as_handled()

	# Gamepad/keyboard pan
	if event is InputEventKey and event.pressed:
		var pan_dir := Vector2.ZERO
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			pan_dir.x += PAN_SPEED * 0.05
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			pan_dir.x -= PAN_SPEED * 0.05
		elif event.keycode == KEY_UP or event.keycode == KEY_W:
			pan_dir.y += PAN_SPEED * 0.05
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			pan_dir.y -= PAN_SPEED * 0.05
		if pan_dir != Vector2.ZERO:
			_pan_offset += pan_dir
			_draw_control.queue_redraw()


func _handle_click(screen_pos: Vector2) -> void:
	## Checks if the click is near a POI and selects it.
	var map_pos := _screen_to_map(screen_pos)
	var best_dist := 20.0 / _zoom  # Click tolerance in map units
	_selected_poi = {}
	_fast_travel_target = ""

	for district_id in _map_data:
		var data: MinimapData = _map_data[district_id]
		var offset: Vector2 = DISTRICT_OFFSETS.get(district_id, Vector2.ZERO)
		for poi in data.poi_markers:
			var poi_world: Vector2 = poi.position + offset
			var dist := map_pos.distance_to(poi_world)
			if dist < best_dist:
				best_dist = dist
				_selected_poi = poi.duplicate()
				_selected_poi["district_id"] = district_id

	if not _selected_poi.is_empty():
		_show_poi_info(_selected_poi)
	else:
		# Check if clicking on a district area for fast travel
		for district_id in _map_data:
			var data: MinimapData = _map_data[district_id]
			var offset: Vector2 = DISTRICT_OFFSETS.get(district_id, Vector2.ZERO)
			var bounds: Rect2 = data.bounds
			bounds.position += offset
			if bounds.has_point(map_pos):
				_show_district_info(district_id)
				break
		if _selected_poi.is_empty() and _fast_travel_target.is_empty():
			_info_panel.visible = false

	_draw_control.queue_redraw()


func _show_poi_info(poi: Dictionary) -> void:
	_info_label.text = "%s\n%s" % [poi.get("label", "Unknown"), poi.get("type", "").capitalize()]
	_info_panel.visible = true

	# Show fast travel if this POI is in a different district and is a known transition
	var poi_district: String = poi.get("district_id", "")
	if poi.get("type", "") == "transition" and poi_district != _player_district:
		# Determine target from label (hacky but works for data-driven approach)
		_fast_travel_target = poi_district
		_fast_travel_button.visible = true
		_fast_travel_button.text = "FAST TRAVEL (-%d min)" % FAST_TRAVEL_TIME_COST
	else:
		_fast_travel_button.visible = false


func _show_district_info(district_id: String) -> void:
	var data: MinimapData = _map_data.get(district_id)
	if data == null:
		return
	var unlocked := _is_district_unlocked(district_id)
	var status := "UNLOCKED" if unlocked else "LOCKED"
	_info_label.text = "%s\n%s" % [data.district_name, status]
	_info_panel.visible = true

	if unlocked and district_id != _player_district:
		_fast_travel_target = district_id
		_fast_travel_button.visible = true
		_fast_travel_button.text = "FAST TRAVEL (-%d min)" % FAST_TRAVEL_TIME_COST
	else:
		_fast_travel_button.visible = false
		_fast_travel_target = ""


func _is_district_unlocked(district_id: String) -> bool:
	# Check via the FreeRoam's DistrictManager if available
	var free_roam := _find_free_roam()
	if free_roam and free_roam.district_manager:
		return free_roam.district_manager.is_district_unlocked(district_id)
	# Fallback: downtown always unlocked
	return district_id == "downtown"


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _on_draw() -> void:
	if not _is_open:
		return

	var viewport_center := _draw_control.size * 0.5
	var origin := viewport_center + _pan_offset

	# Draw each district
	for district_id in _map_data:
		var data: MinimapData = _map_data[district_id]
		var offset: Vector2 = DISTRICT_OFFSETS.get(district_id, Vector2.ZERO)
		var unlocked := _is_district_unlocked(district_id)

		# District bounds (subtle border)
		var bounds := data.bounds
		var tl := _map_to_screen_raw(bounds.position + offset, origin)
		var br := _map_to_screen_raw(bounds.end + offset, origin)
		var rect := Rect2(tl, br - tl)

		# Background fill per district
		var bg_col := data.background_color
		if not unlocked:
			bg_col = LOCKED_OVERLAY
		_draw_control.draw_rect(rect, bg_col)

		# District border
		_draw_control.draw_rect(rect, DISTRICT_BORDER_COLOR, false, 1.0)

		# District name
		var name_pos := _map_to_screen_raw(offset + Vector2(0, bounds.position.y - 15), origin)
		var font := ThemeDB.fallback_font
		if font:
			var col := TITLE_COLOR if unlocked else Color(0.4, 0.4, 0.4, 0.5)
			_draw_control.draw_string(font, name_pos, data.district_name,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, col)

		if not unlocked:
			# Draw lock indicator
			var lock_pos := _map_to_screen_raw(offset, origin)
			if font:
				_draw_control.draw_string(font, lock_pos + Vector2(-20, 5), "LOCKED",
					HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.8, 0.2, 0.2, 0.7))
			continue

		# Draw roads
		var road_col := data.road_color if data.road_color.a > 0 else ROAD_COLOR_DEFAULT
		for road in data.road_segments:
			var start_px := _map_to_screen_raw(road.start + offset, origin)
			var end_px := _map_to_screen_raw(road.end + offset, origin)
			var w := maxf(road.width * _zoom * 0.5, 0.5)
			_draw_control.draw_line(start_px, end_px, road_col, w, true)

		# Draw POIs
		for poi in data.poi_markers:
			var px := _map_to_screen_raw(poi.position + offset, origin)
			var col: Color = poi.get("color", Color.WHITE)

			# Glow effect for selected POI
			var is_selected: bool = (not _selected_poi.is_empty() and
				_selected_poi.get("label", "") == poi.get("label", "") and
				_selected_poi.get("district_id", "") == district_id)

			if is_selected:
				_draw_control.draw_circle(px, 10.0 * _zoom, Color(col, 0.3))

			_draw_poi_icon(px, poi.get("type", ""), col)

			# Label
			if _zoom >= 0.5 and font:
				_draw_control.draw_string(font, px + Vector2(8 * _zoom, 4),
					poi.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(10 * _zoom), Color(col, 0.8))

	# Draw player position
	_draw_player_marker(origin)


func _draw_poi_icon(pos: Vector2, poi_type: String, color: Color) -> void:
	var s := 5.0 * _zoom
	match poi_type:
		"garage":
			_draw_control.draw_circle(pos, s * 0.7, color)
		"race":
			var flag := PackedVector2Array([
				pos + Vector2(0, -s),
				pos + Vector2(s, -s * 0.5),
				pos + Vector2(0, 0),
			])
			_draw_control.draw_colored_polygon(flag, color)
			_draw_control.draw_line(pos + Vector2(0, s), pos + Vector2(0, -s), color, 1.5)
		"mission":
			var points := PackedVector2Array()
			for i in range(8):
				var angle := i * TAU / 8.0 - PI / 2.0
				var r := s if i % 2 == 0 else s * 0.4
				points.append(pos + Vector2(cos(angle), sin(angle)) * r)
			_draw_control.draw_colored_polygon(points, color)
		"transition":
			var arrow := PackedVector2Array([
				pos + Vector2(0, -s),
				pos + Vector2(s * 0.6, s * 0.3),
				pos + Vector2(-s * 0.6, s * 0.3),
			])
			_draw_control.draw_colored_polygon(arrow, color)
		"contact":
			_draw_control.draw_circle(pos + Vector2(0, -s * 0.5), s * 0.35, color)
			var body := PackedVector2Array([
				pos + Vector2(-s * 0.4, s * 0.6),
				pos + Vector2(s * 0.4, s * 0.6),
				pos + Vector2(0, -s * 0.1),
			])
			_draw_control.draw_colored_polygon(body, color)
		"shop":
			_draw_control.draw_circle(pos, s * 0.5, Color(color, 0.4))
			_draw_control.draw_arc(pos, s * 0.5, 0, TAU, 12, color, 1.5)
		_:
			_draw_control.draw_circle(pos, 3.0 * _zoom, color)


func _draw_player_marker(origin: Vector2) -> void:
	var district_offset: Vector2 = DISTRICT_OFFSETS.get(_player_district, Vector2.ZERO)
	var player_map_pos := _player_position + district_offset
	var px := _map_to_screen_raw(player_map_pos, origin)

	# Pulsing glow
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	_draw_control.draw_circle(px, 12.0 * _zoom * (0.8 + 0.2 * pulse), Color(PLAYER_COLOR, 0.2))
	_draw_control.draw_circle(px, 6.0 * _zoom, PLAYER_COLOR)

	# "YOU" label
	var font := ThemeDB.fallback_font
	if font:
		_draw_control.draw_string(font, px + Vector2(-10, -10 * _zoom),
			"YOU", HORIZONTAL_ALIGNMENT_CENTER, -1, int(10 * _zoom), PLAYER_COLOR)


func _map_to_screen_raw(map_pos: Vector2, origin: Vector2) -> Vector2:
	return origin + map_pos * _zoom


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	var viewport_center := _draw_control.size * 0.5
	var origin := viewport_center + _pan_offset
	return (screen_pos - origin) / _zoom


# ---------------------------------------------------------------------------
# Open / Close
# ---------------------------------------------------------------------------

func open_map() -> void:
	if _is_open:
		return

	_is_open = true
	visible = true

	# Center on player
	_update_player_position()
	var district_offset: Vector2 = DISTRICT_OFFSETS.get(_player_district, Vector2.ZERO)
	_pan_offset = -(_player_position + district_offset) * _zoom

	# Pause the game
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

	_draw_control.queue_redraw()
	print("[Map] World map opened.")


func close_map() -> void:
	if not _is_open:
		return

	_is_open = false
	visible = false
	_info_panel.visible = false
	_selected_poi = {}
	_fast_travel_target = ""

	get_tree().paused = false
	print("[Map] World map closed.")


func is_open() -> bool:
	return _is_open


func _update_player_position() -> void:
	var free_roam := _find_free_roam()
	if free_roam == null:
		return
	var vehicle: Node3D = free_roam.player_vehicle
	if vehicle and is_instance_valid(vehicle):
		_player_position = Vector2(vehicle.global_transform.origin.x, vehicle.global_transform.origin.z)
	if free_roam.district_manager:
		_player_district = free_roam.district_manager.current_district_id


func _on_district_entered(district_id: String) -> void:
	_player_district = district_id


# ---------------------------------------------------------------------------
# Fast Travel
# ---------------------------------------------------------------------------

func _on_fast_travel_pressed() -> void:
	if _fast_travel_target.is_empty():
		return

	if not _is_district_unlocked(_fast_travel_target):
		print("[Map] Cannot fast travel to locked district: %s" % _fast_travel_target)
		return

	print("[Map] Fast traveling to %s" % _fast_travel_target)

	# Advance game time
	if GameManager.world_time:
		GameManager.world_time.advance_minutes(FAST_TRAVEL_TIME_COST)

	# Close the map first
	close_map()

	# Request district transition
	var free_roam := _find_free_roam()
	if free_roam and free_roam.district_manager:
		if _fast_travel_target != free_roam.district_manager.current_district_id:
			free_roam.district_manager.request_transition(_fast_travel_target)
		else:
			EventBus.hud_message.emit("Already in this district!", 2.0)


func _find_free_roam() -> Node:
	## Walk up the tree to find FreeRoam.
	var node := get_parent()
	while node:
		if "player_vehicle" in node and "district_manager" in node:
			return node
		node = node.get_parent()
	return null
