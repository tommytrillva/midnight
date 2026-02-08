## Touge (mountain pass) 1v1 race controller.
## Two-round format: each racer leads one run down the pass.
## The leader sets the pace; the chaser tries to close the gap or overtake.
## Diesel's preferred format per the GDD — dramatic tension built into the format.
class_name TougeRace
extends Node

# --- Configuration ---
## Maximum gap in seconds before leader is declared dominant and round ends.
const MAX_GAP_SECONDS := 5.0
## Gap (seconds) below which chaser is "in striking distance" for bonus points.
const STRIKING_DISTANCE := 1.0
## Meters per second assumed for gap-to-time conversion at reference speed.
const REFERENCE_SPEED_MS := 30.0  # ~108 km/h reference
## Points awarded per round based on gap.
const POINTS_DOMINANT_WIN := 100   # Leader pulled >5s gap
const POINTS_CLOSE_WIN := 70      # Leader finished, chaser within 2s
const POINTS_NARROW_WIN := 50     # Leader finished, chaser within 5s
const POINTS_OVERTAKE_WIN := 120  # Chaser overtook leader — instant round win
## Minimum progress (0-1) the leader must reach before overtake counts.
const MIN_PROGRESS_FOR_OVERTAKE := 0.1

enum TougeState { IDLE, ROUND_STARTING, ROUND_ACTIVE, ROUND_ENDED, MATCH_OVER }
enum RoundOutcome { LEADER_DOMINANT, LEADER_WIN, CHASER_OVERTAKE, IN_PROGRESS }

# --- State ---
var state: TougeState = TougeState.IDLE
var current_round: int = 0  # 1 or 2
var total_rounds: int = 2

# Racer identifiers
var player_id: int = 0
var opponent_id: int = 1
var player_name: String = ""
var opponent_name: String = ""

# Round state
var leader_id: int = 0
var chaser_id: int = 0
var leader_progress: float = 0.0
var chaser_progress: float = 0.0
var leader_speed_ms: float = 0.0
var gap_meters: float = 0.0
var gap_seconds: float = 0.0
var round_timer: float = 0.0
var round_outcome: RoundOutcome = RoundOutcome.IN_PROGRESS

# Scoring
var round_scores: Array[Dictionary] = []  # Per-round results
var player_total_points: int = 0
var opponent_total_points: int = 0

# References
var _track: RaceTrack = null
var _player_vehicle: VehicleController = null
var _opponent_vehicle: Node3D = null  # RaceAI or VehicleController
var _race_manager: RaceManager = null


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Initialize the touge match. Call after vehicles are spawned and positioned.
func activate(
	track: RaceTrack,
	player_vehicle: VehicleController,
	opponent_vehicle: Node3D,
	p_name: String,
	o_name: String,
	p_id: int = 0,
	o_id: int = 1,
) -> void:
	_track = track
	_player_vehicle = player_vehicle
	_opponent_vehicle = opponent_vehicle
	player_name = p_name
	opponent_name = o_name
	player_id = p_id
	opponent_id = o_id
	_race_manager = GameManager.race_manager

	# Reset
	current_round = 0
	round_scores.clear()
	player_total_points = 0
	opponent_total_points = 0
	state = TougeState.IDLE

	set_process(true)
	set_physics_process(true)

	print("[Touge] Match activated: %s vs %s" % [player_name, opponent_name])
	start_next_round()


func deactivate() -> void:
	set_process(false)
	set_physics_process(false)
	state = TougeState.IDLE
	print("[Touge] Match deactivated")


# ---------------------------------------------------------------------------
# Round Management
# ---------------------------------------------------------------------------

func start_next_round() -> void:
	current_round += 1
	if current_round > total_rounds:
		_finish_match()
		return

	# Round 1: opponent leads, player chases. Round 2: player leads.
	if current_round == 1:
		leader_id = opponent_id
		chaser_id = player_id
	else:
		leader_id = player_id
		chaser_id = opponent_id

	leader_progress = 0.0
	chaser_progress = 0.0
	gap_meters = 0.0
	gap_seconds = 0.0
	round_timer = 0.0
	round_outcome = RoundOutcome.IN_PROGRESS

	state = TougeState.ROUND_STARTING

	var leader_name := player_name if leader_id == player_id else opponent_name
	var chaser_name := player_name if chaser_id == player_id else opponent_name

	EventBus.touge_round_started.emit(current_round, leader_id, chaser_id)
	print("[Touge] Round %d — Leader: %s | Chaser: %s" % [current_round, leader_name, chaser_name])

	# Brief delay then go
	await get_tree().create_timer(1.0).timeout
	state = TougeState.ROUND_ACTIVE


func _physics_process(delta: float) -> void:
	if state != TougeState.ROUND_ACTIVE:
		return

	round_timer += delta
	_update_progress()
	_update_gap()
	_check_round_conditions()


func _update_progress() -> void:
	## Read progress for both racers from the RaceManager racer states.
	for racer in _race_manager.racers:
		if racer.racer_id == leader_id:
			leader_progress = racer.progress
		elif racer.racer_id == chaser_id:
			chaser_progress = racer.progress


func _update_gap() -> void:
	## Calculate gap in meters and convert to approximate seconds.
	if _track == null or _track.racing_line == null:
		return

	var track_length := _track.racing_line.curve.get_baked_length()
	gap_meters = (leader_progress - chaser_progress) * track_length

	# Convert to seconds using leader's speed (or reference speed if leader is slow/stopped)
	leader_speed_ms = _get_leader_speed()
	var effective_speed: float = maxf(leader_speed_ms, REFERENCE_SPEED_MS * 0.3)
	gap_seconds = gap_meters / effective_speed

	EventBus.touge_gap_updated.emit(gap_meters, gap_seconds)


