## Street furniture and prop generator for MIDNIGHT GRIND downtown environment.
## Creates street lights, traffic cones, barriers, dumpsters, parked cars,
## neon signs (TextMesh3D), and puddle reflections for wet-road look.
## All geometry is procedural using built-in Godot mesh types.
class_name StreetProps
extends Node3D

## Which prop type this node should spawn.
enum PropType {
	STREET_LIGHT,
	TRAFFIC_CONE,
	BARRIER,
	DUMPSTER,
	PARKED_CAR,
	NEON_SIGN,
	PUDDLE,
}

# --- Configuration ---
@export var prop_type: PropType = PropType.STREET_LIGHT
@export var light_color: Color = Color(1.0, 0.7, 0.4, 1.0)
@export var neon_text: String = "OPEN"
@export var neon_sign_color: Color = Color(1.0, 0.0, 0.4, 1.0)
@export var parked_car_color: Color = Color(0.3, 0.3, 0.35, 1.0)
@export var parked_car_style: int = 0  ## 0-3 maps to VehicleVisual.BodyStyle

# --- Neon text options for random sign generation ---
const NEON_TEXTS: Array[String] = [
	"OPEN", "BAR", "NOODLES", "24HR", "DRIFT", "TUNER",
	"GARAGE", "MOTEL", "CAFE", "PARTS", "SPEED", "RACING",
	"CLUB", "TATTOO", "RAMEN", "ARCADE",
]

const NEON_PALETTE: Array[Color] = [
	Color(1.0, 0.0, 0.4),
	Color(0.0, 1.0, 0.8),
	Color(0.4, 0.0, 1.0),
	Color(1.0, 0.3, 0.0),
	Color(0.0, 0.6, 1.0),
	Color(1.0, 1.0, 0.0),
]


func _ready() -> void:
	build()


## Build the configured prop type.
func build() -> void:
	_clear_children()
	match prop_type:
		PropType.STREET_LIGHT:
			_build_street_light()
		PropType.TRAFFIC_CONE:
			_build_traffic_cone()
		PropType.BARRIER:
			_build_barrier()
		PropType.DUMPSTER:
			_build_dumpster()
		PropType.PARKED_CAR:
			_build_parked_car()
		PropType.NEON_SIGN:
			_build_neon_sign()
		PropType.PUDDLE:
			_build_puddle()
	print("[StreetProps] Built %s prop" % PropType.keys()[prop_type])


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()


# ---------------------------------------------------------------------------
# Material helpers
# ---------------------------------------------------------------------------

