## Procedural building generator for the MIDNIGHT GRIND cityscape.
## Creates varied low-poly buildings with window grids, neon signage,
## rooftop details (AC units, water towers), and fire escapes.
## Designed for the PS1/PS2 retro night-city aesthetic.
class_name BuildingGenerator
extends Node3D

# --- Configuration ---
@export var building_width: float = 15.0
@export var building_depth: float = 15.0
@export var floor_count: int = 5
@export var floor_height: float = 3.5
@export var has_ground_floor_neon: bool = true
@export var has_fire_escape: bool = false
@export var has_rooftop_details: bool = true
@export var wall_color: Color = Color(0.12, 0.1, 0.15, 1.0)
@export var wall_color_variation: float = 0.03
@export var window_lit_probability: float = 0.4
@export var seed_value: int = -1  ## -1 = random each build

# --- Neon palette for ground-floor signage ---
const NEON_PALETTE: Array[Color] = [
	Color(1.0, 0.0, 0.4),    # Hot pink
	Color(0.0, 1.0, 0.8),    # Cyan/teal
	Color(0.4, 0.0, 1.0),    # Purple
	Color(1.0, 0.3, 0.0),    # Orange
	Color(0.0, 0.6, 1.0),    # Blue
	Color(1.0, 1.0, 0.0),    # Yellow
	Color(0.0, 1.0, 0.3),    # Green
]

# --- Window colors ---
const WINDOW_LIT_COLORS: Array[Color] = [
	Color(1.0, 0.9, 0.6),    # Warm yellow
	Color(0.6, 0.8, 1.0),    # Cool blue (TV glow)
	Color(1.0, 0.7, 0.5),    # Warm orange
	Color(0.8, 0.9, 1.0),    # White fluorescent
]

const WINDOW_DARK_COLOR := Color(0.03, 0.03, 0.05, 1.0)

var _rng := RandomNumberGenerator.new()
var _building_root: Node3D = null


func _ready() -> void:
	build()


## Build the entire building from scratch.
func build() -> void:
	_clear_children()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

	_building_root = Node3D.new()
	_building_root.name = "BuildingRoot"
	add_child(_building_root)

	var total_height: float = floor_count * floor_height

	_build_walls(total_height)
	_build_windows(total_height)

	if has_ground_floor_neon:
		_build_ground_floor_neon()

	if has_rooftop_details:
		_build_rooftop(total_height)

	if has_fire_escape:
		_build_fire_escape(total_height)

	print("[BuildingGenerator] Built %d-floor building (%.0fx%.0f, seed=%d)" % [
		floor_count, building_width, building_depth,
		_rng.seed if seed_value >= 0 else -1
	])


## Rebuild with new parameters.
func rebuild(p_width: float, p_depth: float, p_floors: int, p_seed: int = -1) -> void:
	building_width = p_width
	building_depth = p_depth
	floor_count = p_floors
	seed_value = p_seed
	build()


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()
	_building_root = null


# ---------------------------------------------------------------------------
# Wall construction
# ---------------------------------------------------------------------------

