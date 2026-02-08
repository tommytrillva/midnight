## Manages navigation waypoints for active missions and custom markers.
## Renders on-screen directional indicators (arrows at viewport edge) pointing
## toward off-screen waypoints, with distance display.
class_name WaypointSystem
extends Node


## A single waypoint entry.
class Waypoint:
	var id: String = ""
	var world_position: Vector3 = Vector3.ZERO
	var label: String = ""
	var color: Color = Color.YELLOW
	var is_primary: bool = false
	var is_mission: bool = false

	func _init(p_id: String = "", p_pos: Vector3 = Vector3.ZERO, p_label: String = "", p_color: Color = Color.YELLOW) -> void:
		id = p_id
		world_position = p_pos
		label = p_label
		color = p_color


## Active waypoints. Primary is drawn larger, secondary are smaller.
var _waypoints: Dictionary = {}  # id -> Waypoint
var _primary_id: String = ""

## Cached references
var _camera: Camera3D = null
var _viewport_size: Vector2 = Vector2(1152, 648)

## Visual config
const ARROW_SIZE := 16.0
const ARROW_MARGIN := 40.0
const DISTANCE_FADE_NEAR := 5.0    # Meters - start fading at this distance
const DISTANCE_FADE_FAR := 500.0   # Meters - fully visible beyond this
const INDICATOR_FONT_SIZE := 12
const PRIMARY_SCALE := 1.4


func _ready() -> void:
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.mission_failed.connect(_on_mission_failed)
	print("[Waypoint] WaypointSystem initialized.")


func _process(_delta: float) -> void:
	# Update camera reference each frame (cameras can change)
	_camera = get_viewport().get_camera_3d()
	_viewport_size = get_viewport().get_visible_rect().size


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_waypoint(position: Vector3, label: String = "", color: Color = Color.YELLOW, id: String = "") -> void:
	## Sets or updates a waypoint. If id is empty, generates one.
	if id.is_empty():
		id = "wp_%d" % randi()
	var wp := Waypoint.new(id, position, label, color)
	_waypoints[id] = wp
	# First waypoint becomes primary
	if _primary_id.is_empty():
		_primary_id = id
		wp.is_primary = true
	print("[Waypoint] Set waypoint '%s' at %s — %s" % [id, str(position), label])


func clear_waypoint(id: String = "") -> void:
	## Clears a specific waypoint by id, or all waypoints if id is empty.
	if id.is_empty():
		_waypoints.clear()
		_primary_id = ""
		print("[Waypoint] All waypoints cleared.")
	elif id in _waypoints:
		_waypoints.erase(id)
		if _primary_id == id:
			_primary_id = ""
			# Promote next waypoint to primary
			if not _waypoints.is_empty():
				var next_id: String = _waypoints.keys()[0]
				_primary_id = next_id
				_waypoints[next_id].is_primary = true
		print("[Waypoint] Cleared waypoint '%s'" % id)


func set_primary(id: String) -> void:
	## Promotes a waypoint to primary.
	if id in _waypoints:
		if _primary_id in _waypoints:
			_waypoints[_primary_id].is_primary = false
		_primary_id = id
		_waypoints[id].is_primary = true


func set_mission_waypoint(mission_id: String) -> void:
	## Auto-sets a waypoint from mission data. Reads position from the mission's
	## target_position or objective_location fields.
	var mission: Dictionary = GameManager.story.get_mission(mission_id)
	if mission.is_empty():
		print("[Waypoint] WARNING: Mission '%s' not found." % mission_id)
		return

	var pos_arr: Array = mission.get("target_position", [])
	var target_pos := Vector3.ZERO
	if pos_arr.size() >= 3:
		target_pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
	elif mission.has("objective_location"):
		var loc: Array = mission.get("objective_location", [])
		if loc.size() >= 3:
			target_pos = Vector3(loc[0], loc[1], loc[2])

	var label: String = mission.get("name", "Objective")
	var color := Color(1.0, 1.0, 0.0)  # Mission yellow

	var wp := Waypoint.new("mission_" + mission_id, target_pos, label, color)
	wp.is_mission = true
	wp.is_primary = true

	# Demote current primary
	if _primary_id in _waypoints:
		_waypoints[_primary_id].is_primary = false

	_waypoints[wp.id] = wp
	_primary_id = wp.id
	print("[Waypoint] Mission waypoint set for '%s': %s at %s" % [mission_id, label, str(target_pos)])


