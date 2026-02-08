## Global audio manager handling music playlists, ambient soundscapes,
## dynamic race intensity, crossfading, and bus volume control.
## All actual playback of engine/SFX is delegated to EngineAudio and SFXManager;
## this node owns the music pipeline and coordinates volume buses.
class_name AudioManagerSystem
extends Node

# ── Audio Bus Names ──────────────────────────────────────────────────
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_ENGINE := "Engine"
const BUS_VOICE := "Voice"

# ── Playlist / State Mapping ─────────────────────────────────────────
enum MusicState { MENU, FREE_ROAM, RACING, GARAGE, DIALOGUE, CUTSCENE }

## Loaded from data/audio/music_playlist.json
var _playlists: Dictionary = {}

## Per-state playlist key mapping
var _state_playlist_map: Dictionary = {
	MusicState.MENU: "main_menu",
	MusicState.FREE_ROAM: "free_roam_chill",
	MusicState.RACING: "racing_sprint",
	MusicState.GARAGE: "garage",
	MusicState.DIALOGUE: "",
	MusicState.CUTSCENE: "",
}

var _current_music_state: MusicState = MusicState.MENU
var _current_playlist_id: String = ""
var _current_track_index: int = -1
var _playlist_tracks: Array = []

# ── Music Players (A/B for crossfade) ───────────────────────────────
var music_player_a: AudioStreamPlayer = null
var music_player_b: AudioStreamPlayer = null
var _active_player: AudioStreamPlayer = null  ## Points to whichever is currently live
var _crossfade_tween: Tween = null

# ── Ambient Layer ────────────────────────────────────────────────────
## Ambient sounds loop during free roam (city hum, neon, traffic).
var _ambient_players: Array[AudioStreamPlayer] = []
var _ambient_active: bool = false
var _ambient_fade_tween: Tween = null

# ── Dynamic Race Intensity ───────────────────────────────────────────
## During races, a secondary "intensity layer" can be mixed in.
## 0.0 = calm cruising, 1.0 = full send / final lap.
var race_intensity: float = 0.0
var _intensity_player: AudioStreamPlayer = null
var _intensity_tween: Tween = null

# ── Volume Settings (linear dB) ─────────────────────────────────────
var music_volume_db: float = 0.0
var sfx_volume_db: float = 0.0
var engine_volume_db: float = 0.0
var voice_volume_db: float = 0.0

## Persisted user preferences (set from options menu)
var _bus_volumes: Dictionary = {
	BUS_MASTER: 0.0,
	BUS_MUSIC: 0.0,
	BUS_SFX: 0.0,
	BUS_ENGINE: 0.0,
	BUS_VOICE: 0.0,
}

const SILENCE_DB := -60.0
const CROSSFADE_DEFAULT := 1.5  ## seconds


# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# --- Music players ---
	music_player_a = AudioStreamPlayer.new()
	music_player_a.bus = BUS_MUSIC
	music_player_a.name = "MusicPlayerA"
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.bus = BUS_MUSIC
	music_player_b.name = "MusicPlayerB"
	add_child(music_player_b)

	_active_player = music_player_a

	# When a track finishes, auto-advance the playlist
	music_player_a.finished.connect(_on_music_track_finished)
	music_player_b.finished.connect(_on_music_track_finished)

	# --- Intensity layer ---
	_intensity_player = AudioStreamPlayer.new()
	_intensity_player.bus = BUS_MUSIC
	_intensity_player.name = "IntensityLayer"
	_intensity_player.volume_db = SILENCE_DB
	add_child(_intensity_player)

	# --- Load playlist data ---
	_load_playlists()

	# --- Connect EventBus signals ---
	_connect_signals()

	_ensure_buses()
	print("[Audio] AudioManager ready — %d playlists loaded." % _playlists.size())


func _connect_signals() -> void:
	EventBus.race_started.connect(_on_race_started)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.race_countdown_tick.connect(_on_countdown_tick)
	EventBus.radio_next_track.connect(_on_radio_next)
	EventBus.radio_previous_track.connect(_on_radio_previous)
	EventBus.game_state_audio_changed.connect(_on_game_state_audio_changed)
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.pursuit_started.connect(_on_pursuit_started)
	EventBus.pursuit_escaped.connect(_on_pursuit_escaped)


