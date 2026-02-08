## Procedural car model builder using CSG primitives and MeshInstance3D nodes.
## Generates low-poly vehicle geometry with configurable body styles, paint colors,
## headlights/taillights, undercarriage neon, and exhaust pipe.
## Designed for PS1/PS2 retro aesthetic with the PSX shader applied on top.
class_name VehicleVisual
extends Node3D

## Body style presets for different car silhouettes.
enum BodyStyle {
	SEDAN,
	COUPE,
	HATCHBACK,
	MUSCLE,
}

## Level of detail -- FULL for player/close cars, LOW for distant parked cars.
enum DetailLevel {
	FULL,
	LOW,
}

# --- Configuration ---
@export var body_style: BodyStyle = BodyStyle.SEDAN
@export var detail_level: DetailLevel = DetailLevel.FULL
@export var body_color: Color = Color(0.8, 0.1, 0.15, 1.0)
@export var body_metallic: float = 0.6
@export var body_roughness: float = 0.35
@export var enable_neon_undercarriage: bool = false
@export var neon_color: Color = Color(0.0, 0.6, 1.0, 1.0)
@export var headlight_on: bool = true
@export var taillight_on: bool = true

# --- PSX Shader ---
const PSX_SHADER_PATH := "res://assets/shaders/retro_psx.gdshader"
var _psx_shader: Shader = null

# --- Internal references ---
var _body_root: Node3D = null
var _lights_root: Node3D = null
var _wheels_root: Node3D = null
var _neon_root: Node3D = null
var _exhaust_mesh: MeshInstance3D = null

# --- Body dimension tables per style ---
# Format: { main_body, hood, cabin, trunk } as [width, height, depth, y_offset, z_offset]
const BODY_PROFILES := {
	BodyStyle.SEDAN: {
		"main":   [1.7, 0.45, 4.2, 0.35, 0.0],
		"hood":   [1.6, 0.15, 1.2, 0.68, 1.35],
		"cabin":  [1.5, 0.55, 1.6, 0.95, 0.1],
		"trunk":  [1.55, 0.3, 0.9, 0.68, -1.5],
		"fender_w": 0.22,
		"fender_h": 0.35,
	},
	BodyStyle.COUPE: {
		"main":   [1.65, 0.42, 4.0, 0.34, 0.0],
		"hood":   [1.55, 0.12, 1.4, 0.64, 1.3],
		"cabin":  [1.45, 0.5, 1.3, 0.88, 0.15],
		"trunk":  [1.5, 0.22, 0.8, 0.62, -1.4],
		"fender_w": 0.24,
		"fender_h": 0.38,
	},
	BodyStyle.HATCHBACK: {
		"main":   [1.6, 0.45, 3.6, 0.35, 0.0],
		"hood":   [1.5, 0.14, 1.1, 0.66, 1.15],
		"cabin":  [1.45, 0.6, 1.8, 0.95, -0.1],
		"trunk":  [1.45, 0.45, 0.5, 0.78, -1.3],
		"fender_w": 0.2,
		"fender_h": 0.32,
	},
	BodyStyle.MUSCLE: {
		"main":   [1.85, 0.48, 4.5, 0.38, 0.0],
		"hood":   [1.75, 0.2, 1.5, 0.72, 1.5],
		"cabin":  [1.55, 0.5, 1.4, 0.95, 0.05],
		"trunk":  [1.65, 0.28, 0.9, 0.68, -1.65],
		"fender_w": 0.28,
		"fender_h": 0.42,
	},
}


func _ready() -> void:
	_load_psx_shader()
	build()


## Rebuild the entire visual from scratch based on current settings.
func build() -> void:
	_clear_children()
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)

	_lights_root = Node3D.new()
	_lights_root.name = "Lights"
	add_child(_lights_root)

	_wheels_root = Node3D.new()
	_wheels_root.name = "Wheels"
	add_child(_wheels_root)

	var profile: Dictionary = BODY_PROFILES[body_style]

	_build_body(profile)
	_build_wheel_wells(profile)
	_build_wheels()
	_build_headlights(profile)
	_build_taillights(profile)
	_build_exhaust(profile)

	if enable_neon_undercarriage:
		_build_neon_undercarriage(profile)

	if detail_level == DetailLevel.FULL:
		_build_side_mirrors(profile)
		_build_bumpers(profile)

	print("[VehicleVisual] Built %s style vehicle (%s detail)" % [
		BodyStyle.keys()[body_style],
		DetailLevel.keys()[detail_level],
	])


