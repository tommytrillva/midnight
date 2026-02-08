## Central management for ghost recording and playback.
## Auto-records every race, saves personal bests per track, loads ghosts
## for time trial mode, and stores era-keyed ghosts for the Act 4
## "Ghosts of Past" mission where the player races their younger self.
class_name GhostManager
extends Node

# ── Child nodes (created at runtime) ────────────────────────────────────────
var recorder: GhostRecorder = null
var _active_ghost_players: Array = []  # Array of GhostPlayer

# ── Cached ghost index ──────────────────────────────────────────────────────
## track_id -> { vehicle_id -> GhostData } — best ghost per vehicle per track.
var _best_ghosts: Dictionary = {}
## track_id -> { act -> GhostData } — era ghosts for "Ghosts of Past".
var _era_ghosts: Dictionary = {}

# ── Last recording ──────────────────────────────────────────────────────────
var _last_recorded_ghost: GhostData = null


# ═══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Create the recorder as a child node
	recorder = GhostRecorder.new()
	recorder.name = "GhostRecorder"
	add_child(recorder)

	# Connect race events for auto-record flow
	EventBus.race_started.connect(_on_race_started)
	EventBus.race_finished.connect(_on_race_finished)

	# Ensure ghost directory exists
	_ensure_ghost_directory()

	# Load ghost index from disk
	_load_ghost_index()

	print("[Ghost] GhostManager ready. %d tracks with saved ghosts." % _best_ghosts.size())


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API — SAVING
# ═══════════════════════════════════════════════════════════════════════════════

func save_ghost(ghost_data: GhostData) -> void:
	## Saves a ghost to disk. If it is a new personal best, emits signals
	## and updates the best ghost cache.
	if ghost_data == null or ghost_data.frames.is_empty():
		return

	var track: String = ghost_data.track_id
	var vehicle: String = ghost_data.vehicle_id

	# Check if this is a new personal best
	var old_best: GhostData = _get_cached_best(track, vehicle)
	var is_new_best: bool = old_best == null or ghost_data.total_time < old_best.total_time

	if is_new_best:
		# Save as best ghost
		ghost_data.save_to_file(ghost_data.get_save_path())
		_cache_best(track, vehicle, ghost_data)

		if old_best != null:
			EventBus.ghost_beaten.emit(track, old_best.total_time, ghost_data.total_time)
			print("[Ghost] New PB! Track: %s | Old: %.2fs -> New: %.2fs" % [
				track, old_best.total_time, ghost_data.total_time])
		else:
			print("[Ghost] First ghost saved for track: %s (%.2fs)" % [track, ghost_data.total_time])

		EventBus.personal_best_set.emit(track, ghost_data.total_time)

	# Always save as era ghost (latest run for the current act)
	ghost_data.save_to_file(ghost_data.get_era_save_path())
	_cache_era(track, ghost_data.act_recorded, ghost_data)


func save_last_recording() -> void:
	## Convenience: saves the last ghost produced by the recorder.
	if _last_recorded_ghost != null:
		save_ghost(_last_recorded_ghost)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API — LOADING
# ═══════════════════════════════════════════════════════════════════════════════

func load_ghost(track_id: String, vehicle_id: String) -> GhostData:
	## Loads the best ghost for a specific track + vehicle combo.
	## Tries cache first, falls back to disk.
	var cached: GhostData = _get_cached_best(track_id, vehicle_id)
	if cached != null:
		return cached

	var path: String = GhostData.get_ghost_directory() + "%s_%s.json" % [track_id, vehicle_id]
	var ghost: GhostData = GhostData.load_from_file(path)
	if ghost != null:
		_cache_best(track_id, vehicle_id, ghost)
	return ghost


