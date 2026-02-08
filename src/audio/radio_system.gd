## In-car radio system with station switching, DJ commentary,
## song progress tracking, favorites, and auto-mute during dialogue.
## Communicates via EventBus signals — never references other systems directly.
class_name RadioSystem
extends Node

# ── Constants ────────────────────────────────────────────────────────
const STATION_OFF_ID := 0
const STATION_MIN := 0
const STATION_MAX := 5
const TUNING_STATIC_DURATION := 0.4  ## seconds of static between stations
const DJ_LINE_CHANCE := 0.35  ## probability of DJ line between songs
const DJ_EVENT_LINE_CHANCE := 0.6  ## probability of queued event line playing
const FAVORITE_WEIGHT_BONUS := 3  ## extra picks in weighted shuffle for favorites
const DEFAULT_VOLUME_DB := 0.0
const SILENCE_DB := -60.0

# ── Station Data ─────────────────────────────────────────────────────
## Loaded from data/audio/radio_stations.json
var _stations: Dictionary = {}  ## id -> station dict
var _station_order: Array[int] = []  ## ordered station IDs for cycling

## Loaded from data/audio/dj_event_lines.json
var _dj_event_lines: Array = []

## Queued event lines waiting to be played (by station_id)
var _queued_event_lines: Dictionary = {}  ## station_id -> Array of line strings

# ── Playback State ───────────────────────────────────────────────────
var _current_station_id: int = STATION_OFF_ID
var _is_on: bool = false
var _radio_volume_db: float = DEFAULT_VOLUME_DB
var _muted_for_dialogue: bool = false
var _pre_mute_volume_db: float = DEFAULT_VOLUME_DB

## Per-station playback progress: station_id -> { "track_index": int, "position": float }
var _station_progress: Dictionary = {}

## Current track being played
var _current_track: MusicTrackData = null
var _current_track_id: String = ""

## Favorites: set of track IDs that get weighted shuffle bonus
var _favorite_tracks: Dictionary = {}  ## track_id -> true

## DJ state
var _dj_line_pending: bool = false
var _dj_line_text: String = ""
var _dj_line_timer: float = 0.0
const DJ_LINE_DISPLAY_DURATION := 4.0

## Tuning static state
var _is_tuning: bool = false
var _tuning_timer: float = 0.0
var _tuning_target_station: int = -1

# ── Audio Players ────────────────────────────────────────────────────
var _music_player: AudioStreamPlayer = null
var _static_player: AudioStreamPlayer = null

# ── Preloaded Streams ───────────────────────────────────────────────
## Path to tuning static sound effect
const TUNING_STATIC_PATH := "res://assets/audio/sfx/radio_static.ogg"
var _tuning_static_stream: AudioStream = null


# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	name = "RadioSystem"

	# --- Create music player for radio ---
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.name = "RadioMusicPlayer"
	add_child(_music_player)
	_music_player.finished.connect(_on_track_finished)

	# --- Create static/tuning player ---
	_static_player = AudioStreamPlayer.new()
	_static_player.bus = "SFX"
	_static_player.name = "RadioStaticPlayer"
	add_child(_static_player)

	# --- Load data ---
	_load_stations()
	_load_dj_event_lines()
	_load_tuning_static()

	# --- Initialize station progress ---
	for station_id: int in _station_order:
		if station_id != STATION_OFF_ID:
			_station_progress[station_id] = {"track_index": 0, "position": 0.0}

	# --- Connect EventBus signals ---
	_connect_signals()

	print("[Radio] RadioSystem ready — %d stations loaded." % _stations.size())


func _connect_signals() -> void:
	EventBus.radio_toggle.connect(_on_radio_toggle)
	EventBus.radio_next_track.connect(_on_radio_next_track)
	EventBus.radio_previous_track.connect(_on_radio_previous_track)
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	EventBus.cinematic_started.connect(_on_cinematic_started)
	EventBus.cinematic_finished.connect(_on_cinematic_finished)

	# Listen for game events that trigger DJ commentary
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.rep_tier_changed.connect(_on_rep_tier_changed)
	EventBus.pursuit_escaped.connect(_on_pursuit_escaped)
	EventBus.vehicle_acquired.connect(_on_vehicle_acquired)
	EventBus.pink_slip_won.connect(_on_pink_slip_won)


