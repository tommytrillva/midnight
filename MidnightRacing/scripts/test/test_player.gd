extends CharacterBody3D

## Test Player - Simple player controller for testing triggers
##
## This script provides basic movement for testing mission triggers
## and other gameplay systems without requiring the full vehicle system.

@export var move_speed: float = 5.0
@export var sprint_speed: float = 10.0
@export var jump_velocity: float = 4.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	# Add to player group for trigger detection
	add_to_group("player")
	print("Test player initialized")

func _physics_process(delta):
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get input direction
	var input_dir = Input.get_vector("steer_left", "steer_right", "accelerate", "brake")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Apply movement
	if direction:
		var speed = sprint_speed if Input.is_action_pressed("handbrake") else move_speed
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()

	# Debug output for position
	if Input.is_action_just_pressed("ui_text_completion_query"):
		print("Player position: ", global_position)
