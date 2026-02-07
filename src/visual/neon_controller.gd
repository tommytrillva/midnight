## Controls all neon signs and colored lights in the city.
## Finds signs by the "neon_lights" group, manages flicker effects,
## broken sign behavior, and intensity transitions between day and night.
class_name NeonController
extends Node

# --- Configuration ---
const FLICKER_MIN_INTERVAL := 0.05   # Fastest flicker (seconds)
const FLICKER_MAX_INTERVAL := 0.3    # Slowest flicker (seconds)
const BROKEN_FLICKER_CHANCE := 0.15  # Chance per sign of being "broken"
const DUSK_STAGGER_RANGE := 3.0      # Seconds of random delay when signs turn on at dusk
const BUZZ_FLICKER_COUNT := 5        # Number of flickers when a sign "buzzes to life"
const COLOR_TEMP_NIGHT := 0.0        # Color temperature shift: 0 = neutral
const COLOR_TEMP_DAWN := 0.15        # Warmer shift near dawn

# --- State ---
var _neon_lights: Array[Node] = []
var _broken_signs: Array[Node] = []
var _sign_base_energies: Dictionary = {}  # Node -> original energy
var _sign_base_colors: Dictionary = {}    # Node -> original color
var _current_intensity: float = 1.0
var _target_intensity: float = 1.0
var _is_activated: bool = true
var _initialized: bool = false

# Flicker timers for broken signs
var _broken_timers: Dictionary = {}  # Node -> { timer: float, on: bool, next_flip: float }

# Buzz-to-life tracking for dusk activation
var _buzzing_signs: Dictionary = {}  # Node -> { flickers_left: int, timer: float }


func _ready() -> void:
	# Defer finding neon lights until the scene tree is ready
	await get_tree().process_frame
	_find_neon_lights()
	_initialized = true

	EventBus.neon_lights_activated.connect(_on_neon_activated)
	EventBus.neon_lights_deactivated.connect(_on_neon_deactivated)

	print("[Neon] NeonController ready. Found %d neon lights" % _neon_lights.size())


func _process(delta: float) -> void:
	if not _initialized:
		return

	# Smooth intensity transition
	_current_intensity = move_toward(_current_intensity, _target_intensity, delta * 0.5)

	# Update all neon lights
	for light in _neon_lights:
		if not is_instance_valid(light):
			continue
		_update_sign_intensity(light)

	# Update broken sign flickers
	_process_broken_flickers(delta)

	# Update buzz-to-life animations
	_process_buzz_to_life(delta)


# --- Public API ---

func set_neon_intensity(intensity: float) -> void:
	## Set target neon intensity. 0.0 = day (off), 1.0 = night (full).
	_target_intensity = clampf(intensity, 0.0, 1.0)


func flicker_sign(sign_node: Node3D) -> void:
	## Trigger a one-shot random flicker effect on a sign.
	if not is_instance_valid(sign_node):
		return

	var tween := create_tween()
	var base_energy: float = _sign_base_energies.get(sign_node, 1.0)
	var flicker_count := randi_range(2, 6)

	for i in flicker_count:
		var on_energy := base_energy * _current_intensity * randf_range(0.3, 1.0)
		var off_energy := base_energy * _current_intensity * randf_range(0.0, 0.15)
		var duration := randf_range(FLICKER_MIN_INTERVAL, FLICKER_MAX_INTERVAL)

		if sign_node is Light3D:
			tween.tween_property(sign_node, "light_energy", off_energy, duration * 0.3)
			tween.tween_property(sign_node, "light_energy", on_energy, duration * 0.7)
		elif sign_node is MeshInstance3D:
			tween.tween_callback(_set_emission_strength.bind(sign_node, off_energy))
			tween.tween_interval(duration * 0.3)
			tween.tween_callback(_set_emission_strength.bind(sign_node, on_energy))
			tween.tween_interval(duration * 0.7)


func broken_sign(sign_node: Node3D) -> void:
	## Mark a sign as permanently broken with intermittent flicker.
	if sign_node in _broken_signs:
		return

	_broken_signs.append(sign_node)
	_broken_timers[sign_node] = {
		"timer": 0.0,
		"on": true,
		"next_flip": randf_range(0.5, 4.0),
	}
	print("[Neon] Sign marked as broken: %s" % sign_node.name)


func get_neon_count() -> int:
	return _neon_lights.size()


# --- Internal ---

func _find_neon_lights() -> void:
	## Discover all neon light nodes in the "neon_lights" group.
	_neon_lights.clear()
	_sign_base_energies.clear()
	_sign_base_colors.clear()
	_broken_signs.clear()

	var group_nodes := get_tree().get_nodes_in_group("neon_lights")
	for node in group_nodes:
		_neon_lights.append(node)

		# Cache original energy and color
		if node is Light3D:
			_sign_base_energies[node] = node.light_energy
			_sign_base_colors[node] = node.light_color
		elif node is MeshInstance3D:
			var mat := node.get_surface_override_material(0)
			if mat == null:
				mat = node.mesh.surface_get_material(0) if node.mesh else null
			if mat is StandardMaterial3D:
				_sign_base_energies[node] = mat.emission_energy_multiplier
				_sign_base_colors[node] = mat.emission
			else:
				_sign_base_energies[node] = 1.0
				_sign_base_colors[node] = Color.WHITE
		else:
			_sign_base_energies[node] = 1.0
			_sign_base_colors[node] = Color.WHITE

		# Randomly mark some signs as broken for atmosphere
		if randf() < BROKEN_FLICKER_CHANCE:
			broken_sign(node)

	print("[Neon] Cached %d neon light base values" % _sign_base_energies.size())


