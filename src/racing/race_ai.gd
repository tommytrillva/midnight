## AI racer controller. Follows path nodes with rubber-banding
## difficulty scaled by the race's AI difficulty setting.
## Per GDD Pillar 6: Unified challenge, AI difficulty fixed per event.
class_name RaceAI
extends VehicleBody3D

@export var difficulty: float = 0.5 # 0.0 (easy) to 1.0 (hard)
@export var path: Path3D = null
@export var racer_id: int = 1
@export var display_name: String = "AI Racer"

var _path_follow: PathFollow3D = null
var _target_speed: float = 80.0 # km/h
var _current_speed: float = 0.0
var _progress: float = 0.0 # 0.0-1.0 along path

# Rubber banding
var _player_progress: float = 0.0
var _rubber_band_mult: float = 1.0

const BASE_SPEED := 60.0
const MAX_SPEED := 180.0
const RUBBER_BAND_STRENGTH := 0.15


func _ready() -> void:
	if path:
		_path_follow = PathFollow3D.new()
		_path_follow.loop = false
		path.add_child(_path_follow)


func _physics_process(delta: float) -> void:
	if GameManager.race_manager.current_state != RaceManager.RaceState.RACING:
		return

	_update_rubber_band()
	_update_speed(delta)
	_update_position(delta)
	_report_progress()


func _update_rubber_band() -> void:
	# Check player progress for rubber banding
	for racer in GameManager.race_manager.racers:
		if racer.is_player:
			_player_progress = racer.progress
			break

	var diff := _player_progress - _progress
	if diff > 0.05: # Player is ahead
		_rubber_band_mult = 1.0 + diff * RUBBER_BAND_STRENGTH
	elif diff < -0.05: # AI is ahead
		_rubber_band_mult = 1.0 + diff * RUBBER_BAND_STRENGTH * 0.5
	else:
		_rubber_band_mult = 1.0


func _update_speed(delta: float) -> void:
	_target_speed = lerpf(BASE_SPEED, MAX_SPEED, difficulty)
	_target_speed *= _rubber_band_mult

	# Add some variation
	_target_speed += sin(Time.get_ticks_msec() * 0.001 + float(racer_id)) * 5.0

	_current_speed = move_toward(_current_speed, _target_speed, 30.0 * delta)


func _update_position(delta: float) -> void:
	if _path_follow == null:
		return

	var speed_ms := _current_speed / 3.6
	_path_follow.progress += speed_ms * delta
	_progress = _path_follow.progress_ratio

	# Update our transform to follow path
	global_transform.origin = _path_follow.global_transform.origin
	global_transform.basis = _path_follow.global_transform.basis


func _report_progress() -> void:
	for racer in GameManager.race_manager.racers:
		if racer.racer_id == racer_id:
			racer.progress = _progress
			break

	# Check finish
	if _progress >= 0.99:
		GameManager.race_manager.report_finish(racer_id)


func set_player_progress(progress: float) -> void:
	_player_progress = progress