## Set the body paint color at runtime and refresh materials.
func set_paint_color(color: Color) -> void:
	body_color = color
	_refresh_body_materials()


## Toggle headlights/taillights on or off.
func set_lights_enabled(headlights: bool, taillights: bool) -> void:
	headlight_on = headlights
	taillight_on = taillights
	_refresh_light_state()


## Toggle undercarriage neon glow.
func set_neon_enabled(enabled: bool, color: Color = neon_color) -> void:
	enable_neon_undercarriage = enabled
	neon_color = color
	if _neon_root:
		_neon_root.queue_free()
		_neon_root = null
	if enabled:
		var profile: Dictionary = BODY_PROFILES[body_style]
		_build_neon_undercarriage(profile)


# ---------------------------------------------------------------------------
# Internal build helpers
# ---------------------------------------------------------------------------

func _load_psx_shader() -> void:
	_psx_shader = load(PSX_SHADER_PATH) as Shader
	if _psx_shader == null:
		print("[VehicleVisual] Warning: PSX shader not found at %s, falling back to StandardMaterial3D" % PSX_SHADER_PATH)


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()
	_body_root = null
	_lights_root = null
	_wheels_root = null
	_neon_root = null
	_exhaust_mesh = null


func _make_body_material() -> Material:
	if _psx_shader:
		var mat := ShaderMaterial.new()
		mat.shader = _psx_shader
		mat.set_shader_parameter("albedo_color", body_color)
		mat.set_shader_parameter("vertex_snap_intensity", 0.4)
		mat.set_shader_parameter("affine_intensity", 0.5)
		return mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		mat.metallic = body_metallic
		mat.roughness = body_roughness
		return mat


func _make_emissive_material(color: Color, strength: float = 2.0) -> Material:
	if _psx_shader:
		var mat := ShaderMaterial.new()
		mat.shader = _psx_shader
		mat.set_shader_parameter("albedo_color", color)
		mat.set_shader_parameter("emission_color", color)
		mat.set_shader_parameter("emission_strength", strength)
		mat.set_shader_parameter("vertex_snap_intensity", 0.3)
		mat.set_shader_parameter("affine_intensity", 0.3)
		return mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = strength
		return mat


func _make_glass_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.18, 0.25, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.1
	return mat


func _make_rubber_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.1, 1.0)
	mat.metallic = 0.0
	mat.roughness = 0.95
	return mat


func _make_chrome_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.75, 1.0)
	mat.metallic = 0.9
	mat.roughness = 0.15
	return mat


func _add_box_mesh(parent: Node3D, dimensions: Vector3, pos: Vector3, mat: Material, mesh_name: String = "Mesh") -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = mesh_name
	var box := BoxMesh.new()
	box.size = dimensions
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)
	return mesh_inst


func _add_cylinder_mesh(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, mesh_name: String = "Mesh") -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = mesh_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 8  # Low-poly retro look
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = pos
	parent.add_child(mesh_inst)
	return mesh_inst


## Build the main car body panels: base slab, hood, cabin, trunk.
func _build_body(profile: Dictionary) -> void:
	var body_mat := _make_body_material()

	# Main body slab
	var main: Array = profile["main"]
	_add_box_mesh(
		_body_root,
		Vector3(main[0], main[1], main[2]),
		Vector3(0.0, main[3], main[4]),
		body_mat,
		"MainBody"
	)

	# Hood
	var hood: Array = profile["hood"]
	_add_box_mesh(
		_body_root,
		Vector3(hood[0], hood[1], hood[2]),
		Vector3(0.0, hood[3], hood[4]),
		body_mat,
		"Hood"
	)

	# Cabin (windshield area) -- glass material
	var cabin: Array = profile["cabin"]
	var cabin_mesh := _add_box_mesh(
		_body_root,
		Vector3(cabin[0], cabin[1], cabin[2]),
		Vector3(0.0, cabin[3], cabin[4]),
		body_mat,
		"Cabin"
	)

	# Windshield glass overlay (slightly inset)
	if detail_level == DetailLevel.FULL:
		var glass_mat := _make_glass_material()
		# Front windshield
		_add_box_mesh(
			_body_root,
			Vector3(cabin[0] - 0.1, cabin[1] - 0.08, 0.04),
			Vector3(0.0, cabin[3], cabin[4] + cabin[2] * 0.5),
			glass_mat,
			"WindshieldFront"
		)
		# Rear windshield
		_add_box_mesh(
			_body_root,
			Vector3(cabin[0] - 0.1, cabin[1] - 0.08, 0.04),
			Vector3(0.0, cabin[3], cabin[4] - cabin[2] * 0.5),
			glass_mat,
			"WindshieldRear"
		)
		# Side windows L
		_add_box_mesh(
			_body_root,
			Vector3(0.04, cabin[1] - 0.15, cabin[2] - 0.2),
			Vector3(-cabin[0] * 0.5, cabin[3] + 0.02, cabin[4]),
			glass_mat,
			"WindowLeft"
		)
		# Side windows R
		_add_box_mesh(
			_body_root,
			Vector3(0.04, cabin[1] - 0.15, cabin[2] - 0.2),
			Vector3(cabin[0] * 0.5, cabin[3] + 0.02, cabin[4]),
			glass_mat,
			"WindowRight"
		)

	# Trunk
	var trunk: Array = profile["trunk"]
	_add_box_mesh(
		_body_root,
		Vector3(trunk[0], trunk[1], trunk[2]),
		Vector3(0.0, trunk[3], trunk[4]),
		body_mat,
		"Trunk"
	)


