## Plays back a recorded ghost run as a semi-transparent vehicle.
## Renders a BoxMesh stand-in with a ghostly shader, interpolates between
## recorded frames for smooth motion, and optionally trails a fading
## ribbon of past positions behind the ghost.
class_name GhostPlayer
extends Node3D

## Path to the ghost vehicle shader (created alongside this script).
const GHOST_SHADER_PATH: String = "res://assets/shaders/ghost_vehicle.gdshader"

## Number of trail positions to store for the fading ribbon.
const TRAIL_LENGTH: int = 30
## Interval (seconds) between trail point captures.
const TRAIL_INTERVAL: float = 0.05

## Default ghost vehicle size (meters) — approximates a compact sports car.
const DEFAULT_BODY_SIZE: Vector3 = Vector3(1.8, 1.2, 4.4)

## Era-based tint colours (matches GDD Act colour coding).
const ERA_COLORS: Dictionary = {
	1: Color(1.0, 0.65, 0.2, 1.0),   # Act 1 — warm orange/amber
	2: Color(0.3, 0.5, 1.0, 1.0),    # Act 2 — cool blue
	3: Color(1.0, 0.2, 0.15, 1.0),   # Act 3 — red/angry
	0: Color(0.3, 0.95, 1.0, 1.0),   # Current/best — cyan/white
}

# ── Exported ─────────────────────────────────────────────────────────────────
@export var ghost_opacity: float = 0.4
@export var ghost_color: Color = Color(0.3, 0.95, 1.0, 1.0)
@export var pulse_speed: float = 2.0
@export var show_trail: bool = true

# ── Nodes ────────────────────────────────────────────────────────────────────
var _mesh_instance: MeshInstance3D = null
var _shader_material: ShaderMaterial = null
var _trail_mesh: ImmediateMesh = null
var _trail_instance: MeshInstance3D = null

# ── State ────────────────────────────────────────────────────────────────────
var _ghost_data: GhostData = null
var _playing: bool = false
var _current_time: float = 0.0
var _trail_positions: Array = []  # Array of Vector3
var _trail_timer: float = 0.0
var _finished: bool = false


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_build_ghost_mesh()
	_build_trail()
	set_process(false)
	print("[Ghost] GhostPlayer ready.")


func _process(delta: float) -> void:
	if not _playing or _ghost_data == null:
		return

	_current_time += delta

	# Check if playback has ended
	if _current_time >= _ghost_data.total_time:
		_current_time = _ghost_data.total_time
		_finished = true
		_apply_frame(_ghost_data.get_frame_at_time(_current_time))
		stop_playback()
		return

	# Get interpolated frame and apply
	var frame: GhostData.GhostFrame = _ghost_data.get_frame_at_time(_current_time)
	_apply_frame(frame)

	# Trail
	if show_trail:
		_trail_timer += delta
		if _trail_timer >= TRAIL_INTERVAL:
			_trail_timer -= TRAIL_INTERVAL
			_update_trail(frame.position)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func load_ghost(ghost_data: GhostData) -> void:
	## Load a GhostData resource for playback.
	_ghost_data = ghost_data
	_current_time = 0.0
	_finished = false
	_trail_positions.clear()

	# Set era-based colour tint
	var act: int = ghost_data.act_recorded
	if ERA_COLORS.has(act):
		ghost_color = ERA_COLORS[act]
	else:
		ghost_color = ERA_COLORS[0]

	_update_shader_params()

	# Position at first frame
	if ghost_data.frames.size() > 0:
		_apply_frame(ghost_data.frames[0])

	print("[Ghost] Ghost loaded — track: %s, vehicle: %s, time: %.2fs, act: %d" % [
		ghost_data.track_id, ghost_data.vehicle_id, ghost_data.total_time, act])


func start_playback() -> void:
	## Begin playing the loaded ghost from the beginning.
	if _ghost_data == null:
		push_warning("[Ghost] No ghost data loaded — cannot start playback.")
		return

	_current_time = 0.0
	_playing = true
	_finished = false
	_trail_positions.clear()
	_trail_timer = 0.0
	visible = true
	set_process(true)
	print("[Ghost] Playback started.")


func stop_playback() -> void:
	## Stop playback. The ghost remains visible at its last position.
	_playing = false
	set_process(false)
	print("[Ghost] Playback stopped at %.2fs." % _current_time)


func set_time(time: float) -> void:
	## Scrub to a specific time in the recording.
	## Useful for replays and analysis UIs.
	if _ghost_data == null:
		return
	_current_time = clampf(time, 0.0, _ghost_data.total_time)
	var frame: GhostData.GhostFrame = _ghost_data.get_frame_at_time(_current_time)
	_apply_frame(frame)