func load_best_ghost(track_id: String) -> GhostData:
	## Returns the fastest ghost across all vehicles for the given track.
	## Scans cache first; does NOT scan disk for every possible vehicle.
	if not _best_ghosts.has(track_id):
		return null

	var vehicles: Dictionary = _best_ghosts[track_id]
	var best: GhostData = null
	for vid: String in vehicles:
		var ghost: GhostData = vehicles[vid]
		if best == null or ghost.total_time < best.total_time:
			best = ghost
	return best


func load_era_ghost(act: int, track_id: String) -> GhostData:
	## Loads a ghost recorded during a specific story act.
	## Used by the "Ghosts of Past" mission in Act 4.
	if _era_ghosts.has(track_id):
		var acts: Dictionary = _era_ghosts[track_id]
		if acts.has(act):
			return acts[act]

	# Try loading from disk
	# Era ghosts can be from any vehicle, so we scan the directory
	var dir := DirAccess.open(GhostData.get_ghost_directory())
	if dir == null:
		return null

	var pattern: String = "%s_" % track_id
	var suffix: String = "_act%d.json" % act

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with(pattern) and file_name.ends_with(suffix):
			var path: String = GhostData.get_ghost_directory() + file_name
			var ghost: GhostData = GhostData.load_from_file(path)
			if ghost != null:
				_cache_era(track_id, act, ghost)
				dir.list_dir_end()
				return ghost
		file_name = dir.get_next()
	dir.list_dir_end()

	return null


func get_all_ghosts_for_track(track_id: String) -> Array:
	## Returns all known ghosts (best per vehicle) for the given track.
	var result: Array = []
	if _best_ghosts.has(track_id):
		var vehicles: Dictionary = _best_ghosts[track_id]
		for vid: String in vehicles:
			result.append(vehicles[vid])

	# Also include era ghosts that might not be the best
	if _era_ghosts.has(track_id):
		var acts: Dictionary = _era_ghosts[track_id]
		for act: int in acts:
			var era_ghost: GhostData = acts[act]
			# Avoid duplicates (an era ghost might also be the best)
			var dominated: bool = false
			for existing: GhostData in result:
				if existing.vehicle_id == era_ghost.vehicle_id \
						and existing.act_recorded == era_ghost.act_recorded:
					dominated = true
					break
			if not dominated:
				result.append(era_ghost)

	return result


func has_ghost(track_id: String) -> bool:
	## Returns true if any ghost exists for this track (cached or on disk).
	if _best_ghosts.has(track_id) and not _best_ghosts[track_id].is_empty():
		return true

	# Quick disk check: see if any files match this track
	var dir := DirAccess.open(GhostData.get_ghost_directory())
	if dir == null:
		return false

	var pattern: String = "%s_" % track_id
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with(pattern) and file_name.ends_with(".json"):
			dir.list_dir_end()
			return true
		file_name = dir.get_next()
	dir.list_dir_end()

	return false


# ═══════════════════════════════════════════════════════════════════════════════
#  GHOST PLAYER MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

func spawn_ghost_player(ghost_data: GhostData, parent: Node3D = null) -> GhostPlayer:
	## Creates a GhostPlayer node, loads the ghost data, and adds it to the
	## scene tree. Returns the player for further control.
	var player := GhostPlayer.new()
	player.name = "GhostPlayer_%s_act%d" % [ghost_data.vehicle_id, ghost_data.act_recorded]
	player.load_ghost(ghost_data)

	if parent != null:
		parent.add_child(player)
	else:
		add_child(player)

	_active_ghost_players.append(player)
	print("[Ghost] Spawned ghost player: %s" % player.name)
	return player


func start_all_ghosts() -> void:
	## Starts playback on all active ghost players.
	for player: GhostPlayer in _active_ghost_players:
		if player and is_instance_valid(player):
			player.start_playback()


func stop_all_ghosts() -> void:
	## Stops playback on all active ghost players.
	for player: GhostPlayer in _active_ghost_players:
		if player and is_instance_valid(player):
			player.stop_playback()


