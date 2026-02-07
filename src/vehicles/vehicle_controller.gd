## Player vehicle physics controller using Godot's VehicleBody3D.
## Implements arcade-sim hybrid handling matching the GDD's
## "deep mechanical truth" pillar with accessible controls.
class_name VehicleController
extends VehicleBody3D

@export var vehicle_data: VehicleData = null

# --- Physics Tuning ---
@export_group("Engine")
@export var max_engine_force: float = 300.0
@export var max_brake_force: float = 50.0
@export var max_steer_angle: float = 0.4 # radians
@export var engine_brake_force: float = 5.0

@export_group("Transmission")
@export var gear_ratios: Array[float] = [3.5, 2.5, 1.8, 1.3, 1.0, 0.8]
@export var reverse_ratio: float = -3.0
@export var final_drive: float = 3.7
@export var shift_time: float = 0.15 # Seconds to shift
@export var auto_shift: bool = true

@export_group("Handling")
@export var steer_speed: float = 3.0 # How fast steering responds
@export var steer_return_speed: float = 5.0
@export var handbrake_force: float = 80.0
@export var downforce_factor: float = 0.5

@export_group("Nitrous")
@export var nitro_force_mult: float = 1.5
@export var nitro_max: float = 100.0
@export var nitro_consumption_rate: float = 25.0 # Per second
@export var nitro_regen_rate: float = 5.0

# --- State ---
var current_gear: int = 1 # 0=neutral, -1=reverse, 1-6=forward
var current_rpm: float = 0.0
var current_speed_kmh: float = 0.0
var is_shifting: bool = false
var shift_timer: float = 0.0
var nitro_amount: float = 0.0
var nitro_active: bool = false
var is_handbraking: bool = false

# Input state
var input_throttle: float = 0.0
var input_brake: float = 0.0
var input_steer: float = 0.0

# Drift detection
var drift_angle: float = 0.0
var is_drifting: bool = false
var drift_score: float = 0.0

const RPM_IDLE := 800.0
const RPM_LIMITER_BUFFER := 500.0


func _ready() -> void:
	if vehicle_data:
		_apply_vehicle_data()


func _physics_process(delta: float) -> void:
	_read_input()
	_update_speed()
	_update_rpm(delta)
	_update_shifting(delta)
	_update_nitro(delta)
	_apply_forces(delta)
	_update_drift(delta)
	_apply_skill_effects()


func _read_input() -> void:
	input_throttle = Input.get_action_strength("accelerate")
	input_brake = Input.get_action_strength("brake")
	input_steer = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	is_handbraking = Input.is_action_pressed("handbrake")
	nitro_active = Input.is_action_pressed("nitro") and nitro_amount > 0

	if Input.is_action_just_pressed("shift_up"):
		shift_up()
	if Input.is_action_just_pressed("shift_down"):
		shift_down()


func _update_speed() -> void:
	current_speed_kmh = linear_velocity.length() * 3.6


func _update_rpm(delta: float) -> void:
	if vehicle_data == null:
		return

	var max_rpm := float(vehicle_data.redline_rpm)
	var wheel_rpm := abs(current_speed_kmh / 3.6) * 60.0 / (2.0 * PI * 0.33) # ~0.33m wheel radius

	if current_gear > 0 and current_gear <= gear_ratios.size():
		var ratio := gear_ratios[current_gear - 1] * final_drive
		current_rpm = wheel_rpm * ratio
	elif current_gear == -1:
		current_rpm = wheel_rpm * abs(reverse_ratio) * final_drive
	else:
		current_rpm = RPM_IDLE

	current_rpm = clampf(current_rpm, RPM_IDLE, max_rpm + RPM_LIMITER_BUFFER)

	# Auto shift
	if auto_shift and not is_shifting:
		if current_rpm >= max_rpm * 0.95 and current_gear < gear_ratios.size():
			shift_up()
		elif current_rpm <= max_rpm * 0.35 and current_gear > 1:
			shift_down()


