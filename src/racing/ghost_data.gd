## Stores a complete ghost recording for a single race run.
## Includes interpolated frame lookup, serialization for disk persistence,
## and metadata for the "Ghosts of Past" Act 4 mission.
class_name GhostData
extends Resource

## Track this ghost was recorded on.
var track_id: String = ""
## Vehicle ID used during the recording.
var vehicle_id: String = ""
## Human-readable vehicle name (for UI display).
var vehicle_name: String = ""
## Total race time in seconds.
var total_time: float = 0.0
## Ordered array of GhostFrame snapshots (recorded at ~20 fps).
var frames: Array = []  # Array of GhostFrame
## ISO date string when this ghost was recorded.
var recorded_date: String = ""
## Which story act the player was in when this ghost was recorded.
## Used by the Act 4 "Ghosts of Past" mission to tint era-specific ghosts.
var act_recorded: int = 1
## Player name at time of recording.
var player_name: String = ""


# ═══════════════════════════════════════════════════════════════════════════════
#  FRAME ACCESS
# ═══════════════════════════════════════════════════════════════════════════════

func get_frame_at_time(time: float) -> GhostFrame:
	## Returns an interpolated GhostFrame at the given timestamp.
	## Clamps to first/last frame if time is out of bounds.
	if frames.is_empty():
		return GhostFrame.new()

	# Clamp to valid range
	if time <= 0.0 or frames.size() == 1:
		return frames[0]
	if time >= total_time:
		return frames[frames.size() - 1]

	# Binary search for the surrounding frames
	var low: int = 0
	var high: int = frames.size() - 1

	while low < high - 1:
		var mid: int = (low + high) / 2
		if frames[mid].timestamp <= time:
			low = mid
		else:
			high = mid

	var frame_a: GhostFrame = frames[low]
	var frame_b: GhostFrame = frames[high]

	# Interpolation factor between the two bracketing frames
	var dt: float = frame_b.timestamp - frame_a.timestamp
	if dt <= 0.0:
		return frame_a

	var t: float = clampf((time - frame_a.timestamp) / dt, 0.0, 1.0)
	return GhostFrame.interpolate(frame_a, frame_b, t)


func get_total_frames() -> int:
	return frames.size()


func get_duration() -> float:
	if frames.is_empty():
		return 0.0
	return frames[frames.size() - 1].timestamp


# ═══════════════════════════════════════════════════════════════════════════════
#  SERIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

func serialize() -> Dictionary:
	var serialized_frames: Array = []
	for frame: GhostFrame in frames:
		serialized_frames.append(frame.serialize())

	return {
		"track_id": track_id,
		"vehicle_id": vehicle_id,
		"vehicle_name": vehicle_name,
		"total_time": total_time,
		"recorded_date": recorded_date,
		"act_recorded": act_recorded,
		"player_name": player_name,
		"frame_count": frames.size(),
		"frames": serialized_frames,
	}


func deserialize(data: Dictionary) -> void:
	track_id = data.get("track_id", "")
	vehicle_id = data.get("vehicle_id", "")
	vehicle_name = data.get("vehicle_name", "")
	total_time = data.get("total_time", 0.0)
	recorded_date = data.get("recorded_date", "")
	act_recorded = data.get("act_recorded", 1)
	player_name = data.get("player_name", "")

	frames.clear()
	var frame_dicts: Array = data.get("frames", [])
	for fd: Dictionary in frame_dicts:
		var frame := GhostFrame.new()
		frame.deserialize(fd)
		frames.append(frame)


# ═══════════════════════════════════════════════════════════════════════════════
#  FILE I/O
# ═══════════════════════════════════════════════════════════════════════════════

static func get_ghost_directory() -> String:
	return "user://ghosts/"


func get_save_path() -> String:
	return GhostData.get_ghost_directory() + "%s_%s.json" % [track_id, vehicle_id]


func get_era_save_path() -> String:
	return GhostData.get_ghost_directory() + "%s_%s_act%d.json" % [track_id, vehicle_id, act_recorded]