func set_opacity(alpha: float) -> void:
	## Adjust ghost transparency (0.0 = invisible, 1.0 = solid).
	ghost_opacity = clampf(alpha, 0.0, 1.0)
	_update_shader_params()


func set_ghost_tint(color: Color) -> void:
	## Override the ghost tint colour.
	ghost_color = color
	_update_shader_params()


func set_era_color(act: int) -> void:
	## Set the ghost colour based on the story act.
	if ERA_COLORS.has(act):
		ghost_color = ERA_COLORS[act]
	else:
		ghost_color = ERA_COLORS[0]
	_update_shader_params()


func is_playing() -> bool:
	return _playing


func is_finished() -> bool:
	return _finished


func get_current_time() -> float:
	return _current_time


func get_current_speed() -> float:
	if _ghost_data == null:
		return 0.0
	var frame: GhostData.GhostFrame = _ghost_data.get_frame_at_time(_current_time)
	return frame.speed


# ═══════════════════════════════════════════════════════════════════════════════
#  MESH CONSTRUCTION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_ghost_mesh() -> void:
	## Creates a simple BoxMesh body with the ghost shader applied.
	## In production, this can be swapped for the actual vehicle mesh.
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = DEFAULT_BODY_SIZE
	_mesh_instance.mesh = box

	# Offset the mesh up so the bottom sits at y=0 (ground level)
	_mesh_instance.position.y = DEFAULT_BODY_SIZE.y * 0.5

	# Build shader material
	_shader_material = ShaderMaterial.new()
	var shader := load(GHOST_SHADER_PATH) as Shader
	if shader:
		_shader_material.shader = shader
	else:
		# Fallback: basic transparent material if shader is missing
		push_warning("[Ghost] Ghost shader not found at %s — using fallback." % GHOST_SHADER_PATH)
		var fallback := StandardMaterial3D.new()
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fallback.albedo_color = Color(ghost_color.r, ghost_color.g, ghost_color.b, ghost_opacity)
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh_instance.material_override = fallback
		add_child(_mesh_instance)
		return

	_update_shader_params()
	_mesh_instance.material_override = _shader_material

	# Ghost should not cast shadows
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_mesh_instance)


func _build_trail() -> void:
	## Sets up an ImmediateMesh for the fading trail ribbon.
	_trail_mesh = ImmediateMesh.new()
	_trail_instance = MeshInstance3D.new()
	_trail_instance.mesh = _trail_mesh
	_trail_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Trail uses a simple unshaded transparent material
	var trail_mat := StandardMaterial3D.new()
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.albedo_color = Color(ghost_color.r, ghost_color.g, ghost_color.b, 0.2)
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.no_depth_test = true
	_trail_instance.material_override = trail_mat

	add_child(_trail_instance)


# ═══════════════════════════════════════════════════════════════════════════════
#  FRAME APPLICATION
# ═══════════════════════════════════════════════════════════════════════════════

func _apply_frame(frame: GhostData.GhostFrame) -> void:
	## Applies the interpolated frame data to this node's transform.
	global_transform.origin = frame.position
	rotation_degrees = frame.rotation


# ═══════════════════════════════════════════════════════════════════════════════
#  TRAIL
# ═══════════════════════════════════════════════════════════════════════════════

func _update_trail(pos: Vector3) -> void:
	## Adds a point to the trail and redraws the ribbon mesh.
	_trail_positions.append(pos)
	if _trail_positions.size() > TRAIL_LENGTH:
		_trail_positions.pop_front()

	_draw_trail()


func _draw_trail() -> void:
	## Draws the trail as a vertical ribbon fading from opaque to transparent.
	_trail_mesh.clear_surfaces()

	if _trail_positions.size() < 2:
		return

	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var count: int = _trail_positions.size()
	var half_height: float = 0.4  # ribbon height (meters)

	for i in range(count):
		var alpha: float = float(i) / float(count - 1) * ghost_opacity * 0.5
		var color := Color(ghost_color.r, ghost_color.g, ghost_color.b, alpha)
		var pos: Vector3 = _trail_positions[i]

		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(pos + Vector3.UP * half_height)
		_trail_mesh.surface_set_color(color)
		_trail_mesh.surface_add_vertex(pos - Vector3.UP * half_height)

	_trail_mesh.surface_end()


# ═══════════════════════════════════════════════════════════════════════════════
#  SHADER PARAMS
# ═══════════════════════════════════════════════════════════════════════════════

func _update_shader_params() -> void:
	## Pushes the current visual settings into the shader material.
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("ghost_color", ghost_color)
	_shader_material.set_shader_parameter("base_opacity", ghost_opacity)
	_shader_material.set_shader_parameter("pulse_speed", pulse_speed)