func _make_wall_material(base_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Apply slight random color variation for gritty city look
	var variation := wall_color_variation
	mat.albedo_color = Color(
		clampf(base_color.r + _rng.randf_range(-variation, variation), 0.0, 1.0),
		clampf(base_color.g + _rng.randf_range(-variation, variation), 0.0, 1.0),
		clampf(base_color.b + _rng.randf_range(-variation, variation), 0.0, 1.0),
		1.0
	)
	mat.roughness = _rng.randf_range(0.75, 0.95)
	mat.metallic = 0.0
	return mat


func _build_walls(total_height: float) -> void:
	var walls_node := Node3D.new()
	walls_node.name = "Walls"
	_building_root.add_child(walls_node)

	# Main building volume (single box for the primary structure)
	var main_mat := _make_wall_material(wall_color)
	var main_mesh := MeshInstance3D.new()
	main_mesh.name = "MainVolume"
	var box := BoxMesh.new()
	box.size = Vector3(building_width, total_height, building_depth)
	main_mesh.mesh = box
	main_mesh.material_override = main_mat
	main_mesh.position = Vector3(0.0, total_height * 0.5, 0.0)
	walls_node.add_child(main_mesh)

	# Foundation strip (slightly wider, darker base)
	var foundation_mat := _make_wall_material(wall_color * 0.7)
	var foundation := MeshInstance3D.new()
	foundation.name = "Foundation"
	var fbox := BoxMesh.new()
	fbox.size = Vector3(building_width + 0.3, 0.5, building_depth + 0.3)
	foundation.mesh = fbox
	foundation.material_override = foundation_mat
	foundation.position = Vector3(0.0, 0.25, 0.0)
	walls_node.add_child(foundation)

	# Cornice at the top (decorative ledge)
	var cornice_mat := _make_wall_material(wall_color * 0.85)
	var cornice := MeshInstance3D.new()
	cornice.name = "Cornice"
	var cbox := BoxMesh.new()
	cbox.size = Vector3(building_width + 0.2, 0.3, building_depth + 0.2)
	cornice.mesh = cbox
	cornice.material_override = cornice_mat
	cornice.position = Vector3(0.0, total_height + 0.15, 0.0)
	walls_node.add_child(cornice)

	# Vertical pilasters on corners for detail
	if floor_count >= 4:
		var pilaster_mat := _make_wall_material(wall_color * 0.9)
		var pilaster_size := Vector3(0.4, total_height, 0.4)
		var hw: float = building_width * 0.5
		var hd: float = building_depth * 0.5
		var corners := [
			Vector3(-hw, total_height * 0.5, -hd),
			Vector3(hw, total_height * 0.5, -hd),
			Vector3(-hw, total_height * 0.5, hd),
			Vector3(hw, total_height * 0.5, hd),
		]
		for i in range(corners.size()):
			var pilaster := MeshInstance3D.new()
			pilaster.name = "Pilaster_%d" % i
			var pbox := BoxMesh.new()
			pbox.size = pilaster_size
			pilaster.mesh = pbox
			pilaster.material_override = pilaster_mat
			pilaster.position = corners[i]
			walls_node.add_child(pilaster)


# ---------------------------------------------------------------------------
# Window grid
# ---------------------------------------------------------------------------

func _build_windows(total_height: float) -> void:
	var windows_node := Node3D.new()
	windows_node.name = "Windows"
	_building_root.add_child(windows_node)

	var window_w := 0.8
	var window_h := 1.2
	var spacing_x := 2.5
	var spacing_y := floor_height

	# Calculate how many windows fit per wall
	var cols: int = int((building_width - 2.0) / spacing_x)
	var start_x: float = -(cols - 1) * spacing_x * 0.5

	# Front and back walls (along Z axis)
	for face_sign in [-1.0, 1.0]:
		var face_z: float = face_sign * building_depth * 0.5 + face_sign * 0.02
		for floor_idx in range(floor_count):
			# Skip ground floor windows if neon signage is there
			if floor_idx == 0 and has_ground_floor_neon:
				continue
			var win_y: float = floor_idx * spacing_y + spacing_y * 0.6
			for col in range(cols):
				var win_x: float = start_x + col * spacing_x
				var is_lit: bool = _rng.randf() < window_lit_probability
				var win_color: Color
				if is_lit:
					win_color = WINDOW_LIT_COLORS[_rng.randi_range(0, WINDOW_LIT_COLORS.size() - 1)]
				else:
					win_color = WINDOW_DARK_COLOR

				var win_mat: Material
				if is_lit:
					win_mat = _make_window_emissive(win_color, _rng.randf_range(0.8, 2.0))
				else:
					var dark := StandardMaterial3D.new()
					dark.albedo_color = win_color
					dark.roughness = 0.3
					dark.metallic = 0.1
					win_mat = dark

				var win := MeshInstance3D.new()
				win.name = "Window_F%d_C%d_%s" % [floor_idx, col, "front" if face_sign > 0 else "back"]
				var wbox := BoxMesh.new()
				wbox.size = Vector3(window_w, window_h, 0.05)
				win.mesh = wbox
				win.material_override = win_mat
				win.position = Vector3(win_x, win_y, face_z)
				windows_node.add_child(win)

	# Side walls (along X axis)
	var side_cols: int = int((building_depth - 2.0) / spacing_x)
	var side_start_z: float = -(side_cols - 1) * spacing_x * 0.5

	for face_sign in [-1.0, 1.0]:
		var face_x: float = face_sign * building_width * 0.5 + face_sign * 0.02
		for floor_idx in range(floor_count):
			if floor_idx == 0 and has_ground_floor_neon:
				continue
			var win_y: float = floor_idx * spacing_y + spacing_y * 0.6
			for col in range(side_cols):
				var win_z: float = side_start_z + col * spacing_x
				var is_lit: bool = _rng.randf() < window_lit_probability
				var win_color: Color
				if is_lit:
					win_color = WINDOW_LIT_COLORS[_rng.randi_range(0, WINDOW_LIT_COLORS.size() - 1)]
				else:
					win_color = WINDOW_DARK_COLOR

				var win_mat: Material
				if is_lit:
					win_mat = _make_window_emissive(win_color, _rng.randf_range(0.8, 2.0))
				else:
					var dark := StandardMaterial3D.new()
					dark.albedo_color = win_color
					dark.roughness = 0.3
					dark.metallic = 0.1
					win_mat = dark

				var win := MeshInstance3D.new()
				win.name = "Window_F%d_C%d_%s" % [floor_idx, col, "left" if face_sign < 0 else "right"]
				var wbox := BoxMesh.new()
				wbox.size = Vector3(0.05, window_h, window_w)
				win.mesh = wbox
				win.material_override = win_mat
				win.position = Vector3(face_x, win_y, win_z)
				windows_node.add_child(win)


func _make_window_emissive(color: Color, strength: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = strength
	mat.roughness = 0.2
	mat.metallic = 0.1
	return mat


# ---------------------------------------------------------------------------
# Ground floor neon signage
# ---------------------------------------------------------------------------

func _build_ground_floor_neon() -> void:
	var neon_node := Node3D.new()
	neon_node.name = "NeonSigns"
	_building_root.add_child(neon_node)

	var sign_y: float = floor_height * 0.7
	var sign_height := 1.0
	var sign_width: float = _rng.randf_range(building_width * 0.3, building_width * 0.6)

	# Neon sign panel on front face
	var neon_color: Color = NEON_PALETTE[_rng.randi_range(0, NEON_PALETTE.size() - 1)]
	var sign_z: float = building_depth * 0.5 + 0.08

	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = neon_color
	sign_mat.emission_enabled = true
	sign_mat.emission = neon_color
	sign_mat.emission_energy_multiplier = 3.0

	var sign_mesh := MeshInstance3D.new()
	sign_mesh.name = "NeonPanel_Front"
	var sbox := BoxMesh.new()
	sbox.size = Vector3(sign_width, sign_height, 0.06)
	sign_mesh.mesh = sbox
	sign_mesh.material_override = sign_mat
	sign_mesh.position = Vector3(
		_rng.randf_range(-building_width * 0.15, building_width * 0.15),
		sign_y,
		sign_z
	)
	neon_node.add_child(sign_mesh)

	# Neon OmniLight to illuminate sidewalk
	var neon_light := OmniLight3D.new()
	neon_light.name = "NeonLight_Front"
	neon_light.light_color = neon_color
	neon_light.light_energy = 2.5
	neon_light.omni_range = 8.0
	neon_light.position = Vector3(sign_mesh.position.x, sign_y, sign_z + 1.0)
	neon_node.add_child(neon_light)

	# Optionally add a second sign on a side face
	if _rng.randf() > 0.4:
		var side_color: Color = NEON_PALETTE[_rng.randi_range(0, NEON_PALETTE.size() - 1)]
		var side_sign_w: float = _rng.randf_range(building_depth * 0.2, building_depth * 0.4)
		var side_sign_x: float = building_width * 0.5 + 0.08
		if _rng.randf() > 0.5:
			side_sign_x *= -1.0

		var side_mat := StandardMaterial3D.new()
		side_mat.albedo_color = side_color
		side_mat.emission_enabled = true
		side_mat.emission = side_color
		side_mat.emission_energy_multiplier = 2.5

		var side_mesh := MeshInstance3D.new()
		side_mesh.name = "NeonPanel_Side"
		var ssbox := BoxMesh.new()
		ssbox.size = Vector3(0.06, sign_height * 0.8, side_sign_w)
		side_mesh.mesh = ssbox
		side_mesh.material_override = side_mat
		side_mesh.position = Vector3(side_sign_x, sign_y + 0.5, 0.0)
		neon_node.add_child(side_mesh)

		var side_light := OmniLight3D.new()
		side_light.name = "NeonLight_Side"
		side_light.light_color = side_color
		side_light.light_energy = 2.0
		side_light.omni_range = 6.0
		side_light.position = Vector3(
			side_sign_x + (1.0 if side_sign_x > 0 else -1.0),
			sign_y + 0.5,
			0.0
		)
		neon_node.add_child(side_light)

	# Ground floor storefront darker panel below sign
	var storefront_mat := StandardMaterial3D.new()
	storefront_mat.albedo_color = Color(0.06, 0.04, 0.08, 1.0)
	storefront_mat.roughness = 0.6
	storefront_mat.metallic = 0.1

	var storefront := MeshInstance3D.new()
	storefront.name = "Storefront"
	var sfbox := BoxMesh.new()
	sfbox.size = Vector3(building_width + 0.1, floor_height, 0.08)
	storefront.mesh = sfbox
	storefront.material_override = storefront_mat
	storefront.position = Vector3(0.0, floor_height * 0.5, building_depth * 0.5 + 0.04)
	neon_node.add_child(storefront)


# ---------------------------------------------------------------------------
# Rooftop details (AC units, water tower, antenna)
# ---------------------------------------------------------------------------

func _build_rooftop(total_height: float) -> void:
	var roof_node := Node3D.new()
	roof_node.name = "Rooftop"
	_building_root.add_child(roof_node)

	var roof_y: float = total_height + 0.01
	var hw: float = building_width * 0.5
	var hd: float = building_depth * 0.5

	# Roof surface (flat, slightly darker)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = wall_color * 0.8
	roof_mat.roughness = 0.9

	# AC units (2-4 boxes)
	var ac_mat := StandardMaterial3D.new()
	ac_mat.albedo_color = Color(0.35, 0.35, 0.38, 1.0)
	ac_mat.roughness = 0.7
	ac_mat.metallic = 0.2

	var ac_count: int = _rng.randi_range(2, 4)
	for i in range(ac_count):
		var ac := MeshInstance3D.new()
		ac.name = "ACUnit_%d" % i
		var acbox := BoxMesh.new()
		var ac_w: float = _rng.randf_range(1.0, 2.0)
		var ac_h: float = _rng.randf_range(0.8, 1.5)
		var ac_d: float = _rng.randf_range(0.8, 1.5)
		acbox.size = Vector3(ac_w, ac_h, ac_d)
		ac.mesh = acbox
		ac.material_override = ac_mat
		ac.position = Vector3(
			_rng.randf_range(-hw * 0.6, hw * 0.6),
			roof_y + ac_h * 0.5,
			_rng.randf_range(-hd * 0.6, hd * 0.6)
		)
		roof_node.add_child(ac)

	# Water tower (cylinder on stilts) -- only on taller buildings
	if floor_count >= 4 and _rng.randf() > 0.3:
		var tower_node := Node3D.new()
		tower_node.name = "WaterTower"
		roof_node.add_child(tower_node)

		var tower_x: float = _rng.randf_range(-hw * 0.3, hw * 0.3)
		var tower_z: float = _rng.randf_range(-hd * 0.3, hd * 0.3)
		var tower_radius: float = _rng.randf_range(1.0, 1.8)
		var tower_height: float = _rng.randf_range(2.0, 3.0)
		var stilt_height: float = 1.5

		# Stilts (4 thin cylinders)
		var stilt_mat := StandardMaterial3D.new()
		stilt_mat.albedo_color = Color(0.25, 0.22, 0.2, 1.0)
		stilt_mat.roughness = 0.8
		stilt_mat.metallic = 0.4

		var stilt_offsets := [
			Vector3(-tower_radius * 0.5, 0, -tower_radius * 0.5),
			Vector3(tower_radius * 0.5, 0, -tower_radius * 0.5),
			Vector3(-tower_radius * 0.5, 0, tower_radius * 0.5),
			Vector3(tower_radius * 0.5, 0, tower_radius * 0.5),
		]
		for j in range(4):
			var stilt := MeshInstance3D.new()
			stilt.name = "Stilt_%d" % j
			var scyl := CylinderMesh.new()
			scyl.top_radius = 0.08
			scyl.bottom_radius = 0.08
			scyl.height = stilt_height
			scyl.radial_segments = 4
			stilt.mesh = scyl
			stilt.material_override = stilt_mat
			stilt.position = Vector3(
				tower_x + stilt_offsets[j].x,
				roof_y + stilt_height * 0.5,
				tower_z + stilt_offsets[j].z
			)
			tower_node.add_child(stilt)

		# Tank (cylinder)
		var tank_mat := StandardMaterial3D.new()
		tank_mat.albedo_color = Color(0.3, 0.25, 0.2, 1.0)
		tank_mat.roughness = 0.85
		tank_mat.metallic = 0.1

		var tank := MeshInstance3D.new()
		tank.name = "Tank"
		var tcyl := CylinderMesh.new()
		tcyl.top_radius = tower_radius
		tcyl.bottom_radius = tower_radius
		tcyl.height = tower_height
		tcyl.radial_segments = 8
		tank.mesh = tcyl
		tank.material_override = tank_mat
		tank.position = Vector3(tower_x, roof_y + stilt_height + tower_height * 0.5, tower_z)
		tower_node.add_child(tank)

		# Conical roof on tank
		var cone := MeshInstance3D.new()
		cone.name = "TankRoof"
		var ccyl := CylinderMesh.new()
		ccyl.top_radius = 0.1
		ccyl.bottom_radius = tower_radius + 0.1
		ccyl.height = 0.8
		ccyl.radial_segments = 8
		cone.mesh = ccyl
		cone.material_override = tank_mat
		cone.position = Vector3(tower_x, roof_y + stilt_height + tower_height + 0.4, tower_z)
		tower_node.add_child(cone)

	# Antenna (thin cylinder)
	if _rng.randf() > 0.5:
		var antenna_mat := StandardMaterial3D.new()
		antenna_mat.albedo_color = Color(0.4, 0.4, 0.4, 1.0)
		antenna_mat.metallic = 0.6
		antenna_mat.roughness = 0.3

		var antenna := MeshInstance3D.new()
		antenna.name = "Antenna"
		var acyl := CylinderMesh.new()
		acyl.top_radius = 0.03
		acyl.bottom_radius = 0.06
		acyl.height = _rng.randf_range(3.0, 6.0)
		acyl.radial_segments = 4
		antenna.mesh = acyl
		antenna.material_override = antenna_mat
		antenna.position = Vector3(
			_rng.randf_range(-hw * 0.4, hw * 0.4),
			roof_y + acyl.height * 0.5,
			_rng.randf_range(-hd * 0.4, hd * 0.4)
		)
		roof_node.add_child(antenna)

		# Blinking red light on antenna tip
		var blink_light := OmniLight3D.new()
		blink_light.name = "AntennaLight"
		blink_light.light_color = Color(1, 0, 0)
		blink_light.light_energy = 1.0
		blink_light.omni_range = 3.0
		blink_light.position = Vector3(antenna.position.x, roof_y + acyl.height, antenna.position.z)
		roof_node.add_child(blink_light)


# ---------------------------------------------------------------------------
# Fire escape (simple ladder geometry on one face)
# ---------------------------------------------------------------------------

func _build_fire_escape(total_height: float) -> void:
	var escape_node := Node3D.new()
	escape_node.name = "FireEscape"
	_building_root.add_child(escape_node)

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.2, 0.18, 0.16, 1.0)
	metal_mat.metallic = 0.6
	metal_mat.roughness = 0.5

	# Place on the side wall
	var face_x: float = -building_width * 0.5 - 0.15
	var escape_z: float = _rng.randf_range(-building_depth * 0.2, building_depth * 0.2)

	var platform_width := 1.8
	var platform_depth := 1.2
	var railing_height := 1.0

	for floor_idx in range(1, floor_count):
		var platform_y: float = floor_idx * floor_height

		# Platform (flat box)
		var platform := MeshInstance3D.new()
		platform.name = "Platform_%d" % floor_idx
		var pbox := BoxMesh.new()
		pbox.size = Vector3(platform_depth, 0.06, platform_width)
		platform.mesh = pbox
		platform.material_override = metal_mat
		platform.position = Vector3(face_x - platform_depth * 0.5, platform_y, escape_z)
		escape_node.add_child(platform)

		# Railings (thin boxes for left, right, front)
		var rail_positions := [
			Vector3(face_x - platform_depth * 0.5, platform_y + railing_height * 0.5, escape_z - platform_width * 0.5),
			Vector3(face_x - platform_depth * 0.5, platform_y + railing_height * 0.5, escape_z + platform_width * 0.5),
			Vector3(face_x - platform_depth, platform_y + railing_height * 0.5, escape_z),
		]
		var rail_sizes := [
			Vector3(platform_depth, railing_height, 0.05),
			Vector3(platform_depth, railing_height, 0.05),
			Vector3(0.05, railing_height, platform_width),
		]
		for r in range(3):
			var rail := MeshInstance3D.new()
			rail.name = "Railing_%d_%d" % [floor_idx, r]
			var rbox := BoxMesh.new()
			rbox.size = rail_sizes[r]
			rail.mesh = rbox
			rail.material_override = metal_mat
			rail.position = rail_positions[r]
			escape_node.add_child(rail)

		# Ladder connecting to floor below (vertical thin box)
		if floor_idx > 1:
			var ladder := MeshInstance3D.new()
			ladder.name = "Ladder_%d" % floor_idx
			var lbox := BoxMesh.new()
			lbox.size = Vector3(0.05, floor_height, 0.5)
			ladder.mesh = lbox
			ladder.material_override = metal_mat
			ladder.position = Vector3(
				face_x - platform_depth * 0.8,
				platform_y - floor_height * 0.5,
				escape_z
			)
			escape_node.add_child(ladder)

			# Ladder rungs
			var rung_count: int = int(floor_height / 0.4)
			for rung in range(rung_count):
				var rung_mesh := MeshInstance3D.new()
				rung_mesh.name = "Rung_%d_%d" % [floor_idx, rung]
				var rungbox := BoxMesh.new()
				rungbox.size = Vector3(0.04, 0.04, 0.5)
				rung_mesh.mesh = rungbox
				rung_mesh.material_override = metal_mat
				rung_mesh.position = Vector3(
					face_x - platform_depth * 0.8,
					platform_y - floor_height + rung * 0.4 + 0.2,
					escape_z
				)
				escape_node.add_child(rung_mesh)
