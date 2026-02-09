## Free roam gameplay controller. Manages the player driving around
## Nova Pacifica districts, triggering races, garage visits, dialogue,
## and district transitions via DistrictManager.
## Uses ScreenTransition for polished scene changes.
extends Node3D

const PlayerVehicleScene := preload("res://scenes/vehicles/player_vehicle.tscn")
const RaceSessionScene := preload("res://scenes/racing/race_session.tscn")
const SkillTreeScene := preload("res://scenes/ui/skill_tree_ui.tscn")
const PauseMenuScene := preload("res://scenes/ui/pause_menu.tscn")

@onready var downtown: Node3D = $Downtown
@onready var free_roam_hud: Node = $FreeRoamHUD
@onready var dialogue_ui: Node = $DialogueUI
@onready var garage_ui: Control = $GarageUI

var player_vehicle: VehicleController = null
var _in_garage_zone: bool = false
var _in_race_zone: bool = false
var _race_session: Node3D = null
var _skill_tree_ui: Node = null
var pause_menu: PauseMenu = null

## District management
var district_manager: DistrictManager = null
var _current_district_node: Node3D = null

## Screen transition reference (found from parent Main scene)
var _screen_transition: ScreenTransition = null


func _ready() -> void:
	print("[FreeRoam] Starting initialization...")
	print("[FreeRoam] Downtown node: %s, visible: %s" % [downtown, downtown.visible if downtown else "null"])

	_spawn_player_vehicle()

	# Initialize district manager
	_setup_district_manager()

	_setup_interactions()
	_setup_dialogue()

	# Find the ScreenTransition node from the main scene tree
	_screen_transition = _find_screen_transition()

	GameManager.change_state(GameManager.GameState.FREE_ROAM)

	# Connect to story events
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)

	# Listen for district changes to re-setup interactions
	EventBus.district_entered.connect(_on_district_entered)

	if garage_ui:
		garage_ui.visible = false

	# Connect skills button from HUD
	if free_roam_hud and free_roam_hud.has_signal("skills_button_pressed"):
		free_roam_hud.skills_button_pressed.connect(_open_skill_tree)

	# Instantiate pause menu
	pause_menu = PauseMenuScene.instantiate()
	add_child(pause_menu)

	_update_hud_district_name()
	print("[FreeRoam] %s loaded. Drive around!" % district_manager.get_current_district_name())
	print("[FreeRoam] Scene children: %s" % get_child_count())
	print("[FreeRoam] Vehicle visible: %s, position: %s" % [player_vehicle.visible if player_vehicle else "null", player_vehicle.global_transform.origin if player_vehicle else "null"])


func _find_screen_transition() -> ScreenTransition:
	## Walk up the tree to find a ScreenTransition node.
	var node := get_parent()
	while node:
		for child in node.get_children():
			if child is ScreenTransition:
				return child
		node = node.get_parent()
	# Not found — create a local fallback
	var st := ScreenTransition.new()
	add_child(st)
	print("[FreeRoam] Created local ScreenTransition (no parent found).")
	return st


func _setup_district_manager() -> void:
	district_manager = DistrictManager.new()
	district_manager.name = "DistrictManager"
	add_child(district_manager)

	# Set up with this node as the district parent and the player vehicle
	district_manager.setup(self, player_vehicle)

	# Register Downtown as the initially loaded district
	_current_district_node = downtown
	district_manager.set_initial_district(downtown, "downtown")


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
		print("[FreeRoam] Vehicle spawned at: %s" % spawn.global_transform.origin)
	else:
		player_vehicle.global_transform.origin = Vector3(0, 1, 0)
		print("[FreeRoam] Vehicle spawned at default position: Vector3(0, 1, 0)")

	add_child(player_vehicle)
	print("[FreeRoam] Vehicle added to scene tree. Visible: %s" % player_vehicle.visible)

	# Activate camera
	var camera := player_vehicle.get_node_or_null("CameraMount/ChaseCamera") as Camera3D
	if camera:
		if camera is CameraController:
			camera.target = player_vehicle
		camera.make_current()
		print("[FreeRoam] Camera activated at position: %s" % camera.global_position)
		print("[FreeRoam] Camera found and activated. Current: %s, Position: %s" % [camera.current, camera.global_transform.origin])
	else:
		print("[FreeRoam] ERROR: Camera not found at CameraMount/ChaseCamera!")


