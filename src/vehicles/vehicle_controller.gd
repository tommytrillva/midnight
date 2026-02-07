## Arcade-tuned vehicle physics controller for MIDNIGHT GRIND.
## Wraps Godot's VehicleBody3D with custom force curves, handbrake-initiated
## drift mechanics, nitro boost, auto-shifting transmission, and full
## VehicleData / EventBus integration.  Designed for fun-first feel: quick
## off the line, satisfying drifts, speed-dependent steering.
class_name VehicleController
extends VehicleBody3D

@export var vehicle_data: VehicleData = null

# ── Engine ───────────────────────────────────────────────────────────────────
@export_group("Engine")
## Base engine force per driven wheel (overridden by VehicleData).
@export var max_engine_force: float = 2500.0
## Brake force fed to VehicleBody3D.brake (rear wheels for RWD).
@export var max_brake_force: float = 120.0
## Passive deceleration force when neither throttle nor brake is held.
@export var engine_brake_force: float = 12.0
## Fraction of redline where peak torque lives (0.0-1.0).
@export var torque_peak_frac: float = 0.55

# ── Transmission ─────────────────────────────────────────────────────────────
@export_group("Transmission")
@export var gear_ratios: Array[float] = [3.4, 2.5, 1.8, 1.4, 1.1, 0.9]
@export var reverse_ratio: float = -3.2
@export var final_drive: float = 3.7
## Duration of the clutch-out dead zone during a shift (seconds).
@export var shift_time: float = 0.12
@export var auto_shift: bool = true
## RPM fraction that triggers an auto up-shift.
@export var shift_up_frac: float = 0.92
## RPM fraction that triggers an auto down-shift.
@export var shift_down_frac: float = 0.38

# ── Steering ─────────────────────────────────────────────────────────────────
@export_group("Steering")
## Maximum wheel angle at crawl speed (radians).
@export var max_steer_angle: float = 0.45
## How fast (rad/s) steering moves toward player input.
@export var steer_speed: float = 4.5
## How fast steering centres when input is released.
@export var steer_return_speed: float = 7.0
## Steering authority retained at top speed (0.3 = 30%).
@export var high_speed_steer_mult: float = 0.32

# ── Drift ────────────────────────────────────────────────────────────────────
@export_group("Drift")
## Slip angle (degrees) required to enter drift state.
@export var drift_entry_angle: float = 12.0
## Minimum speed (km/h) to start or sustain a drift.
@export var drift_min_speed: float = 25.0
## Rear friction when the handbrake is yanked (initiates slide).
@export var handbrake_friction: float = 0.9
## Rear friction during sustained drift (higher = tighter arc).
@export var drift_rear_friction: float = 1.6
## Front friction during drift (boosted for countersteer authority).
@export var drift_front_friction: float = 4.5
## Resting rear friction (recovery target after drift).
@export var normal_rear_friction: float = 4.2
## Resting front friction.
@export var normal_front_friction: float = 3.8
## Extra steering responsiveness when countersteering in a drift.
@export var countersteer_mult: float = 1.5
## Yaw-damping strength during drift (prevents spin, keeps it smooth).
@export var drift_stability: float = 4.0
## Additional yaw-damping awarded for proper countersteer input.
@export var countersteer_stability: float = 3.0
## How much throttle lowers rear friction to widen the drift (0-1).
@export var throttle_angle_push: float = 0.35
## Lerp rate for friction dropping into drift / handbrake.
@export var friction_attack: float = 10.0
## Lerp rate for friction recovering after drift ends.
@export var friction_release: float = 3.5
## Slip angle above which the drift becomes a spin-out (score lost).
@export var spinout_angle: float = 110.0

