## Stores map layout data per district: road segments, POIs, bounds, and theme.
## Loaded from JSON files in data/maps/.
class_name MinimapData
extends Resource


## A single road segment on the minimap.
## start/end are Vector2 positions in world-space XZ coordinates.
var road_segments: Array = []  # Array of {start: Vector2, end: Vector2, width: float}

## Points of interest visible on the minimap.
## type: "garage", "race", "mission", "transition", "contact", "shop"
var poi_markers: Array = []  # Array of {position: Vector2, type: String, label: String, icon: String, color: Color}

## Bounding rectangle of the district in world XZ coordinates.
var bounds: Rect2 = Rect2()

## Display name of the district.
var district_name: String = ""

## District identifier.
var district_id: String = ""

## Color theme for roads in this district.
var road_color: Color = Color(0.0, 0.9, 0.9, 0.6)  # Neon cyan default

## Background tint for the district on the world map.
var background_color: Color = Color(0.05, 0.05, 0.1, 0.8)

## Scale factor: world units to map units (default 1:1).
var scale_factor: float = 1.0


func get_roads_in_view(center: Vector2, radius: float) -> Array:
	## Returns road segments that are at least partially within the given circle.
	var result: Array = []
	var radius_sq := radius * radius
	for segment in road_segments:
		var seg_start: Vector2 = segment.start
		var seg_end: Vector2 = segment.end
		# Check if either endpoint is within radius, or if segment passes through
		if _point_in_radius(seg_start, center, radius_sq) or \
			_point_in_radius(seg_end, center, radius_sq) or \
			_segment_intersects_circle(seg_start, seg_end, center, radius):
			result.append(segment)
	return result


func get_pois_in_view(center: Vector2, radius: float) -> Array:
	## Returns POI markers within the given radius of center.
	var result: Array = []
	var radius_sq := radius * radius
	for poi in poi_markers:
		var pos: Vector2 = poi.position
		if _point_in_radius(pos, center, radius_sq):
			result.append(poi)
	return result


func _point_in_radius(point: Vector2, center: Vector2, radius_sq: float) -> bool:
	return point.distance_squared_to(center) <= radius_sq


func _segment_intersects_circle(seg_start: Vector2, seg_end: Vector2, center: Vector2, radius: float) -> bool:
	## Returns true if the line segment intersects or is inside the circle.
	var d := seg_end - seg_start
	var f := seg_start - center
	var a := d.dot(d)
	if a < 0.0001:
		return false
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0:
		return false
	discriminant = sqrt(discriminant)
	var t1 := (-b - discriminant) / (2.0 * a)
	var t2 := (-b + discriminant) / (2.0 * a)
	# Check if intersection is within the segment [0, 1]
	return (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0) or (t1 < 0.0 and t2 > 1.0)


static func load_from_json(path: String) -> MinimapData:
	## Loads minimap data from a JSON file and returns a populated MinimapData.
	var data := MinimapData.new()

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[Minimap] ERROR: Could not open map data at '%s'" % path)
		return data

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		print("[Minimap] ERROR: Failed to parse JSON at '%s': %s" % [path, json.get_error_message()])
		return data

	var map_dict: Dictionary = json.data
	data.district_id = map_dict.get("district_id", "")
	data.district_name = map_dict.get("district_name", "")
	data.scale_factor = map_dict.get("scale_factor", 1.0)

	# Parse bounds
	var b: Dictionary = map_dict.get("bounds", {})
	data.bounds = Rect2(
		b.get("x", 0.0), b.get("y", 0.0),
		b.get("width", 500.0), b.get("height", 500.0)
	)

	# Parse road color
	var rc: Array = map_dict.get("road_color", [0.0, 0.9, 0.9, 0.6])
	if rc.size() >= 4:
		data.road_color = Color(rc[0], rc[1], rc[2], rc[3])

	# Parse background color
	var bg: Array = map_dict.get("background_color", [0.05, 0.05, 0.1, 0.8])
	if bg.size() >= 4:
		data.background_color = Color(bg[0], bg[1], bg[2], bg[3])

	# Parse road segments
	var roads: Array = map_dict.get("roads", [])
	for road in roads:
		var start_arr: Array = road.get("start", [0, 0])
		var end_arr: Array = road.get("end", [0, 0])
		data.road_segments.append({
			"start": Vector2(start_arr[0], start_arr[1]),
			"end": Vector2(end_arr[0], end_arr[1]),
			"width": road.get("width", 2.0),
		})

	# Parse POIs
	var pois: Array = map_dict.get("pois", [])
	for poi in pois:
		var pos_arr: Array = poi.get("position", [0, 0])
		var color_arr: Array = poi.get("color", [1.0, 1.0, 1.0, 1.0])
		var poi_color := Color.WHITE
		if color_arr.size() >= 4:
			poi_color = Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3])
		elif color_arr.size() >= 3:
			poi_color = Color(color_arr[0], color_arr[1], color_arr[2])
		data.poi_markers.append({
			"position": Vector2(pos_arr[0], pos_arr[1]),
			"type": poi.get("type", "unknown"),
			"label": poi.get("label", ""),
			"icon": poi.get("icon", ""),
			"color": poi_color,
		})

	print("[Minimap] Loaded map data for '%s': %d roads, %d POIs" % [
		data.district_name, data.road_segments.size(), data.poi_markers.size()
	])
	return data
