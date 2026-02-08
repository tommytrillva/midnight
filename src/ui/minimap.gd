## Top-down minimap showing player position, roads, POIs, and other vehicles.
## Renders via _draw() with a circular mask. Updates at 30fps for performance.
class_name Minimap
extends Control


## Map data files indexed by district_id
const MAP_DATA_PATHS := {
	"downtown": "res://data/maps/downtown_map.json",
	"harbor": "res://data/maps/harbor_map.json",
	"industrial": "res://data/maps/industrial_map.json",
	"hillside": "res://data/maps/hillside_map.json",
}

## POI type -> default color mapping
const POI_COLORS := {
	"garage": Color(1.0, 0.6, 0.0),      # Orange
	"race": Color(0.2, 1.0, 0.3),         # Green
	"mission": Color(1.0, 1.0, 0.0),      # Yellow
	"transition": Color(1.0, 1.0, 1.0),   # White
	"contact": Color(0.7, 0.4, 1.0),      # Purple
	"shop": Color(0.0, 1.0, 1.0),         # Cyan
}

## POI icon shapes drawn procedurally
enum POIShape { WRENCH, FLAG, STAR, ARROW, PERSON, DOLLAR, DOT }
const POI_SHAPES := {
	"garage": POIShape.WRENCH,
	"race": POIShape.FLAG,
	"mission": POIShape.STAR,
	"transition": POIShape.ARROW,
	"contact": POIShape.PERSON,
	"shop": POIShape.DOLLAR,
}

## Zoom levels: world units visible as radius
const ZOOM_LEVELS := [80.0, 160.0, 320.0]
const ZOOM_NAMES := ["CLOSE", "MED", "FAR"]

## --- Exported Config ---
@export var minimap_size: float = 200.0
@export var border_width: float = 3.0
@export var border_color: Color = Color(0.0, 0.9, 0.9, 0.9)  # Neon cyan
@export var bg_color: Color = Color(0.02, 0.02, 0.06, 0.7)
@export var road_default_color: Color = Color(0.0, 0.7, 0.7, 0.5)
@export var player_color: Color = Color(0.0, 1.0, 0.8, 1.0)
@export var north_up: bool = false  # If true, map does not rotate with player
@export var update_fps: float = 30.0

## --- State ---
var _map_data: Dictionary = {}  # district_id -> MinimapData
var _current_map: MinimapData = null
var _zoom_index: int = 0
var _player_position: Vector2 = Vector2.ZERO
var _player_heading: float = 0.0  # Radians, 0 = north (+Z in Godot is south)
var _update_timer: float = 0.0
var _update_interval: float = 1.0 / 30.0
var _mission_pulse_time: float = 0.0
var _other_vehicles: Array = []  # Array of Vector2 positions
var _center: Vector2 = Vector2.ZERO
var _radius: float = 100.0


func _ready() -> void:
	_update_interval = 1.0 / update_fps
	_radius = minimap_size * 0.5
	_center = Vector2(_radius, _radius)
	custom_minimum_size = Vector2(minimap_size, minimap_size)
	size = Vector2(minimap_size, minimap_size)

	# Load all map data
	for district_id in MAP_DATA_PATHS:
		var path: String = MAP_DATA_PATHS[district_id]
		_map_data[district_id] = MinimapData.load_from_json(path)

	# Connect to district change
	EventBus.district_entered.connect(_on_district_entered)

	# Set initial district
	var current_id: String = "downtown"
	if GameManager and GameManager.player_data:
		current_id = GameManager.player_data.current_district
	_set_current_map(current_id)

	# Clip to circular shape using a shader or manual draw clipping
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	print("[Minimap] Initialized. Zoom: %s, Size: %d" % [ZOOM_NAMES[_zoom_index], int(minimap_size)])


func _process(delta: float) -> void:
	_mission_pulse_time += delta * 3.0
	_update_timer += delta
	if _update_timer < _update_interval:
		return
	_update_timer = 0.0

	_update_player_transform()
	_update_other_vehicles()
	queue_redraw()