# ── Nitro ────────────────────────────────────────────────────────────────────
@export_group("Nitro")
## Engine-force multiplier while nitro is firing.
@export var nitro_force_mult: float = 1.6
## Tank capacity (set to 0 by _apply_vehicle_data if no NOS part).
@export var nitro_max: float = 100.0
## Fuel burned per second while active.
@export var nitro_drain: float = 28.0
## Fuel gained per second while drifting.
@export var nitro_drift_regen: float = 14.0
## Fuel gained per second while drafting another vehicle.
@export var nitro_draft_regen: float = 8.0
## Trickle fuel gain per second (always on).
@export var nitro_passive_regen: float = 1.5

# ── Physics ──────────────────────────────────────────────────────────────────
@export_group("Physics")
## Downforce (N) per km/h above threshold.
@export var downforce_factor: float = 1.0
## Speed threshold (km/h) where downforce starts.
@export var downforce_start: float = 40.0
## Traction-control yaw-damping (0 = disabled).
@export var tc_strength: float = 5.0
## Yaw rate (rad/s) threshold before TC intervenes (outside drift).
@export var tc_yaw_limit: float = 3.0
## Handbrake brake value sent to VehicleBody3D.
@export var handbrake_brake: float = 100.0


# ═══════════════════════════════════════════════════════════════════════════════
#  RUNTIME STATE
# ═══════════════════════════════════════════════════════════════════════════════

## Current forward gear (1-N). 0 = neutral, -1 = reverse.
var current_gear: int = 1
## Engine RPM derived from wheel speed and gear ratio.
var current_rpm: float = 0.0
## Scalar speed in km/h (magnitude of linear_velocity).
var current_speed_kmh: float = 0.0
## True during the clutch-out dead zone of a gear change.
var is_shifting: bool = false
var shift_timer: float = 0.0
## Current nitro fuel (0 .. nitro_max).
var nitro_amount: float = 0.0
## True when nitro is actively firing this frame.
var nitro_active: bool = false
## True when handbrake input is held.
var is_handbraking: bool = false
## Angle (degrees) between heading and velocity direction.
var drift_angle: float = 0.0
## True when the vehicle is in a recognised drift.
var is_drifting: bool = false
## Score accumulated during the current drift chain.
var drift_score: float = 0.0
## Sign of the drift direction (+1 tail-right, -1 tail-left).
var drift_direction: float = 0.0
## Raw input values.
var input_throttle: float = 0.0
var input_brake: float = 0.0
var input_steer: float = 0.0
## Set externally by RaceManager when another car is directly ahead.
var is_drafting: bool = false

# -- Weather ------------------------------------------------------------------
## Current weather grip multiplier (1.0 = dry, lower = slippery).
var _weather_grip: float = 1.0
## Current road wetness level (0.0-1.0) from WeatherSystem.
var _road_wetness: float = 0.0
## Hydroplaning state: true when speed + wetness cause grip loss.
var _is_hydroplaning: bool = false
## Speed threshold (km/h) above which hydroplaning risk begins on wet roads.
const HYDROPLANE_SPEED_THRESHOLD: float = 120.0
## Wetness level above which hydroplaning can occur.
const HYDROPLANE_WETNESS_THRESHOLD: float = 0.6
## Extra oversteer tendency multiplier when roads are wet.
const WET_OVERSTEER_MULT: float = 0.7

# -- Private ------------------------------------------------------------------
var _was_drifting: bool = false
var _was_nitro: bool = false
var _top_speed_kmh: float = 200.0
var _handling_mult: float = 1.0
var _skill_handling_mult: float = 1.0
var _skill_speed_mult: float = 1.0
var _damage_steer_pull: float = 0.0
var _prev_speed_bucket: int = -1
var _launch_ready: bool = false
var _launch_boost_timer: float = 0.0
var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []


# ═══════════════════════════════════════════════════════════════════════════════
#  CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

