extends Area3D
class_name MissionTrigger

## Mission Trigger - Detects player proximity and triggers story missions
##
## This trigger connects to StoryManager to check mission availability,
## shows UI prompts, and handles mission activation.

# Mission configuration
@export var mission_id: String = ""
@export var character_name: String = ""
@export var auto_trigger: bool = false
@export var show_indicator: bool = true
@export var interaction_key: String = "interact"  # Input action name

# Visual indicator settings
@export_group("Visual Indicator")
@export var indicator_color: Color = Color.YELLOW
@export var indicator_height: float = 3.0
@export var indicator_scale: float = 1.0

# Internal state
var player_in_area: bool = false
var player_node: Node3D = null
var mission_available: bool = false
var mission_triggered: bool = false
var indicator_mesh: MeshInstance3D = null
var prompt_label: Label3D = null

signal mission_activated(mission_id: String)
signal player_entered_trigger
signal player_exited_trigger

func _ready():
	# Set up Area3D
	monitoring = true
	monitorable = false

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Validate mission_id
	if mission_id.is_empty():
		push_warning("MissionTrigger has no mission_id set!")

	# Create visual indicator
	if show_indicator:
		_create_indicator()

	# Connect to StoryManager signals
	if StoryManager:
		StoryManager.mission_started.connect(_on_mission_started)
		StoryManager.mission_completed.connect(_on_mission_completed)

	# Initial mission availability check
	_check_mission_availability()

	print("MissionTrigger initialized: ", mission_id)

func _process(_delta):
	# Handle player interaction
	if player_in_area and mission_available and not auto_trigger:
		if Input.is_action_just_pressed(interaction_key):
			_activate_mission()

	# Update indicator visibility and animation
	if indicator_mesh:
		indicator_mesh.visible = player_in_area and mission_available
		if indicator_mesh.visible:
			# Rotate indicator for visibility
			indicator_mesh.rotate_y(1.0 * _delta)

	# Update prompt label
	if prompt_label:
		prompt_label.visible = player_in_area and mission_available and not auto_trigger

func _on_body_entered(body: Node3D):
	"""Detect when player enters trigger area"""
	if body.is_in_group("player") or body.is_in_group("player_vehicle"):
		player_node = body
		player_in_area = true
		player_entered_trigger.emit()

		print("Player entered mission trigger: ", mission_id)

		# Check if mission is available
		_check_mission_availability()

		# Auto-trigger if enabled
		if auto_trigger and mission_available:
			_activate_mission()

func _on_body_exited(body: Node3D):
	"""Detect when player exits trigger area"""
	if body == player_node:
		player_in_area = false
		player_node = null
		player_exited_trigger.emit()

		print("Player exited mission trigger: ", mission_id)

func _check_mission_availability():
	"""Check if the mission is available to activate"""
	if mission_id.is_empty() or not StoryManager:
		mission_available = false
		return

	var mission = StoryManager.get_mission(mission_id)
	if mission.is_empty():
		push_warning("Mission not found in StoryManager: ", mission_id)
		mission_available = false
		return

	# Mission is available if requirements are met and it hasn't been completed
	var requirements_met = StoryManager.check_requirements(mission.requirements)
	var not_completed = not mission.completed
	var not_triggered = not mission.triggered

	mission_available = requirements_met and not_completed and not_triggered

	if mission_available:
		print("Mission available: ", mission.title)

func _activate_mission():
	"""Activate the mission"""
	if mission_triggered or not mission_available:
		return

	mission_triggered = true
	print("Activating mission: ", mission_id)

	# Trigger dialogue if character is specified
	if not character_name.is_empty() and StoryManager:
		StoryManager.trigger_dialogue(character_name, global_position)

	# Trigger the mission in StoryManager
	if StoryManager:
		StoryManager.trigger_mission(mission_id)

	# Emit signal
	mission_activated.emit(mission_id)

	# Hide indicator after activation
	if indicator_mesh:
		indicator_mesh.visible = false
	if prompt_label:
		prompt_label.visible = false

func _on_mission_started(started_mission_id: String):
	"""Handle mission started signal from StoryManager"""
	if started_mission_id == mission_id:
		mission_triggered = true
		mission_available = false

func _on_mission_completed(completed_mission_id: String):
	"""Handle mission completed signal from StoryManager"""
	# Check if any new missions became available
	_check_mission_availability()

func _create_indicator():
	"""Create visual indicator for the mission trigger"""
	# Create indicator mesh (cylinder or sphere above the trigger)
	indicator_mesh = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.3 * indicator_scale
	mesh.bottom_radius = 0.5 * indicator_scale
	mesh.height = 1.0 * indicator_scale
	indicator_mesh.mesh = mesh

	# Create material for indicator
	var material = StandardMaterial3D.new()
	material.albedo_color = indicator_color
	material.emission_enabled = true
	material.emission = indicator_color
	material.emission_energy_multiplier = 2.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.7
	indicator_mesh.material_override = material

	# Position indicator above trigger
	indicator_mesh.position = Vector3(0, indicator_height, 0)
	add_child(indicator_mesh)
	indicator_mesh.visible = false

	# Create prompt label (3D text)
	prompt_label = Label3D.new()
	prompt_label.text = "[E] Interact"
	prompt_label.font_size = 32
	prompt_label.outline_size = 4
	prompt_label.modulate = Color.WHITE
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.position = Vector3(0, indicator_height + 1.0, 0)
	add_child(prompt_label)
	prompt_label.visible = false

	print("Visual indicator created for: ", mission_id)

func set_mission_id(new_mission_id: String):
	"""Set the mission ID dynamically"""
	mission_id = new_mission_id
	_check_mission_availability()

func set_character_name(new_character_name: String):
	"""Set the character name dynamically"""
	character_name = new_character_name

func set_auto_trigger(enabled: bool):
	"""Enable or disable auto-triggering"""
	auto_trigger = enabled

# Debug helpers
func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()

	if mission_id.is_empty():
		warnings.append("mission_id is not set. This trigger will not function correctly.")

	# Check if trigger has collision shape
	var has_collision = false
	for child in get_children():
		if child is CollisionShape3D:
			has_collision = true
			break

	if not has_collision:
		warnings.append("No CollisionShape3D found. Add a collision shape to detect player.")

	return warnings
