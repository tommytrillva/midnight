## Controls street lights, traffic lights, and vehicle headlights.
## Street lights use warm sodium vapor color, turn on at dusk, off at dawn.
## Some lights are broken/flickering for atmosphere.
class_name StreetLightController
extends Node

# --- Configuration ---
const SODIUM_VAPOR_COLOR := Color(1.0, 0.8, 0.4)
const SODIUM_VAPOR_DIM := Color(0.8, 0.6, 0.3)
const BROKEN_LIGHT_CHANCE := 0.1  # 10% of street lights are broken
const TRAFFIC_CYCLE_DURATION := 8.0  # Seconds per traffic light phase

# Traffic light colors
const TRAFFIC_RED := Color(1.0, 0.1, 0.1)
const TRAFFIC_YELLOW := Color(1.0, 0.85, 0.1)
const TRAFFIC_GREEN := Color(0.1, 1.0, 0.3)

# Headlight configuration
const HEADLIGHT_COLOR := Color(1.0, 0.97, 0.9)
const HEADLIGHT_INTENSITY := 3.0
const HEADLIGHT_RANGE := 40.0
const HEADLIGHT_SPOT_ANGLE := 30.0

# --- State ---
var _street_lights: Array[Node] = []
var _traffic_lights: Array[Node] = []
var _broken_lights: Array[Node] = []
var _vehicle_headlights: Dictionary = {}  # vehicle_node -> [left_light, right_light]

var _lights_enabled: bool = true
var _target_enabled: bool = true
var _light_base_energies: Dictionary = {}  # Node -> original energy
var _initialized: bool = false

# Broken light flicker state
var _broken_states: Dictionary = {}  # Node -> { timer, on, next_flip }

# Traffic light state
var _traffic_timer: float = 0.0
var _traffic_phase: int = 0  # 0=green, 1=yellow, 2=red

# Headlight state
var _headlights_active: bool = false


func _ready() -> void:
	await get_tree().process_frame
	_find_street_lights()
	_find_traffic_lights()
	_initialized = true

	EventBus.headlights_needed_changed.connect(_on_headlights_needed_changed)
	EventBus.district_entered.connect(_on_district_entered)

	print("[Lights] StreetLightController ready. Street: %d, Traffic: %d" % [
		_street_lights.size(), _traffic_lights.size()
	])


func _process(delta: float) -> void:
	if not _initialized:
		return

	# Process broken light flickers
	_process_broken_lights(delta)

	# Process traffic light cycling
	_process_traffic_lights(delta)

	# Process headlight wet-road scatter
	_process_headlight_scatter()


# --- Public API ---

func set_lights_enabled(enabled: bool) -> void:
	## Turn street lights on or off. Called by DayNightCycle.
	if _target_enabled == enabled:
		return

	_target_enabled = enabled

	if enabled:
		_activate_street_lights()
	else:
		_deactivate_street_lights()


func is_lights_on() -> bool:
	return _lights_enabled


func register_vehicle_headlights(vehicle: Node3D) -> void:
	## Register a vehicle node to have headlights created and managed.
	if vehicle in _vehicle_headlights:
		return

	var left_light := _create_headlight(vehicle, Vector3(-0.7, 0.5, -2.0), "HeadlightL")
	var right_light := _create_headlight(vehicle, Vector3(0.7, 0.5, -2.0), "HeadlightR")
	_vehicle_headlights[vehicle] = [left_light, right_light]

	# Set initial state
	left_light.visible = _headlights_active
	right_light.visible = _headlights_active

	print("[Lights] Registered headlights for vehicle: %s" % vehicle.name)


func unregister_vehicle_headlights(vehicle: Node3D) -> void:
	## Remove headlights from a vehicle.
	if vehicle not in _vehicle_headlights:
		return

	var lights: Array = _vehicle_headlights[vehicle]
	for light in lights:
		if is_instance_valid(light):
			light.queue_free()
	_vehicle_headlights.erase(vehicle)


func set_headlights_active(active: bool) -> void:
	## Enable or disable all registered vehicle headlights.
	_headlights_active = active

	for vehicle in _vehicle_headlights:
		var lights: Array = _vehicle_headlights[vehicle]
		for light in lights:
			if is_instance_valid(light):
				light.visible = active
				if light is SpotLight3D:
					light.light_energy = HEADLIGHT_INTENSITY if active else 0.0


