extends Node

# Race Manager - Handles race logic, lap counting, and checkpoints

signal race_started
signal race_finished(winner)
signal lap_completed(racer, lap_number)
signal checkpoint_passed(racer, checkpoint_number)

@export var total_laps = 3
@export var countdown_time = 3.0

var racers = []
var racer_data = {}
var race_active = false
var race_started = false
var countdown_timer = 0.0

class RacerData:
	var current_lap = 1
	var checkpoints_passed = []
	var lap_times = []
	var current_lap_start_time = 0.0
	var total_race_time = 0.0
	var position = 0
	var finished = false

	func _init():
		current_lap = 1
		checkpoints_passed = []
		lap_times = []
		current_lap_start_time = 0.0
		total_race_time = 0.0
		position = 0
		finished = false

func _ready():
	setup_checkpoints()
	call_deferred("find_racers")

func find_racers():
	"""Find all racers in the scene (player and AI)"""
	# Find player vehicle
	var player_vehicles = get_tree().get_nodes_in_group("player_vehicle")
	for vehicle in player_vehicles:
		add_racer(vehicle)

	# Find AI racers
	var ai_racers = get_tree().get_nodes_in_group("ai_racer")
	for ai in ai_racers:
		add_racer(ai)

	print("Race Manager: Found ", racers.size(), " racers")

func add_racer(racer: Node):
	"""Add a racer to the race"""
	if not racer in racers:
		racers.append(racer)
		racer_data[racer] = RacerData.new()
		print("Added racer: ", racer.name)

func setup_checkpoints():
	"""Connect checkpoint signals"""
	var checkpoints = get_tree().get_nodes_in_group("checkpoint")
	for checkpoint in checkpoints:
		if checkpoint is Area3D:
			checkpoint.body_entered.connect(_on_checkpoint_entered.bind(checkpoint))

	var start_finish = get_tree().get_nodes_in_group("start_finish")
	for finish_line in start_finish:
		if finish_line is Area3D:
			finish_line.body_entered.connect(_on_start_finish_crossed.bind(finish_line))

	print("Race Manager: ", checkpoints.size(), " checkpoints set up")

func start_race():
	"""Start the race countdown"""
	if not race_active:
		race_active = true
		countdown_timer = countdown_time
		print("Race starting in ", countdown_time, " seconds...")

func _process(delta):
	if race_active and not race_started:
		countdown_timer -= delta
		if countdown_timer <= 0:
			race_started = true
			for racer in racers:
				racer_data[racer].current_lap_start_time = Time.get_ticks_msec() / 1000.0
			race_started.emit()
			print("Race started!")

	if race_started and not is_race_finished():
		update_race_times(delta)
		update_positions()

func update_race_times(delta):
	"""Update race times for all racers"""
	for racer in racers:
		var data = racer_data[racer]
		if not data.finished:
			data.total_race_time += delta

func update_positions():
	"""Update racer positions based on lap and progress"""
	var sorted_racers = racers.duplicate()

	sorted_racers.sort_custom(func(a, b):
		var data_a = racer_data[a]
		var data_b = racer_data[b]

		# Finished racers come first
		if data_a.finished and not data_b.finished:
			return true
		if data_b.finished and not data_a.finished:
			return false

		# Compare laps
		if data_a.current_lap != data_b.current_lap:
			return data_a.current_lap > data_b.current_lap

		# Compare checkpoints passed
		if data_a.checkpoints_passed.size() != data_b.checkpoints_passed.size():
			return data_a.checkpoints_passed.size() > data_b.checkpoints_passed.size()

		# If AI racers, compare path progress
		if a.has_method("get_progress") and b.has_method("get_progress"):
			return a.get_progress() > b.get_progress()

		return false
	)

	# Update positions
	for i in range(sorted_racers.size()):
		racer_data[sorted_racers[i]].position = i + 1

func _on_checkpoint_entered(body: Node3D, checkpoint: Area3D):
	"""Handle checkpoint crossing"""
	if body in racers and race_started:
		var data = racer_data[body]
		var checkpoint_id = checkpoint.get_index()

		if not checkpoint_id in data.checkpoints_passed:
			data.checkpoints_passed.append(checkpoint_id)
			checkpoint_passed.emit(body, checkpoint_id)
			print(body.name, " passed checkpoint ", checkpoint_id)

func _on_start_finish_crossed(body: Node3D, finish_line: Area3D):
	"""Handle start/finish line crossing"""
	if body in racers and race_started:
		var data = racer_data[body]

		# Check if all checkpoints were passed
		var checkpoints = get_tree().get_nodes_in_group("checkpoint")
		if data.checkpoints_passed.size() >= checkpoints.size():
			# Complete lap
			var lap_time = (Time.get_ticks_msec() / 1000.0) - data.current_lap_start_time
			data.lap_times.append(lap_time)
			data.checkpoints_passed.clear()

			print(body.name, " completed lap ", data.current_lap, " in ", lap_time, " seconds")
			lap_completed.emit(body, data.current_lap)

			data.current_lap += 1
			data.current_lap_start_time = Time.get_ticks_msec() / 1000.0

			# Check if race is finished
			if data.current_lap > total_laps:
				data.finished = true
				print(body.name, " finished the race!")

				# Check if this is the winner
				var finished_count = 0
				for racer in racers:
					if racer_data[racer].finished:
						finished_count += 1

				if finished_count == 1:
					race_finished.emit(body)
					print(body.name, " wins the race!")

func is_race_finished() -> bool:
	"""Check if all racers have finished"""
	for racer in racers:
		if not racer_data[racer].finished:
			return false
	return true

func get_racer_position(racer: Node) -> int:
	"""Get the current position of a racer"""
	if racer in racer_data:
		return racer_data[racer].position
	return 0

func get_racer_lap(racer: Node) -> int:
	"""Get the current lap of a racer"""
	if racer in racer_data:
		return racer_data[racer].current_lap
	return 0

func get_racer_time(racer: Node) -> float:
	"""Get the current race time of a racer"""
	if racer in racer_data:
		return racer_data[racer].total_race_time
	return 0.0

func get_countdown() -> float:
	"""Get remaining countdown time"""
	return max(0.0, countdown_timer)