const RPM_IDLE: float = 900.0
const RPM_REDLINE_BUFFER: float = 400.0
const WHEEL_RADIUS: float = 0.33
## Hysteresis factor: drift exits at entry_angle * this.
const DRIFT_EXIT_FACTOR: float = 0.65
## km/h bucket width for the speed_changed signal (avoids per-frame spam).
const SPEED_SIGNAL_BUCKET: float = 2.0
## Minimum velocity (m/s) needed to compute a meaningful drift angle.
const MIN_VEL_FOR_ANGLE: float = 3.0
## Launch-boost force multiplier and duration.
const LAUNCH_BOOST_MULT: float = 1.4
const LAUNCH_BOOST_DURATION: float = 0.6


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_cache_wheels()
	_connect_signals()

	_top_speed_kmh = 200.0
	if vehicle_data:
		_apply_vehicle_data()

	_set_wheel_friction_now(normal_front_friction, normal_rear_friction)
	nitro_amount = nitro_max
	print("[Vehicle] Ready. Top speed: %d km/h | Force: %d N" % [
		int(_top_speed_kmh), int(max_engine_force)])


func _physics_process(delta: float) -> void:
	# ── Input ──
	_read_input()

	# ── State ──
	_update_speed()
	_update_rpm(delta)
	_update_shifting(delta)
	_update_drift(delta)
	_update_nitro(delta)

	# ── Forces ──
	_apply_steering(delta)
	_apply_engine_force(delta)
	_apply_braking(delta)
	_apply_wheel_friction(delta)
	_apply_downforce()
	_apply_drift_forces(delta)
	_apply_traction_control()

	# ── Modifiers ──
	_apply_damage_effects()
	_apply_skill_effects()
	_apply_weather_effects(delta)

	# ── Output ──
	_emit_telemetry()


# ═══════════════════════════════════════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════════════════════════════════════

func _read_input() -> void:
	input_throttle = Input.get_action_strength("accelerate")
	input_brake = Input.get_action_strength("brake")
	input_steer = Input.get_action_strength("steer_left") \
		- Input.get_action_strength("steer_right")
	is_handbraking = Input.is_action_pressed("handbrake")

	# Nitro toggle with activation / depletion signals
	var wants_nitro := Input.is_action_pressed("nitro")
	if wants_nitro and nitro_amount > 0.0 and not nitro_active:
		nitro_active = true
		EventBus.nitro_activated.emit(get_instance_id())
	elif (not wants_nitro or nitro_amount <= 0.0) and nitro_active:
		nitro_active = false

	# Manual shifting (ignored when auto_shift is true, but still wired up)
	if Input.is_action_just_pressed("shift_up"):
		shift_up()
	if Input.is_action_just_pressed("shift_down"):
		shift_down()


# ═══════════════════════════════════════════════════════════════════════════════
#  SPEED  /  RPM  /  TRANSMISSION
# ═══════════════════════════════════════════════════════════════════════════════

func _update_speed() -> void:
	current_speed_kmh = linear_velocity.length() * 3.6


func _update_rpm(delta: float) -> void:
	var max_rpm := 7000.0
	if vehicle_data:
		max_rpm = float(vehicle_data.redline_rpm)

	# During a shift the clutch is out — RPM drifts toward a mid-range idle
	if is_shifting:
		current_rpm = move_toward(current_rpm, RPM_IDLE + 800.0, 4000.0 * delta)
		return

	# Derive RPM from wheel surface speed through the drivetrain
	var wheel_rps := (current_speed_kmh / 3.6) / (TAU * WHEEL_RADIUS)

	if current_gear > 0 and current_gear <= gear_ratios.size():
		var total_ratio := gear_ratios[current_gear - 1] * final_drive
		current_rpm = wheel_rps * 60.0 * total_ratio
	elif current_gear == -1:
		current_rpm = wheel_rps * 60.0 * absf(reverse_ratio) * final_drive
	else:
		current_rpm = RPM_IDLE

	# When nearly stationary, let throttle rev the engine freely
	if current_speed_kmh < 5.0 and input_throttle > 0.1:
		var rev_target := RPM_IDLE + input_throttle * (max_rpm * 0.7 - RPM_IDLE)
		current_rpm = maxf(current_rpm, lerpf(current_rpm, rev_target, 6.0 * delta))

	current_rpm = clampf(current_rpm, RPM_IDLE, max_rpm + RPM_REDLINE_BUFFER)

	# Auto-shift
	if auto_shift and not is_shifting:
		if current_rpm >= max_rpm * shift_up_frac \
				and current_gear > 0 and current_gear < gear_ratios.size():
			shift_up()
		elif current_rpm <= max_rpm * shift_down_frac and current_gear > 1:
			shift_down()