# --- Street Light Discovery ---

func _find_street_lights() -> void:
	## Find all street lights in the "street_lights" group.
	_street_lights.clear()
	_light_base_energies.clear()
	_broken_lights.clear()

	var group_nodes := get_tree().get_nodes_in_group("street_lights")
	for node in group_nodes:
		_street_lights.append(node)

		# Cache original energy
		if node is Light3D:
			_light_base_energies[node] = node.light_energy

			# Randomly mark some as broken
			if randf() < BROKEN_LIGHT_CHANCE:
				_broken_lights.append(node)
				_broken_states[node] = {
					"timer": 0.0,
					"on": true,
					"next_flip": randf_range(2.0, 10.0),
				}

	# If no grouped lights found, also search for OmniLight3D children
	# under nodes named "StreetLights" for backward compatibility
	if _street_lights.is_empty():
		_find_street_lights_by_name()


func _find_street_lights_by_name() -> void:
	## Fallback: find street lights by parent node name.
	var scene := get_tree().current_scene
	if not scene:
		return

	var street_light_parents := _find_nodes_by_name(scene, "StreetLights")
	for parent in street_light_parents:
		for child in parent.get_children():
			if child is OmniLight3D or child is SpotLight3D:
				# Skip neon signs (they have non-sodium colors)
				if child.name.begins_with("Neon"):
					continue

				_street_lights.append(child)
				_light_base_energies[child] = child.light_energy

				if randf() < BROKEN_LIGHT_CHANCE:
					_broken_lights.append(child)
					_broken_states[child] = {
						"timer": 0.0,
						"on": true,
						"next_flip": randf_range(2.0, 10.0),
					}

	if _street_lights.size() > 0:
		print("[Lights] Found %d street lights by name search" % _street_lights.size())


func _find_nodes_by_name(root: Node, target_name: String) -> Array[Node]:
	var results: Array[Node] = []
	if root.name == target_name:
		results.append(root)
	for child in root.get_children():
		results.append_array(_find_nodes_by_name(child, target_name))
	return results


func _find_traffic_lights() -> void:
	## Find all traffic lights in the "traffic_lights" group.
	_traffic_lights = []
	var group_nodes := get_tree().get_nodes_in_group("traffic_lights")
	for node in group_nodes:
		_traffic_lights.append(node)


# --- Street Light Activation ---

func _activate_street_lights() -> void:
	## Turn on all street lights with a warm-up effect.
	_lights_enabled = true
	print("[Lights] Street lights activating")

	for light in _street_lights:
		if not is_instance_valid(light):
			continue
		if light in _broken_lights:
			continue  # Broken lights handled separately

		if light is Light3D:
			var base_energy: float = _light_base_energies.get(light, 2.0)
			light.visible = true

			# Warm-up tween: starts dim, ramps to full
			var tween := create_tween()
			light.light_energy = 0.0
			var delay := randf_range(0.0, 1.5)
			tween.tween_interval(delay)
			tween.tween_property(light, "light_energy", base_energy * 0.3, 0.1)
			tween.tween_property(light, "light_energy", base_energy * 0.1, 0.1)
			tween.tween_property(light, "light_energy", base_energy * 0.7, 0.2)
			tween.tween_property(light, "light_energy", base_energy, 0.5)


func _deactivate_street_lights() -> void:
	## Turn off all street lights.
	_lights_enabled = false
	print("[Lights] Street lights deactivating")

	for light in _street_lights:
		if not is_instance_valid(light):
			continue

		if light is Light3D:
			var tween := create_tween()
			tween.tween_property(light, "light_energy", 0.0, 1.0)
			tween.tween_callback(func() -> void:
				if is_instance_valid(light):
					light.visible = false
			)


# --- Broken Light Processing ---

