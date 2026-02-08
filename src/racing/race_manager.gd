## Manages race lifecycle: setup, countdown, tracking, finish, and results.
## Supports all race types from GDD Section 6.3.
class_name RaceManager
extends Node

enum RaceType {
	STREET_SPRINT,
	CIRCUIT,
	DRAG,
	HIGHWAY_BATTLE,
	TOUGE,
	DRIFT,
	PINK_SLIP,
	TIME_ATTACK,
	TOURNAMENT,
}

enum RaceState { IDLE, SETUP, COUNTDOWN, RACING, FINISHED, RESULTS }

var current_state: RaceState = RaceState.IDLE
var current_race: RaceData = null
var race_timer: float = 0.0
var countdown_timer: float = 0.0
var racers: Array[RacerState] = []


func start_race(race_data: RaceData) -> void:
	if current_state != RaceState.IDLE:
		push_warning("[RaceManager] Cannot start race — already in state: %s" % RaceState.keys()[current_state])
		return

	current_race = race_data
	current_state = RaceState.SETUP
	racers.clear()
	race_timer = 0.0

	# Initialize racer states
	var player_racer := RacerState.new()
	player_racer.racer_id = 0
	player_racer.is_player = true
	player_racer.display_name = GameManager.player_data.player_name
	racers.append(player_racer)

	for i in range(race_data.ai_count):
		var ai_racer := RacerState.new()
		ai_racer.racer_id = i + 1
		ai_racer.is_player = false
		ai_racer.display_name = race_data.ai_names[i] if i < race_data.ai_names.size() else "Racer %d" % (i + 1)
		racers.append(ai_racer)

	print("[RaceManager] Race setup: %s (%s) — %d racers" % [
		race_data.race_name,
		RaceType.keys()[race_data.race_type],
		racers.size()
	])

	_begin_countdown()


func _begin_countdown() -> void:
	current_state = RaceState.COUNTDOWN
	countdown_timer = 3.0


func _process(delta: float) -> void:
	match current_state:
		RaceState.COUNTDOWN:
			_process_countdown(delta)
		RaceState.RACING:
			_process_racing(delta)


func _process_countdown(delta: float) -> void:
	var prev := ceili(countdown_timer)
	countdown_timer -= delta
	var curr := ceili(countdown_timer)
	if curr != prev and curr > 0:
		EventBus.race_countdown_tick.emit(curr)
	if countdown_timer <= 0.0:
		current_state = RaceState.RACING
		race_timer = 0.0
		EventBus.race_started.emit(current_race.to_dict())
		print("[RaceManager] GO!")


func _process_racing(delta: float) -> void:
	race_timer += delta
	_update_positions()


func _update_positions() -> void:
	# Sort racers by progress (descending)
	racers.sort_custom(func(a, b): return a.progress > b.progress)
	for i in range(racers.size()):
		if racers[i].position != i + 1:
			racers[i].position = i + 1
			EventBus.race_position_changed.emit(racers[i].racer_id, i + 1)


func report_checkpoint(racer_id: int, checkpoint_index: int) -> void:
	for racer in racers:
		if racer.racer_id == racer_id:
			racer.last_checkpoint = checkpoint_index
			EventBus.checkpoint_reached.emit(racer_id, checkpoint_index)
			break


func report_lap(racer_id: int) -> void:
	for racer in racers:
		if racer.racer_id == racer_id:
			racer.current_lap += 1
			EventBus.lap_completed.emit(racer_id, racer.current_lap, race_timer)
			break


func report_finish(racer_id: int) -> void:
	for racer in racers:
		if racer.racer_id == racer_id:
			racer.finished = true
			racer.finish_time = race_timer
			break

	# Check if all finished
	var all_done := true
	for racer in racers:
		if not racer.finished:
			all_done = false
			break

	if all_done:
		_finish_race()


func report_dnf(racer_id: int) -> void:
	for racer in racers:
		if racer.racer_id == racer_id:
			racer.dnf = true
			racer.finished = true
			break