func _update_shifting(delta: float) -> void:
	if is_shifting:
		shift_timer -= delta
		if shift_timer <= 0.0:
			is_shifting = false

	if _launch_boost_timer > 0.0:
		_launch_boost_timer -= delta


func _get_torque_curve(norm_rpm: float) -> float:
	## Bell-shaped torque multiplier peaking at torque_peak_frac.
	## Returns 0.3 .. 1.0 — keeps some power even outside the sweet spot
	## so the car never feels completely dead at any RPM.
	var x := (norm_rpm - torque_peak_frac) / 0.45
	return clampf(1.0 - x * x * 0.6, 0.3, 1.0)


func shift_up() -> void:
	if current_gear < gear_ratios.size() and not is_shifting:
		current_gear += 1
		is_shifting = true
		shift_timer = shift_time
		EventBus.gear_shifted.emit(get_instance_id(), current_gear)


func shift_down() -> void:
	if current_gear > 1 and not is_shifting:
		current_gear -= 1
		is_shifting = true
		shift_timer = shift_time
		EventBus.gear_shifted.emit(get_instance_id(), current_gear)


# ═══════════════════════════════════════════════════════════════════════════════
#  STEERING
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_steering(delta: float) -> void:
	# Speed-dependent authority: full at crawl, reduced at vmax
	var speed_ratio := clampf(current_speed_kmh / maxf(_top_speed_kmh, 1.0), 0.0, 1.0)
	var speed_steer := lerpf(1.0, high_speed_steer_mult, speed_ratio)

	# Handling stat + skill modifier
	var handling := clampf(_handling_mult * _skill_handling_mult, 0.4, 1.8)

	var effective_angle := max_steer_angle * speed_steer * handling
	var target_steer := input_steer * effective_angle

	# Countersteer boost during drift — snappier response when steering
	# into the slide lets the player sustain the drift more easily.
	if is_drifting and _is_countersteering():
		var boost := (countersteer_mult - 1.0) * absf(input_steer)
		target_steer *= (1.0 + boost)

	# Damage-induced pull (oscillating, worsens with damage %)
	target_steer += _damage_steer_pull

	# Smooth interpolation toward target
	var interp := steer_speed if absf(input_steer) > 0.05 else steer_return_speed
	steering = move_toward(steering, target_steer, interp * delta)


# ═══════════════════════════════════════════════════════════════════════════════
#  ENGINE FORCE
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_engine_force(delta: float) -> void:
	if is_shifting:
		engine_force = 0.0
		return

	# Arcade power curve: quadratic fall-off toward top speed gives a
	# strong launch that tapers naturally instead of a hard limiter.
	var top := maxf(_top_speed_kmh, 1.0)
	if nitro_active:
		top *= 1.15  # nitro lets you push past normal vmax slightly

	var speed_ratio := clampf(current_speed_kmh / top, 0.0, 1.0)
	var power_curve := maxf(1.0 - speed_ratio * speed_ratio, 0.0)

	# Torque-band feel from RPM position
	var max_rpm := 7000.0
	if vehicle_data:
		max_rpm = float(vehicle_data.redline_rpm)
	var norm_rpm := clampf(current_rpm / maxf(max_rpm, 1.0), 0.0, 1.0)
	var torque_mult := _get_torque_curve(norm_rpm)

	# Lower gears multiply torque at the wheel (simple arcade model)
	var gear_mult := 1.0
	if current_gear > 0 and current_gear <= gear_ratios.size():
		var t := float(current_gear - 1) / maxf(float(gear_ratios.size() - 1), 1.0)
		gear_mult = lerpf(1.3, 0.85, t)

	var force := input_throttle * max_engine_force * power_curve * torque_mult * gear_mult

	# Skill speed bonus
	force *= _skill_speed_mult

	# Nitro
	if nitro_active:
		force *= nitro_force_mult

	# Launch boost (brief burst awarded for holding throttle through countdown)
	if _launch_boost_timer > 0.0:
		force *= LAUNCH_BOOST_MULT

	# Reverse (capped power, inverted)
	if current_gear == -1:
		force = -input_throttle * max_engine_force * 0.35

	engine_force = force