func _input(event: InputEvent) -> void:
	# Toggle zoom with Z key or minimap_zoom action
	if event.is_action_pressed("minimap_zoom") or \
		(event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z):
		_cycle_zoom()
		get_viewport().set_input_as_handled()

	# Toggle north-up with N key
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		north_up = not north_up
		print("[Minimap] North-up: %s" % str(north_up))


func _cycle_zoom() -> void:
	_zoom_index = (_zoom_index + 1) % ZOOM_LEVELS.size()
	print("[Minimap] Zoom level: %s (%d units)" % [ZOOM_NAMES[_zoom_index], int(ZOOM_LEVELS[_zoom_index])])


func _set_current_map(district_id: String) -> void:
	if district_id in _map_data:
		_current_map = _map_data[district_id]
	else:
		_current_map = null
		print("[Minimap] WARNING: No map data for district '%s'" % district_id)


func _on_district_entered(district_id: String) -> void:
	_set_current_map(district_id)


func _update_player_transform() -> void:
	## Reads the player vehicle's world position and heading.
	var free_roam := _find_free_roam()
	if free_roam == null:
		return
	var vehicle: Node3D = free_roam.player_vehicle
	if vehicle == null or not is_instance_valid(vehicle):
		return

	var pos3d: Vector3 = vehicle.global_transform.origin
	_player_position = Vector2(pos3d.x, pos3d.z)

	# Heading: -Z is forward in Godot, we want angle from north (negative Z)
	var forward := -vehicle.global_transform.basis.z
	_player_heading = atan2(forward.x, forward.z)


func _update_other_vehicles() -> void:
	## Scans for other vehicles in the scene tree near the player.
	_other_vehicles.clear()
	var free_roam := _find_free_roam()
	if free_roam == null:
		return
	var vehicle: Node3D = free_roam.player_vehicle
	if vehicle == null:
		return

	var view_radius := ZOOM_LEVELS[_zoom_index]
	# Find AI vehicles in the scene
	var vehicles := get_tree().get_nodes_in_group("vehicles")
	for v in vehicles:
		if v == vehicle:
			continue
		if v is Node3D:
			var vpos := Vector2(v.global_transform.origin.x, v.global_transform.origin.z)
			if vpos.distance_to(_player_position) <= view_radius:
				_other_vehicles.append(vpos)


func _find_free_roam() -> Node:
	## Walk up from the HUD to find the FreeRoam node.
	var node := get_parent()
	while node:
		if node.has_method("_spawn_player_vehicle"):
			return node
		# Check if the node has a player_vehicle property
		if "player_vehicle" in node:
			return node
		node = node.get_parent()
	return null


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var half := _radius
	var center := _center

	# Background circle
	draw_circle(center, half, bg_color)

	var view_radius := ZOOM_LEVELS[_zoom_index]
	var rotation_angle := 0.0
	if not north_up:
		rotation_angle = -_player_heading

	# Draw roads
	if _current_map:
		_draw_roads(center, half, view_radius, rotation_angle)
		_draw_pois(center, half, view_radius, rotation_angle)

	# Draw other vehicles
	_draw_other_vehicles(center, half, view_radius, rotation_angle)

	# Draw player arrow (always centered)
	_draw_player_arrow(center, rotation_angle)

	# Draw north indicator
	_draw_north_indicator(center, half, rotation_angle)

	# Border ring
	draw_arc(center, half - border_width * 0.5, 0, TAU, 64, border_color, border_width)

	# Zoom indicator text
	_draw_zoom_indicator(center, half)

	# Circular mask - clear outside the circle by drawing opaque corners
	_draw_circular_mask(center, half)


func _world_to_minimap(world_pos: Vector2, center: Vector2, half: float, view_radius: float, rotation: float) -> Vector2:
	## Converts a world XZ position to minimap pixel coordinates.
	var offset := world_pos - _player_position
	# Scale to minimap pixels
	var scale := half / view_radius
	var mapped := offset * scale
	# Rotate around center
	if rotation != 0.0:
		mapped = mapped.rotated(rotation)
	return center + mapped


func _is_in_circle(pos: Vector2, center: Vector2, radius: float) -> bool:
	return pos.distance_squared_to(center) <= radius * radius


