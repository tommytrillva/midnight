extends Node

# Race Spawner - Spawns player and AI racers at their spawn points

@export var player_vehicle_scene: PackedScene
@export var ai_vehicle_scene: PackedScene
@export var num_ai_racers = 5

var spawn_points = []
var player_spawn: Marker3D
var ai_spawns = []

func _ready():
	find_spawn_points()
	call_deferred("spawn_racers")

func find_spawn_points():
	"""Find all spawn points in the scene"""
	var spawn_parent = get_node_or_null("../SpawnPoints")
	if not spawn_parent:
		print("Warning: SpawnPoints node not found!")
		return

	player_spawn = spawn_parent.get_node_or_null("PlayerSpawn")

	# Find AI spawn points
	for child in spawn_parent.get_children():
		if child is Marker3D and child.name.begins_with("AISpawn"):
			ai_spawns.append(child)

	print("Found ", ai_spawns.size(), " AI spawn points")

func spawn_racers():
	"""Spawn all racers at their positions"""
	# Spawn player
	if player_spawn and player_vehicle_scene:
		var player = player_vehicle_scene.instantiate()
		get_parent().add_child(player)
		player.global_position = player_spawn.global_position
		player.global_rotation = player_spawn.global_rotation
		print("Player spawned at ", player.global_position)

	# Spawn AI racers
	if ai_vehicle_scene:
		var spawn_count = min(num_ai_racers, ai_spawns.size())
		for i in range(spawn_count):
			var ai = ai_vehicle_scene.instantiate()
			get_parent().add_child(ai)
			ai.global_position = ai_spawns[i].global_position
			ai.global_rotation = ai_spawns[i].global_rotation
			print("AI racer ", i+1, " spawned at ", ai.global_position)

	# Start race after spawning
	await get_tree().create_timer(1.0).timeout
	var race_manager = get_node_or_null("../RaceManager")
	if race_manager:
		race_manager.start_race()