func _setup_interactions() -> void:
	_setup_district_interactions(_current_district_node)


func _setup_district_interactions(district_node: Node3D) -> void:
	## Connects interaction Area3D signals for the given district.
	if district_node == null:
		return

	# Disconnect previous district interaction signals (safe even if not connected)
	_in_garage_zone = false
	_in_race_zone = false

	# Torres Garage trigger (Downtown-specific)
	var garage_trigger := district_node.get_node_or_null("InteractionPoints/TorresGarage") as Area3D
	if garage_trigger:
		if not garage_trigger.body_entered.is_connected(_on_garage_entered):
			garage_trigger.body_entered.connect(_on_garage_entered)
			garage_trigger.body_exited.connect(_on_garage_exited)

	# Race start trigger — generic name used across districts
	var race_trigger := district_node.get_node_or_null("InteractionPoints/RaceStartPoint") as Area3D
	if race_trigger:
		if not race_trigger.body_entered.is_connected(_on_race_zone_entered):
			race_trigger.body_entered.connect(_on_race_zone_entered)
			race_trigger.body_exited.connect(_on_race_zone_exited)

	# Harbor: Dock Race Start
	var dock_race := district_node.get_node_or_null("InteractionPoints/DockRaceStart") as Area3D
	if dock_race:
		if not dock_race.body_entered.is_connected(_on_race_zone_entered):
			dock_race.body_entered.connect(_on_race_zone_entered)
			dock_race.body_exited.connect(_on_race_zone_exited)

	# Industrial: Illegal Race Meetup
	var illegal_race := district_node.get_node_or_null("InteractionPoints/IllegalRaceMeetup") as Area3D
	if illegal_race:
		if not illegal_race.body_entered.is_connected(_on_race_zone_entered):
			illegal_race.body_entered.connect(_on_race_zone_entered)
			illegal_race.body_exited.connect(_on_race_zone_exited)

	# Industrial: Diesel's Garage
	var diesel_garage := district_node.get_node_or_null("InteractionPoints/DieselsGarage") as Area3D
	if diesel_garage:
		if not diesel_garage.body_entered.is_connected(_on_garage_entered):
			diesel_garage.body_entered.connect(_on_garage_entered)
			diesel_garage.body_exited.connect(_on_garage_exited)

	# Hillside: Route 9 Start (touge race)
	var route9 := district_node.get_node_or_null("InteractionPoints/Route9Start") as Area3D
	if route9:
		if not route9.body_entered.is_connected(_on_race_zone_entered):
			route9.body_entered.connect(_on_race_zone_entered)
			route9.body_exited.connect(_on_race_zone_exited)

	# Setup all RaceTrigger nodes in the RaceEvents group
	_setup_race_triggers(district_node)

	print("[FreeRoam] Interactions setup for %s" % district_node.name)


func _setup_race_triggers(district_node: Node3D) -> void:
	## Find and setup all RaceTrigger nodes in the district.
	var race_events := district_node.get_node_or_null("RaceEvents") as Node3D
	if race_events:
		for child in race_events.get_children():
			if child is RaceTrigger:
				# RaceTrigger handles its own body_entered/exited signals
				# We just need to track it for the interact action
				pass
	print("[FreeRoam] Race triggers setup for %s" % district_node.name)


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
	# Garage state: ESC or pause closes the garage instead of opening pause menu
	if GameManager.current_state == GameManager.GameState.GARAGE:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			close_garage()
			get_viewport().set_input_as_handled()
			return

	# Pause menu toggle
	if event.is_action_pressed("pause"):
		if pause_menu and not pause_menu.is_open():
			if GameManager.current_state not in [
				GameManager.GameState.MENU,
				GameManager.GameState.LOADING,
				GameManager.GameState.PAUSED,
				GameManager.GameState.GARAGE,
			]:
				pause_menu.open_menu()
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("interact"):
		if GameManager.current_state != GameManager.GameState.FREE_ROAM:
			return

		# District transition takes priority when in a transition zone
		if district_manager and district_manager.in_transition_zone:
			var target := district_manager.pending_target_id
			if not target.is_empty():
				print("[FreeRoam] Player requested transition to %s" % target)
				_transition_to_district(target)
				return

		if _in_garage_zone:
			_open_garage()
		elif _in_race_zone:
			_start_available_race()

	# Open skill tree with K key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K and GameManager.current_state == GameManager.GameState.FREE_ROAM:
			_open_skill_tree()