func _make_metal_material(color: Color = Color(0.3, 0.3, 0.32)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.5
	mat.roughness = 0.4
	return mat


func _make_emissive_material(color: Color, strength: float = 2.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = strength
	return mat


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, node_name: String = "Mesh") -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


func _add_cylinder(parent: Node3D, top_r: float, bot_r: float, height: float, pos: Vector3, mat: Material, segments: int = 8, node_name: String = "Mesh") -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bot_r
	mesh.height = height
	mesh.radial_segments = segments
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	parent.add_child(inst)
	return inst


# ---------------------------------------------------------------------------
# Street Light: pole + arm + lamp housing + light cone mesh + OmniLight3D
# ---------------------------------------------------------------------------

func _build_street_light() -> void:
	var root := Node3D.new()
	root.name = "StreetLight"
	add_child(root)

	var pole_mat := _make_metal_material(Color(0.2, 0.2, 0.22))
	var pole_height := 7.0

	# Main pole
	_add_cylinder(root, 0.08, 0.12, pole_height, Vector3(0, pole_height * 0.5, 0), pole_mat, 6, "Pole")

	# Base plate
	_add_cylinder(root, 0.25, 0.3, 0.15, Vector3(0, 0.075, 0), pole_mat, 6, "Base")

	# Arm extending outward
	var arm_length := 2.0
	_add_box(root, Vector3(arm_length, 0.08, 0.08), Vector3(arm_length * 0.5, pole_height - 0.2, 0), pole_mat, "Arm")

	# Lamp housing (box at end of arm)
	var lamp_mat := _make_metal_material(Color(0.25, 0.25, 0.28))
	_add_box(root, Vector3(0.6, 0.15, 0.35), Vector3(arm_length, pole_height - 0.35, 0), lamp_mat, "LampHousing")

	# Light cone mesh (inverted truncated cone for visible light volume)
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(light_color.r, light_color.g, light_color.b, 0.08)
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var cone := MeshInstance3D.new()
	cone.name = "LightCone"
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.3
	cone_mesh.bottom_radius = 4.0
	cone_mesh.height = pole_height - 0.5
	cone_mesh.radial_segments = 6
	cone.mesh = cone_mesh
	cone.material_override = cone_mat
	cone.position = Vector3(arm_length, (pole_height - 0.5) * 0.5 - 0.2, 0)
	root.add_child(cone)

	# Actual OmniLight3D for scene illumination
	var omni := OmniLight3D.new()
	omni.name = "Light"
	omni.light_color = light_color
	omni.light_energy = 2.5
	omni.omni_range = 20.0
	omni.shadow_enabled = false  # Performance: no shadow for street lights
	omni.position = Vector3(arm_length, pole_height - 0.5, 0)
	root.add_child(omni)

	# Warm glow spot on the lamp face
	var glow_mat := _make_emissive_material(light_color, 3.0)
	_add_box(root, Vector3(0.4, 0.04, 0.25), Vector3(arm_length, pole_height - 0.44, 0), glow_mat, "LampGlow")


# ---------------------------------------------------------------------------
# Traffic Cone: orange cone with white stripe
# ---------------------------------------------------------------------------

func _build_traffic_cone() -> void:
	var root := Node3D.new()
	root.name = "TrafficCone"
	add_child(root)

	# Orange cone body
	var orange_mat := StandardMaterial3D.new()
	orange_mat.albedo_color = Color(1.0, 0.4, 0.05, 1.0)
	orange_mat.roughness = 0.8

	_add_cylinder(root, 0.02, 0.18, 0.5, Vector3(0, 0.25, 0), orange_mat, 6, "ConeBody")

	# White reflective stripe
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.95, 0.95, 0.95, 1.0)
	white_mat.roughness = 0.3
	white_mat.metallic = 0.2

	_add_cylinder(root, 0.08, 0.12, 0.08, Vector3(0, 0.32, 0), white_mat, 6, "Stripe")

	# Base (flat square-ish)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.15, 0.15, 0.15, 1.0)
	base_mat.roughness = 0.9

	_add_box(root, Vector3(0.35, 0.04, 0.35), Vector3(0, 0.02, 0), base_mat, "Base")


# ---------------------------------------------------------------------------
# Barrier: concrete jersey barrier
# ---------------------------------------------------------------------------

func _build_barrier() -> void:
	var root := Node3D.new()
	root.name = "Barrier"
	add_child(root)

	var concrete_mat := StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.55, 0.52, 0.48, 1.0)
	concrete_mat.roughness = 0.95
	concrete_mat.metallic = 0.0

	# Main body (tapered -- wider at bottom)
	# Lower section (wider)
	_add_box(root, Vector3(0.6, 0.45, 2.0), Vector3(0, 0.225, 0), concrete_mat, "LowerSection")
	# Upper section (narrower)
	_add_box(root, Vector3(0.35, 0.45, 2.0), Vector3(0, 0.675, 0), concrete_mat, "UpperSection")

	# Yellow/red stripe warning markings
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.9, 0.7, 0.0, 1.0)
	stripe_mat.roughness = 0.6

	# Diagonal stripe panels on front face
	_add_box(root, Vector3(0.36, 0.15, 0.02), Vector3(0, 0.6, 1.01), stripe_mat, "StripeFront")
	_add_box(root, Vector3(0.36, 0.15, 0.02), Vector3(0, 0.6, -1.01), stripe_mat, "StripeBack")


# ---------------------------------------------------------------------------
# Dumpster: open-top metal container
# ---------------------------------------------------------------------------