func _update_shifting(delta: float) -> void:
	if is_shifting:
		shift_timer -= delta
		if shift_timer <= 0:
			is_shifting = false


func _update_nitro(delta: float) -> void:
	if nitro_active and nitro_amount > 0:
		nitro_amount = maxf(nitro_amount - nitro_consumption_rate * delta, 0.0)
		if nitro_amount <= 0:
			nitro_active = false
			EventBus.nitro_depleted.emit(0)
	elif not nitro_active and nitro_amount < nitro_max:
		nitro_amount = minf(nitro_amount + nitro_regen_rate * delta, nitro_max)


func _apply_forces(_delta: float) -> void:
	if vehicle_data == null:
		return

	# Steering
	var target_steer := input_steer * max_steer_angle
	var steer_spd := steer_speed if abs(input_steer) > 0.1 else steer_return_speed
	steering = move_toward(steering, target_steer, steer_spd * _delta)

	# Speed-dependent steering reduction
	var speed_factor := clampf(1.0 - (current_speed_kmh / 200.0) * 0.6, 0.4, 1.0)
	steering *= speed_factor

	# Engine force
	var force := 0.0
	if not is_shifting:
		var effective_hp := vehicle_data.current_hp
		var stats := vehicle_data.get_effective_stats()
		force = input_throttle * max_engine_force * (effective_hp / vehicle_data.stock_hp)

		if nitro_active:
			force *= nitro_force_mult

		if current_gear == -1:
			force *= -0.5

	engine_force = force

	# Braking
	var brake := input_brake * max_brake_force
	if is_handbraking:
		brake = handbrake_force
	elif input_throttle < 0.1 and input_brake < 0.1:
		brake = engine_brake_force

	self.brake = brake

	# Downforce at speed
	if current_speed_kmh > 50.0:
		var downforce := current_speed_kmh * downforce_factor
		apply_central_force(Vector3.DOWN * downforce)


func _update_drift(delta: float) -> void:
	if linear_velocity.length() < 5.0:
		is_drifting = false
		return

	var forward := -global_transform.basis.z.normalized()
	var velocity_dir := linear_velocity.normalized()
	drift_angle = rad_to_deg(acos(clampf(forward.dot(velocity_dir), -1.0, 1.0)))

	is_drifting = drift_angle > 15.0 and current_speed_kmh > 30.0

	if is_drifting:
		drift_score += drift_angle * current_speed_kmh * 0.001 * delta


func _apply_skill_effects() -> void:
	## Apply active skill tree effects to vehicle performance.
	var speed_mult := GameManager.skills.get_stat_multiplier("speed")
	var handling_mult := GameManager.skills.get_stat_multiplier("handling")
	max_steer_angle = 0.4 * handling_mult


func shift_up() -> void:
	if current_gear < gear_ratios.size() and not is_shifting:
		current_gear += 1
		is_shifting = true
		shift_timer = shift_time
		EventBus.gear_shifted.emit(0, current_gear)


func shift_down() -> void:
	if current_gear > 1 and not is_shifting:
		current_gear -= 1
		is_shifting = true
		shift_timer = shift_time
		EventBus.gear_shifted.emit(0, current_gear)


func _apply_vehicle_data() -> void:
	## Configure physics from VehicleData.
	if vehicle_data == null:
		return

	var stats := vehicle_data.get_effective_stats()
	max_engine_force = stats.speed * 3.0 + stats.acceleration * 2.0
	max_brake_force = stats.braking * 1.5
	mass = stats.weight

	# Nitrous check
	var has_nos := vehicle_data.installed_parts.get("nitrous", "") != "" and \
		vehicle_data.installed_parts.get("nitrous", "") != "nitrous_none"
	nitro_max = 100.0 if has_nos else 0.0
	nitro_amount = nitro_max


func setup_from_data(data: VehicleData) -> void:
	vehicle_data = data
	_apply_vehicle_data()