func _process(delta: float) -> void:
	# --- Handle tuning static transition ---
	if _is_tuning:
		_tuning_timer -= delta
		if _tuning_timer <= 0.0:
			_is_tuning = false
			_static_player.stop()
			_complete_station_switch(_tuning_target_station)
		return

	# --- DJ line display timer ---
	if _dj_line_pending:
		_dj_line_timer -= delta
		if _dj_line_timer <= 0.0:
			_dj_line_pending = false
			_dj_line_text = ""

	# --- Save playback position for current station ---
	if _is_on and _music_player.playing and _current_station_id != STATION_OFF_ID:
		_station_progress[_current_station_id]["position"] = _music_player.get_playback_position()


# ═════════════════════════════════════════════════════════════════════
#  Data Loading
# ═════════════════════════════════════════════════════════════════════

func _load_stations() -> void:
	var path := "res://data/audio/radio_stations.json"
	if not FileAccess.file_exists(path):
		print("[Radio] No station file at %s — no stations available." % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[Radio] Failed to open station file.")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		print("[Radio] Station JSON parse error: %s" % json.get_error_message())
		return

	var data: Variant = json.data
	if not data is Dictionary:
		print("[Radio] Station JSON root is not a Dictionary.")
		return

	var stations_arr: Array = data.get("stations", [])
	for station_data: Variant in stations_arr:
		if station_data is Dictionary:
			var sid: int = station_data.get("id", -1)
			if sid >= 0:
				_stations[sid] = station_data
				_station_order.append(sid)

	_station_order.sort()
	print("[Radio] Loaded %d stations." % _stations.size())


func _load_dj_event_lines() -> void:
	var path := "res://data/audio/dj_event_lines.json"
	if not FileAccess.file_exists(path):
		print("[Radio] No DJ event lines file at %s." % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[Radio] Failed to open DJ event lines file.")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		print("[Radio] DJ event lines JSON parse error: %s" % json.get_error_message())
		return

	var data: Variant = json.data
	if data is Dictionary:
		_dj_event_lines = data.get("event_lines", [])
		print("[Radio] Loaded %d DJ event lines." % _dj_event_lines.size())


func _load_tuning_static() -> void:
	if ResourceLoader.exists(TUNING_STATIC_PATH):
		var res: Resource = load(TUNING_STATIC_PATH)
		if res is AudioStream:
			_tuning_static_stream = res as AudioStream
			print("[Radio] Tuning static loaded.")
	else:
		print("[Radio] No tuning static at %s — tuning will be silent." % TUNING_STATIC_PATH)


# ═════════════════════════════════════════════════════════════════════
#  Public API
# ═════════════════════════════════════════════════════════════════════

func set_station(station_id: int) -> void:
	## Switch to a specific station by ID. Plays tuning static in between.
	if station_id < STATION_MIN or station_id > STATION_MAX:
		print("[Radio] Invalid station ID: %d" % station_id)
		return
	if station_id == _current_station_id and _is_on:
		return

	# Save current playback position before switching
	_save_current_position()

	# If turning off
	if station_id == STATION_OFF_ID:
		_stop_playback()
		_current_station_id = STATION_OFF_ID
		_is_on = false
		EventBus.radio_station_changed.emit(STATION_OFF_ID, "OFF")
		print("[Radio] Radio turned off.")
		return

	# Play tuning static, then switch
	_is_on = true
	_start_tuning_transition(station_id)


func next_station() -> void:
	## Cycle to next station (wraps around, skips OFF unless currently on).
	var current_index := _station_order.find(_current_station_id)
	if current_index == -1:
		current_index = 0

	var next_index := (current_index + 1) % _station_order.size()
	# Skip OFF when cycling forward (unless we're already off and toggling on)
	if _station_order[next_index] == STATION_OFF_ID and _is_on:
		next_index = (next_index + 1) % _station_order.size()

	set_station(_station_order[next_index])


func prev_station() -> void:
	## Cycle to previous station (wraps around, skips OFF unless currently on).
	var current_index := _station_order.find(_current_station_id)
	if current_index == -1:
		current_index = 0

	var prev_index := (current_index - 1 + _station_order.size()) % _station_order.size()
	# Skip OFF when cycling backward
	if _station_order[prev_index] == STATION_OFF_ID and _is_on:
		prev_index = (prev_index - 1 + _station_order.size()) % _station_order.size()

	set_station(_station_order[prev_index])


func get_current_station() -> Dictionary:
	## Return the full station data dictionary for the current station.
	return _stations.get(_current_station_id, {})


func get_current_track() -> MusicTrackData:
	## Return the current MusicTrackData, or null if nothing is playing.
	return _current_track


func get_current_track_id() -> String:
	## Return the current track ID string.
	return _current_track_id


func toggle_radio() -> void:
	## Toggle radio on/off. When turning on, resumes last station or defaults to 1.
	if _is_on:
		set_station(STATION_OFF_ID)
	else:
		var resume_station := _current_station_id if _current_station_id != STATION_OFF_ID else 1
		set_station(resume_station)


func set_volume(volume: float) -> void:
	## Set radio volume (linear 0.0 to 1.0, converted to dB internally).
	volume = clampf(volume, 0.0, 1.0)
	if volume <= 0.01:
		_radio_volume_db = SILENCE_DB
	else:
		_radio_volume_db = linear_to_db(volume)

	if not _muted_for_dialogue:
		_music_player.volume_db = _radio_volume_db

	EventBus.radio_volume_changed.emit(volume)
	print("[Radio] Volume set to %.0f%% (%.1f dB)" % [volume * 100.0, _radio_volume_db])


func get_volume_linear() -> float:
	## Return the current volume as a linear value 0.0-1.0.
	if _radio_volume_db <= SILENCE_DB:
		return 0.0
	return db_to_linear(_radio_volume_db)


func toggle_favorite(track_id: String) -> void:
	## Toggle a track as favorite.
	if track_id.is_empty():
		return
	if _favorite_tracks.has(track_id):
		_favorite_tracks.erase(track_id)
		EventBus.radio_song_favorited.emit(track_id, false)
		print("[Radio] Unfavorited: %s" % track_id)
	else:
		_favorite_tracks[track_id] = true
		EventBus.radio_song_favorited.emit(track_id, true)
		print("[Radio] Favorited: %s" % track_id)


func toggle_current_favorite() -> void:
	## Toggle favorite status of the currently playing track.
	if not _current_track_id.is_empty():
		toggle_favorite(_current_track_id)


func is_favorite(track_id: String) -> bool:
	return _favorite_tracks.has(track_id)


func is_on() -> bool:
	return _is_on


func is_tuning() -> bool:
	return _is_tuning


func get_dj_line_text() -> String:
	return _dj_line_text


func is_dj_speaking() -> bool:
	return _dj_line_pending


func get_station_count() -> int:
	## Return the number of playable stations (excluding OFF).
	return maxi(_stations.size() - 1, 0)


# ═════════════════════════════════════════════════════════════════════
#  Station Switching Internals
# ═════════════════════════════════════════════════════════════════════

func _start_tuning_transition(target_station_id: int) -> void:
	## Play tuning static, then complete the switch.
	_is_tuning = true
	_tuning_timer = TUNING_STATIC_DURATION
	_tuning_target_station = target_station_id

	# Stop current music immediately
	_music_player.stop()

	# Play static
	if _tuning_static_stream:
		_static_player.stream = _tuning_static_stream
		_static_player.volume_db = _radio_volume_db - 6.0  ## static is quieter
		_static_player.play()

	print("[Radio] Tuning... -> Station %d" % target_station_id)


func _complete_station_switch(station_id: int) -> void:
	## Called after tuning static finishes. Start playing the station.
	_current_station_id = station_id
	var station: Dictionary = _stations.get(station_id, {})
	var station_name: String = station.get("name", "UNKNOWN")

	EventBus.radio_station_changed.emit(station_id, station_name)
	print("[Radio] Now playing: %s (%s)" % [station_name, station.get("frequency", "?")])

	# Resume from saved progress
	_play_station_track(station_id)


func _play_station_track(station_id: int) -> void:
	## Play the current track for a station, resuming from saved position.
	var station: Dictionary = _stations.get(station_id, {})
	var playlist: Array = station.get("playlist", [])
	if playlist.is_empty():
		print("[Radio] Station %d has no playlist." % station_id)
		return

	var progress: Dictionary = _station_progress.get(station_id, {"track_index": 0, "position": 0.0})
	var track_index: int = progress.get("track_index", 0)
	var position: float = progress.get("position", 0.0)

	# Weighted shuffle: favorites get more picks
	track_index = _get_next_track_index(station_id, track_index, false)

	if track_index < 0 or track_index >= playlist.size():
		track_index = 0

	var track_id: String = playlist[track_index]
	_current_track_id = track_id

	# Build a MusicTrackData from the track ID
	_current_track = _build_track_data(track_id, station)

	# Try to load and play the audio
	var stream_path: String = _current_track.stream_path
	var stream: AudioStream = _load_audio_stream(stream_path)
	if stream:
		_music_player.stream = stream
		_music_player.volume_db = _radio_volume_db if not _muted_for_dialogue else SILENCE_DB
		_music_player.play(position)
		print("[Radio] Playing: %s (pos %.1fs)" % [_current_track.get_display_string(), position])
	else:
		# No audio file — still emit the track info for UI, advance on a timer
		print("[Radio] No audio stream for track '%s' at '%s' — displaying info only." % [track_id, stream_path])
		_music_player.stop()

	# Update progress
	_station_progress[station_id]["track_index"] = track_index
	_station_progress[station_id]["position"] = position

	# Emit track changed
	EventBus.music_track_changed.emit(_current_track.title, _current_track.artist)


func _build_track_data(track_id: String, station: Dictionary) -> MusicTrackData:
	## Construct a MusicTrackData from a track ID and station info.
	var track := MusicTrackData.new()
	# Convert track_id to display-friendly title
	track.title = track_id.replace("_", " ").capitalize()
	track.artist = station.get("dj_name", "Unknown")
	track.genre = station.get("genre", "")
	track.stream_path = "res://assets/audio/music/radio/%s.ogg" % track_id
	track.radio_stations = [station.get("name", "")]
	return track


func _get_next_track_index(station_id: int, current_index: int, advance: bool) -> int:
	## Get the next track index, with weighted shuffle for favorites.
	var station: Dictionary = _stations.get(station_id, {})
	var playlist: Array = station.get("playlist", [])
	if playlist.is_empty():
		return -1

	if not advance:
		# Just return current or saved index
		return clampi(current_index, 0, playlist.size() - 1)

	# Build weighted pool
	var weighted_pool: Array[int] = []
	for i: int in range(playlist.size()):
		var tid: String = playlist[i]
		var weight: int = 1
		if _favorite_tracks.has(tid):
			weight += FAVORITE_WEIGHT_BONUS
		for _w: int in range(weight):
			weighted_pool.append(i)

	# Pick random from weighted pool, avoiding current track if possible
	if weighted_pool.size() <= 1:
		return (current_index + 1) % playlist.size()

	var attempts := 0
	var pick: int = current_index
	while pick == current_index and attempts < 10:
		pick = weighted_pool[randi() % weighted_pool.size()]
		attempts += 1

	return pick


func _save_current_position() -> void:
	## Save the current playback position for the current station.
	if _current_station_id != STATION_OFF_ID and _music_player.playing:
		_station_progress[_current_station_id]["position"] = _music_player.get_playback_position()


func _stop_playback() -> void:
	## Stop all radio audio.
	_music_player.stop()
	_static_player.stop()
	_current_track = null
	_current_track_id = ""
	_dj_line_pending = false
	_dj_line_text = ""


# ═════════════════════════════════════════════════════════════════════
#  DJ Commentary
# ═════════════════════════════════════════════════════════════════════

func _maybe_play_dj_line() -> void:
	## Possibly play a DJ line between tracks.
	if _current_station_id == STATION_OFF_ID:
		return

	# Check for queued event lines first
	if _queued_event_lines.has(_current_station_id):
		var queue: Array = _queued_event_lines[_current_station_id]
		if not queue.is_empty() and randf() < DJ_EVENT_LINE_CHANCE:
			var line: String = queue.pop_front()
			if queue.is_empty():
				_queued_event_lines.erase(_current_station_id)
			_show_dj_line(line)
			return

	# Random DJ line from station data
	if randf() < DJ_LINE_CHANCE:
		var station: Dictionary = _stations.get(_current_station_id, {})
		var dj_lines: Array = station.get("dj_lines", [])
		if not dj_lines.is_empty():
			var line: String = dj_lines[randi() % dj_lines.size()]
			_show_dj_line(line)


func _show_dj_line(line: String) -> void:
	## Display a DJ text line (voice-over placeholder for now).
	var station: Dictionary = _stations.get(_current_station_id, {})
	var dj_name: String = station.get("dj_name", "DJ")

	_dj_line_pending = true
	_dj_line_text = line
	_dj_line_timer = DJ_LINE_DISPLAY_DURATION

	EventBus.radio_dj_line.emit(dj_name, line)
	print("[Radio] DJ %s: \"%s\"" % [dj_name, line])


func _queue_event_line(event_key: String) -> void:
	## Find matching DJ event lines and queue them for their stations.
	for entry: Variant in _dj_event_lines:
		if entry is Dictionary:
			var event: String = entry.get("event", "")
			if event == event_key:
				var station_id: int = entry.get("station", -1)
				var line: String = entry.get("line", "")
				if station_id > 0 and not line.is_empty():
					if not _queued_event_lines.has(station_id):
						_queued_event_lines[station_id] = []
					_queued_event_lines[station_id].append(line)
					print("[Radio] Queued event line for station %d: %s" % [station_id, event_key])


# ═════════════════════════════════════════════════════════════════════
#  Auto-Mute During Dialogue / Cutscenes
# ═════════════════════════════════════════════════════════════════════

func _mute_for_dialogue() -> void:
	if _muted_for_dialogue:
		return
	_muted_for_dialogue = true
	_pre_mute_volume_db = _music_player.volume_db
	# Duck the volume rather than fully mute
	var ducked_db: float = _radio_volume_db - 18.0
	if ducked_db < SILENCE_DB:
		ducked_db = SILENCE_DB
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", ducked_db, 0.5)
	print("[Radio] Ducked for dialogue.")


func _unmute_after_dialogue() -> void:
	if not _muted_for_dialogue:
		return
	_muted_for_dialogue = false
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", _radio_volume_db, 0.8)
	print("[Radio] Restored volume after dialogue.")


# ═════════════════════════════════════════════════════════════════════
#  Track Finished Handler
# ═════════════════════════════════════════════════════════════════════

func _on_track_finished() -> void:
	## When a track finishes, play DJ line, then advance to next track.
	if not _is_on or _current_station_id == STATION_OFF_ID:
		return

	# DJ commentary between songs
	_maybe_play_dj_line()

	# Advance to next track
	var station: Dictionary = _stations.get(_current_station_id, {})
	var playlist: Array = station.get("playlist", [])
	if playlist.is_empty():
		return

	var progress: Dictionary = _station_progress.get(_current_station_id, {"track_index": 0, "position": 0.0})
	var current_index: int = progress.get("track_index", 0)
	var next_index := _get_next_track_index(_current_station_id, current_index, true)

	_station_progress[_current_station_id]["track_index"] = next_index
	_station_progress[_current_station_id]["position"] = 0.0

	_play_station_track(_current_station_id)


# ═════════════════════════════════════════════════════════════════════
#  EventBus Callbacks
# ═════════════════════════════════════════════════════════════════════

func _on_radio_toggle() -> void:
	toggle_radio()


func _on_radio_next_track() -> void:
	if not _is_on:
		return
	_save_current_position()
	var station: Dictionary = _stations.get(_current_station_id, {})
	var playlist: Array = station.get("playlist", [])
	if playlist.is_empty():
		return
	var progress: Dictionary = _station_progress.get(_current_station_id, {"track_index": 0, "position": 0.0})
	var current_index: int = progress.get("track_index", 0)
	var next_index := (current_index + 1) % playlist.size()
	_station_progress[_current_station_id]["track_index"] = next_index
	_station_progress[_current_station_id]["position"] = 0.0
	_play_station_track(_current_station_id)


func _on_radio_previous_track() -> void:
	if not _is_on:
		return
	# If more than 3 seconds into the track, restart it; otherwise go previous
	if _music_player.playing and _music_player.get_playback_position() > 3.0:
		_music_player.seek(0.0)
		_station_progress[_current_station_id]["position"] = 0.0
		return
	var station: Dictionary = _stations.get(_current_station_id, {})
	var playlist: Array = station.get("playlist", [])
	if playlist.is_empty():
		return
	var progress: Dictionary = _station_progress.get(_current_station_id, {"track_index": 0, "position": 0.0})
	var current_index: int = progress.get("track_index", 0)
	var prev_index := (current_index - 1 + playlist.size()) % playlist.size()
	_station_progress[_current_station_id]["track_index"] = prev_index
	_station_progress[_current_station_id]["position"] = 0.0
	_play_station_track(_current_station_id)


func _on_dialogue_started(_dialogue_id: String) -> void:
	_mute_for_dialogue()


func _on_dialogue_ended(_dialogue_id: String) -> void:
	_unmute_after_dialogue()


func _on_cinematic_started(_cinematic_id: String) -> void:
	_mute_for_dialogue()


func _on_cinematic_finished(_cinematic_id: String) -> void:
	_unmute_after_dialogue()


func _on_mission_completed(mission_id: String, _outcome: Dictionary) -> void:
	_queue_event_line("mission_complete:%s" % mission_id)


func _on_rep_tier_changed(_old_tier: int, new_tier: int) -> void:
	# Map tier numbers to tier names for event matching
	var tier_names := {0: "UNKNOWN", 1: "KNOWN", 2: "RESPECTED", 3: "FEARED", 4: "LEGENDARY"}
	var tier_name: String = tier_names.get(new_tier, "")
	if not tier_name.is_empty():
		_queue_event_line("rep_tier:%s" % tier_name)


func _on_pursuit_escaped() -> void:
	_queue_event_line("pursuit_escaped")


func _on_vehicle_acquired(_vehicle_id: String, _source: String) -> void:
	_queue_event_line("vehicle_acquired")


func _on_pink_slip_won(_won_vehicle: Dictionary) -> void:
	_queue_event_line("pink_slip_won")


# ═════════════════════════════════════════════════════════════════════
#  Serialization
# ═════════════════════════════════════════════════════════════════════

func serialize() -> Dictionary:
	_save_current_position()
	return {
		"current_station_id": _current_station_id,
		"is_on": _is_on,
		"radio_volume_db": _radio_volume_db,
		"station_progress": _station_progress.duplicate(true),
		"favorite_tracks": _favorite_tracks.keys(),
		"queued_event_lines": _queued_event_lines.duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	_current_station_id = data.get("current_station_id", STATION_OFF_ID)
	_is_on = data.get("is_on", false)
	_radio_volume_db = data.get("radio_volume_db", DEFAULT_VOLUME_DB)

	# Restore station progress
	var saved_progress: Dictionary = data.get("station_progress", {})
	for key: Variant in saved_progress:
		# JSON may store keys as strings, convert to int
		var station_id: int = int(key)
		if _station_progress.has(station_id):
			_station_progress[station_id] = saved_progress[key]

	# Restore favorites
	_favorite_tracks.clear()
	var saved_favs: Array = data.get("favorite_tracks", [])
	for fav_id: Variant in saved_favs:
		_favorite_tracks[str(fav_id)] = true

	# Restore queued event lines
	var saved_queued: Dictionary = data.get("queued_event_lines", {})
	_queued_event_lines.clear()
	for key: Variant in saved_queued:
		var station_id: int = int(key)
		_queued_event_lines[station_id] = saved_queued[key]

	# Resume playback if radio was on
	if _is_on and _current_station_id != STATION_OFF_ID:
		_play_station_track(_current_station_id)
		EventBus.radio_station_changed.emit(_current_station_id, _stations.get(_current_station_id, {}).get("name", ""))

	print("[Radio] Deserialized — station %d, on=%s, %d favorites." % [_current_station_id, str(_is_on), _favorite_tracks.size()])


# ═════════════════════════════════════════════════════════════════════
#  Utility
# ═════════════════════════════════════════════════════════════════════

func _load_audio_stream(path: String) -> AudioStream:
	## Safely attempt to load an AudioStream resource.
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is AudioStream:
		return res as AudioStream
	print("[Radio] Resource at '%s' is not an AudioStream." % path)
	return null