func _build_dumpster() -> void:
	var root := Node3D.new()
	root.name = "Dumpster"
	add_child(root)

	var body_mat := _make_metal_material(Color(0.15, 0.25, 0.15))  # Dark green

	# Main body
	_add_box(root, Vector3(1.8, 1.2, 1.2), Vector3(0, 0.7, 0), body_mat, "Body")

	# Rim (slightly wider at top)
	var rim_mat := _make_metal_material(Color(0.18, 0.28, 0.18))
	_add_box(root, Vector3(1.9, 0.08, 1.3), Vector3(0, 1.34, 0), rim_mat, "Rim")

	# Wheels (small cylinders on bottom)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
	wheel_mat.roughness = 0.9

	var wheel_positions := [
		Vector3(-0.7, 0.1, 0.5),
		Vector3(0.7, 0.1, 0.5),
		Vector3(-0.7, 0.1, -0.5),
		Vector3(0.7, 0.1, -0.5),
	]
	for i in range(4):
		var wheel := _add_cylinder(root, 0.1, 0.1, 0.06, wheel_positions[i], wheel_mat, 6, "Wheel_%d" % i)
		wheel.rotation_degrees = Vector3(0, 0, 90)

	# Lid panels (two halves, one slightly open for character)
	var lid_mat := _make_metal_material(Color(0.13, 0.22, 0.13))
	_add_box(root, Vector3(0.85, 0.04, 1.15), Vector3(-0.45, 1.38, 0), lid_mat, "LidL")
	# Right lid slightly angled (open) -- just offset upward and rotated
	var lid_r := _add_box(root, Vector3(0.85, 0.04, 1.15), Vector3(0.5, 1.5, 0), lid_mat, "LidR")
	lid_r.rotation_degrees = Vector3(0, 0, -25)


# ---------------------------------------------------------------------------
# Parked Car: simplified VehicleVisual at LOW detail
# ---------------------------------------------------------------------------

func _build_parked_car() -> void:
	var car := VehicleVisual.new()
	car.name = "ParkedCar"
	car.body_style = parked_car_style as VehicleVisual.BodyStyle
	car.detail_level = VehicleVisual.DetailLevel.LOW
	car.body_color = parked_car_color
	car.headlight_on = false
	car.taillight_on = false
	car.enable_neon_undercarriage = false
	add_child(car)


# ---------------------------------------------------------------------------
# Neon Sign: TextMesh3D with emissive material
# ---------------------------------------------------------------------------

func _build_neon_sign() -> void:
	var root := Node3D.new()
	root.name = "NeonSign"
	add_child(root)

	var text_to_show: String = neon_text if neon_text != "" else NEON_TEXTS[randi() % NEON_TEXTS.size()]
	var color_to_use: Color = neon_sign_color

	# Backing panel (dark rectangle behind text)
	var backing_mat := StandardMaterial3D.new()
	backing_mat.albedo_color = Color(0.04, 0.03, 0.05, 1.0)
	backing_mat.roughness = 0.8

	var text_width: float = text_to_show.length() * 0.45
	_add_box(root, Vector3(text_width + 0.4, 1.0, 0.08), Vector3(0, 0, -0.05), backing_mat, "Backing")

	# Border frame around sign
	var frame_mat := _make_metal_material(Color(0.15, 0.15, 0.18))
	# Top
	_add_box(root, Vector3(text_width + 0.5, 0.06, 0.12), Vector3(0, 0.5, -0.04), frame_mat, "FrameTop")
	# Bottom
	_add_box(root, Vector3(text_width + 0.5, 0.06, 0.12), Vector3(0, -0.5, -0.04), frame_mat, "FrameBottom")
	# Left
	_add_box(root, Vector3(0.06, 1.0, 0.12), Vector3(-(text_width + 0.5) * 0.5, 0, -0.04), frame_mat, "FrameLeft")
	# Right
	_add_box(root, Vector3(0.06, 1.0, 0.12), Vector3((text_width + 0.5) * 0.5, 0, -0.04), frame_mat, "FrameRight")

	# TextMesh3D with neon glow
	var text_mesh_node := MeshInstance3D.new()
	text_mesh_node.name = "NeonText"
	var tmesh := TextMesh.new()
	tmesh.text = text_to_show
	tmesh.font_size = 72
	tmesh.depth = 0.05
	text_mesh_node.mesh = tmesh
	text_mesh_node.material_override = _make_emissive_material(color_to_use, 4.0)
	text_mesh_node.position = Vector3(0, 0, 0.02)
	# Scale down to fit -- TextMesh is in pixel-ish units
	text_mesh_node.scale = Vector3(0.012, 0.012, 1.0)
	root.add_child(text_mesh_node)

	# Neon glow light illuminating surroundings
	var glow := OmniLight3D.new()
	glow.name = "NeonGlow"
	glow.light_color = color_to_use
	glow.light_energy = 2.5
	glow.omni_range = 8.0
	glow.position = Vector3(0, 0, 1.5)
	root.add_child(glow)


# ---------------------------------------------------------------------------
# Puddle: flat reflective plane for wet road look
# ---------------------------------------------------------------------------