func _process_broken_lights(delta: float) -> void:
	## Update flicker state for all broken street lights.
	for light in _broken_lights:
		if not is_instance_valid(light):
			continue
		if not _lights_enabled:
			if light is Light3D:
				light.light_energy = 0.0
			continue

		var state: Dictionary = _broken_states.get(light, {})
		if state.is_empty():
			continue

		state["timer"] += delta
		if state["timer"] >= state["next_flip"]:
			state["timer"] = 0.0
			state["on"] = not state["on"]

			if state["on"]:
				state["next_flip"] = randf_range(0.5, 6.0)
			else:
				# Short off periods (buzzing) or long dead periods
				if randf() < 0.7:
					state["next_flip"] = randf_range(0.03, 0.15)  # Quick buzz
				else:
					state["next_flip"] = randf_range(1.0, 5.0)   # Long dead

			_broken_states[light] = state

		if light is Light3D:
			var base_energy: float = _light_base_energies.get(light, 2.0)
			if state["on"]:
				light.light_energy = base_energy * randf_range(0.5, 0.9)
				light.light_color = SODIUM_VAPOR_DIM
			else:
				light.light_energy = base_energy * randf_range(0.0, 0.05)


# --- Traffic Light Processing ---

func _process_traffic_lights(delta: float) -> void:
	## Cycle traffic lights through red/yellow/green (cosmetic only).
	if _traffic_lights.is_empty():
		return

	_traffic_timer += delta

	var phase_duration: float
	match _traffic_phase:
		0:  # Green
			phase_duration = TRAFFIC_CYCLE_DURATION * 0.5
		1:  # Yellow
			phase_duration = TRAFFIC_CYCLE_DURATION * 0.15
		2:  # Red
			phase_duration = TRAFFIC_CYCLE_DURATION * 0.35
		_:
			phase_duration = TRAFFIC_CYCLE_DURATION * 0.35

	if _traffic_timer >= phase_duration:
		_traffic_timer = 0.0
		_traffic_phase = (_traffic_phase + 1) % 3

		var color: Color
		match _traffic_phase:
			0: color = TRAFFIC_GREEN
			1: color = TRAFFIC_YELLOW
			2: color = TRAFFIC_RED
			_: color = TRAFFIC_RED

		for light in _traffic_lights:
			if is_instance_valid(light) and light is Light3D:
				light.light_color = color


# --- Headlight Creation ---

func _create_headlight(vehicle: Node3D, local_pos: Vector3, light_name: String) -> SpotLight3D:
	## Create a SpotLight3D headlight attached to a vehicle.
	var headlight := SpotLight3D.new()
	headlight.name = light_name
	headlight.light_color = HEADLIGHT_COLOR
	headlight.light_energy = HEADLIGHT_INTENSITY
	headlight.spot_range = HEADLIGHT_RANGE
	headlight.spot_angle = HEADLIGHT_SPOT_ANGLE
	headlight.spot_attenuation = 0.8
	headlight.shadow_enabled = true
	headlight.light_bake_mode = Light3D.BAKE_DISABLED

	# Position relative to vehicle
	headlight.position = local_pos
	# Point forward and slightly down
	headlight.rotation_degrees = Vector3(-10, 0, 0)

	vehicle.add_child(headlight)
	return headlight


# --- Headlight Wet Road Scatter ---

func _process_headlight_scatter() -> void:
	## Increase headlight scatter when road is wet (rain weather).
	if not GameManager.world_time:
		return

	var weather := GameManager.world_time.current_weather
	var is_wet := weather in ["light_rain", "heavy_rain", "storm"]

	for vehicle in _vehicle_headlights:
		var lights: Array = _vehicle_headlights[vehicle]
		for light in lights:
			if not is_instance_valid(light):
				continue
			if light is SpotLight3D:
				if is_wet and _headlights_active:
					# Wider, slightly brighter cone on wet roads
					light.spot_angle = HEADLIGHT_SPOT_ANGLE * 1.3
					light.light_energy = HEADLIGHT_INTENSITY * 1.15
				elif _headlights_active:
					light.spot_angle = HEADLIGHT_SPOT_ANGLE
					light.light_energy = HEADLIGHT_INTENSITY


# --- Signal Handlers ---

func _on_headlights_needed_changed(needed: bool) -> void:
	## Auto-toggle headlights based on ambient darkness.
	set_headlights_active(needed)
	print("[Lights] Headlights %s" % ("ON" if needed else "OFF"))


func _on_district_entered(_district_id: String) -> void:
	## Re-scan for street lights when entering a new district.
	_find_street_lights()
	_find_traffic_lights()

	if _lights_enabled:
		_activate_street_lights()
