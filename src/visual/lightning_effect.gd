## Lightning and thunder effect for MIDNIGHT GRIND storm weather.
## Creates dramatic lightning flashes using DirectionalLight3D pulses,
## screen flash overlays, delayed thunder audio, and distant lightning
## flickers. Fires at random intervals during active storms.
class_name LightningEffect
extends Node

# ── Configuration ────────────────────────────────────────────────────────────
@export_group("References")
## Main DirectionalLight3D in the scene for lightning intensity spikes.
@export var main_light: DirectionalLight3D = null

@export_group("Timing")
## Minimum seconds between lightning strikes during a storm.
@export var min_interval: float = 5.0
## Maximum seconds between lightning strikes during a storm.
@export var max_interval: float = 20.0
## Duration of the bright flash phase (seconds).
@export var flash_duration: float = 0.1
## Duration of the afterglow fade (seconds).
@export var fade_duration: float = 0.3

@export_group("Intensity")
## Peak light energy during a close lightning strike.
@export var close_flash_energy: float = 3.0
## Peak light energy during a distant lightning flash.
@export var distant_flash_energy: float = 0.8
## Chance (0-1) of a double flash (re-flash shortly after first).
@export var double_flash_chance: float = 0.3

@export_group("Thunder")
## Minimum delay (seconds) between lightning flash and thunder.
@export var thunder_min_delay: float = 0.5
## Maximum delay (seconds) between lightning flash and thunder.
@export var thunder_max_delay: float = 3.0

@export_group("Distant Lightning")
## Whether to show subtle distant flashes between main strikes.
@export var enable_distant: bool = true
## Interval range for distant flashes.
@export var distant_min_interval: float = 3.0
@export var distant_max_interval: float = 10.0

# ── State ────────────────────────────────────────────────────────────────────
var _storm_active: bool = false
var _strike_timer: float = 0.0
var _next_strike_time: float = 10.0

# Flash animation state
var _flashing: bool = false
var _flash_phase: float = 0.0  # 0 = rising, 1 = peak, 2 = fading
var _flash_timer: float = 0.0
var _flash_intensity: float = 0.0
var _base_light_energy: float = 0.35

# Double flash state
var _pending_double_flash: bool = false
var _double_flash_timer: float = 0.0

# Thunder pending
var _thunder_pending: bool = false
var _thunder_timer: float = 0.0
var _thunder_intensity: float = 1.0

# Distant lightning
var _distant_timer: float = 0.0
var _distant_next_time: float = 5.0

# Screen flash overlay
var _screen_flash: ColorRect = null
var _flash_canvas: CanvasLayer = null
var _screen_flash_alpha: float = 0.0

# Fork lightning mesh
var _fork_mesh: MeshInstance3D = null


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_screen_flash()
	_setup_fork_lightning()
	if main_light:
		_base_light_energy = main_light.light_energy
	print("[Lightning] Lightning effect initialized")


func _process(delta: float) -> void:
	if _storm_active:
		_update_storm_timer(delta)
		_update_distant_lightning(delta)

	if _flashing:
		_update_flash(delta)

	if _pending_double_flash:
		_update_double_flash(delta)

	if _thunder_pending:
		_update_thunder(delta)

	_update_screen_flash(delta)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func start_storm() -> void:
	## Begin generating lightning at random intervals.
	if _storm_active:
		return
	_storm_active = true
	_strike_timer = 0.0
	_next_strike_time = randf_range(min_interval * 0.3, min_interval)  # Quick first strike
	_distant_timer = 0.0
	_distant_next_time = randf_range(distant_min_interval, distant_max_interval)
	print("[Lightning] Storm started")


func stop_storm() -> void:
	## Stop generating lightning. Active flashes will finish naturally.
	if not _storm_active:
		return
	_storm_active = false
	print("[Lightning] Storm stopped")


