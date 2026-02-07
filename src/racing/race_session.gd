## Orchestrates a complete race from start to finish.
## Handles vehicle spawning, AI setup, HUD wiring, and result transitions.
extends Node3D

const PlayerVehicleScene := preload("res://scenes/vehicles/player_vehicle.tscn")

@onready var race_track: RaceTrack = $SprintTrack
@onready var race_hud_node: Node = $RaceHUD
@onready var results_panel: Control = $ResultsUI

var race_data: RaceData = null
var player_vehicle: VehicleController = null
var ai_vehicles: Array[Node3D] = []
var _results_shown: bool = false

signal race_session_complete(results: Dictionary)


func _ready() -> void:
	if results_panel:
		results_panel.visible = false
	EventBus.race_finished.connect(_on_race_finished)


func setup_race(data: RaceData) -> void:
	race_data = data
	_spawn_player()
	_spawn_ai()
	_wire_hud()
	GameManager.change_state(GameManager.GameState.RACING)
	GameManager.race_manager.start_race(data)
	print("[RaceSession] Race ready: %s" % data.race_name)


func _spawn_player() -> void:
	player_vehicle = PlayerVehicleScene.instantiate() as VehicleController
	add_child(player_vehicle)

	# Load player's current vehicle data
	var vehicle_data := GameManager.garage.get_vehicle(
		GameManager.player_data.current_vehicle_id
	)
	if vehicle_data:
		player_vehicle.setup_from_data(vehicle_data)

	# Position at spawn
	var spawn := race_track.get_spawn_position(0)
	player_vehicle.global_transform = spawn

	# Setup camera
	var camera := player_vehicle.get_node_or_null("CameraMount/ChaseCamera") as CameraController
	if camera:
		camera.target = player_vehicle
		camera.make_current()

	# Connect track
	race_track.setup(player_vehicle)


func _spawn_ai() -> void:
	if race_data == null:
		return
	for i in range(race_data.ai_count):
		# For MVP, AI uses simplified path following (no full VehicleBody3D)
		var ai := RaceAI.new()
		ai.racer_id = i + 1
		ai.display_name = race_data.ai_names[i] if i < race_data.ai_names.size() else "Racer %d" % (i + 1)
		ai.difficulty = race_data.ai_difficulty
		ai.path = race_track.racing_line
		add_child(ai)
		ai_vehicles.append(ai)

		var spawn := race_track.get_spawn_position(i + 1)
		ai.global_transform = spawn


func _wire_hud() -> void:
	var hud := race_hud_node
	if hud == null:
		return
	# HUD auto-connects via EventBus signals, but we update speed manually
	pass


func _process(_delta: float) -> void:
	if player_vehicle == null:
		return

	# Update player progress in RaceManager
	if GameManager.race_manager.current_state == RaceManager.RaceState.RACING:
		for racer in GameManager.race_manager.racers:
			if racer.is_player:
				racer.progress = race_track.get_player_progress()
				break

	# Update HUD speed display
	if race_hud_node and race_hud_node.has_method("update_speed"):
		race_hud_node.update_speed(player_vehicle.current_speed_kmh)
	if race_hud_node and race_hud_node.has_method("update_rpm"):
		race_hud_node.update_rpm(
			player_vehicle.current_rpm,
			float(player_vehicle.vehicle_data.redline_rpm) if player_vehicle.vehicle_data else 7000.0
		)
	if race_hud_node and race_hud_node.has_method("update_nitro"):
		race_hud_node.update_nitro(player_vehicle.nitro_amount, player_vehicle.nitro_max)


func _on_race_finished(results: Dictionary) -> void:
	if _results_shown:
		return
	_results_shown = true
	_show_results(results)


func _show_results(results: Dictionary) -> void:
	if results_panel == null:
		# No UI — just emit and return
		await get_tree().create_timer(3.0).timeout
		race_session_complete.emit(results)
		return

	results_panel.visible = true

	# Populate results
	var position_label := results_panel.get_node_or_null("Position") as Label
	if position_label:
		var pos: int = results.get("player_position", 0)
		position_label.text = _ordinal(pos)

	var time_label := results_panel.get_node_or_null("Time") as Label
	if time_label:
		time_label.text = _format_time(results.get("total_time", 0.0))

	var cash_label := results_panel.get_node_or_null("Cash") as Label
	if cash_label:
		var won: bool = results.get("player_won", false)
		var payout := GameManager.economy.get_race_payout(
			"street_sprint", 0 if won else 1, race_data.tier if race_data else 1
		)
		cash_label.text = "+$%d" % payout if won else "$0"

	var continue_btn := results_panel.get_node_or_null("ContinueButton") as Button
	if continue_btn:
		continue_btn.pressed.connect(func():
			race_session_complete.emit(results)
		)
	else:
		# Auto-dismiss after delay
		await get_tree().create_timer(5.0).timeout
		race_session_complete.emit(results)


func cleanup() -> void:
	if player_vehicle:
		player_vehicle.queue_free()
	for ai in ai_vehicles:
		ai.queue_free()
	ai_vehicles.clear()
	GameManager.race_manager.cleanup_race()


func _ordinal(n: int) -> String:
	match n:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return "%dTH" % n


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	var ms := int((seconds - int(seconds)) * 1000)
	return "%d:%02d.%03d" % [mins, secs, ms]