func _build_puddle() -> void:
	var root := Node3D.new()
	root.name = "Puddle"
	add_child(root)

	# Reflective puddle surface
	var puddle_mat := StandardMaterial3D.new()
	puddle_mat.albedo_color = Color(0.05, 0.05, 0.08, 0.6)
	puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle_mat.metallic = 0.95
	puddle_mat.roughness = 0.05
	puddle_mat.specular_mode = BaseMaterial3D.SPECULAR_TOON  # Sharp reflections

	var puddle_mesh := MeshInstance3D.new()
	puddle_mesh.name = "PuddleSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 2.0)
	puddle_mesh.mesh = plane
	puddle_mesh.material_override = puddle_mat
	puddle_mesh.position = Vector3(0, 0.005, 0)  # Just above road surface
	root.add_child(puddle_mesh)

	# Subtle edge darkening (slightly larger darker plane underneath)
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.03, 0.03, 0.05, 0.4)
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.roughness = 0.9

	var edge_mesh := MeshInstance3D.new()
	edge_mesh.name = "PuddleEdge"
	var edge_plane := PlaneMesh.new()
	edge_plane.size = Vector2(3.5, 2.5)
	edge_mesh.mesh = edge_plane
	edge_mesh.material_override = edge_mat
	edge_mesh.position = Vector3(0, 0.003, 0)
	root.add_child(edge_mesh)


# ---------------------------------------------------------------------------
# Static factory methods for batch creation
# ---------------------------------------------------------------------------

## Create a row of street lights along a road segment.
static func create_street_light_row(parent: Node3D, start: Vector3, end: Vector3, spacing: float, side_offset: float, color: Color = Color(1.0, 0.7, 0.4)) -> Array[StreetProps]:
	var lights: Array[StreetProps] = []
	var direction: Vector3 = (end - start).normalized()
	var total_dist: float = start.distance_to(end)
	var perpendicular := direction.cross(Vector3.UP).normalized() * side_offset

	var dist := 0.0
	var index := 0
	while dist < total_dist:
		var pos: Vector3 = start + direction * dist + perpendicular
		var light := StreetProps.new()
		light.name = "StreetLight_%d" % index
		light.prop_type = PropType.STREET_LIGHT
		light.light_color = color
		light.position = pos
		# Rotate to face road
		light.look_at(pos + direction, Vector3.UP)
		parent.add_child(light)
		lights.append(light)
		dist += spacing
		index += 1

	print("[StreetProps] Created %d street lights" % lights.size())
	return lights


## Scatter puddles randomly in an area.
static func scatter_puddles(parent: Node3D, center: Vector3, radius: float, count: int) -> Array[StreetProps]:
	var puddles: Array[StreetProps] = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(count):
		var offset := Vector3(
			rng.randf_range(-radius, radius),
			0,
			rng.randf_range(-radius, radius)
		)
		var puddle := StreetProps.new()
		puddle.name = "Puddle_%d" % i
		puddle.prop_type = PropType.PUDDLE
		puddle.position = center + offset
		puddle.rotation_degrees.y = rng.randf_range(0, 360)
		parent.add_child(puddle)
		puddles.append(puddle)

	print("[StreetProps] Scattered %d puddles" % puddles.size())
	return puddles


## Create a cluster of parked cars along a curb.
static func create_parked_car_row(parent: Node3D, start: Vector3, direction: Vector3, count: int, spacing: float = 6.0) -> Array[StreetProps]:
	var cars: Array[StreetProps] = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var car_colors: Array[Color] = [
		Color(0.15, 0.15, 0.18),  # Dark grey
		Color(0.6, 0.6, 0.62),   # Silver
		Color(0.1, 0.1, 0.3),    # Dark blue
		Color(0.3, 0.08, 0.08),  # Dark red
		Color(0.85, 0.85, 0.8),  # White
		Color(0.05, 0.05, 0.05), # Black
	]

	for i in range(count):
		var pos: Vector3 = start + direction.normalized() * (i * spacing)
		var car := StreetProps.new()
		car.name = "ParkedCar_%d" % i
		car.prop_type = PropType.PARKED_CAR
		car.parked_car_color = car_colors[rng.randi_range(0, car_colors.size() - 1)]
		car.parked_car_style = rng.randi_range(0, 3)
		car.position = pos
		# Align car along road direction
		car.look_at(pos + direction, Vector3.UP)
		parent.add_child(car)
		cars.append(car)

	print("[StreetProps] Created %d parked cars" % cars.size())
	return cars