# ═══════════════════════════════════════════════════════════════════════════════
#  BRAKING
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_braking(_delta: float) -> void:
	var brake_val := 0.0

	if is_handbraking:
		brake_val = handbrake_brake
	elif input_brake > 0.05:
		brake_val = input_brake * max_brake_force
		# VehicleBody3D.brake only acts on driven (rear) wheels.  Apply a
		# supplemental central force so front brakes contribute too.
		if current_speed_kmh > 2.0:
			var front_force := -linear_velocity.normalized() \
				* input_brake * max_brake_force * 8.0
			apply_central_force(front_force)
	elif input_throttle < 0.05:
		# Engine braking — gentle drag when coasting
		brake_val = engine_brake_force
		if current_speed_kmh > 5.0:
			apply_central_force(
				-linear_velocity.normalized() * engine_brake_force * 3.0)

	self.brake = brake_val


# ═══════════════════════════════════════════════════════════════════════════════
#  DRIFT SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

func _update_drift(delta: float) -> void:
	_was_drifting = is_drifting

	# Need minimum velocity for a meaningful slip angle
	if linear_velocity.length() < MIN_VEL_FOR_ANGLE:
		if is_drifting:
			_end_drift(false)
		drift_angle = 0.0
		return

	# Angle between car's forward vector and its actual velocity
	var forward := -global_transform.basis.z.normalized()
	var vel_dir := linear_velocity.normalized()
	drift_angle = rad_to_deg(acosf(clampf(forward.dot(vel_dir), -1.0, 1.0)))

	# Direction: which side is the tail swinging toward
	var cross_y := forward.cross(vel_dir).y
	if absf(cross_y) > 0.01:
		drift_direction = signf(cross_y)

	# ── State machine ──
	if not is_drifting:
		# ENTRY: angle exceeds threshold at sufficient speed
		if drift_angle > drift_entry_angle and current_speed_kmh > drift_min_speed:
			is_drifting = true
			drift_score = 0.0
			EventBus.drift_started.emit(get_instance_id())
			print("[Vehicle] Drift started — %.0f deg @ %.0f km/h" % [
				drift_angle, current_speed_kmh])
	else:
		# EXIT conditions (hysteresis prevents flicker at the boundary)
		var exit_angle := drift_entry_angle * DRIFT_EXIT_FACTOR
		var exit_speed := drift_min_speed * 0.8

		if drift_angle < exit_angle or current_speed_kmh < exit_speed:
			_end_drift(false)
		elif drift_angle > spinout_angle:
			_end_drift(true)
		else:
			# Score accumulates while the drift is alive
			drift_score += drift_angle * current_speed_kmh * 0.001 * delta


func _end_drift(spun_out: bool) -> void:
	if not is_drifting:
		return
	is_drifting = false
	var final_score := 0.0 if spun_out else drift_score
	EventBus.drift_ended.emit(get_instance_id(), final_score)
	if spun_out:
		print("[Vehicle] Spin-out! Drift score lost.")
	else:
		print("[Vehicle] Drift ended — score: %.1f" % final_score)
	drift_score = 0.0