func remove_all_ghosts() -> void:
	## Removes and frees all active ghost player nodes.
	for player: GhostPlayer in _active_ghost_players:
		if player and is_instance_valid(player):
			player.stop_playback()
			player.queue_free()
	_active_ghost_players.clear()
	print("[Ghost] All ghost players removed.")


func get_active_ghost_count() -> int:
	return _active_ghost_players.size()


# ═══════════════════════════════════════════════════════════════════════════════
#  RACE EVENT HOOKS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_race_started(race_data: Dictionary) -> void:
	## When a race starts, begin all ghost playback instances and ensure
	## the recorder is running.
	start_all_ghosts()


func _on_race_finished(results: Dictionary) -> void:
	## When a race finishes, stop the recorder and save if the player
	## completed the race (not DNF).
	# Retrieve the recorded ghost from the recorder
	_last_recorded_ghost = recorder.stop_recording()

	var player_dnf: bool = results.get("player_dnf", false)
	if _last_recorded_ghost != null and not player_dnf:
		save_ghost(_last_recorded_ghost)
	elif player_dnf:
		print("[Ghost] Player DNF — ghost not saved as personal best.")

	# Stop ghost playback
	stop_all_ghosts()


# ═══════════════════════════════════════════════════════════════════════════════
#  DISK / CACHE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _ensure_ghost_directory() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("ghosts"):
		dir.make_dir("ghosts")
		print("[Ghost] Created ghost directory: user://ghosts/")


func _load_ghost_index() -> void:
	## Scans the ghost directory and caches metadata for quick lookup.
	var dir := DirAccess.open(GhostData.get_ghost_directory())
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if file_name.ends_with(".json"):
			var path: String = GhostData.get_ghost_directory() + file_name
			var ghost: GhostData = GhostData.load_from_file(path)
			if ghost != null:
				# Categorise: era ghost or best ghost
				if "_act" in file_name:
					_cache_era(ghost.track_id, ghost.act_recorded, ghost)
				else:
					_cache_best(ghost.track_id, ghost.vehicle_id, ghost)
		file_name = dir.get_next()
	dir.list_dir_end()


func _cache_best(track_id: String, vehicle_id: String, ghost: GhostData) -> void:
	if not _best_ghosts.has(track_id):
		_best_ghosts[track_id] = {}
	_best_ghosts[track_id][vehicle_id] = ghost


func _get_cached_best(track_id: String, vehicle_id: String) -> GhostData:
	if _best_ghosts.has(track_id):
		var vehicles: Dictionary = _best_ghosts[track_id]
		if vehicles.has(vehicle_id):
			return vehicles[vehicle_id]
	return null


func _cache_era(track_id: String, act: int, ghost: GhostData) -> void:
	if not _era_ghosts.has(track_id):
		_era_ghosts[track_id] = {}
	_era_ghosts[track_id][act] = ghost


# ═══════════════════════════════════════════════════════════════════════════════
#  SERIALIZATION (for save/load game state — index only, not frame data)
# ═══════════════════════════════════════════════════════════════════════════════

func serialize() -> Dictionary:
	## Serializes a lightweight index of known ghosts (not the full frame data).
	## Full ghost data lives in separate files in user://ghosts/.
	var best_index: Dictionary = {}
	for track_id: String in _best_ghosts:
		best_index[track_id] = {}
		var vehicles: Dictionary = _best_ghosts[track_id]
		for vid: String in vehicles:
			var ghost: GhostData = vehicles[vid]
			best_index[track_id][vid] = {
				"total_time": ghost.total_time,
				"recorded_date": ghost.recorded_date,
				"act_recorded": ghost.act_recorded,
			}

	return {
		"best_ghost_index": best_index,
	}


func deserialize(data: Dictionary) -> void:
	## Restores the ghost index from save data. Actual ghost files are
	## loaded on demand from user://ghosts/.
	_best_ghosts.clear()
	_era_ghosts.clear()

	# Re-scan disk to rebuild full cache (index in save is just a hint)
	_load_ghost_index()