func _update_sign_intensity(sign_node: Node) -> void:
	## Apply current intensity to a single sign (unless it's being flickered).
	if sign_node in _buzzing_signs:
		return  # Buzz animation handles this sign
	if sign_node in _broken_signs:
		return  # Broken flicker handles this sign

	var base_energy: float = _sign_base_energies.get(sign_node, 1.0)
	var target_energy := base_energy * _current_intensity

	if sign_node is Light3D:
		sign_node.light_energy = target_energy
		sign_node.visible = _current_intensity > 0.01
	elif sign_node is MeshInstance3D:
		_set_emission_strength(sign_node, target_energy)


func _process_broken_flickers(delta: float) -> void:
	## Update all broken sign flicker states.
	for sign_node in _broken_signs:
		if not is_instance_valid(sign_node):
			continue

		var state: Dictionary = _broken_timers.get(sign_node, {})
		if state.is_empty():
			continue

		state["timer"] += delta
		if state["timer"] >= state["next_flip"]:
			state["timer"] = 0.0
			state["on"] = not state["on"]

			if state["on"]:
				# On for a random duration
				state["next_flip"] = randf_range(1.0, 8.0)
			else:
				# Off for a short burst (or long if really broken)
				state["next_flip"] = randf_range(0.05, 2.0)

			_broken_timers[sign_node] = state

		# Apply broken state
		var base_energy: float = _sign_base_energies.get(sign_node, 1.0)
		var energy: float
		if state["on"]:
			# Flickering slightly even when "on"
			energy = base_energy * _current_intensity * randf_range(0.7, 1.0)
		else:
			energy = base_energy * _current_intensity * randf_range(0.0, 0.05)

		if sign_node is Light3D:
			sign_node.light_energy = energy
		elif sign_node is MeshInstance3D:
			_set_emission_strength(sign_node, energy)


func _process_buzz_to_life(delta: float) -> void:
	## Animate signs that are "buzzing to life" at dusk.
	var completed: Array[Node] = []

	for sign_node in _buzzing_signs:
		if not is_instance_valid(sign_node):
			completed.append(sign_node)
			continue

		var state: Dictionary = _buzzing_signs[sign_node]
		state["timer"] += delta

		if state["timer"] >= 0.08:  # Quick flicker interval
			state["timer"] = 0.0
			state["flickers_left"] -= 1

			var base_energy: float = _sign_base_energies.get(sign_node, 1.0)
			var is_on := state["flickers_left"] % 2 == 0

			var energy: float
			if is_on:
				energy = base_energy * _current_intensity * randf_range(0.4, 0.9)
			else:
				energy = base_energy * _current_intensity * randf_range(0.0, 0.1)

			if sign_node is Light3D:
				sign_node.light_energy = energy
			elif sign_node is MeshInstance3D:
				_set_emission_strength(sign_node, energy)

			if state["flickers_left"] <= 0:
				completed.append(sign_node)

			_buzzing_signs[sign_node] = state

	for sign_node in completed:
		_buzzing_signs.erase(sign_node)


func _set_emission_strength(mesh: MeshInstance3D, strength: float) -> void:
	## Set emission energy on a MeshInstance3D's material.
	var mat := mesh.get_surface_override_material(0)
	if mat == null and mesh.mesh:
		# Create an override so we don't modify the shared resource
		mat = mesh.mesh.surface_get_material(0)
		if mat:
			mat = mat.duplicate()
			mesh.set_surface_override_material(0, mat)

	if mat is StandardMaterial3D:
		mat.emission_enabled = strength > 0.01
		mat.emission_energy_multiplier = strength


func _apply_color_temperature_shift(base_color: Color, shift: float) -> Color:
	## Shift color temperature. Positive = warmer (towards orange).
	if absf(shift) < 0.001:
		return base_color
	return Color(
		clampf(base_color.r + shift * 0.2, 0.0, 1.0),
		base_color.g,
		clampf(base_color.b - shift * 0.15, 0.0, 1.0),
		base_color.a
	)


# --- Signal Handlers ---

func _on_neon_activated() -> void:
	## Neon signs turning on at dusk. Stagger activation with buzz effect.
	_is_activated = true
	print("[Neon] Neon signs activating (dusk)")

	for sign_node in _neon_lights:
		if not is_instance_valid(sign_node):
			continue
		if sign_node in _broken_signs:
			continue  # Broken signs have their own behavior

		# Random delay before each sign buzzes to life
		var delay := randf_range(0.0, DUSK_STAGGER_RANGE)
		var flicker_count := randi_range(3, BUZZ_FLICKER_COUNT)

		# Schedule the buzz-to-life after the delay
		get_tree().create_timer(delay).timeout.connect(
			func() -> void:
				if is_instance_valid(sign_node):
					_buzzing_signs[sign_node] = {
						"flickers_left": flicker_count,
						"timer": 0.0,
					}
		)


func _on_neon_deactivated() -> void:
	## Neon signs turning off at dawn/day.
	_is_activated = false
	_buzzing_signs.clear()
	print("[Neon] Neon signs deactivating (day)")