## Build wheel well arches (subtle indentations shown as darker panels).
func _build_wheel_wells(profile: Dictionary) -> void:
	var well_mat := StandardMaterial3D.new()
	well_mat.albedo_color = Color(0.05, 0.05, 0.07, 1.0)
	well_mat.roughness = 0.95

	var fw: float = profile["fender_w"]
	var fh: float = profile["fender_h"]
	var well_depth := 0.5

	# Wheel positions matching player_vehicle.tscn
	var wheel_positions := [
		Vector3(-0.75, 0.15, 1.3),   # FL
		Vector3(0.75, 0.15, 1.3),    # FR
		Vector3(-0.75, 0.15, -1.2),  # RL
		Vector3(0.75, 0.15, -1.2),   # RR
	]

	for i in range(wheel_positions.size()):
		var wp: Vector3 = wheel_positions[i]
		_add_box_mesh(
			_body_root,
			Vector3(fw, fh, well_depth),
			Vector3(wp.x, wp.y + fh * 0.5, wp.z),
			well_mat,
			"WheelWell_%d" % i
		)


## Build visual wheel meshes (cylinder + hubcap disc).
func _build_wheels() -> void:
	var rubber_mat := _make_rubber_material()
	var chrome_mat := _make_chrome_material()

	var wheel_positions := [
		Vector3(-0.75, 0.1, 1.3),
		Vector3(0.75, 0.1, 1.3),
		Vector3(-0.75, 0.1, -1.2),
		Vector3(0.75, 0.1, -1.2),
	]

	for i in range(wheel_positions.size()):
		var wp: Vector3 = wheel_positions[i]
		var wheel_node := Node3D.new()
		wheel_node.name = "WheelVisual_%d" % i
		wheel_node.position = wp
		_wheels_root.add_child(wheel_node)

		# Tire (cylinder rotated to align with axle)
		var tire := MeshInstance3D.new()
		tire.name = "Tire"
		var tire_mesh := CylinderMesh.new()
		tire_mesh.top_radius = 0.33
		tire_mesh.bottom_radius = 0.33
		tire_mesh.height = 0.22
		tire_mesh.radial_segments = 8
		tire.mesh = tire_mesh
		tire.material_override = rubber_mat
		# Rotate so cylinder axis is along X (axle direction)
		tire.rotation_degrees = Vector3(0, 0, 90)
		wheel_node.add_child(tire)

		# Hubcap (smaller disc on the outside face)
		if detail_level == DetailLevel.FULL:
			var hubcap := MeshInstance3D.new()
			hubcap.name = "Hubcap"
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.22
			hub_mesh.bottom_radius = 0.22
			hub_mesh.height = 0.04
			hub_mesh.radial_segments = 6
			hubcap.mesh = hub_mesh
			hubcap.material_override = chrome_mat
			hubcap.rotation_degrees = Vector3(0, 0, 90)
			var side_sign := -1.0 if wp.x < 0 else 1.0
			hubcap.position = Vector3(side_sign * 0.12, 0, 0)
			wheel_node.add_child(hubcap)