func _draw_roads(center: Vector2, half: float, view_radius: float, rotation: float) -> void:
	var roads := _current_map.get_roads_in_view(_player_position, view_radius)
	var road_col := _current_map.road_color if _current_map.road_color.a > 0 else road_default_color

	for road in roads:
		var start_px := _world_to_minimap(road.start, center, half, view_radius, rotation)
		var end_px := _world_to_minimap(road.end, center, half, view_radius, rotation)

		# Clip lines that extend outside the circle - simple approach: draw and let mask handle it
		var width_px := maxf(road.width * (half / view_radius), 1.0)
		width_px = clampf(width_px, 1.0, 4.0)
		draw_line(start_px, end_px, road_col, width_px, true)


func _draw_pois(center: Vector2, half: float, view_radius: float, rotation: float) -> void:
	var pois := _current_map.get_pois_in_view(_player_position, view_radius)

	for poi in pois:
		var px := _world_to_minimap(poi.position, center, half, view_radius, rotation)
		if not _is_in_circle(px, center, half - 4.0):
			continue

		var col: Color = poi.get("color", POI_COLORS.get(poi.type, Color.WHITE))
		var shape: int = POI_SHAPES.get(poi.type, POIShape.DOT)

		# Mission markers pulse
		if poi.type == "mission":
			var pulse := 0.5 + 0.5 * sin(_mission_pulse_time)
			col.a = 0.5 + 0.5 * pulse

		_draw_poi_shape(px, shape, col)


func _draw_poi_shape(pos: Vector2, shape: int, color: Color) -> void:
	var s := 5.0  # Base icon size
	match shape:
		POIShape.WRENCH:
			# Simple wrench: two small circles connected by a line
			draw_circle(pos + Vector2(-s * 0.5, -s * 0.5), 2.0, color)
			draw_circle(pos + Vector2(s * 0.5, s * 0.5), 2.0, color)
			draw_line(pos + Vector2(-s * 0.4, -s * 0.4), pos + Vector2(s * 0.4, s * 0.4), color, 1.5)

		POIShape.FLAG:
			# Flag on a pole
			draw_line(pos + Vector2(0, s), pos + Vector2(0, -s), color, 1.5)
			var flag_points := PackedVector2Array([
				pos + Vector2(0, -s),
				pos + Vector2(s, -s * 0.5),
				pos + Vector2(0, 0),
			])
			draw_colored_polygon(flag_points, color)

		POIShape.STAR:
			# 4-pointed star
			var points := PackedVector2Array()
			for i in range(8):
				var angle := i * TAU / 8.0 - PI / 2.0
				var r := s if i % 2 == 0 else s * 0.4
				points.append(pos + Vector2(cos(angle), sin(angle)) * r)
			draw_colored_polygon(points, color)

		POIShape.ARROW:
			# Arrow pointing up (transition)
			var arrow := PackedVector2Array([
				pos + Vector2(0, -s),
				pos + Vector2(s * 0.6, s * 0.3),
				pos + Vector2(0, 0),
				pos + Vector2(-s * 0.6, s * 0.3),
			])
			draw_colored_polygon(arrow, color)

		POIShape.PERSON:
			# Simple person icon: circle head + triangle body
			draw_circle(pos + Vector2(0, -s * 0.5), 2.5, color)
			var body := PackedVector2Array([
				pos + Vector2(-s * 0.4, s * 0.7),
				pos + Vector2(s * 0.4, s * 0.7),
				pos + Vector2(0, -s * 0.1),
			])
			draw_colored_polygon(body, color)

		POIShape.DOLLAR:
			# Dollar sign: circle with line through it
			draw_circle(pos, s * 0.6, Color(color, 0.4))
			draw_arc(pos, s * 0.6, 0, TAU, 12, color, 1.5)
			draw_line(pos + Vector2(0, -s * 0.8), pos + Vector2(0, s * 0.8), color, 1.5)

		_:  # DOT
			draw_circle(pos, 3.0, color)