func get_waypoint_count() -> int:
	return _waypoints.size()


func has_waypoint(id: String) -> bool:
	return id in _waypoints


func get_primary_waypoint() -> Waypoint:
	if _primary_id in _waypoints:
		return _waypoints[_primary_id]
	return null


func get_all_waypoints() -> Array:
	return _waypoints.values()


# ---------------------------------------------------------------------------
# Drawing — called by the HUD overlay
# ---------------------------------------------------------------------------

func get_indicators(player_pos: Vector3) -> Array:
	## Returns an array of indicator dictionaries for the HUD to draw.
	## Each dict: {screen_pos, is_on_screen, edge_pos, angle, distance, label, color, is_primary}
	var result: Array = []
	if _camera == null:
		return result

	for wp in _waypoints.values():
		var indicator := _compute_indicator(wp, player_pos)
		if indicator != null:
			result.append(indicator)

	return result


func _compute_indicator(wp: Waypoint, player_pos: Vector3) -> Dictionary:
	## Computes screen position and edge clamping for a single waypoint.
	if _camera == null:
		return {}

	var world_pos := wp.world_position
	var distance := player_pos.distance_to(world_pos)

	# Opacity based on distance
	var alpha := 1.0
	if distance < DISTANCE_FADE_NEAR:
		alpha = distance / DISTANCE_FADE_NEAR

	# Project to screen
	var screen_pos := _camera.unproject_position(world_pos)
	var is_behind := _camera.is_position_behind(world_pos)
	var is_on_screen := false

	if not is_behind:
		var margin := ARROW_MARGIN
		if screen_pos.x >= margin and screen_pos.x <= _viewport_size.x - margin and \
			screen_pos.y >= margin and screen_pos.y <= _viewport_size.y - margin:
			is_on_screen = true

	# Edge-clamped position for off-screen indicator
	var edge_pos := screen_pos
	var angle := 0.0

	if not is_on_screen:
		var center := _viewport_size * 0.5
		var dir := Vector2.ZERO

		if is_behind:
			# Flip direction for behind-camera waypoints
			dir = (center - screen_pos).normalized()
			# Ensure the point is actually moved to the right side
			dir = -dir if dir.length() < 0.01 else dir
		else:
			dir = (screen_pos - center).normalized()

		# Clamp to viewport edges with margin
		var margin := ARROW_MARGIN
		var half := _viewport_size * 0.5 - Vector2(margin, margin)
		if abs(dir.x) > 0.001 and abs(dir.y) > 0.001:
			var scale_x: float = half.x / abs(dir.x)
			var scale_y: float = half.y / abs(dir.y)
			var t := minf(scale_x, scale_y)
			edge_pos = center + dir * t
		elif abs(dir.x) > 0.001:
			edge_pos = center + dir * (half.x / abs(dir.x))
		elif abs(dir.y) > 0.001:
			edge_pos = center + dir * (half.y / abs(dir.y))
		else:
			edge_pos = center + Vector2(0, -half.y)

		angle = atan2(dir.y, dir.x)

	var col := wp.color
	col.a = alpha

	return {
		"screen_pos": screen_pos,
		"edge_pos": edge_pos,
		"is_on_screen": is_on_screen,
		"angle": angle,
		"distance": distance,
		"label": wp.label,
		"color": col,
		"is_primary": wp.is_primary,
		"is_mission": wp.is_mission,
		"id": wp.id,
	}


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_mission_started(mission_id: String) -> void:
	set_mission_waypoint(mission_id)


func _on_mission_completed(mission_id: String, _outcome: Dictionary) -> void:
	var wp_id := "mission_" + mission_id
	clear_waypoint(wp_id)


func _on_mission_failed(mission_id: String, _reason: String) -> void:
	var wp_id := "mission_" + mission_id
	clear_waypoint(wp_id)
