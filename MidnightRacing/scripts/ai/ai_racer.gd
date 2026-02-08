extends VehicleBody3D

# AI Racer - Controls AI vehicles using Path3D for pathfinding

@export var path_follow: PathFollow3D = null
@export var max_speed = 100.0
@export var acceleration_speed = 50.0
@export var steer_speed = 2.0
@export var look_ahead_distance = 10.0

var current_speed = 0.0
var target_position = Vector3.ZERO

func _ready():
	# Find path if not assigned
	if not path_follow:
		find_race_path()

	add_to_group("ai_racer")

func find_race_path():
	"""Find the race path in the scene"""
	var paths = get_tree().get_nodes_in_group("race_path")
	if paths.size() > 0:
		var path = paths[0]
		if path is Path3D:
			# Create PathFollow3D node
			path_follow = PathFollow3D.new()
			path.add_child(path_follow)
			path_follow.loop = true
			print("AI Racer connected to race path")
		else:
			print("Warning: Race path found but not a Path3D!")
	else:
		print("Warning: No race path found for AI racer!")

func _physics_process(delta):
	if not path_follow:
		return

	# Update path follow position
	path_follow.progress += current_speed * delta

	# Get target position ahead on path
	var temp_progress = path_follow.progress + look_ahead_distance
	var original_progress = path_follow.progress
	path_follow.progress = temp_progress
	target_position = path_follow.global_position
	path_follow.progress = original_progress

	# Calculate steering
	var direction_to_target = (target_position - global_position).normalized()
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x

	# Calculate steering angle
	var steer = direction_to_target.dot(right)
	steering = lerp(steering, steer * 0.5, steer_speed * delta)

	# Calculate forward progress
	var forward_dot = direction_to_target.dot(forward)

	# Accelerate or brake
	if forward_dot > 0.0:
		current_speed = lerp(current_speed, max_speed, acceleration_speed * delta)
		engine_force = 150.0
		brake = 0.0
	else:
		# Brake if going wrong direction
		current_speed = lerp(current_speed, 0.0, acceleration_speed * delta * 2.0)
		engine_force = 0.0
		brake = 3.0

	# Handle sharp turns
	if abs(steer) > 0.7:
		current_speed = lerp(current_speed, max_speed * 0.5, acceleration_speed * delta)

func set_race_path(path: Path3D):
	"""Set the race path for this AI racer"""
	if path and path is Path3D:
		path_follow = PathFollow3D.new()
		path.add_child(path_follow)
		path_follow.loop = true
		print("AI Racer path set")

func get_progress() -> float:
	"""Get current progress on path"""
	if path_follow:
		return path_follow.progress_ratio
	return 0.0

func reset_to_start():
	"""Reset AI to start of path"""
	if path_follow:
		path_follow.progress = 0.0
		current_speed = 0.0