func trigger_lightning(intensity: float = 1.0) -> void:
	## Manually trigger a lightning flash at the given intensity (0-1).
	_start_flash(lerpf(distant_flash_energy, close_flash_energy, clampf(intensity, 0.0, 1.0)))

	# Schedule thunder based on "distance" (inverse of intensity)
	var distance := 1.0 - clampf(intensity, 0.0, 1.0)
	_thunder_pending = true
	_thunder_timer = lerpf(thunder_min_delay, thunder_max_delay, distance)
	_thunder_intensity = intensity

	# Chance of double flash for close strikes
	if intensity > 0.5 and randf() < double_flash_chance:
		_pending_double_flash = true
		_double_flash_timer = randf_range(0.15, 0.35)

	# Show fork lightning mesh briefly for close strikes
	if intensity > 0.6:
		_show_fork_lightning(intensity)

	# Emit signal
	EventBus.lightning_struck.emit()

	print("[Lightning] Strike! Intensity: %.2f" % intensity)


# ═══════════════════════════════════════════════════════════════════════════════
#  STORM TIMER
# ═══════════════════════════════════════════════════════════════════════════════

func _update_storm_timer(delta: float) -> void:
	_strike_timer += delta
	if _strike_timer >= _next_strike_time:
		_strike_timer = 0.0
		_next_strike_time = randf_range(min_interval, max_interval)

		# Randomize intensity: most strikes are medium, occasional close ones
		var intensity := randf_range(0.4, 1.0)
		# Bias toward medium-distance strikes
		intensity = intensity * intensity  # Squares bias toward lower values
		intensity = lerpf(0.3, 1.0, intensity)  # Remap to useful range

		trigger_lightning(intensity)


func _update_distant_lightning(delta: float) -> void:
	if not enable_distant:
		return

	_distant_timer += delta
	if _distant_timer >= _distant_next_time:
		_distant_timer = 0.0
		_distant_next_time = randf_range(distant_min_interval, distant_max_interval)

		# Subtle distant flash (no thunder, low intensity)
		var distant_intensity := randf_range(0.1, 0.3)
		_start_flash(distant_flash_energy * distant_intensity)
		# Very subtle screen flash
		_screen_flash_alpha = distant_intensity * 0.05


# ═══════════════════════════════════════════════════════════════════════════════
#  FLASH ANIMATION
# ═══════════════════════════════════════════════════════════════════════════════

func _start_flash(energy: float) -> void:
	_flashing = true
	_flash_phase = 0.0
	_flash_timer = 0.0
	_flash_intensity = energy

	# Screen flash proportional to intensity
	var normalized := clampf(energy / close_flash_energy, 0.0, 1.0)
	_screen_flash_alpha = lerpf(0.02, 0.15, normalized)


func _update_flash(delta: float) -> void:
	_flash_timer += delta

	if _flash_timer < flash_duration:
		# Rising to peak
		var t := _flash_timer / flash_duration
		_set_light_energy(lerpf(_base_light_energy, _flash_intensity, t))
	elif _flash_timer < flash_duration + fade_duration:
		# Fading from peak
		var fade_t := (_flash_timer - flash_duration) / fade_duration
		_set_light_energy(lerpf(_flash_intensity, _base_light_energy, fade_t))
	else:
		# Flash complete
		_flashing = false
		_set_light_energy(_base_light_energy)


func _update_double_flash(delta: float) -> void:
	_double_flash_timer -= delta
	if _double_flash_timer <= 0.0:
		_pending_double_flash = false
		# Second flash is slightly weaker
		_start_flash(_flash_intensity * 0.7)


func _set_light_energy(energy: float) -> void:
	if main_light:
		main_light.light_energy = energy


# ═══════════════════════════════════════════════════════════════════════════════
#  SCREEN FLASH
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_screen_flash() -> void:
	_flash_canvas = CanvasLayer.new()
	_flash_canvas.name = "LightningFlashCanvas"
	_flash_canvas.layer = 95  # Above most UI
	add_child(_flash_canvas)

	_screen_flash = ColorRect.new()
	_screen_flash.name = "LightningFlash"
	_screen_flash.color = Color(0.95, 0.95, 1.0, 0.0)
	_screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_canvas.add_child(_screen_flash)


func _update_screen_flash(delta: float) -> void:
	if _screen_flash_alpha > 0.001:
		_screen_flash_alpha = move_toward(_screen_flash_alpha, 0.0, delta * 2.0)
		_screen_flash.color = Color(0.95, 0.95, 1.0, _screen_flash_alpha)
		_screen_flash.visible = true
	else:
		_screen_flash_alpha = 0.0
		_screen_flash.visible = false


