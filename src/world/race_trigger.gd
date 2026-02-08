## Race event trigger for free roam world.
## Place in districts to let players start specific races.
## Displays info label and connects to race session when player interacts.
class_name RaceTrigger
extends Area3D

## Race configuration
@export var race_name: String = "Street Race"
@export var race_type: RaceManager.RaceType = RaceManager.RaceType.STREET_SPRINT
@export var track_scene_path: String = ""
@export var entry_fee: int = 0
@export var base_payout: int = 500
@export var lap_count: int = 1
@export var ai_count: int = 3
@export var required_rep_tier: int = 0

## Visual configuration
@export var marker_color: Color = Color(0, 1, 0.8, 1)
@export var label_text: String = ""

var _player_in_zone: bool = false
var _marker_mesh: MeshInstance3D = null
var _label_3d: Label3D = null


func _ready() -> void:
	# Set collision layer for interaction triggers
	collision_layer = 32

	# Create visual marker if it doesn't exist
	_setup_visual_marker()

	# Setup label
	_setup_label()

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	print("[RaceTrigger] %s ready at %s" % [race_name, global_position])


func _setup_visual_marker() -> void:
	# Check if marker already exists as child
	_marker_mesh = get_node_or_null("VisualMarker") as MeshInstance3D
	if _marker_mesh == null:
		_marker_mesh = MeshInstance3D.new()
		_marker_mesh.name = "VisualMarker"
		add_child(_marker_mesh)

		# Create cylinder mesh for the pad
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 3.0
		cylinder.bottom_radius = 3.0
		cylinder.height = 0.3
		_marker_mesh.mesh = cylinder

		# Position slightly above ground
		_marker_mesh.position = Vector3(0, 0.2, 0)

	# Create or update material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = marker_color
	mat.emission_enabled = true
	mat.emission = marker_color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.7
	_marker_mesh.material_override = mat


func _setup_label() -> void:
	# Check if label already exists
	_label_3d = get_node_or_null("InfoLabel") as Label3D
	if _label_3d == null:
		_label_3d = Label3D.new()
		_label_3d.name = "InfoLabel"
		add_child(_label_3d)

	# Set label text
	if label_text.is_empty():
		var fee_text := "" if entry_fee == 0 else " - $%d Entry" % entry_fee
		_label_3d.text = "%s%s" % [race_name, fee_text]
	else:
		_label_3d.text = label_text

	# Configure label appearance
	_label_3d.position = Vector3(0, 4, 0)
	_label_3d.font_size = 48
	_label_3d.outline_size = 4
	_label_3d.modulate = marker_color
	_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _on_body_entered(body: Node3D) -> void:
	# Check if it's the player vehicle
	if body.is_in_group("player"):
		_player_in_zone = true
		var fee_text := "" if entry_fee == 0 else " ($%d entry)" % entry_fee
		EventBus.hud_message.emit("Press [F] to start %s%s" % [race_name, fee_text], 3.0)
		print("[RaceTrigger] Player entered %s zone" % race_name)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_zone = false
		print("[RaceTrigger] Player exited %s zone" % race_name)


func is_player_in_zone() -> bool:
	return _player_in_zone


func can_enter_race() -> bool:
	# Check if player meets requirements
	if GameManager.reputation.get_tier() < required_rep_tier:
		return false

	if entry_fee > 0 and GameManager.economy.get_cash() < entry_fee:
		return false

	return true


func create_race_data() -> RaceData:
	var data := RaceData.new()
	data.race_id = "freeplay_%s_%d" % [race_name.to_lower().replace(" ", "_"), randi()]
	data.race_name = race_name
	data.race_type = race_type
	data.tier = GameManager.reputation.get_tier()
	data.track_id = track_scene_path
	data.ai_count = ai_count
	data.ai_difficulty = 0.3 + GameManager.reputation.get_tier() * 0.1
	data.entry_fee = entry_fee
	data.base_payout = base_payout
	data.lap_count = lap_count
	data.is_story_mission = false

	# Generate AI names based on race type
	data.ai_names = _generate_ai_names()

	return data


func _generate_ai_names() -> Array[String]:
	var names: Array[String] = []
	var name_pools := {
		RaceManager.RaceType.STREET_SPRINT: ["Speed Demon", "Night Runner", "Street King"],
		RaceManager.RaceType.CIRCUIT: ["Circuit Master", "Track Veteran", "Pro Racer"],
		RaceManager.RaceType.DRIFT: ["Drift King", "Slide Master", "Angle Lord"],
		RaceManager.RaceType.TOUGE: ["Mountain Warrior", "Touge Legend", "Downhill Ace"],
	}

	var pool := name_pools.get(race_type, ["Street Racer", "Local Driver", "Newcomer"])

	for i in range(ai_count):
		if i < pool.size():
			names.append(pool[i])
		else:
			names.append("Racer %d" % (i + 1))

	return names


func _process(_delta: float) -> void:
	# Pulse effect for marker
	if _marker_mesh and _marker_mesh.material_override:
		var mat := _marker_mesh.material_override as StandardMaterial3D
		if mat:
			var pulse := (sin(Time.get_ticks_msec() * 0.003) + 1.0) * 0.5
			mat.emission_energy_multiplier = 1.5 + pulse * 1.5