func _apply_wheel_friction(delta: float) -> void:
	## Dynamically adjusts per-wheel friction to create drift feel.
	## Handbrake -> sharp rear grip loss.  Sustained drift -> moderate rear
	## loss with boosted front for countersteer.  Recovery -> smooth return.
	var target_front := normal_front_friction
	var target_rear := normal_rear_friction
	var lerp_speed := friction_release * _handling_mult * _skill_handling_mult

	if is_handbraking and current_speed_kmh > 10.0:
		target_rear = handbrake_friction
		lerp_speed = friction_attack
	elif is_drifting:
		# Throttle input pushes rear friction lower = wider drift angle
		var throttle_loss := throttle_angle_push * input_throttle
		target_rear = lerpf(drift_rear_friction, handbrake_friction, throttle_loss)
		target_front = drift_front_friction
		lerp_speed = friction_attack

	for w: VehicleWheel3D in _front_wheels:
		w.wheel_friction_slip = lerpf(
			w.wheel_friction_slip, target_front, lerp_speed * delta)
	for w: VehicleWheel3D in _rear_wheels:
		w.wheel_friction_slip = lerpf(
			w.wheel_friction_slip, target_rear, lerp_speed * delta)


func _apply_drift_forces(_delta: float) -> void:
	## Yaw-damping during drift prevents uncontrollable spins while still
	## feeling loose.  Countersteering awards extra stability so skilled
	## players can sustain long, smooth arcs.
	if not is_drifting:
		return

	var damping := drift_stability
	if _is_countersteering():
		damping += countersteer_stability * absf(input_steer)

	var correction := -angular_velocity.y * damping
	apply_torque(Vector3(0.0, correction, 0.0))


func _is_countersteering() -> bool:
	## True when the player steers INTO the slide (correct drift input).
	## drift_direction +1 = tail swings right of velocity, countersteer =
	## steer right = positive input_steer matches positive drift_direction.
	return absf(input_steer) > 0.1 \
		and signf(input_steer) == signf(drift_direction)


# ═══════════════════════════════════════════════════════════════════════════════
#  NITRO
# ═══════════════════════════════════════════════════════════════════════════════

func _update_nitro(delta: float) -> void:
	# Drain while firing
	if nitro_active and nitro_amount > 0.0:
		nitro_amount -= nitro_drain * delta
		if nitro_amount <= 0.0:
			nitro_amount = 0.0
			nitro_active = false
			EventBus.nitro_depleted.emit(get_instance_id())

	# Regeneration (stacks: passive + drift + drafting)
	var regen := nitro_passive_regen
	if is_drifting:
		regen += nitro_drift_regen
	if is_drafting:
		regen += nitro_draft_regen

	if nitro_amount < nitro_max:
		nitro_amount = minf(nitro_amount + regen * delta, nitro_max)


# ═══════════════════════════════════════════════════════════════════════════════
#  PHYSICS HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_downforce() -> void:
	if current_speed_kmh > downforce_start:
		var force := (current_speed_kmh - downforce_start) * downforce_factor
		apply_central_force(Vector3.DOWN * force)


func _apply_traction_control() -> void:
	## Damps yaw when NOT drifting to prevent accidental spins from
	## bumps, kerbs, or aggressive inputs.  Disabled during drift so
	## the slide feels free.
	if is_drifting or is_handbraking or tc_strength <= 0.0:
		return

	var yaw := absf(angular_velocity.y)
	if yaw > tc_yaw_limit:
		var overshoot := yaw - tc_yaw_limit
		var correction := -signf(angular_velocity.y) * overshoot * tc_strength
		apply_torque(Vector3(0.0, correction, 0.0))


# ═══════════════════════════════════════════════════════════════════════════════
#  VEHICLE-DATA  /  DAMAGE  /  SKILL INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_vehicle_data() -> void:
	## Derives concrete physics values from the abstract VehicleData stats.
	if vehicle_data == null:
		return

	var stats := vehicle_data.get_effective_stats()

	# Force / speed / handling from stats
	max_engine_force = stats.acceleration * 40.0 + stats.hp * 5.0
	max_brake_force = stats.braking * 2.5 + 30.0
	_top_speed_kmh = stats.speed * 2.0 + 50.0
	_handling_mult = clampf(stats.handling / 50.0, 0.4, 2.0)
	mass = stats.weight

	# Nitro only available when an NOS part is installed
	var nos_part: String = vehicle_data.installed_parts.get("nitrous", "")
	var has_nos := not nos_part.is_empty() and nos_part != "nitrous_none"
	nitro_max = 100.0 if has_nos else 0.0
	nitro_amount = nitro_max

	print("[Vehicle] Stats applied — force:%d brake:%d top:%d handling:%.2f mass:%d nos:%s" % [
		int(max_engine_force), int(max_brake_force), int(_top_speed_kmh),
		_handling_mult, int(mass), str(has_nos)])