func _finish_race() -> void:
	current_state = RaceState.FINISHED

	# Sort by finish time (DNF at end)
	racers.sort_custom(func(a, b):
		if a.dnf and not b.dnf:
			return false
		if b.dnf and not a.dnf:
			return true
		return a.finish_time < b.finish_time
	)

	var results := _build_results()
	EventBus.race_finished.emit(results)
	_apply_results(results)
	current_state = RaceState.RESULTS
	print("[RaceManager] Race finished: %s" % current_race.race_name)


func _build_results() -> Dictionary:
	var player_position := 0
	var player_dnf := false
	var positions := []

	for i in range(racers.size()):
		var racer := racers[i]
		positions.append({
			"racer_id": racer.racer_id,
			"name": racer.display_name,
			"position": i + 1,
			"time": racer.finish_time,
			"dnf": racer.dnf,
			"is_player": racer.is_player,
		})
		if racer.is_player:
			player_position = i + 1
			player_dnf = racer.dnf

	return {
		"race_name": current_race.race_name,
		"race_type": current_race.race_type,
		"race_id": current_race.race_id,
		"total_time": race_timer,
		"positions": positions,
		"player_position": player_position,
		"player_won": player_position == 1 and not player_dnf,
		"player_dnf": player_dnf,
		"is_pink_slip": current_race.is_pink_slip,
		"is_story_mission": current_race.is_story_mission,
		"mission_id": current_race.mission_id,
	}


func _apply_results(results: Dictionary) -> void:
	var player_won: bool = results.player_won
	var player_dnf: bool = results.player_dnf
	var position: int = results.player_position

	# Record stats
	GameManager.player_data.record_race_result(player_won, player_dnf)

	# Cash payout
	if player_won or position <= 3:
		var payout := GameManager.economy.get_race_payout(
			RaceType.keys()[current_race.race_type].to_lower(),
			position - 1,
			current_race.tier
		)
		GameManager.economy.earn(payout, "race_%s" % current_race.race_id)

	# REP changes
	if player_won:
		var rep_gain := _calculate_rep_gain(results)
		GameManager.reputation.earn_rep(rep_gain, "race_win")
	elif player_dnf:
		GameManager.reputation.lose_rep(100, "dnf")
	else:
		GameManager.reputation.lose_rep(
			_calculate_rep_loss(results), "race_loss"
		)

	# Wear on player vehicle
	var wear := randf_range(1.0, 5.0)
	var vehicle := GameManager.garage.get_vehicle(GameManager.player_data.current_vehicle_id)
	if vehicle:
		vehicle.apply_wear(wear)
		vehicle.add_race_to_history(current_race.race_id, "win" if player_won else "loss")

	# Pink slip handling
	if current_race.is_pink_slip:
		GameManager.player_data.record_pink_slip(player_won)
		if player_won:
			EventBus.pink_slip_won.emit(current_race.opponent_vehicle_data)
		else:
			EventBus.pink_slip_lost.emit({
				"vehicle_id": GameManager.player_data.current_vehicle_id
			})


func _calculate_rep_gain(results: Dictionary) -> int:
	var base := 100
	match current_race.race_type:
		RaceType.STREET_SPRINT: base = 100
		RaceType.CIRCUIT: base = 200
		RaceType.DRAG: base = 150
		RaceType.HIGHWAY_BATTLE: base = 250
		RaceType.TOUGE: base = 300
		RaceType.DRIFT: base = 150
		RaceType.PINK_SLIP: base = 500
		RaceType.TOURNAMENT: base = 1000

	if current_race.is_story_mission:
		base = int(base * 2.5)

	return base


func _calculate_rep_loss(results: Dictionary) -> int:
	if current_race.is_story_mission:
		return 200
	return 30


func cleanup_race() -> void:
	current_state = RaceState.IDLE
	current_race = null
	racers.clear()
	race_timer = 0.0


func serialize() -> Dictionary:
	return {} # Race state is transient, not saved


func deserialize(_data: Dictionary) -> void:
	pass


## Inner class for tracking individual racer state during a race.
class RacerState:
	var racer_id: int = 0
	var is_player: bool = false
	var display_name: String = ""
	var position: int = 0
	var progress: float = 0.0
	var current_lap: int = 0
	var last_checkpoint: int = -1
	var finish_time: float = 0.0
	var finished: bool = false
	var dnf: bool = false