func _draw_other_vehicles(center: Vector2, half: float, view_radius: float, rotation: float) -> void:
	for vpos in _other_vehicles:
		var px := _world_to_minimap(vpos, center, half, view_radius, rotation)
		if _is_in_circle(px, center, half - 4.0):
			draw_circle(px, 2.5, Color(1.0, 1.0, 1.0, 0.7))


func _draw_player_arrow(center: Vector2, _rotation: float) -> void:
	## Draws a directional arrow at center. If north_up, rotate the arrow by heading.
	var arrow_size := 8.0
	var angle := 0.0
	if north_up:
		angle = _player_heading

	var forward := Vector2(sin(angle), -cos(angle))
	var right := Vector2(cos(angle), sin(angle))

	var tip := center + forward * arrow_size
	var left_pt := center - forward * arrow_size * 0.6 - right * arrow_size * 0.5
	var right_pt := center - forward * arrow_size * 0.6 + right * arrow_size * 0.5

	var points := PackedVector2Array([tip, right_pt, center - forward * arrow_size * 0.2, left_pt])
	draw_colored_polygon(points, player_color)
	# Outline for visibility
	draw_polyline(PackedVector2Array([tip, right_pt, center - forward * arrow_size * 0.2, left_pt, tip]),
		Color(0.0, 0.0, 0.0, 0.5), 1.5)


func _draw_north_indicator(center: Vector2, half: float, rotation: float) -> void:
	## Draws 'N' at the top of the minimap, rotated appropriately.
	var north_angle := rotation  # When north_up, rotation is 0, so N is at top
	var north_dir := Vector2(sin(north_angle), -cos(north_angle))
	var north_pos := center + north_dir * (half - 14.0)

	if _is_in_circle(north_pos, center, half - 4.0):
		# Draw a small 'N' indicator
		var font := ThemeDB.fallback_font
		if font:
			draw_string(font, north_pos + Vector2(-4, 4), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
				Color(1.0, 0.2, 0.2, 0.9))


func _draw_zoom_indicator(center: Vector2, half: float) -> void:
	## Draws the current zoom level name at the bottom of the minimap.
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := ZOOM_NAMES[_zoom_index]
	var pos := center + Vector2(-12, half - 8.0)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9,
		Color(0.6, 0.6, 0.6, 0.7))


func _draw_circular_mask(center: Vector2, half: float) -> void:
	## Draws opaque rectangles in the corners to create a circular mask effect.
	## This is a simple approach — the circle clips the drawn content visually.
	var rect_size := Vector2(minimap_size, minimap_size)
	var mask_color := Color(0.0, 0.0, 0.0, 0.0)

	# We draw a ring of small segments around the circle to mask corners
	# Using a series of triangles from the circle edge to the bounding box corners
	var segments := 64
	var mask_bg := Color(0.0, 0.0, 0.0, 1.0)

	for i in range(segments):
		var angle_a := float(i) / segments * TAU
		var angle_b := float(i + 1) / segments * TAU

		var inner_a := center + Vector2(cos(angle_a), sin(angle_a)) * half
		var inner_b := center + Vector2(cos(angle_b), sin(angle_b)) * half

		# Extend to the bounding box edge
		var outer_a := center + Vector2(cos(angle_a), sin(angle_a)) * (half * 1.5)
		var outer_b := center + Vector2(cos(angle_b), sin(angle_b)) * (half * 1.5)

		# Clamp to control rect
		outer_a = outer_a.clamp(Vector2.ZERO, rect_size)
		outer_b = outer_b.clamp(Vector2.ZERO, rect_size)

		var poly := PackedVector2Array([inner_a, outer_a, outer_b, inner_b])
		draw_colored_polygon(poly, mask_bg)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_zoom_level(index: int) -> void:
	_zoom_index = clampi(index, 0, ZOOM_LEVELS.size() - 1)


func get_zoom_level() -> int:
	return _zoom_index


func get_current_view_radius() -> float:
	return ZOOM_LEVELS[_zoom_index]


func set_minimap_size(new_size: float) -> void:
	minimap_size = new_size
	_radius = new_size * 0.5
	_center = Vector2(_radius, _radius)
	custom_minimum_size = Vector2(new_size, new_size)
	size = Vector2(new_size, new_size)
