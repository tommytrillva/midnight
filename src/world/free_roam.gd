## Free roam gameplay controller. Manages the player driving around
## Downtown Nova Pacifica, triggering races, garage visits, and dialogue.
extends Node3D

const PlayerVehicleScene := preload("res://scenes/vehicles/player_vehicle.tscn")
const RaceSessionScene := preload("res://scenes/racing/race_session.tscn")

@onready var downtown: Node3D = $Downtown
@onready var free_roam_hud: Node = $FreeRoamHUD
@onready var dialogue_ui: Node = $DialogueUI
@onready var garage_ui: Control = $GarageUI

var player_vehicle: VehicleController = null
var _in_garage_zone: bool = false
var _in_race_zone: bool = false
var _race_session: Node3D = null


func _ready() -> void:
	_spawn_player_vehicle()
	_setup_interactions()
	_setup_dialogue()

	GameManager.change_state(GameManager.GameState.FREE_ROAM)

	# Connect to story events
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)

	if garage_ui:
		garage_ui.visible = false

	print("[FreeRoam] Downtown loaded. Drive around!")


func _spawn_player_vehicle() -> void:
	player_vehicle = PlayerVehicleScene.instantiate() as VehicleController

	# Load vehicle data
	var vid := GameManager.player_data.current_vehicle_id
	var vehicle_data := GameManager.garage.get_vehicle(vid)
	if vehicle_data:
		player_vehicle.setup_from_data(vehicle_data)

	# Position at spawn
	var spawn := downtown.get_node_or_null("PlayerSpawn") as Marker3D
	if spawn:
		player_vehicle.global_transform = spawn.global_transform
	else:
		player_vehicle.global_transform.origin = Vector3(0, 1, 0)

	add_child(player_vehicle)

	# Activate camera
	var camera := player_vehicle.get_node_or_null("CameraMount/ChaseCamera") as CameraController
	if camera:
		camera.target = player_vehicle
		camera.make_current()


func _setup_interactions() -> void:
	# Torres Garage trigger
	var garage_trigger := downtown.get_node_or_null("InteractionPoints/TorresGarage") as Area3D
	if garage_trigger:
		garage_trigger.body_entered.connect(_on_garage_entered)
		garage_trigger.body_exited.connect(_on_garage_exited)

	# Race start trigger
	var race_trigger := downtown.get_node_or_null("InteractionPoints/RaceStartPoint") as Area3D
	if race_trigger:
		race_trigger.body_entered.connect(_on_race_zone_entered)
		race_trigger.body_exited.connect(_on_race_zone_exited)


func _setup_dialogue() -> void:
	if dialogue_ui and dialogue_ui.has_method("setup"):
		dialogue_ui.setup(GameManager.story._dialogue_system)


func _process(_delta: float) -> void:
	if player_vehicle == null:
		return

	# Update free roam HUD speed
	if free_roam_hud:
		var speed_label := free_roam_hud.get_node_or_null("HUD/BottomBar/Speed") as Label
		if speed_label:
			speed_label.text = "%d KM/H" % int(player_vehicle.current_speed_kmh)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _in_garage_zone and GameManager.current_state == GameManager.GameState.FREE_ROAM:
			_open_garage()
		elif _in_race_zone and GameManager.current_state == GameManager.GameState.FREE_ROAM:
			_start_available_race()


func _on_garage_entered(body: Node3D) -> void:
	if body == player_vehicle:
		_in_garage_zone = true
		EventBus.hud_message.emit("Press [F] to enter Torres Garage", 3.0)


func _on_garage_exited(body: Node3D) -> void:
	if body == player_vehicle:
		_in_garage_zone = false


func _on_race_zone_entered(body: Node3D) -> void:
	if body == player_vehicle:
		_in_race_zone = true
		EventBus.hud_message.emit("Press [F] to start a race", 3.0)


func _on_race_zone_exited(body: Node3D) -> void:
	if body == player_vehicle:
		_in_race_zone = false


func _open_garage() -> void:
	GameManager.change_state(GameManager.GameState.GARAGE)
	if garage_ui:
		garage_ui.visible = true
		if garage_ui.has_method("refresh"):
			garage_ui.refresh()


func close_garage() -> void:
	GameManager.change_state(GameManager.GameState.FREE_ROAM)
	if garage_ui:
		garage_ui.visible = false