## Build headlight glow meshes at the front of the vehicle.
func _build_headlights(profile: Dictionary) -> void:
	var hood: Array = profile["hood"]
	var main: Array = profile["main"]
	var front_z: float = main[4] + main[2] * 0.5
	var headlight_y: float = hood[3] + 0.02

	var light_color := Color(1.0, 0.95, 0.8, 1.0)
	var off_color := Color(0.4, 0.38, 0.35, 1.0)
	var mat := _make_emissive_material(light_color if headlight_on else off_color, 3.0 if headlight_on else 0.0)

	# Left headlight
	_add_box_mesh(
		_lights_root,
		Vector3(0.28, 0.12, 0.06),
		Vector3(-0.5, headlight_y, front_z),
		mat,
		"HeadlightL"
	)
	# Right headlight
	_add_box_mesh(
		_lights_root,
		Vector3(0.28, 0.12, 0.06),
		Vector3(0.5, headlight_y, front_z),
		mat,
		"HeadlightR"
	)

	# Turn signal indicators (smaller, amber)
	if detail_level == DetailLevel.FULL:
		var amber := _make_emissive_material(Color(1.0, 0.6, 0.0), 1.5)
		_add_box_mesh(
			_lights_root,
			Vector3(0.12, 0.06, 0.04),
			Vector3(-0.72, headlight_y - 0.05, front_z),
			amber,
			"TurnSignalFL"
		)
		_add_box_mesh(
			_lights_root,
			Vector3(0.12, 0.06, 0.04),
			Vector3(0.72, headlight_y - 0.05, front_z),
			amber,
			"TurnSignalFR"
		)


## Build taillight glow meshes at the rear.
func _build_taillights(profile: Dictionary) -> void:
	var trunk: Array = profile["trunk"]
	var main: Array = profile["main"]
	var rear_z: float = main[4] - main[2] * 0.5
	var taillight_y: float = trunk[3] + 0.05

	var red := Color(1.0, 0.05, 0.05, 1.0)
	var off_red := Color(0.3, 0.02, 0.02, 1.0)
	var mat := _make_emissive_material(red if taillight_on else off_red, 2.5 if taillight_on else 0.0)

	# Left taillight
	_add_box_mesh(
		_lights_root,
		Vector3(0.3, 0.1, 0.05),
		Vector3(-0.55, taillight_y, rear_z),
		mat,
		"TaillightL"
	)
	# Right taillight
	_add_box_mesh(
		_lights_root,
		Vector3(0.3, 0.1, 0.05),
		Vector3(0.55, taillight_y, rear_z),
		mat,
		"TaillightR"
	)

	# Reverse light (white, small, center low)
	if detail_level == DetailLevel.FULL:
		var white := _make_emissive_material(Color(0.9, 0.9, 1.0), 0.5)
		_add_box_mesh(
			_lights_root,
			Vector3(0.15, 0.06, 0.04),
			Vector3(0.0, taillight_y - 0.08, rear_z),
			white,
			"ReverseLight"
		)


## Build exhaust pipe at the rear underside.
func _build_exhaust(profile: Dictionary) -> void:
	var main: Array = profile["main"]
	var rear_z: float = main[4] - main[2] * 0.5
	var chrome := _make_chrome_material()

	var exhaust_node := Node3D.new()
	exhaust_node.name = "Exhaust"
	_body_root.add_child(exhaust_node)

	# Exhaust pipe (cylinder)
	_exhaust_mesh = _add_cylinder_mesh(
		exhaust_node,
		0.04,
		0.25,
		Vector3(0.4, 0.15, rear_z - 0.1),
		chrome,
		"ExhaustPipe"
	)
	_exhaust_mesh.rotation_degrees = Vector3(90, 0, 0)

	# Second exhaust for muscle cars
	if body_style == BodyStyle.MUSCLE:
		var pipe2 := _add_cylinder_mesh(
			exhaust_node,
			0.045,
			0.28,
			Vector3(-0.4, 0.15, rear_z - 0.1),
			chrome,
			"ExhaustPipe2"
		)
		pipe2.rotation_degrees = Vector3(90, 0, 0)