func _on_district_entered(district_id: String) -> void:
	## Called when the player arrives in a new district.
	# Update the current district node reference
	if district_manager and district_manager._current_district_node:
		_current_district_node = district_manager._current_district_node

	# Reconnect interaction zones for the new district
	_setup_district_interactions(_current_district_node)

	# Update HUD
	_update_hud_district_name()

	print("[FreeRoam] Entered district: %s" % district_id)


func _update_hud_district_name() -> void:
	if free_roam_hud == null or district_manager == null:
		return
	var district_label := free_roam_hud.get_node_or_null("HUD/TopBar/DistrictName") as Label
	if district_label:
		district_label.text = district_manager.get_current_district_name()


func _on_garage_entered(body: Node3D) -> void:
	if body == player_vehicle:
		_in_garage_zone = true
		EventBus.hud_message.emit("Press [F] to enter garage", 3.0)


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


# ---------------------------------------------------------------------------
# Garage — Quick fade_black transition (0.3s)
# ---------------------------------------------------------------------------

func _open_garage() -> void:
	# Check for story missions tied to the garage zone first (e.g. torres_garage)
	var story_mid := _get_story_mission_for_zone("garage")
	if not story_mid.is_empty():
		GameManager.story.start_mission(story_mid)
		return

	if _screen_transition:
		await _screen_transition.transition_in(ScreenTransition.TransitionType.FADE_BLACK, 0.15)
	GameManager.change_state(GameManager.GameState.GARAGE)
	if garage_ui:
		garage_ui.visible = true
		if garage_ui.has_method("refresh"):
			garage_ui.refresh()
	if _screen_transition:
		await _screen_transition.transition_out(ScreenTransition.TransitionType.FADE_BLACK, 0.15)


func close_garage() -> void:
	if _screen_transition:
		await _screen_transition.transition_in(ScreenTransition.TransitionType.FADE_BLACK, 0.15)
	GameManager.change_state(GameManager.GameState.FREE_ROAM)
	if garage_ui:
		garage_ui.visible = false
	if _screen_transition:
		await _screen_transition.transition_out(ScreenTransition.TransitionType.FADE_BLACK, 0.15)


# ---------------------------------------------------------------------------
# Skill Tree
# ---------------------------------------------------------------------------

func _open_skill_tree() -> void:
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return
	GameManager.change_state(GameManager.GameState.PAUSED)
	if _skill_tree_ui == null:
		_skill_tree_ui = SkillTreeScene.instantiate()
		add_child(_skill_tree_ui)
	_skill_tree_ui.visible = true
	print("[FreeRoam] Skill tree opened.")


func close_skill_tree() -> void:
	GameManager.change_state(GameManager.GameState.FREE_ROAM)
	if _skill_tree_ui:
		_skill_tree_ui.visible = false
	print("[FreeRoam] Skill tree closed.")


func _get_story_mission_for_zone(zone: String) -> String:
	## Return the ID of an available story mission whose trigger_zone matches.
	for mid in GameManager.story.available_missions:
		var m := GameManager.story.get_mission(mid)
		if m.get("trigger_zone", "") == zone:
			return mid
	return ""


# ---------------------------------------------------------------------------
# District Transition — Pixelate transition (through loading screen if big)
# ---------------------------------------------------------------------------

