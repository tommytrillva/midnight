## Race track controller. Manages checkpoints, finish line detection,
## and player progress tracking along a Path3D racing line.
class_name RaceTrack
extends Node3D

@export var racing_line: Path3D = null
@export var is_circuit: bool = true # true=loop, false=point-to-point
@export var lap_count: int = 1

var checkpoints: Array[Area3D] = []
var finish_line: Area3D = null
var spawn_points: Array[Marker3D] = []
var _player_vehicle: VehicleController = null
var _player_lap: int = 0
var _player_checkpoints_hit: int = 0
var _total_checkpoints: int = 0


func _ready() -> void:
	_find_checkpoints()
	_find_spawn_points()


func setup(player: VehicleController) -> void:
	_player_vehicle = player
	_player_lap = 0
	_player_checkpoints_hit = 0

	# Connect checkpoint area signals
	for i in range(checkpoints.size()):
		var cp := checkpoints[i]
		var idx := i
		cp.body_entered.connect(func(body): _on_checkpoint_entered(body, idx))

	if finish_line:
		finish_line.body_entered.connect(_on_finish_line_entered)


func get_player_progress() -> float:
	## Returns 0.0-1.0 progress along the track.
	if _player_vehicle == null or racing_line == null:
		return 0.0
	var closest := racing_line.curve.get_closest_offset(
		racing_line.to_local(_player_vehicle.global_transform.origin)
	)
	var total_length := racing_line.curve.get_baked_length()
	if total_length <= 0:
		return 0.0
	var lap_progress := closest / total_length
	if is_circuit and lap_count > 1:
		return (float(_player_lap) + lap_progress) / float(lap_count)
	return lap_progress


func get_spawn_position(index: int) -> Transform3D:
	if index < spawn_points.size():
		return spawn_points[index].global_transform
	# Fallback: offset from first spawn
	var base := spawn_points[0].global_transform if spawn_points.size() > 0 else Transform3D.IDENTITY
	base.origin += base.basis.x * (index * 3.0) # Side by side
	return base


func _find_checkpoints() -> void:
	var cp_node := get_node_or_null("Checkpoints")
	if cp_node:
		for child in cp_node.get_children():
			if child is Area3D:
				checkpoints.append(child)
	_total_checkpoints = checkpoints.size()

	finish_line = get_node_or_null("FinishLine") as Area3D
	print("[RaceTrack] Found %d checkpoints, finish line: %s" % [
		_total_checkpoints, "yes" if finish_line else "no"
	])


func _find_spawn_points() -> void:
	var sp_node := get_node_or_null("SpawnPoints")
	if sp_node:
		for child in sp_node.get_children():
			if child is Marker3D:
				spawn_points.append(child)


func _on_checkpoint_entered(body: Node3D, index: int) -> void:
	if body != _player_vehicle:
		return
	# Ensure sequential checkpoint order
	if index == _player_checkpoints_hit % _total_checkpoints:
		_player_checkpoints_hit += 1
		GameManager.race_manager.report_checkpoint(0, index)


func _on_finish_line_entered(body: Node3D) -> void:
	if body != _player_vehicle:
		return
	# Must have hit all checkpoints this lap
	var expected := (_player_lap + 1) * _total_checkpoints
	if _player_checkpoints_hit < expected and _total_checkpoints > 0:
		return # Shortcut detected

	_player_lap += 1
	if is_circuit and _player_lap < lap_count:
		GameManager.race_manager.report_lap(0)
	else:
		GameManager.race_manager.report_finish(0)