## Build neon undercarriage glow strips.
func _build_neon_undercarriage(profile: Dictionary) -> void:
	_neon_root = Node3D.new()
	_neon_root.name = "NeonUndercarriage"
	add_child(_neon_root)

	var main: Array = profile["main"]
	var glow_mat := _make_emissive_material(neon_color, 3.5)
	var glow_y := 0.08  # Just above ground

	# Side strips (left and right)
	_add_box_mesh(
		_neon_root,
		Vector3(0.06, 0.02, main[2] * 0.7),
		Vector3(-main[0] * 0.45, glow_y, main[4]),
		glow_mat,
		"NeonStripL"
	)
	_add_box_mesh(
		_neon_root,
		Vector3(0.06, 0.02, main[2] * 0.7),
		Vector3(main[0] * 0.45, glow_y, main[4]),
		glow_mat,
		"NeonStripR"
	)

	# Front strip
	_add_box_mesh(
		_neon_root,
		Vector3(main[0] * 0.6, 0.02, 0.06),
		Vector3(0.0, glow_y, main[4] + main[2] * 0.3),
		glow_mat,
		"NeonStripFront"
	)

	# Rear strip
	_add_box_mesh(
		_neon_root,
		Vector3(main[0] * 0.6, 0.02, 0.06),
		Vector3(0.0, glow_y, main[4] - main[2] * 0.3),
		glow_mat,
		"NeonStripRear"
	)

	# OmniLight to cast neon color on ground
	var neon_light := OmniLight3D.new()
	neon_light.name = "NeonGlowLight"
	neon_light.light_color = neon_color
	neon_light.light_energy = 1.5
	neon_light.omni_range = 4.0
	neon_light.position = Vector3(0.0, 0.15, main[4])
	_neon_root.add_child(neon_light)


## Build side mirrors (small boxes on cabin sides).
func _build_side_mirrors(profile: Dictionary) -> void:
	var cabin: Array = profile["cabin"]
	var chrome := _make_chrome_material()

	var mirror_y: float = cabin[3] - 0.05
	var mirror_z: float = cabin[4] + cabin[2] * 0.35

	_add_box_mesh(
		_body_root,
		Vector3(0.08, 0.06, 0.1),
		Vector3(-cabin[0] * 0.5 - 0.08, mirror_y, mirror_z),
		chrome,
		"MirrorL"
	)
	_add_box_mesh(
		_body_root,
		Vector3(0.08, 0.06, 0.1),
		Vector3(cabin[0] * 0.5 + 0.08, mirror_y, mirror_z),
		chrome,
		"MirrorR"
	)


## Build front and rear bumper bars.
func _build_bumpers(profile: Dictionary) -> void:
	var main: Array = profile["main"]
	var bumper_mat := StandardMaterial3D.new()
	bumper_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	bumper_mat.roughness = 0.7
	bumper_mat.metallic = 0.3

	var front_z: float = main[4] + main[2] * 0.5 + 0.04
	var rear_z: float = main[4] - main[2] * 0.5 - 0.04

	# Front bumper
	_add_box_mesh(
		_body_root,
		Vector3(main[0] + 0.05, 0.18, 0.08),
		Vector3(0.0, 0.25, front_z),
		bumper_mat,
		"BumperFront"
	)
	# Rear bumper
	_add_box_mesh(
		_body_root,
		Vector3(main[0] + 0.05, 0.18, 0.08),
		Vector3(0.0, 0.25, rear_z),
		bumper_mat,
		"BumperRear"
	)


## Refresh body material color on all body mesh children.
func _refresh_body_materials() -> void:
	if _body_root == null:
		return
	var mat := _make_body_material()
	for child in _body_root.get_children():
		if child is MeshInstance3D and child.name.begins_with("Main") or \
			child.name.begins_with("Hood") or child.name.begins_with("Cabin") or \
			child.name.begins_with("Trunk"):
			child.material_override = mat


## Refresh light emissive state.
func _refresh_light_state() -> void:
	if _lights_root == null:
		return
	for child in _lights_root.get_children():
		if child is MeshInstance3D:
			if child.name.begins_with("Headlight"):
				var c := Color(1.0, 0.95, 0.8) if headlight_on else Color(0.4, 0.38, 0.35)
				child.material_override = _make_emissive_material(c, 3.0 if headlight_on else 0.0)
			elif child.name.begins_with("Taillight"):
				var c := Color(1.0, 0.05, 0.05) if taillight_on else Color(0.3, 0.02, 0.02)
				child.material_override = _make_emissive_material(c, 2.5 if taillight_on else 0.0)


## Get the position of the exhaust pipe tip (for VFX particle attachment).
func get_exhaust_position() -> Vector3:
	if _exhaust_mesh:
		return _exhaust_mesh.global_position
	# Fallback to approximate rear center
	var main: Array = BODY_PROFILES[body_style]["main"]
	return global_position + Vector3(0.4, 0.15, -(main[2] * 0.5 + 0.2))


## Get all wheel visual nodes for spinning animation.
func get_wheel_visuals() -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	if _wheels_root:
		for child in _wheels_root.get_children():
			wheels.append(child)
	return wheels