func _transition_to_district(target_id: String) -> void:
	if _screen_transition:
		await _screen_transition.transition_in(ScreenTransition.TransitionType.PIXELATE, 0.5)

	# Perform the actual district swap
	district_manager.request_transition(target_id)

	if _screen_transition:
		await _screen_transition.transition_out(ScreenTransition.TransitionType.PIXELATE, 0.5)


# ---------------------------------------------------------------------------
# Race Start — Wipe horizontal transition
# ---------------------------------------------------------------------------

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

	# Check for RaceTrigger in current district
	var race_trigger := _get_active_race_trigger()
	if race_trigger:
		if not race_trigger.can_enter_race():
			if race_trigger.entry_fee > 0 and GameManager.economy.get_cash() < race_trigger.entry_fee:
				EventBus.hud_message.emit("Not enough cash! Need $%d" % race_trigger.entry_fee, 3.0)
			else:
				EventBus.hud_message.emit("Rep tier too low for this race!", 3.0)
			return

		# Deduct entry fee
		if race_trigger.entry_fee > 0:
			GameManager.economy.spend(race_trigger.entry_fee, "race_entry")

		_launch_race(race_trigger.create_race_data())
		return

	# Fallback to freeplay race
	_launch_race(_create_freeplay_race())


func _get_active_race_trigger() -> RaceTrigger:
	## Find the RaceTrigger that the player is currently in.
	if _current_district_node == null:
		return null

	var race_events := _current_district_node.get_node_or_null("RaceEvents") as Node3D
	if race_events:
		for child in race_events.get_children():
			if child is RaceTrigger and child.is_player_in_zone():
				return child

	return null


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
	# Wipe horizontal transition into race
	if _screen_transition:
		await _screen_transition.transition_in(ScreenTransition.TransitionType.WIPE_HORIZONTAL, 0.4)

	_hide_free_roam()

	_race_session = RaceSessionScene.instantiate()
	add_child(_race_session)
	_race_session.race_session_complete.connect(_on_race_complete)
	_race_session.setup_race(data)

	if _screen_transition:
		await _screen_transition.transition_out(ScreenTransition.TransitionType.WIPE_HORIZONTAL, 0.4)


func _on_race_complete(results: Dictionary) -> void:
	# Fade black transition back to free roam
	if _screen_transition:
		await _screen_transition.transition_in(ScreenTransition.TransitionType.FADE_BLACK, 0.4)

	if _race_session:
		_race_session.cleanup()
		_race_session.queue_free()
		_race_session = null

	_show_free_roam()
	GameManager.change_state(GameManager.GameState.FREE_ROAM)

	if _screen_transition:
		await _screen_transition.transition_out(ScreenTransition.TransitionType.FADE_BLACK, 0.4)

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
		else:
			# No post-dialogue — check for auto-trigger missions now
			GameManager.story.check_auto_trigger_missions()

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

	# Use mission-specific race configuration if provided
	var race_config: Dictionary = mission.get("race_config", {})
	data.tier = race_config.get("tier", 1)
	data.ai_count = race_config.get("ai_count", 1)
	data.ai_names = race_config.get("ai_names", ["Street Racer"])
	data.ai_difficulty = race_config.get("ai_difficulty", 0.35)
	data.lap_count = race_config.get("lap_count", 0)
	data.pre_race_dialogue_id = mission.get("pre_dialogue", "")
	data.post_race_win_dialogue_id = mission.get("post_win_dialogue", "")
	data.post_race_lose_dialogue_id = mission.get("post_lose_dialogue", "")
	return data


func _hide_free_roam() -> void:
	if player_vehicle:
		player_vehicle.visible = false
		player_vehicle.set_physics_process(false)
	if _current_district_node:
		_current_district_node.visible = false
	if free_roam_hud:
		free_roam_hud.visible = false


func _show_free_roam() -> void:
	if player_vehicle:
		player_vehicle.visible = true
		player_vehicle.set_physics_process(true)
	if _current_district_node:
		_current_district_node.visible = true
	if free_roam_hud:
		free_roam_hud.visible = true
