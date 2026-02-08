## Chase camera for racing. Follows the target vehicle with smooth
## interpolation, speed-dependent FOV, and drift-aware positioning.
class_name CameraController
extends Camera3D

@export var target: Node3D = null
@export var follow_distance: float = 6.0
@export var follow_height: float = 2.5
@export var look_ahead: float = 3.0
@export var position_smoothing: float = 5.0
@export var rotation_smoothing: float = 8.0
@export var fov_base: float = 65.0
@export var fov_max: float = 85.0
@export var fov_speed_factor: float = 0.1 # FOV increase per km/h
@export var drift_offset: float = 1.5 # Lateral offset when drifting
@export var shake_intensity: float = 0.0

var _velocity: Vector3 = Vector3.ZERO
var _shake_timer: float = 0.0


func _ready() -> void:
	EventBus.vehicle_collision.connect(_on_collision)
	EventBus.nitro_activated.connect(_on_nitro)
	print("[CameraController] Camera initialized. Target: %s, Current: %s" % [target, current])


func _physics_process(delta: float) -> void:
	if target == null:
		if Engine.get_physics_frames() % 60 == 0:  # Print once per second
			print("[CameraController] WARNING: Target is null!")
		return

	var vehicle := target as VehicleController
	var speed_kmh := 0.0
	var is_drifting := false
	var drift_angle := 0.0

	if vehicle:
		speed_kmh = vehicle.current_speed_kmh
		is_drifting = vehicle.is_drifting
		drift_angle = vehicle.drift_angle

	# Calculate desired position behind the target
	var target_forward := -target.global_transform.basis.z.normalized()
	var target_right := target.global_transform.basis.x.normalized()
	var target_pos := target.global_transform.origin

	var desired_pos := target_pos \
		- target_forward * follow_distance \
		+ Vector3.UP * follow_height

	# Look ahead based on speed
	var ahead_amount := look_ahead * clampf(speed_kmh / 100.0, 0.0, 1.5)
	var look_target := target_pos + target_forward * ahead_amount

	# Drift camera offset
	if is_drifting and drift_angle > 15.0:
		var drift_dir := 1.0 if target.steering > 0 else -1.0
		var offset_amount := clampf((drift_angle - 15.0) / 30.0, 0.0, 1.0) * drift_offset
		desired_pos += target_right * drift_dir * offset_amount

	# Speed-dependent distance (pull back at high speed)
	var speed_dist_bonus := clampf(speed_kmh / 200.0, 0.0, 1.0) * 2.0
	desired_pos -= target_forward * speed_dist_bonus

	# Smooth follow
	global_transform.origin = global_transform.origin.lerp(desired_pos, position_smoothing * delta)

	# Smooth look-at
	var current_basis := global_transform.basis
	look_at(look_target, Vector3.UP)
	var target_basis := global_transform.basis
	global_transform.basis = current_basis.slerp(target_basis, rotation_smoothing * delta)

	# Speed-dependent FOV
	var target_fov := fov_base + clampf(speed_kmh * fov_speed_factor, 0.0, fov_max - fov_base)
	fov = lerpf(fov, target_fov, 3.0 * delta)

	# Camera shake
	if _shake_timer > 0:
		_shake_timer -= delta
		var offset := Vector3(
			randf_range(-1, 1) * shake_intensity,
			randf_range(-1, 1) * shake_intensity * 0.5,
			0.0
		) * (_shake_timer / 0.5) # Fade out
		global_transform.origin += offset


func apply_shake(intensity: float = 0.3, duration: float = 0.3) -> void:
	shake_intensity = intensity
	_shake_timer = duration


func _on_collision(_vehicle_id: int, impact_force: float) -> void:
	if impact_force > 5.0:
		apply_shake(clampf(impact_force * 0.02, 0.1, 0.5), 0.4)


func _on_nitro(_vehicle_id: int) -> void:
	apply_shake(0.15, 0.2)