func _apply_damage_effects() -> void:
	## Damage above 20% introduces a subtle oscillating steering pull
	## that worsens as damage climbs.  Communicates "your car is hurt"
	## without making it unplayable.
	if vehicle_data == null:
		_damage_steer_pull = 0.0
		return

	if vehicle_data.damage_percentage > 20.0:
		var severity := (vehicle_data.damage_percentage - 20.0) / 80.0
		_damage_steer_pull = sin(
			Time.get_ticks_msec() * 0.002) * severity * 0.03
	else:
		_damage_steer_pull = 0.0


func _apply_skill_effects() -> void:
	## Reads handling and speed multipliers from the skill tree so
	## late-game characters feel noticeably better.
	if GameManager.skills == null:
		_skill_handling_mult = 1.0
		_skill_speed_mult = 1.0
		return

	_skill_handling_mult = GameManager.skills.get_stat_multiplier("handling")
	_skill_speed_mult = GameManager.skills.get_stat_multiplier("speed")


# ═══════════════════════════════════════════════════════════════════════════════
#  TELEMETRY  /  EVENT-BUS OUTPUT
# ═══════════════════════════════════════════════════════════════════════════════

func _emit_telemetry() -> void:
	# Speed — bucketed so we emit ~every 2 km/h instead of every frame
	var bucket := int(current_speed_kmh / SPEED_SIGNAL_BUCKET)
	if bucket != _prev_speed_bucket:
		_prev_speed_bucket = bucket
		EventBus.speed_changed.emit(get_instance_id(), current_speed_kmh)

	# Tire screech intensity for audio / VFX
	if is_drifting or (is_handbraking and current_speed_kmh > 15.0):
		var intensity := clampf(drift_angle / 50.0, 0.2, 1.0)
		EventBus.tire_screech.emit(get_instance_id(), intensity)

	# Nitro flame VFX toggle
	if nitro_active != _was_nitro:
		EventBus.nitro_flame.emit(get_instance_id(), nitro_active)
		_was_nitro = nitro_active


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func setup_from_data(data: VehicleData) -> void:
	## Hot-swap vehicle data at runtime (e.g. entering a different car).
	vehicle_data = data
	_apply_vehicle_data()
	_set_wheel_friction_now(normal_front_friction, normal_rear_friction)


func get_drift_score() -> float:
	return drift_score


func reset_drift_score() -> void:
	drift_score = 0.0


func set_drafting(value: bool) -> void:
	## Call from RaceManager when another car is directly ahead.
	is_drafting = value


