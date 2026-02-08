extends VehicleBody3D

# Vehicle Controller - Handles vehicle physics and input

signal speed_changed(speed: float)
signal rpm_changed(rpm: float)
signal gear_changed(gear: int)

@export var max_engine_force = 200.0
@export var max_brake_force = 5.0
@export var max_steer_angle = 0.5
@export var max_speed_mph = 125.0
@export var nitrous_boost = 100.0

var current_speed_mph = 0.0
var current_rpm = 0.0
var current_gear = 1
var engine_force = 0.0
var brake_force = 0.0
var steer_angle = 0.0
var using_nitrous = false
var nitrous_amount = 100.0

# Vehicle stats (loaded from GameManager)
var vehicle_data = null

func _ready():
	# Load vehicle data from GameManager
	vehicle_data = GameManager.get_current_vehicle()
	if vehicle_data:
		update_vehicle_stats()

func update_vehicle_stats():
	"""Update vehicle performance based on data"""
	if vehicle_data:
		max_speed_mph = vehicle_data.top_speed
		max_engine_force = vehicle_data.hp * 2.0
		# Apply part modifications
		if vehicle_data.parts.engine != "stock":
			max_engine_force *= 1.2
		if vehicle_data.parts.nitrous:
			nitrous_amount = 100.0

func _physics_process(delta):
	# Handle input
	handle_input()

	# Update speed
	var velocity = linear_velocity.length()
	current_speed_mph = velocity * 2.23694  # Convert m/s to mph

	# Calculate RPM based on speed and gear
	current_rpm = (current_speed_mph / max_speed_mph) * 7000.0

	# Auto-shift gears
	auto_shift()

	# Apply forces
	engine_force = engine_force
	brake = brake_force
	steering = steer_angle

	# Emit signals for HUD
	speed_changed.emit(current_speed_mph)
	rpm_changed.emit(current_rpm)

func handle_input():
	"""Handle player input"""
	# Acceleration
	if Input.is_action_pressed("accelerate"):
		engine_force = max_engine_force
		brake_force = 0.0

		# Nitrous boost
		if Input.is_action_pressed("nitrous") and nitrous_amount > 0:
			engine_force += nitrous_boost
			nitrous_amount -= 0.5
			using_nitrous = true
		else:
			using_nitrous = false
	else:
		engine_force = 0.0
		using_nitrous = false

	# Braking
	if Input.is_action_pressed("brake"):
		brake_force = max_brake_force
		engine_force = 0.0

	# Steering
	var steer_input = 0.0
	if Input.is_action_pressed("steer_left"):
		steer_input += 1.0
	if Input.is_action_pressed("steer_right"):
		steer_input -= 1.0

	# Smooth steering
	steer_angle = lerp(steer_angle, steer_input * max_steer_angle, 0.1)

	# Handbrake
	if Input.is_action_pressed("handbrake"):
		brake_force = max_brake_force * 1.5

func auto_shift():
	"""Automatic transmission gear shifting"""
	var speed_ratio = current_speed_mph / max_speed_mph
	var previous_gear = current_gear

	if speed_ratio < 0.15:
		current_gear = 1
	elif speed_ratio < 0.30:
		current_gear = 2
	elif speed_ratio < 0.50:
		current_gear = 3
	elif speed_ratio < 0.70:
		current_gear = 4
	elif speed_ratio < 0.85:
		current_gear = 5
	else:
		current_gear = 6

	# Emit signal when gear changes
	if current_gear != previous_gear:
		gear_changed.emit(current_gear)

func get_speed() -> float:
	"""Get current speed in MPH"""
	return current_speed_mph

func get_rpm() -> float:
	"""Get current RPM"""
	return current_rpm

func get_gear() -> int:
	"""Get current gear"""
	return current_gear

func get_nitrous() -> float:
	"""Get nitrous amount"""
	return nitrous_amount

func refill_nitrous():
	"""Refill nitrous to full"""
	nitrous_amount = 100.0
