## Specialized camera for cutscenes and scripted sequences.
## Provides cinematic camera movements: pan, dolly, orbit, crane, shake, focus.
## Uses tweens internally for smooth interpolation with configurable easing.
## Separate from the gameplay chase camera (CameraController).
class_name CinematicCamera
extends Camera3D

## Emitted when a camera move finishes.
signal move_completed(move_type: String)

## The node being tracked by focus_on, or null.
var _focus_target: Node3D = null

## Active tween for the current camera move.
var _tween: Tween = null

## Shake state
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _shake_origin: Vector3 = Vector3.ZERO

## Depth of field
var _dof_tween: Tween = null

## Whether we are currently tracking a focus target each frame.
var _tracking: bool = false

## Default transition type
var _default_ease: Tween.EaseType = Tween.EASE_IN_OUT
var _default_trans: Tween.TransitionType = Tween.TRANS_CUBIC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[Camera] CinematicCamera ready.")


func _process(delta: float) -> void:
	# Track focus target each frame
	if _tracking and _focus_target and is_instance_valid(_focus_target):
		look_at(_focus_target.global_position, Vector3.UP)

	# Camera shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var decay := clampf(_shake_timer / 0.5, 0.0, 1.0)
		var offset := Vector3(
			randf_range(-1.0, 1.0) * _shake_intensity,
			randf_range(-1.0, 1.0) * _shake_intensity * 0.6,
			randf_range(-1.0, 1.0) * _shake_intensity * 0.3
		) * decay
		global_position = _shake_origin + offset
	elif _shake_timer <= 0.0 and _shake_intensity > 0.0:
		# Shake ended, snap back to origin
		global_position = _shake_origin
		_shake_intensity = 0.0


# ---------------------------------------------------------------------------
# Public API -- Camera Moves
# ---------------------------------------------------------------------------

## Smooth pan from current position to target position over duration.
func pan_to(target: Vector3, duration: float, ease_type: String = "ease_in_out") -> void:
	_kill_tween()
	var easing := _parse_ease(ease_type)

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "global_position", target, duration) \
		.set_ease(easing.ease).set_trans(easing.trans)
	await _tween.finished
	move_completed.emit("pan")
	print("[Camera] Pan complete.")


## Dolly (move toward/away from look direction) by distance over duration.
## Positive distance = move forward, negative = move backward.
func dolly(distance: float, duration: float, ease_type: String = "ease_in_out") -> void:
	_kill_tween()
	var easing := _parse_ease(ease_type)
	var direction := -global_transform.basis.z.normalized()
	var target_pos := global_position + direction * distance

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "global_position", target_pos, duration) \
		.set_ease(easing.ease).set_trans(easing.trans)
	await _tween.finished
	move_completed.emit("dolly")
	print("[Camera] Dolly complete.")


## Orbital movement around a target point by angle degrees over duration.
func orbit(target: Vector3, angle_deg: float, duration: float, ease_type: String = "ease_in_out") -> void:
	_kill_tween()
	var easing := _parse_ease(ease_type)

	var start_pos := global_position
	var offset := start_pos - target
	var radius := Vector2(offset.x, offset.z).length()
	var start_angle := atan2(offset.z, offset.x)
	var end_angle := start_angle + deg_to_rad(angle_deg)
	var height := start_pos.y

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(
		func(t: float) -> void:
			var current_angle := lerpf(start_angle, end_angle, t)
			var x := target.x + cos(current_angle) * radius
			var z := target.z + sin(current_angle) * radius
			global_position = Vector3(x, height, z)
			look_at(target, Vector3.UP),
		0.0, 1.0, duration
	).set_ease(easing.ease).set_trans(easing.trans)
	await _tween.finished
	move_completed.emit("orbit")
	print("[Camera] Orbit complete.")


## Crane the camera up or down by height units over duration.
## Positive height = up, negative = down.
func crane(height: float, duration: float, ease_type: String = "ease_in_out") -> void:
	_kill_tween()
	var easing := _parse_ease(ease_type)
	var target_pos := global_position + Vector3(0.0, height, 0.0)

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "global_position", target_pos, duration) \
		.set_ease(easing.ease).set_trans(easing.trans)
	await _tween.finished
	move_completed.emit("crane")
	print("[Camera] Crane complete.")


## Camera shake with given intensity and duration.
func shake(intensity: float, duration: float) -> void:
	_shake_origin = global_position
	_shake_intensity = intensity
	_shake_timer = duration
	print("[Camera] Shake: intensity=%.2f, duration=%.1fs" % [intensity, duration])
	# Don't await -- shake runs in _process and doesn't block the sequence.


