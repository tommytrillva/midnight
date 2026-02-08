## Resource class holding metadata for a single music track.
## Used by the radio system, playlist UI, and AudioManager to display
## track info on the HUD and filter tracks by mood/genre/BPM.
##
## Create instances in the editor or from code:
##   var track := MusicTrackData.new()
##   track.title = "Neon Rain"
##   track.artist = "DJ Turbo"
class_name MusicTrackData
extends Resource

# ── Core Metadata ────────────────────────────────────────────────────
## Display title shown on the in-game radio HUD.
@export var title: String = ""

## Artist / DJ name.
@export var artist: String = ""

## Genre tag for filtering (e.g. "drum_and_bass", "lo_fi", "synthwave",
## "garage", "j_pop", "ambient_electronic").
@export var genre: String = ""

## Beats per minute — used for beat-synced UI effects and transition timing.
@export var bpm: float = 120.0

## Duration in seconds (informational — actual playback length comes
## from the AudioStream, but this is useful for UI track-list display).
@export var duration_seconds: float = 180.0

## Mood tags for smart playlist selection.
## Examples: "chill", "hype", "melancholy", "aggressive", "dreamy",
## "late_night", "early_morning", "cruising".
@export var mood_tags: Array[String] = []

# ── Audio Reference ──────────────────────────────────────────────────
## Path to the AudioStream resource (e.g. "res://assets/audio/music/neon_rain.ogg").
## The AudioManager resolves this at runtime via load().
@export var stream_path: String = ""

## Optional: pre-loaded stream for editor previews.
@export var stream: AudioStream = null

# ── Radio Metadata ───────────────────────────────────────────────────
## Which in-game radio station(s) this track belongs to.
## Stations: "nova_fm", "midnight_beats", "drift_radio", "lo_fi_cruiser".
@export var radio_stations: Array[String] = []

## Is this track unlocked by default or earned through gameplay?
@export var unlocked_by_default: bool = true

## Optional unlock condition (mission_id, rep_tier, etc.)
@export var unlock_condition: String = ""

# ── Intensity Layering ───────────────────────────────────────────────
## If this track has a companion intensity layer (e.g. drums-only stem
## that gets mixed in during high-intensity moments), reference it here.
@export var intensity_layer_path: String = ""


# ═════════════════════════════════════════════════════════════════════
#  Helpers
# ═════════════════════════════════════════════════════════════════════

func get_display_string() -> String:
	## "Artist — Title" format for HUD display.
	if artist.is_empty():
		return title
	return "%s — %s" % [artist, title]


func has_mood(mood: String) -> bool:
	return mood in mood_tags


func has_genre(target_genre: String) -> bool:
	return genre == target_genre


func get_beat_interval() -> float:
	## Seconds per beat, useful for syncing UI pulses.
	if bpm <= 0.0:
		return 0.5
	return 60.0 / bpm


func matches_filter(filter: Dictionary) -> bool:
	## Check if this track matches a set of filter criteria.
	## filter can contain: "genre", "mood", "station", "bpm_min", "bpm_max".
	if filter.has("genre") and genre != filter["genre"]:
		return false
	if filter.has("mood"):
		if not has_mood(filter["mood"]):
			return false
	if filter.has("station"):
		if not filter["station"] in radio_stations:
			return false
	if filter.has("bpm_min") and bpm < filter["bpm_min"]:
		return false
	if filter.has("bpm_max") and bpm > filter["bpm_max"]:
		return false
	return true


func to_dict() -> Dictionary:
	## Serialize to dictionary (for JSON export or save data).
	return {
		"title": title,
		"artist": artist,
		"genre": genre,
		"bpm": bpm,
		"duration_seconds": duration_seconds,
		"mood_tags": mood_tags,
		"stream_path": stream_path,
		"radio_stations": radio_stations,
		"unlocked_by_default": unlocked_by_default,
		"unlock_condition": unlock_condition,
		"intensity_layer_path": intensity_layer_path,
	}


static func from_dict(data: Dictionary) -> MusicTrackData:
	## Create a MusicTrackData from a dictionary (e.g. loaded from JSON).
	var track := MusicTrackData.new()
	track.title = data.get("title", "")
	track.artist = data.get("artist", "")
	track.genre = data.get("genre", "")
	track.bpm = data.get("bpm", 120.0)
	track.duration_seconds = data.get("duration_seconds", 180.0)
	track.mood_tags.assign(data.get("mood_tags", []))
	track.stream_path = data.get("stream_path", data.get("path", ""))
	track.radio_stations.assign(data.get("radio_stations", []))
	track.unlocked_by_default = data.get("unlocked_by_default", true)
	track.unlock_condition = data.get("unlock_condition", "")
	track.intensity_layer_path = data.get("intensity_layer_path", "")
	return track
