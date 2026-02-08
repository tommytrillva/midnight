## Orchestrates a complete race from start to finish.
## Handles vehicle spawning, AI setup, HUD wiring, and result transitions.
## Detects race type from RaceData and instantiates the appropriate mode controller
## (DriftScoring, TougeRace, CircuitRace) or falls through to the default sprint flow.
## Includes animated countdown, flash-white GO!, slow-mo finish, and slide-in results.
extends Node3D

const PlayerVehicleScene := preload("res://scenes/vehicles/player_vehicle.tscn")
const AIRacerScene := preload("res://scenes/racing/ai_racer.tscn")
const PauseMenuScene := preload("res://scenes/ui/pause_menu.tscn")

# TODO: Fix race track scene SubResource definitions before enabling these
# const DriftArenaScene := preload("res://scenes/racing/drift_arena.tscn")
# const TougeTrackScene := preload("res://scenes/racing/touge_track.tscn")
# const CircuitTrackScene := preload("res://scenes/racing/circuit_track.tscn")

const PinkSlipUIScene := preload("res://scenes/ui/pink_slip_ui.tscn")
const PinkSlipResultScene := preload("res://scenes/ui/pink_slip_result.tscn")

@onready var race_track: RaceTrack = $SprintTrack
@onready var race_hud_node: Node = $RaceHUD
@onready var results_panel: Control = $ResultsUI

var race_data: RaceData = null
var player_vehicle: VehicleController = null
var ai_vehicles: Array[Node3D] = []
var _results_shown: bool = false

# --- Race-type-specific controllers ---
var drift_scoring: DriftScoring = null
var touge_race: TougeRace = null
var circuit_race: CircuitRace = null
var pause_menu: PauseMenu = null

# --- Transition reference ---
var _screen_transition: ScreenTransition = null

# --- Countdown UI ---
var _countdown_label: Label = null

# --- Pink Slip UI ---
var _pink_slip_ui: PinkSlipUI = null
var _pink_slip_result: PinkSlipResult = null
var _pink_slip_challenge: Dictionary = {}

signal race_session_complete(results: Dictionary)


func _ready() -> void:
	if results_panel:
		results_panel.visible = false
	EventBus.race_finished.connect(_on_race_finished)

	# Instantiate pause menu with race restrictions (save disabled)
	pause_menu = PauseMenuScene.instantiate()
	pause_menu.race_mode = true
	add_child(pause_menu)

	# Find screen transition from the tree
	_screen_transition = _find_screen_transition()

	# Create countdown label overlay
	_create_countdown_label()


func _find_screen_transition() -> ScreenTransition:
	var node := get_parent()
	while node:
		for child in node.get_children():
			if child is ScreenTransition:
				return child
		node = node.get_parent()
	return null


func _create_countdown_label() -> void:
	## Creates a centered label used for 3-2-1-GO countdown display.
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	canvas.name = "CountdownLayer"
	add_child(canvas)

	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 120)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_countdown_label.visible = false
	canvas.add_child(_countdown_label)


func setup_race(data: RaceData) -> void:
	race_data = data

	# Pink slip pre-race: show wagering UI before the race begins
	if data.is_pink_slip:
		_show_pink_slip_pre_race(data)
		return # Race setup continues after player accepts in _on_pink_slip_ui_accepted

	_setup_race_internal(data)


func _setup_race_internal(data: RaceData) -> void:
	## Internal race setup — called directly or after pink slip UI acceptance.
	# Swap in the correct track scene based on race type
	_setup_track_for_type(data.race_type)

	_spawn_player()
	_spawn_ai()
	_wire_hud()
	_wire_race_type(data)

	GameManager.change_state(GameManager.GameState.RACING)

	# Animated pre-race sequence: fade in + countdown
	_run_pre_race_sequence(data)