## Start tracking a target node. Camera will face the target each frame.
## Duration is the time to smooth-move to the initial look direction.
func focus_on(target: Node3D, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		push_warning("[Camera] focus_on: invalid target node.")
		return

	_focus_target = target
	_tracking = true

	if duration > 0.0:
		# Smooth transition to face the target
		var start_basis := global_transform.basis
		look_at(target.global_position, Vector3.UP)
		var end_basis := global_transform.basis
		global_transform.basis = start_basis

		_kill_tween()
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween.tween_method(
			func(t: float) -> void:
				global_transform.basis = start_basis.slerp(end_basis, t),
			0.0, 1.0, duration
		).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		await _tween.finished

	move_completed.emit("focus")
	print("[Camera] Focus on: %s" % target.name)


## Stop tracking the current focus target.
func clear_focus() -> void:
	_focus_target = null
	_tracking = false
	print("[Camera] Focus cleared.")


## Set depth of field (requires WorldEnvironment with DOF enabled).
func set_dof(focal_distance: float, blur: float) -> void:
	# DOF is controlled via the camera's attributes or environment.
	# We store values that a post-process setup can read.
	set_meta("dof_focal_distance", focal_distance)
	set_meta("dof_blur_amount", blur)
	print("[Camera] DOF set: focal=%.1f, blur=%.2f" % [focal_distance, blur])


## Move camera along a path defined by an array of Vector3 waypoints.
func follow_path(points: Array, duration: float, look_target: Vector3 = Vector3.INF, ease_type: String = "ease_in_out") -> void:
	if points.size() < 2:
		push_warning("[Camera] follow_path requires at least 2 points.")
		return

	_kill_tween()
	var easing := _parse_ease(ease_type)
	var has_look_target := look_target != Vector3.INF

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	var segment_duration := duration / float(points.size() - 1)
	for i in range(1, points.size()):
		_tween.tween_property(self, "global_position", points[i], segment_duration) \
			.set_ease(easing.ease).set_trans(easing.trans)

	if has_look_target:
		# Continuously face the look target
		_tween.parallel().tween_method(
			func(_t: float) -> void:
				look_at(look_target, Vector3.UP),
			0.0, 1.0, duration
		)

	await _tween.finished
	move_completed.emit("path")
	print("[Camera] Path follow complete.")


## Instantly teleport the camera (no animation).
func teleport(position: Vector3, look_at_target: Vector3 = Vector3.INF) -> void:
	global_position = position
	if look_at_target != Vector3.INF:
		look_at(look_at_target, Vector3.UP)
	print("[Camera] Teleported to %s" % str(position))


## Smoothly blend from the cinematic camera back to a gameplay camera.
func blend_to_camera(target_camera: Camera3D, duration: float) -> void:
	if target_camera == null:
		push_warning("[Camera] blend_to_camera: target is null.")
		return

	_kill_tween()
	var start_pos := global_position
	var start_basis := global_transform.basis
	var end_pos := target_camera.global_position
	var end_basis := target_camera.global_transform.basis

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(
		func(t: float) -> void:
			global_position = start_pos.lerp(end_pos, t)
			global_transform.basis = start_basis.slerp(end_basis, t),
		0.0, 1.0, duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	await _tween.finished

	# Hand off to the target camera
	target_camera.make_current()
	print("[Camera] Blended to gameplay camera.")


## Stop any active camera move immediately.
func stop() -> void:
	_kill_tween()
	_shake_timer = 0.0
	_shake_intensity = 0.0
	_tracking = false
	_focus_target = null


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


## Parse an ease string into ease + transition types.
func _parse_ease(ease_str: String) -> Dictionary:
	match ease_str:
		"ease_in":
			return {"ease": Tween.EASE_IN, "trans": Tween.TRANS_CUBIC}
		"ease_out":
			return {"ease": Tween.EASE_OUT, "trans": Tween.TRANS_CUBIC}
		"ease_in_out":
			return {"ease": Tween.EASE_IN_OUT, "trans": Tween.TRANS_CUBIC}
		"linear":
			return {"ease": Tween.EASE_IN_OUT, "trans": Tween.TRANS_LINEAR}
		"bounce":
			return {"ease": Tween.EASE_OUT, "trans": Tween.TRANS_BOUNCE}
		"elastic":
			return {"ease": Tween.EASE_OUT, "trans": Tween.TRANS_ELASTIC}
		_:
			return {"ease": _default_ease, "trans": _default_trans}