# ═══════════════════════════════════════════════════════════════════════════════
#  WEATHER INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_weather_effects(_delta: float) -> void:
	## Reads weather data from WeatherSystem (via GameManager) and applies
	## grip reduction, wet oversteer tendency, and hydroplaning.

	# Fetch weather grip from WeatherSystem if available
	_weather_grip = 1.0
	_road_wetness = 0.0

	if GameManager.has_node("WeatherSystem"):
		var weather_sys: Node = GameManager.get_node("WeatherSystem")
		if weather_sys.has_method("get_grip_multiplier"):
			_weather_grip = weather_sys.get_grip_multiplier()
		if weather_sys.has_method("get_rain_intensity"):
			_road_wetness = weather_sys.get_rain_intensity()
	elif GameManager.has_node("WorldTimeSystem"):
		# Fallback to WorldTimeSystem grip data
		var world_time: Node = GameManager.get_node("WorldTimeSystem")
		if world_time.has_method("get_grip_multiplier"):
			_weather_grip = world_time.get_grip_multiplier()

	# Apply grip reduction to wheel friction
	if _weather_grip < 1.0:
		for w: VehicleWheel3D in _front_wheels:
			w.wheel_friction_slip *= _weather_grip
		for w: VehicleWheel3D in _rear_wheels:
			w.wheel_friction_slip *= _weather_grip

	# Wet oversteer: reduce rear friction more than front when wet
	if _road_wetness > 0.1 and not is_drifting:
		var wet_factor := _road_wetness * WET_OVERSTEER_MULT
		for w: VehicleWheel3D in _rear_wheels:
			w.wheel_friction_slip *= (1.0 - wet_factor * 0.15)

	# Hydroplaning: at high speed on very wet roads, brief total grip loss
	_update_hydroplaning()


func _update_hydroplaning() -> void:
	## Checks for hydroplaning conditions: high speed + heavy wetness.
	## Hydroplaning causes a sudden severe grip reduction.
	var was_hydroplaning := _is_hydroplaning

	if _road_wetness >= HYDROPLANE_WETNESS_THRESHOLD \
			and current_speed_kmh >= HYDROPLANE_SPEED_THRESHOLD:
		# Chance of hydroplaning scales with speed and wetness
		var risk := (_road_wetness - HYDROPLANE_WETNESS_THRESHOLD) \
			/ (1.0 - HYDROPLANE_WETNESS_THRESHOLD)
		var speed_risk := (current_speed_kmh - HYDROPLANE_SPEED_THRESHOLD) / 80.0
		var total_risk := clampf(risk * speed_risk * 0.02, 0.0, 0.05)

		if not _is_hydroplaning and randf() < total_risk:
			_is_hydroplaning = true
			print("[Vehicle] Hydroplaning!")
		elif _is_hydroplaning and current_speed_kmh < HYDROPLANE_SPEED_THRESHOLD * 0.9:
			_is_hydroplaning = false
	else:
		_is_hydroplaning = false

	# Apply hydroplaning grip loss
	if _is_hydroplaning:
		var hydro_grip := 0.3  # Severe grip loss
		for w: VehicleWheel3D in _front_wheels:
			w.wheel_friction_slip *= hydro_grip
		for w: VehicleWheel3D in _rear_wheels:
			w.wheel_friction_slip *= hydro_grip

	if _is_hydroplaning != was_hydroplaning:
		if _is_hydroplaning:
			print("[Vehicle] Hydroplaning started at %.0f km/h" % current_speed_kmh)
		else:
			print("[Vehicle] Hydroplaning ended")


# ═══════════════════════════════════════════════════════════════════════════════
#  PRIVATE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _cache_wheels() -> void:
	for child in get_children():
		if child is VehicleWheel3D:
			var w := child as VehicleWheel3D
			if w.use_as_steering:
				_front_wheels.append(w)
			if w.use_as_traction:
				_rear_wheels.append(w)
	print("[Vehicle] Wheels cached: %d front, %d rear" % [
		_front_wheels.size(), _rear_wheels.size()])


func _connect_signals() -> void:
	EventBus.race_countdown_tick.connect(_on_race_countdown)
	EventBus.race_started.connect(_on_race_started)


func _set_wheel_friction_now(front: float, rear: float) -> void:
	for w: VehicleWheel3D in _front_wheels:
		w.wheel_friction_slip = front
	for w: VehicleWheel3D in _rear_wheels:
		w.wheel_friction_slip = rear


func _on_race_countdown(count: int) -> void:
	if count <= 3:
		_launch_ready = true


func _on_race_started(_race_data: Dictionary) -> void:
	if _launch_ready and input_throttle > 0.8:
		_launch_boost_timer = LAUNCH_BOOST_DURATION
		print("[Vehicle] Perfect launch!")
	_launch_ready = false