# ═════════════════════════════════════════════════════════════════════
#  Bus Volume Management
# ═════════════════════════════════════════════════════════════════════

func _ensure_buses() -> void:
	## Make sure all named buses exist at runtime.  Godot requires buses
	## to be created in the editor AudioBusLayout, but we defensively
	## check and warn so the game still runs.
	for bus_name: String in [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_ENGINE, BUS_VOICE]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			print("[Audio] WARNING — Bus '%s' not found in AudioBusLayout. Create it in the editor." % bus_name)


func set_bus_volume(bus_name: String, volume_db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		print("[Audio] Cannot set volume: bus '%s' not found." % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, volume_db)
	_bus_volumes[bus_name] = volume_db

	# Keep local mirrors in sync for one-shot players
	match bus_name:
		BUS_MUSIC: music_volume_db = volume_db
		BUS_SFX: sfx_volume_db = volume_db
		BUS_ENGINE: engine_volume_db = volume_db
		BUS_VOICE: voice_volume_db = volume_db

	print("[Audio] Bus '%s' volume set to %.1f dB" % [bus_name, volume_db])


func get_bus_volume(bus_name: String) -> float:
	return _bus_volumes.get(bus_name, 0.0)


func set_bus_muted(bus_name: String, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, muted)


# ═════════════════════════════════════════════════════════════════════
#  Playlist / Music System
# ═════════════════════════════════════════════════════════════════════

func _load_playlists() -> void:
	var path := "res://data/audio/music_playlist.json"
	if not FileAccess.file_exists(path):
		print("[Audio] No playlist file at %s — using empty playlists." % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[Audio] Failed to open playlist file.")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		print("[Audio] Playlist JSON parse error: %s" % json.get_error_message())
		return
	var data: Variant = json.data
	if data is Dictionary:
		_playlists = data
		print("[Audio] Loaded %d playlists from JSON." % _playlists.size())


func switch_music_state(new_state: MusicState, fade_duration: float = CROSSFADE_DEFAULT) -> void:
	if new_state == _current_music_state:
		return
	_current_music_state = new_state
	var playlist_key: String = _state_playlist_map.get(new_state, "")
	if playlist_key.is_empty():
		stop_music(fade_duration)
		return
	play_playlist(playlist_key, fade_duration)


func play_playlist(playlist_id: String, fade_duration: float = CROSSFADE_DEFAULT) -> void:
	if playlist_id == _current_playlist_id and _active_player.playing:
		return

	var playlist: Dictionary = _playlists.get(playlist_id, {})
	var tracks: Array = playlist.get("tracks", [])
	if tracks.is_empty():
		print("[Audio] Playlist '%s' has no tracks or not found." % playlist_id)
		return

	_current_playlist_id = playlist_id
	_playlist_tracks = tracks
	_current_track_index = 0

	_play_track_from_playlist(fade_duration)
	EventBus.music_playlist_changed.emit(playlist_id)
	print("[Audio] Playing playlist: %s (%d tracks)" % [playlist_id, tracks.size()])


func _play_track_from_playlist(fade_duration: float) -> void:
	if _current_track_index < 0 or _current_track_index >= _playlist_tracks.size():
		_current_track_index = 0

	var track_info: Dictionary = _playlist_tracks[_current_track_index]
	var stream_path: String = track_info.get("path", "")
	if stream_path.is_empty():
		print("[Audio] Track entry missing 'path' in playlist '%s'." % _current_playlist_id)
		return

	var stream: AudioStream = _load_stream(stream_path)
	play_music(stream, fade_duration)

	var title: String = track_info.get("title", "Unknown")
	var artist: String = track_info.get("artist", "Unknown")
	EventBus.music_track_changed.emit(title, artist)


func next_track(fade_duration: float = CROSSFADE_DEFAULT) -> void:
	if _playlist_tracks.is_empty():
		return
	_current_track_index = (_current_track_index + 1) % _playlist_tracks.size()
	_play_track_from_playlist(fade_duration)


func previous_track(fade_duration: float = CROSSFADE_DEFAULT) -> void:
	if _playlist_tracks.is_empty():
		return
	_current_track_index = (_current_track_index - 1 + _playlist_tracks.size()) % _playlist_tracks.size()
	_play_track_from_playlist(fade_duration)


func _on_music_track_finished() -> void:
	## Auto-advance to next track in the current playlist.
	if _playlist_tracks.is_empty():
		return
	next_track(0.5)


func _on_radio_next() -> void:
	next_track()


func _on_radio_previous() -> void:
	previous_track()


# ═════════════════════════════════════════════════════════════════════
#  Core Playback  (crossfade A/B)
# ═════════════════════════════════════════════════════════════════════

func play_music(stream: AudioStream, fade_duration: float = CROSSFADE_DEFAULT) -> void:
	if stream == null:
		return
	if _crossfade_tween:
		_crossfade_tween.kill()

	# Swap active player — the outgoing player becomes the fading-out one
	var outgoing: AudioStreamPlayer = _active_player
	var incoming: AudioStreamPlayer = music_player_a if _active_player == music_player_b else music_player_b
	_active_player = incoming

	# Hand the old stream to the outgoing player to fade out
	if outgoing.playing:
		# outgoing already has its stream, just fade it
		pass

	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()

	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.tween_property(incoming, "volume_db", music_volume_db, fade_duration)
	_crossfade_tween.tween_property(outgoing, "volume_db", SILENCE_DB, fade_duration)
	_crossfade_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_duration: float = CROSSFADE_DEFAULT) -> void:
	if _crossfade_tween:
		_crossfade_tween.kill()
	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(_active_player, "volume_db", SILENCE_DB, fade_duration)
	_crossfade_tween.chain().tween_callback(_active_player.stop)
	_current_playlist_id = ""
	_playlist_tracks = []


# ═════════════════════════════════════════════════════════════════════
#  Dynamic Race Intensity
# ═════════════════════════════════════════════════════════════════════

func set_race_intensity(value: float) -> void:
	## Blend in the intensity layer (0.0-1.0).
	race_intensity = clampf(value, 0.0, 1.0)
	var target_db: float = lerpf(SILENCE_DB, music_volume_db, race_intensity)

	if _intensity_tween:
		_intensity_tween.kill()
	_intensity_tween = create_tween()
	_intensity_tween.tween_property(_intensity_player, "volume_db", target_db, 0.3)


func start_race_intensity_layer(stream: AudioStream) -> void:
	## Load and begin playing the race intensity layer track.
	if stream == null:
		return
	_intensity_player.stream = stream
	_intensity_player.volume_db = SILENCE_DB
	_intensity_player.play()
	print("[Audio] Race intensity layer started.")


func stop_race_intensity_layer(fade: float = 1.0) -> void:
	if not _intensity_player.playing:
		return
	if _intensity_tween:
		_intensity_tween.kill()
	_intensity_tween = create_tween()
	_intensity_tween.tween_property(_intensity_player, "volume_db", SILENCE_DB, fade)
	_intensity_tween.chain().tween_callback(_intensity_player.stop)
	race_intensity = 0.0
	print("[Audio] Race intensity layer stopped.")


# ═════════════════════════════════════════════════════════════════════
#  Ambient Soundscape
# ═════════════════════════════════════════════════════════════════════

func start_ambient(layer_paths: Array[String], fade_in: float = 2.0) -> void:
	## Start looping ambient layers (city hum, neon buzz, etc.).
	stop_ambient(0.2)
	for path: String in layer_paths:
		var stream: AudioStream = _load_stream(path)
		if stream == null:
			print("[Audio] Ambient stream not found: %s" % path)
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = BUS_SFX
		player.volume_db = SILENCE_DB
		player.name = "Ambient_%d" % _ambient_players.size()
		add_child(player)
		player.play()
		_ambient_players.append(player)

	# Fade them all in
	_ambient_active = true
	if _ambient_fade_tween:
		_ambient_fade_tween.kill()
	_ambient_fade_tween = create_tween().set_parallel(true)
	for p: AudioStreamPlayer in _ambient_players:
		_ambient_fade_tween.tween_property(p, "volume_db", sfx_volume_db - 12.0, fade_in)

	print("[Audio] Ambient started — %d layers." % _ambient_players.size())


func stop_ambient(fade_out: float = 2.0) -> void:
	if _ambient_players.is_empty():
		return
	_ambient_active = false
	if _ambient_fade_tween:
		_ambient_fade_tween.kill()
	_ambient_fade_tween = create_tween().set_parallel(true)
	for p: AudioStreamPlayer in _ambient_players:
		_ambient_fade_tween.tween_property(p, "volume_db", SILENCE_DB, fade_out)
	# Clean up after fade
	var players_to_free := _ambient_players.duplicate()
	_ambient_players.clear()
	_ambient_fade_tween.chain().tween_callback(func() -> void:
		for p: AudioStreamPlayer in players_to_free:
			if is_instance_valid(p):
				p.stop()
				p.queue_free()
	)
	print("[Audio] Ambient stopping (fade %.1fs)." % fade_out)


# ═════════════════════════════════════════════════════════════════════
#  One-shot Helpers  (kept for backward compat)
# ═════════════════════════════════════════════════════════════════════

func play_sfx(stream: AudioStream, volume_db_offset: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = sfx_volume_db + volume_db_offset
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func play_voice(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_VOICE
	player.volume_db = voice_volume_db
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ═════════════════════════════════════════════════════════════════════
#  EventBus Callbacks
# ═════════════════════════════════════════════════════════════════════

func _on_game_state_audio_changed(state_name: String) -> void:
	match state_name:
		"menu":
			switch_music_state(MusicState.MENU)
			stop_ambient()
		"free_roam":
			switch_music_state(MusicState.FREE_ROAM)
			start_ambient([
				"res://assets/audio/ambient/city_traffic_hum.ogg",
				"res://assets/audio/ambient/neon_buzz.ogg",
				"res://assets/audio/ambient/distant_highway.ogg",
			])
		"racing":
			switch_music_state(MusicState.RACING)
			stop_ambient(0.5)
		"garage":
			switch_music_state(MusicState.GARAGE)
			stop_ambient()
		_:
			print("[Audio] Unknown audio state: %s" % state_name)


func _on_race_started(_race_data: Dictionary) -> void:
	switch_music_state(MusicState.RACING, 0.8)
	stop_ambient(0.5)

	# Try to load a racing intensity layer
	var intensity_stream: AudioStream = _load_stream("res://assets/audio/music/race_intensity_layer.ogg")
	if intensity_stream:
		start_race_intensity_layer(intensity_stream)
	set_race_intensity(0.2)


func _on_race_finished(_results: Dictionary) -> void:
	stop_race_intensity_layer(1.5)
	set_race_intensity(0.0)


func _on_countdown_tick(count: int) -> void:
	## Audio response to 3-2-1-GO countdown handled by SFXManager,
	## but we lower music volume during countdown for clarity.
	if count == 3:
		if _crossfade_tween:
			_crossfade_tween.kill()
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(_active_player, "volume_db", music_volume_db - 8.0, 0.3)
	elif count <= 0:
		# GO — restore music
		if _crossfade_tween:
			_crossfade_tween.kill()
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(_active_player, "volume_db", music_volume_db, 1.0)


func _on_lap_completed(_racer_id: int, lap: int, _time: float) -> void:
	## Ramp up intensity as laps progress.
	## Assumes max 5 laps; adjust based on race_data if needed.
	var intensity := clampf(float(lap) / 5.0, 0.2, 1.0)
	set_race_intensity(intensity)


func _on_pursuit_started() -> void:
	set_race_intensity(minf(race_intensity + 0.4, 1.0))


func _on_pursuit_escaped() -> void:
	set_race_intensity(maxf(race_intensity - 0.4, 0.0))


# ═════════════════════════════════════════════════════════════════════
#  Utility
# ═════════════════════════════════════════════════════════════════════

func _load_stream(path: String) -> AudioStream:
	## Safely attempt to load an AudioStream resource.
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	if res is AudioStream:
		return res as AudioStream
	print("[Audio] Resource at '%s' is not an AudioStream." % path)
	return null


func get_current_track_info() -> Dictionary:
	## Return metadata about the currently playing track (for HUD radio display).
	if _current_track_index < 0 or _current_track_index >= _playlist_tracks.size():
		return {}
	return _playlist_tracks[_current_track_index]