func save_to_file(path: String = "") -> bool:
	var save_path: String = path if not path.is_empty() else get_save_path()

	# Ensure directory exists
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("ghosts"):
		dir.make_dir("ghosts")

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("[Ghost] Failed to save ghost to: %s" % save_path)
		return false

	var json_string := JSON.stringify(serialize(), "\t")
	file.store_string(json_string)
	file.close()
	print("[Ghost] Saved ghost: %s (%.2fs, %d frames)" % [save_path, total_time, frames.size()])
	return true


static func load_from_file(path: String) -> GhostData:
	if not FileAccess.file_exists(path):
		print("[Ghost] Ghost file not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[Ghost] Failed to open ghost file: %s" % path)
		return null

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		push_error("[Ghost] Failed to parse ghost JSON: %s" % path)
		return null

	var ghost := GhostData.new()
	ghost.deserialize(json.data)
	print("[Ghost] Loaded ghost: %s (%.2fs, %d frames)" % [path, ghost.total_time, ghost.frames.size()])
	return ghost


# ═══════════════════════════════════════════════════════════════════════════════
#  GHOST FRAME — Inner class for a single snapshot of vehicle state
# ═══════════════════════════════════════════════════════════════════════════════

class GhostFrame:
	## Seconds since race start.
	var timestamp: float = 0.0
	## World-space position.
	var position: Vector3 = Vector3.ZERO
	## Euler rotation (degrees) for compact serialization.
	var rotation: Vector3 = Vector3.ZERO
	## Speed in km/h.
	var speed: float = 0.0
	## Steering wheel angle (normalized -1 to 1).
	var steering: float = 0.0
	## Whether the vehicle was drifting.
	var drifting: bool = false
	## Whether nitro was active.
	var nitro: bool = false
	## Whether brakes were applied.
	var braking: bool = false
	## Current transmission gear.
	var gear: int = 1

	func serialize() -> Dictionary:
		return {
			"t": snapped(timestamp, 0.001),
			"px": snapped(position.x, 0.01),
			"py": snapped(position.y, 0.01),
			"pz": snapped(position.z, 0.01),
			"rx": snapped(rotation.x, 0.1),
			"ry": snapped(rotation.y, 0.1),
			"rz": snapped(rotation.z, 0.1),
			"spd": snapped(speed, 0.1),
			"str": snapped(steering, 0.01),
			"dft": drifting,
			"nos": nitro,
			"brk": braking,
			"gr": gear,
		}

	func deserialize(data: Dictionary) -> void:
		timestamp = data.get("t", 0.0)
		position = Vector3(
			data.get("px", 0.0),
			data.get("py", 0.0),
			data.get("pz", 0.0)
		)
		rotation = Vector3(
			data.get("rx", 0.0),
			data.get("ry", 0.0),
			data.get("rz", 0.0)
		)
		speed = data.get("spd", 0.0)
		steering = data.get("str", 0.0)
		drifting = data.get("dft", false)
		nitro = data.get("nos", false)
		braking = data.get("brk", false)
		gear = data.get("gr", 1)

	static func interpolate(a: GhostFrame, b: GhostFrame, t: float) -> GhostFrame:
		## Linearly interpolates between two frames. Boolean states snap
		## to whichever frame is closer (t < 0.5 -> a, else -> b).
		var result := GhostFrame.new()
		result.timestamp = lerpf(a.timestamp, b.timestamp, t)
		result.position = a.position.lerp(b.position, t)

		# Angle-safe rotation interpolation (handle 359->1 wrapping)
		result.rotation = Vector3(
			lerp_angle(deg_to_rad(a.rotation.x), deg_to_rad(b.rotation.x), t),
			lerp_angle(deg_to_rad(a.rotation.y), deg_to_rad(b.rotation.y), t),
			lerp_angle(deg_to_rad(a.rotation.z), deg_to_rad(b.rotation.z), t)
		)
		result.rotation = Vector3(
			rad_to_deg(result.rotation.x),
			rad_to_deg(result.rotation.y),
			rad_to_deg(result.rotation.z)
		)

		result.speed = lerpf(a.speed, b.speed, t)
		result.steering = lerpf(a.steering, b.steering, t)

		# Boolean states snap to nearest frame
		var use_b: bool = t >= 0.5
		result.drifting = b.drifting if use_b else a.drifting
		result.nitro = b.nitro if use_b else a.nitro
		result.braking = b.braking if use_b else a.braking
		result.gear = b.gear if use_b else a.gear

		return result