func _run_pre_race_sequence(data: RaceData) -> void:
	## Pre-race: fade from black, dramatic countdown, flash GO!
	# Fade in from black
	if _screen_transition:
		_screen_transition._setup_for_type(ScreenTransition.TransitionType.FADE_BLACK)
		_screen_transition._color_rect.visible = true
		_screen_transition._color_rect.color = Color(0, 0, 0, 1)
		await _screen_transition.transition_out(ScreenTransition.TransitionType.FADE_BLACK, 0.8)

	# Brief pause before countdown
	await get_tree().create_timer(0.3).timeout

	# Animated countdown: 3, 2, 1, GO!
	await _animate_countdown()

	# Now actually start the race logic
	GameManager.race_manager.start_race(data)
	print("[RaceSession] Race ready: %s (%s)" % [
		data.race_name,
		RaceManager.RaceType.keys()[data.race_type]
	])


func _animate_countdown() -> void:
	## Displays 3-2-1-GO! with scale/fade Tween animations.
	if _countdown_label == null:
		return

	# Count 3, 2, 1
	for i in range(3, 0, -1):
		_countdown_label.text = str(i)
		_countdown_label.visible = true
		_countdown_label.scale = Vector2(2.0, 2.0)
		_countdown_label.modulate = Color(1, 1, 1, 1)
		_countdown_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_countdown_label, "scale", Vector2(1.0, 1.0), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(_countdown_label, "modulate:a", 0.3, 0.7).set_ease(Tween.EASE_IN).set_delay(0.3)
		await tween.finished

		EventBus.countdown_beep.emit(i)
		await get_tree().create_timer(0.3).timeout

	# "GO!" — flash white + screen flash
	_countdown_label.text = "GO!"
	_countdown_label.visible = true
	_countdown_label.scale = Vector2(1.5, 1.5)
	_countdown_label.modulate = Color(1, 1, 1, 1)
	_countdown_label.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))

	var go_tween := create_tween()
	go_tween.set_parallel(true)
	go_tween.tween_property(_countdown_label, "scale", Vector2(2.5, 2.5), 0.4).set_ease(Tween.EASE_OUT)
	go_tween.tween_property(_countdown_label, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)

	# Flash white screen effect
	if _screen_transition:
		_screen_transition._setup_for_type(ScreenTransition.TransitionType.FADE_WHITE)
		_screen_transition._color_rect.visible = true
		_screen_transition._color_rect.color = Color(1, 1, 1, 0.6)
		var flash_tween := create_tween()
		flash_tween.tween_property(_screen_transition._color_rect, "color:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)
		flash_tween.tween_callback(func(): _screen_transition._color_rect.visible = false)

	# Screen shake
	_apply_screen_shake(8.0, 0.2)

	EventBus.countdown_go.emit()
	await go_tween.finished
	_countdown_label.visible = false


func _apply_screen_shake(intensity: float, duration: float) -> void:
	## Shakes the camera briefly for impact feel.
	if player_vehicle == null:
		return
	var camera := player_vehicle.get_node_or_null("CameraMount/ChaseCamera") as Camera3D
	if camera == null:
		return

	var original_offset: float = camera.h_offset
	var shake_tween := create_tween()
	var steps: int = int(duration / 0.03)
	for s in range(steps):
		var offset: float = randf_range(-intensity, intensity) * 0.01
		shake_tween.tween_property(camera, "h_offset", original_offset + offset, 0.03)
	shake_tween.tween_property(camera, "h_offset", original_offset, 0.03)


# ---------------------------------------------------------------------------
# Track Setup
# ---------------------------------------------------------------------------

func _setup_track_for_type(race_type: RaceManager.RaceType) -> void:
	## Replace the default SprintTrack child with the correct track scene.
	## For STREET_SPRINT or unknown types we keep the default.
	var new_track_scene: PackedScene = null

	match race_type:
		RaceManager.RaceType.DRIFT:
			new_track_scene = DriftArenaScene
		RaceManager.RaceType.TOUGE:
			new_track_scene = TougeTrackScene
		RaceManager.RaceType.CIRCUIT:
			new_track_scene = CircuitTrackScene

	if new_track_scene == null:
		# Keep default sprint track
		return

	# Remove the default track
	if race_track:
		race_track.queue_free()
		race_track = null

	# Instantiate and add the new track
	var new_track := new_track_scene.instantiate() as RaceTrack
	add_child(new_track)
	move_child(new_track, 0)
	race_track = new_track

	print("[RaceSession] Loaded track scene for %s" % RaceManager.RaceType.keys()[race_type])


# ---------------------------------------------------------------------------
# Race-Type-Specific Wiring
# ---------------------------------------------------------------------------

func _wire_race_type(data: RaceData) -> void:
	match data.race_type:
		RaceManager.RaceType.DRIFT:
			_setup_drift_mode()
		RaceManager.RaceType.TOUGE:
			_setup_touge_mode()
		RaceManager.RaceType.CIRCUIT:
			_setup_circuit_mode(data)


func _setup_drift_mode() -> void:
	drift_scoring = DriftScoring.new()
	add_child(drift_scoring)

	# Build section list from checkpoint nodes (each checkpoint doubles as section boundary)
	var sections: Array[DriftScoring.DriftSection] = []
	if race_track:
		for i in range(race_track.checkpoints.size()):
			var section := DriftScoring.DriftSection.new()
			section.section_name = "Section %d" % (i + 1)
			section.section_index = i
			sections.append(section)

	drift_scoring.activate(player_vehicle, sections)

	# Wire drift zone Area3Ds if the track has them
	var drift_zones_node := race_track.get_node_or_null("DriftZones")
	if drift_zones_node:
		for zone_child in drift_zones_node.get_children():
			if zone_child is Area3D:
				var zone_name: String = zone_child.name
				# Determine multiplier from zone name or default
				var multiplier := 1.5
				if "x2" in zone_name or "Loop" in zone_name:
					multiplier = 2.0
				elif "x3" in zone_name:
					multiplier = 3.0

				zone_child.body_entered.connect(func(body: Node3D):
					if body == player_vehicle:
						drift_scoring.on_drift_zone_entered(zone_name, multiplier)
				)
				zone_child.body_exited.connect(func(body: Node3D):
					if body == player_vehicle:
						drift_scoring.on_drift_zone_exited(zone_name)
				)

	# Wire section advancement to checkpoints
	EventBus.checkpoint_reached.connect(func(racer_id: int, _cp_index: int):
		if racer_id == 0 and drift_scoring:
			drift_scoring.advance_section()
	)

	# Wire drift HUD overlay updates
	if race_hud_node and race_hud_node.has_method("show_drift_overlay"):
		race_hud_node.show_drift_overlay()
	EventBus.drift_combo_updated.connect(_on_drift_combo_updated)
	EventBus.drift_combo_dropped.connect(_on_drift_combo_dropped)
	EventBus.drift_near_miss.connect(_on_drift_near_miss)
	EventBus.drift_section_scored.connect(_on_drift_section_scored)

	print("[RaceSession] Drift mode initialized")


func _setup_touge_mode() -> void:
	touge_race = TougeRace.new()
	add_child(touge_race)

	# Touge is 1v1 — use only the first AI
	var opponent: Node3D = ai_vehicles[0] if ai_vehicles.size() > 0 else null
	var p_name: String = GameManager.player_data.player_name if GameManager.player_data else "Player"
	var o_name: String = race_data.ai_names[0] if race_data.ai_names.size() > 0 else "Opponent"

	touge_race.activate(race_track, player_vehicle, opponent, p_name, o_name, 0, 1)

	# Wire touge gap HUD display
	EventBus.touge_gap_updated.connect(_on_touge_gap_updated)
	EventBus.touge_round_started.connect(_on_touge_round_started)
	EventBus.touge_round_ended.connect(_on_touge_round_ended)
	EventBus.touge_overtake.connect(_on_touge_overtake)
	EventBus.touge_match_result.connect(_on_touge_match_result)

	if race_hud_node and race_hud_node.has_method("show_touge_overlay"):
		race_hud_node.show_touge_overlay()

	print("[RaceSession] Touge mode initialized — 1v1: %s vs %s" % [p_name, o_name])


func _setup_circuit_mode(data: RaceData) -> void:
	circuit_race = CircuitRace.new()
	add_child(circuit_race)

	# Determine settings from race data
	var laps := data.lap_count if data.lap_count > 0 else 3
	var enable_pits := laps >= 5  # Pits for longer races
	var enable_rubber := data.ai_difficulty < 0.8  # No rubber band on hard races
	var pit_area: Area3D = null

	if race_track:
		var pit_lane := race_track.get_node_or_null("PitLane")
		if pit_lane:
			pit_area = pit_lane.get_node_or_null("PitArea") as Area3D

	circuit_race.activate(
		race_track,
		player_vehicle,
		laps,
		enable_pits,
		enable_rubber,
		data.ai_difficulty,
		pit_area,
	)

	# Wire circuit HUD: lap counter, leaderboard, pit stop prompt
	EventBus.circuit_lap_time.connect(_on_circuit_lap_time)
	EventBus.circuit_best_lap.connect(_on_circuit_best_lap)
	EventBus.circuit_leaderboard_updated.connect(_on_circuit_leaderboard_updated)
	EventBus.circuit_dnf_warning.connect(_on_circuit_dnf_warning)
	EventBus.circuit_pit_entered.connect(_on_circuit_pit_entered)
	EventBus.circuit_pit_exited.connect(_on_circuit_pit_exited)

	if race_hud_node and race_hud_node.has_method("show_circuit_overlay"):
		race_hud_node.show_circuit_overlay(laps)

	print("[RaceSession] Circuit mode initialized — %d laps, pits: %s" % [
		laps, "ON" if enable_pits else "OFF"
	])


# ---------------------------------------------------------------------------
# Vehicle Spawning
# ---------------------------------------------------------------------------

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
		var ai := AIRacerScene.instantiate() as RaceAI
		ai.racer_id = i + 1
		ai.display_name = race_data.ai_names[i] if i < race_data.ai_names.size() else "Racer %d" % (i + 1)
		ai.difficulty = race_data.ai_difficulty
		ai.path = race_track.racing_line
		add_child(ai)

		var spawn: Transform3D = race_track.get_spawn_position(i + 1)
		ai.global_transform = spawn

		ai.setup_track(race_track)
		ai_vehicles.append(ai)


func _wire_hud() -> void:
	var hud := race_hud_node
	if hud == null:
		return
	# HUD auto-connects via EventBus signals, but we update speed manually
	pass


# ---------------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if pause_menu and not pause_menu.is_open():
			if GameManager.current_state == GameManager.GameState.RACING:
				pause_menu.open_menu()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Main Process
# ---------------------------------------------------------------------------

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

	# Drift scoring live display
	if drift_scoring and drift_scoring.is_active:
		if race_hud_node and race_hud_node.has_method("update_drift_score"):
			race_hud_node.update_drift_score(drift_scoring.total_score, drift_scoring._combo_count, drift_scoring._combo_multiplier)

	# Touge gap live display
	if touge_race and touge_race.state == TougeRace.TougeState.ROUND_ACTIVE:
		if race_hud_node and race_hud_node.has_method("update_touge_gap"):
			race_hud_node.update_touge_gap(touge_race.gap_meters, touge_race.gap_seconds)

	# Circuit lap counter display
	if circuit_race and circuit_race.state == CircuitRace.CircuitState.RACING:
		if race_hud_node and race_hud_node.has_method("update_lap_counter"):
			var player_data: CircuitRace.RacerLapData = circuit_race.get_racer_data(0)
			if player_data:
				race_hud_node.update_lap_counter(player_data.current_lap, circuit_race.total_laps)

	# Circuit pit stop input
	if circuit_race and circuit_race.state == CircuitRace.CircuitState.RACING:
		if circuit_race.pit_stops_enabled and circuit_race._player_in_pit:
			if Input.is_action_just_pressed("interact"):
				circuit_race.begin_pit_stop()


# ---------------------------------------------------------------------------
# Race Finish — Slow-mo + fade to results
# ---------------------------------------------------------------------------

func _on_race_finished(results: Dictionary) -> void:
	if _results_shown:
		return
	_results_shown = true

	# Deactivate mode controllers and merge their results
	if drift_scoring:
		drift_scoring.deactivate()
		results["drift_results"] = drift_scoring.get_results()
	if touge_race:
		touge_race.deactivate()
		results["touge_results"] = touge_race.get_results()
	if circuit_race:
		circuit_race.deactivate()
		results["circuit_results"] = circuit_race.get_results()

	# Slow-motion finish effect
	_run_finish_sequence(results)


func _run_finish_sequence(results: Dictionary) -> void:
	## Slow-mo dip + fade to results screen.
	# Brief slow-motion
	var original_timescale := Engine.time_scale
	var slowmo_tween := create_tween()
	slowmo_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	slowmo_tween.tween_method(func(val: float): Engine.time_scale = val, 1.0, 0.3, 0.3)
	await slowmo_tween.finished

	await get_tree().create_timer(0.6).timeout

	# Restore time scale
	var restore_tween := create_tween()
	restore_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	restore_tween.tween_method(func(val: float): Engine.time_scale = val, 0.3, original_timescale, 0.4)
	await restore_tween.finished

	# Fade to results
	if _screen_transition:
		await _screen_transition.transition_in(ScreenTransition.TransitionType.FADE_BLACK, 0.5)

	_show_results(results)

	if _screen_transition:
		await _screen_transition.transition_out(ScreenTransition.TransitionType.FADE_BLACK, 0.5)


func _show_results(results: Dictionary) -> void:
	# Pink slip races get the special result screen instead of the normal one
	if results.get("is_pink_slip", false) and not _pink_slip_challenge.is_empty():
		_show_pink_slip_result(results)
		return

	if results_panel == null:
		# No UI — just emit and return
		await get_tree().create_timer(3.0).timeout
		race_session_complete.emit(results)
		return

	results_panel.visible = true

	# --- Slide-in animation for results panel ---
	results_panel.modulate.a = 0.0
	results_panel.position.y += 60.0

	var slide_tween := create_tween()
	slide_tween.set_parallel(true)
	slide_tween.tween_property(results_panel, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	slide_tween.tween_property(results_panel, "position:y", results_panel.position.y - 60.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# --- Common results ---
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
		var race_type_key: String = RaceManager.RaceType.keys()[race_data.race_type].to_lower() if race_data else "street_sprint"
		var payout := GameManager.economy.get_race_payout(
			race_type_key, 0 if won else 1, race_data.tier if race_data else 1
		)
		cash_label.text = "+$%d" % payout if won else "$0"

	# --- Race-type-specific result details ---
	_show_type_specific_results(results)

	# --- Stagger-animate child elements ---
	_stagger_results_children()

	var continue_btn := results_panel.get_node_or_null("ContinueButton") as Button
	if continue_btn:
		continue_btn.pressed.connect(func():
			race_session_complete.emit(results)
		)
	else:
		# Auto-dismiss after delay
		await get_tree().create_timer(5.0).timeout
		race_session_complete.emit(results)


func _stagger_results_children() -> void:
	## Animate each child of the results panel with a staggered slide-in.
	if results_panel == null:
		return
	var delay_offset := 0.0
	for child in results_panel.get_children():
		if child is Control:
			var orig_x := child.position.x
			child.position.x -= 40.0
			child.modulate.a = 0.0
			var child_tween := create_tween()
			child_tween.set_parallel(true)
			child_tween.tween_property(child, "position:x", orig_x, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(delay_offset)
			child_tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(delay_offset)
			delay_offset += 0.08


func _show_type_specific_results(results: Dictionary) -> void:
	var title_label := results_panel.get_node_or_null("Title") as Label
	if title_label == null:
		return

	if results.has("drift_results"):
		var dr: Dictionary = results["drift_results"]
		title_label.text = "DRIFT COMPLETE — RANK: %s" % dr.get("overall_rank", "?")
		var time_label := results_panel.get_node_or_null("Time") as Label
		if time_label:
			time_label.text = "Score: %.0f" % dr.get("total_score", 0.0)

	elif results.has("touge_results"):
		var tr: Dictionary = results["touge_results"]
		var won: bool = tr.get("player_won", false)
		title_label.text = "TOUGE %s" % ("VICTORY" if won else "DEFEAT")
		var time_label := results_panel.get_node_or_null("Time") as Label
		if time_label:
			time_label.text = "You: %d pts — Rival: %d pts" % [
				tr.get("player_total_points", 0),
				tr.get("opponent_total_points", 0),
			]

	elif results.has("circuit_results"):
		title_label.text = "RACE COMPLETE"
		var cr: Dictionary = results["circuit_results"]
		var lb: Array = cr.get("leaderboard", [])
		# Show best lap in time label
		var time_label := results_panel.get_node_or_null("Time") as Label
		if time_label:
			var rd: Dictionary = cr.get("racer_lap_data", {})
			if rd.has(0):
				var player_laps: Dictionary = rd[0]
				time_label.text = "Best Lap: %s" % _format_time(player_laps.get("best_lap_time", 0.0))

	else:
		title_label.text = "RACE COMPLETE"


# ---------------------------------------------------------------------------
# HUD Callbacks — Drift
# ---------------------------------------------------------------------------

func _on_drift_combo_updated(combo_count: int, multiplier: float, current_score: float) -> void:
	if race_hud_node and race_hud_node.has_method("show_drift_combo"):
		race_hud_node.show_drift_combo(combo_count, multiplier, current_score)


func _on_drift_combo_dropped() -> void:
	if race_hud_node and race_hud_node.has_method("hide_drift_combo"):
		race_hud_node.hide_drift_combo()


func _on_drift_near_miss(distance: float, bonus: float) -> void:
	if race_hud_node and race_hud_node.has_method("show_near_miss"):
		race_hud_node.show_near_miss(distance, bonus)


func _on_drift_section_scored(section_index: int, score: float, rank: String) -> void:
	if race_hud_node and race_hud_node.has_method("show_section_rank"):
		race_hud_node.show_section_rank(section_index, score, rank)


# ---------------------------------------------------------------------------
# HUD Callbacks — Touge
# ---------------------------------------------------------------------------

func _on_touge_gap_updated(gap_meters: float, gap_seconds: float) -> void:
	if race_hud_node and race_hud_node.has_method("update_touge_gap"):
		race_hud_node.update_touge_gap(gap_meters, gap_seconds)


func _on_touge_round_started(round_number: int, leader_id: int, chaser_id: int) -> void:
	if race_hud_node and race_hud_node.has_method("show_touge_round_start"):
		var leader_name := "You" if leader_id == 0 else "Rival"
		race_hud_node.show_touge_round_start(round_number, leader_name)


func _on_touge_round_ended(round_number: int, leader_id: int, gap_seconds: float) -> void:
	if race_hud_node and race_hud_node.has_method("show_touge_round_result"):
		race_hud_node.show_touge_round_result(round_number, gap_seconds)


func _on_touge_overtake(chaser_id: int) -> void:
	if race_hud_node and race_hud_node.has_method("show_touge_overtake"):
		var is_player := chaser_id == 0
		race_hud_node.show_touge_overtake(is_player)


func _on_touge_match_result(winner_id: int, scores: Array) -> void:
	# Match result will be shown in _on_race_finished -> _show_results
	pass


# ---------------------------------------------------------------------------
# HUD Callbacks — Circuit
# ---------------------------------------------------------------------------

func _on_circuit_lap_time(racer_id: int, lap: int, time: float) -> void:
	if racer_id == 0 and race_hud_node and race_hud_node.has_method("show_lap_time"):
		race_hud_node.show_lap_time(lap, time)


func _on_circuit_best_lap(racer_id: int, lap: int, time: float) -> void:
	if racer_id == 0 and race_hud_node and race_hud_node.has_method("show_best_lap"):
		race_hud_node.show_best_lap(lap, time)


func _on_circuit_leaderboard_updated(positions: Array) -> void:
	if race_hud_node and race_hud_node.has_method("update_leaderboard"):
		race_hud_node.update_leaderboard(positions)


func _on_circuit_dnf_warning(racer_id: int, seconds_behind: float) -> void:
	if racer_id == 0 and race_hud_node and race_hud_node.has_method("show_dnf_warning"):
		race_hud_node.show_dnf_warning(seconds_behind)


func _on_circuit_pit_entered(racer_id: int) -> void:
	if racer_id == 0 and race_hud_node and race_hud_node.has_method("show_pit_stop_active"):
		race_hud_node.show_pit_stop_active()


func _on_circuit_pit_exited(racer_id: int, repairs: Dictionary) -> void:
	if racer_id == 0 and race_hud_node and race_hud_node.has_method("show_pit_stop_complete"):
		race_hud_node.show_pit_stop_complete(repairs)


# ---------------------------------------------------------------------------
# Pink Slip Pre-Race Flow
# ---------------------------------------------------------------------------

func _show_pink_slip_pre_race(data: RaceData) -> void:
	## Show the pink slip wagering UI before the race starts.
	## The race only proceeds if the player accepts.
	var pink_slip_sys := _get_pink_slip_system()
	if pink_slip_sys == null:
		print("[RaceSession] No PinkSlipSystem found — skipping pink slip UI")
		_setup_race_internal(data)
		return

	# Get the active challenge (already created by PinkSlipSystem or trigger)
	_pink_slip_challenge = pink_slip_sys.get_active_challenge_for_race()
	if _pink_slip_challenge.is_empty():
		# No active challenge — create one from race_data opponent info
		var player_vehicle_data := GameManager.garage.get_vehicle(
			GameManager.player_data.current_vehicle_id
		)
		var opponent_vehicle_data := VehicleData.new()
		opponent_vehicle_data.vehicle_id = data.opponent_vehicle_data.get("vehicle_id", "opponent")
		opponent_vehicle_data.display_name = data.opponent_vehicle_data.get("display_name", "Opponent's Car")
		opponent_vehicle_data.stock_hp = data.opponent_vehicle_data.get("stock_hp", 200.0)
		opponent_vehicle_data.current_hp = opponent_vehicle_data.stock_hp
		opponent_vehicle_data.weight_kg = data.opponent_vehicle_data.get("weight_kg", 1300.0)
		opponent_vehicle_data.base_speed = data.opponent_vehicle_data.get("base_speed", 100.0)

		if player_vehicle_data:
			var race_config := {
				"type": "voluntary",
				"opponent_name": data.ai_names[0] if data.ai_names.size() > 0 else "Opponent",
				"story_protected": data.is_story_mission,
			}
			_pink_slip_challenge = pink_slip_sys.create_challenge(
				player_vehicle_data, opponent_vehicle_data, race_config
			)

	if _pink_slip_challenge.is_empty():
		print("[RaceSession] Could not create pink slip challenge — proceeding without UI")
		_setup_race_internal(data)
		return

	# Instantiate and show the pink slip UI
	_pink_slip_ui = PinkSlipUIScene.instantiate() as PinkSlipUI
	add_child(_pink_slip_ui)
	_pink_slip_ui.challenge_accepted.connect(_on_pink_slip_ui_accepted)
	_pink_slip_ui.challenge_declined.connect(_on_pink_slip_ui_declined)
	_pink_slip_ui.show_challenge(_pink_slip_challenge)

	print("[RaceSession] Pink slip pre-race UI shown")


func _on_pink_slip_ui_accepted(challenge_id: String, player_vehicle_id: String) -> void:
	## Player accepted the pink slip — proceed with race setup.
	var pink_slip_sys := _get_pink_slip_system()
	if pink_slip_sys:
		# Update the challenge with the selected vehicle
		_pink_slip_challenge["player_vehicle_id"] = player_vehicle_id
		pink_slip_sys.accept_challenge(challenge_id)
		pink_slip_sys.set_challenge_in_race(challenge_id)

		# Switch the player's active vehicle to the wagered one
		GameManager.player_data.current_vehicle_id = player_vehicle_id

	# Clean up the UI
	if _pink_slip_ui:
		_pink_slip_ui.queue_free()
		_pink_slip_ui = null

	# Now proceed with the actual race setup
	_setup_race_internal(race_data)
	print("[RaceSession] Pink slip accepted — starting race")


func _on_pink_slip_ui_declined(challenge_id: String) -> void:
	## Player declined the pink slip — abort the race.
	var pink_slip_sys := _get_pink_slip_system()
	if pink_slip_sys:
		pink_slip_sys.decline_challenge(challenge_id)

	# Clean up the UI
	if _pink_slip_ui:
		_pink_slip_ui.queue_free()
		_pink_slip_ui = null

	_pink_slip_challenge = {}

	# Emit session complete with a declined result
	race_session_complete.emit({
		"race_name": race_data.race_name if race_data else "",
		"pink_slip_declined": true,
		"player_won": false,
	})
	print("[RaceSession] Pink slip declined — race aborted")


# ---------------------------------------------------------------------------
# Pink Slip Post-Race Result
# ---------------------------------------------------------------------------

func _show_pink_slip_result(results: Dictionary) -> void:
	## Show the dramatic pink slip result screen after the race.
	var player_won: bool = results.get("player_won", false)

	_pink_slip_result = PinkSlipResultScene.instantiate() as PinkSlipResult
	add_child(_pink_slip_result)
	_pink_slip_result.result_acknowledged.connect(_on_pink_slip_result_done.bind(results))

	if player_won:
		# Build won vehicle data
		var won_vehicle := VehicleData.new()
		won_vehicle.vehicle_id = _pink_slip_challenge.get("opponent_vehicle_id", "")
		won_vehicle.display_name = _pink_slip_challenge.get("opponent_vehicle_name", "Unknown")
		won_vehicle.estimated_value = _pink_slip_challenge.get("opponent_vehicle_value", 0)

		# Try to load full vehicle data from garage (it was just added by PinkSlipSystem)
		var garage_vehicle := GameManager.garage.get_vehicle(won_vehicle.vehicle_id)
		if garage_vehicle:
			won_vehicle = garage_vehicle

		var dialogue: String = _pink_slip_challenge.get("opponent_dialogue_lose", "")
		_pink_slip_result.show_win(won_vehicle, dialogue)
		print("[RaceSession] Pink slip result: WIN — %s" % won_vehicle.display_name)
	else:
		# Build lost vehicle data
		var lost_vehicle := VehicleData.new()
		lost_vehicle.vehicle_id = _pink_slip_challenge.get("player_vehicle_id", "")
		lost_vehicle.display_name = _pink_slip_challenge.get("player_vehicle_name", "Unknown")
		lost_vehicle.estimated_value = _pink_slip_challenge.get("player_vehicle_value", 0)

		var dialogue: String = _pink_slip_challenge.get("opponent_dialogue_win", "")
		_pink_slip_result.show_loss(lost_vehicle, dialogue)
		print("[RaceSession] Pink slip result: LOSS — %s" % lost_vehicle.display_name)


func _on_pink_slip_result_done(results: Dictionary) -> void:
	## Player acknowledged the pink slip result — continue to normal flow.
	if _pink_slip_result:
		_pink_slip_result.queue_free()
		_pink_slip_result = null

	_pink_slip_challenge = {}
	race_session_complete.emit(results)


func _get_pink_slip_system() -> PinkSlipSystem:
	if GameManager.has_node("PinkSlipSystem"):
		return GameManager.get_node("PinkSlipSystem") as PinkSlipSystem
	return null


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func cleanup() -> void:
	# Ensure time_scale is restored
	Engine.time_scale = 1.0

	# Clean up mode controllers
	if drift_scoring:
		drift_scoring.deactivate()
		drift_scoring.queue_free()
		drift_scoring = null
	if touge_race:
		touge_race.deactivate()
		touge_race.queue_free()
		touge_race = null
	if circuit_race:
		circuit_race.deactivate()
		circuit_race.queue_free()
		circuit_race = null

	# Clean up pink slip UI if still open
	if _pink_slip_ui:
		_pink_slip_ui.queue_free()
		_pink_slip_ui = null
	if _pink_slip_result:
		_pink_slip_result.queue_free()
		_pink_slip_result = null
	_pink_slip_challenge = {}

	if player_vehicle:
		player_vehicle.queue_free()
	for ai in ai_vehicles:
		ai.queue_free()
	ai_vehicles.clear()
	GameManager.race_manager.cleanup_race()


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _ordinal(n: int) -> String:
	match n:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return "%dTH" % n


func _format_time(seconds: float) -> String:
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	var ms: int = int((seconds - int(seconds)) * 1000)
	return "%d:%02d.%03d" % [mins, secs, ms]