func _get_leader_speed() -> float:
	## Get the leader's current speed in m/s.
	if leader_id == player_id and _player_vehicle:
		return _player_vehicle.current_speed_kmh / 3.6
	elif _opponent_vehicle and _opponent_vehicle.has_method("get"):
		# RaceAI stores speed internally; fall back to reference
		return REFERENCE_SPEED_MS
	return REFERENCE_SPEED_MS


func _check_round_conditions() -> void:
	# --- Chaser overtake check ---
	if chaser_progress > leader_progress and leader_progress > MIN_PROGRESS_FOR_OVERTAKE:
		round_outcome = RoundOutcome.CHASER_OVERTAKE
		var chaser_name := player_name if chaser_id == player_id else opponent_name
		print("[Touge] OVERTAKE by %s! Instant round win." % chaser_name)
		EventBus.touge_overtake.emit(chaser_id)
		_end_round()
		return

	# --- Leader dominant escape check ---
	if gap_seconds >= MAX_GAP_SECONDS and leader_progress > MIN_PROGRESS_FOR_OVERTAKE:
		round_outcome = RoundOutcome.LEADER_DOMINANT
		var leader_name := player_name if leader_id == player_id else opponent_name
		print("[Touge] %s pulled too far ahead (%.1fs gap). Round over." % [leader_name, gap_seconds])
		EventBus.touge_leader_escaped.emit(leader_id)
		_end_round()
		return

	# --- Leader finished the course ---
	if leader_progress >= 0.99:
		# Leader crossed the finish — round ends on gap at this moment
		if gap_seconds <= 2.0:
			round_outcome = RoundOutcome.LEADER_WIN  # Close but leader still won
		else:
			round_outcome = RoundOutcome.LEADER_WIN  # Standard leader win
		var leader_name := player_name if leader_id == player_id else opponent_name
		print("[Touge] %s finished! Final gap: %.2fs" % [leader_name, gap_seconds])
		_end_round()
		return


# ---------------------------------------------------------------------------
# Round Resolution
# ---------------------------------------------------------------------------

func _end_round() -> void:
	state = TougeState.ROUND_ENDED

	var leader_points := 0
	var chaser_points := 0

	match round_outcome:
		RoundOutcome.CHASER_OVERTAKE:
			chaser_points = POINTS_OVERTAKE_WIN
			leader_points = 0
		RoundOutcome.LEADER_DOMINANT:
			leader_points = POINTS_DOMINANT_WIN
			chaser_points = 0
		RoundOutcome.LEADER_WIN:
			if gap_seconds <= 2.0:
				leader_points = POINTS_CLOSE_WIN
				# Chaser gets partial credit for staying close
				chaser_points = int(POINTS_CLOSE_WIN * (1.0 - gap_seconds / MAX_GAP_SECONDS))
			else:
				leader_points = POINTS_NARROW_WIN
				chaser_points = 0

	# Assign points to player/opponent
	var player_pts := leader_points if leader_id == player_id else chaser_points
	var opponent_pts := leader_points if leader_id == opponent_id else chaser_points
	player_total_points += player_pts
	opponent_total_points += opponent_pts

	var round_result := {
		"round": current_round,
		"leader_id": leader_id,
		"chaser_id": chaser_id,
		"outcome": RoundOutcome.keys()[round_outcome],
		"gap_seconds": gap_seconds,
		"gap_meters": gap_meters,
		"round_time": round_timer,
		"leader_points": leader_points,
		"chaser_points": chaser_points,
		"player_points": player_pts,
		"opponent_points": opponent_pts,
	}
	round_scores.append(round_result)

	EventBus.touge_round_ended.emit(current_round, leader_id, gap_seconds)

	print("[Touge] Round %d result — %s | Player: +%d pts | Opponent: +%d pts | Gap: %.2fs" % [
		current_round,
		RoundOutcome.keys()[round_outcome],
		player_pts,
		opponent_pts,
		gap_seconds,
	])

	# Brief pause, then start next round or finish
	await get_tree().create_timer(3.0).timeout
	start_next_round()


# ---------------------------------------------------------------------------
# Match Resolution
# ---------------------------------------------------------------------------

func _finish_match() -> void:
	state = TougeState.MATCH_OVER

	var winner_id: int
	if player_total_points > opponent_total_points:
		winner_id = player_id
	elif opponent_total_points > player_total_points:
		winner_id = opponent_id
	else:
		# Tie-break: whoever had a better round 2 (the pressure round)
		if round_scores.size() >= 2:
			var r2: Dictionary = round_scores[1] as Dictionary
			winner_id = player_id if r2.get("player_points", 0) >= r2.get("opponent_points", 0) else opponent_id
		else:
			winner_id = player_id  # Fallback

	var winner_name := player_name if winner_id == player_id else opponent_name

	EventBus.touge_match_result.emit(winner_id, round_scores)

	print("[Touge] MATCH OVER — Winner: %s | Player: %d pts | Opponent: %d pts" % [
		winner_name, player_total_points, opponent_total_points
	])

	# Report to RaceManager
	if winner_id == player_id:
		_race_manager.report_finish(player_id)
		_race_manager.report_finish(opponent_id)
	else:
		_race_manager.report_finish(opponent_id)
		_race_manager.report_finish(player_id)


## Build results for integration with RaceManager's _build_results.
func get_results() -> Dictionary:
	return {
		"race_type": "touge",
		"player_total_points": player_total_points,
		"opponent_total_points": opponent_total_points,
		"round_scores": round_scores,
		"player_won": player_total_points > opponent_total_points,
		"winner_name": player_name if player_total_points > opponent_total_points else opponent_name,
	}