# ═══════════════════════════════════════════════════════════════════════════════
#  THUNDER
# ═══════════════════════════════════════════════════════════════════════════════

func _update_thunder(delta: float) -> void:
	_thunder_timer -= delta
	if _thunder_timer <= 0.0:
		_thunder_pending = false
		_play_thunder(_thunder_intensity)


func _play_thunder(intensity: float) -> void:
	## Trigger thunder sound through the AudioManager.
	## Volume scales with intensity (closer = louder).
	var volume_db := lerpf(-20.0, -3.0, clampf(intensity, 0.0, 1.0))

	# Use EventBus to request audio playback (AudioManager handles it)
	# Randomize between different thunder variations
	var thunder_type := "close" if intensity > 0.6 else "distant"
	print("[Lightning] Thunder (%s) at %.1f dB" % [thunder_type, volume_db])

	# If AudioManager is available, play through it
	if Engine.has_singleton("AudioManager"):
		pass  # AudioManager.play_sfx("thunder_%s" % thunder_type, volume_db)
	elif has_node("/root/AudioManager"):
		var audio_mgr := get_node("/root/AudioManager")
		if audio_mgr.has_method("play_sfx"):
			audio_mgr.play_sfx("thunder_%s" % thunder_type, volume_db)


# ═══════════════════════════════════════════════════════════════════════════════
#  FORK LIGHTNING VISUAL
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_fork_lightning() -> void:
	## Creates a simple mesh for fork lightning visualization in the sky.
	_fork_mesh = MeshInstance3D.new()
	_fork_mesh.name = "ForkLightning"
	_fork_mesh.visible = false

	var fork_mat := StandardMaterial3D.new()
	fork_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fork_mat.albedo_color = Color(0.85, 0.88, 1.0, 0.9)
	fork_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fork_mat.emission_enabled = true
	fork_mat.emission = Color(0.8, 0.85, 1.0)
	fork_mat.emission_energy_multiplier = 5.0
	fork_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fork_mesh.material_override = fork_mat

	add_child(_fork_mesh)


func _show_fork_lightning(intensity: float) -> void:
	## Briefly display a fork lightning mesh in the sky.
	if _fork_mesh == null:
		return

	# Generate a procedural lightning bolt mesh
	_fork_mesh.mesh = _generate_bolt_mesh(intensity)

	# Position in the sky, offset randomly from camera
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if camera:
		var offset := Vector3(
			randf_range(-80.0, 80.0),
			randf_range(40.0, 80.0),
			randf_range(-80.0, -30.0)
		)
		_fork_mesh.global_position = camera.global_position + offset

	_fork_mesh.visible = true

	# Hide after a brief moment
	var tween := create_tween()
	tween.tween_interval(flash_duration + 0.05)
	tween.tween_callback(func() -> void: _fork_mesh.visible = false)


func _generate_bolt_mesh(intensity: float) -> ImmediateMesh:
	## Generates a simple jagged line mesh resembling a lightning bolt.
	var mesh := ImmediateMesh.new()
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var segments := int(lerpf(4.0, 10.0, intensity))
	var bolt_length := lerpf(15.0, 40.0, intensity)
	var bolt_width := lerpf(0.3, 1.0, intensity)
	var jag_amount := lerpf(2.0, 6.0, intensity)

	var pos := Vector3.ZERO
	var direction := Vector3(0.0, -1.0, 0.0)

	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var width := bolt_width * (1.0 - t * 0.5)  # Taper toward end

		# Jagged offsets for natural look
		var jag := Vector3(
			randf_range(-jag_amount, jag_amount),
			0.0,
			randf_range(-jag_amount * 0.5, jag_amount * 0.5)
		) if i > 0 and i < segments else Vector3.ZERO

		pos += direction * (bolt_length / float(segments)) + jag
		var right := Vector3(width, 0.0, 0.0)

		var alpha := lerpf(1.0, 0.3, t)
		mesh.surface_set_color(Color(0.9, 0.92, 1.0, alpha))
		mesh.surface_add_vertex(pos + right)
		mesh.surface_set_color(Color(0.9, 0.92, 1.0, alpha))
		mesh.surface_add_vertex(pos - right)

	mesh.surface_end()
	return mesh