func _start_available_race() -> void:
	# Check for story mission races first
	var available := GameManager.story.available_missions
	var race_mission_id := ""
	for mid in available:
		var m := GameManager.story.get_mission(mid)
		if m.get("type", "") in ["street_sprint", "circuit", "drag", "touge"]:
			race_mission_id = mid
			break

	if not race_mission_id.is_empty():
		GameManager.story.start_mission(race_mission_id)
		return

	# Freeplay race
	_launch_race(_create_freeplay_race())


func _create_freeplay_race() -> RaceData:
	var data := RaceData.new()
	data.race_id = "freeplay_%d" % randi()
	data.race_name = "Street Sprint"
	data.race_type = RaceManager.RaceType.STREET_SPRINT
	data.tier = GameManager.reputation.get_tier()
	data.ai_count = 3
	data.ai_names = ["Street Racer", "Local", "Newcomer"]
	data.ai_difficulty = 0.3 + GameManager.reputation.get_tier() * 0.1
	data.base_payout = 500
	return data


func _launch_race(data: RaceData) -> void:
	# Hide free roam, show race session
	_hide_free_roam()

	_race_session = RaceSessionScene.instantiate()
	add_child(_race_session)
	_race_session.race_session_complete.connect(_on_race_complete)
	_race_session.setup_race(data)


func _on_race_complete(results: Dictionary) -> void:
	if _race_session:
		_race_session.cleanup()
		_race_session.queue_free()
		_race_session = null

	_show_free_roam()
	GameManager.change_state(GameManager.GameState.FREE_ROAM)

	# Trigger post-race dialogue if story mission
	if results.get("is_story_mission", false):
		var mission_id: String = results.get("mission_id", "")
		var mission := GameManager.story.get_mission(mission_id)
		var dialogue_id := ""
		if results.get("player_won", false):
			dialogue_id = mission.get("post_win_dialogue", "")
		else:
			dialogue_id = mission.get("post_lose_dialogue", "")
		if not dialogue_id.is_empty():
			GameManager.story._dialogue_system.start_dialogue(dialogue_id)

	# Autosave after race
	SaveManager.autosave()


func _on_mission_started(mission_id: String) -> void:
	var mission := GameManager.story.get_mission(mission_id)
	var mtype: String = mission.get("type", "")

	# Story-only missions just play dialogue (handled by StoryManager)
	# Race missions: after pre-dialogue ends, launch the race
	if mtype in ["street_sprint", "circuit", "drag", "touge"]:
		# Will be handled in _on_dialogue_ended
		pass


func _on_dialogue_ended(dialogue_id: String) -> void:
	# Check if a race mission's pre-dialogue just ended
	for mid in GameManager.story.active_missions:
		var m := GameManager.story.get_mission(mid)
		if m.get("pre_dialogue", "") == dialogue_id:
			var mtype: String = m.get("type", "")
			if mtype in ["street_sprint", "circuit", "drag", "touge"]:
				var data := _create_story_race(mid, m)
				_launch_race(data)
			break


func _create_story_race(mission_id: String, mission: Dictionary) -> RaceData:
	var data := RaceData.new()
	data.race_id = mission_id
	data.race_name = mission.get("name", "Race")
	data.is_story_mission = true
	data.mission_id = mission_id

	match mission.get("type", "street_sprint"):
		"street_sprint":
			data.race_type = RaceManager.RaceType.STREET_SPRINT
		"circuit":
			data.race_type = RaceManager.RaceType.CIRCUIT
		"drag":
			data.race_type = RaceManager.RaceType.DRAG
		"touge":
			data.race_type = RaceManager.RaceType.TOUGE

	data.tier = 1
	data.ai_count = 1
	data.ai_names = ["Street Racer"]
	data.ai_difficulty = 0.35
	data.pre_race_dialogue_id = mission.get("pre_dialogue", "")
	data.post_race_win_dialogue_id = mission.get("post_win_dialogue", "")
	data.post_race_lose_dialogue_id = mission.get("post_lose_dialogue", "")
	return data


func _hide_free_roam() -> void:
	if player_vehicle:
		player_vehicle.visible = false
		player_vehicle.set_physics_process(false)
	downtown.visible = false
	if free_roam_hud:
		free_roam_hud.visible = false


func _show_free_roam() -> void:
	if player_vehicle:
		player_vehicle.visible = true
		player_vehicle.set_physics_process(true)
	downtown.visible = true
	if free_roam_hud:
		free_roam_hud.visible = true
