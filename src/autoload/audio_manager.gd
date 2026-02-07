## Global audio manager handling music, SFX, engine sounds, and voice.
## Supports crossfading between music tracks and layered engine audio.
extends Node

# Audio buses
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_ENGINE := "Engine"
const BUS_VOICE := "Voice"

var music_player: AudioStreamPlayer = null
var music_crossfade_player: AudioStreamPlayer = null
var _crossfade_tween: Tween = null

var music_volume_db: float = 0.0
var sfx_volume_db: float = 0.0
var engine_volume_db: float = 0.0
var voice_volume_db: float = 0.0


func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = BUS_MUSIC
	add_child(music_player)

	music_crossfade_player = AudioStreamPlayer.new()
	music_crossfade_player.bus = BUS_MUSIC
	add_child(music_crossfade_player)


func play_music(stream: AudioStream, fade_duration: float = 1.0) -> void:
	if stream == null:
		return
	if _crossfade_tween:
		_crossfade_tween.kill()

	music_crossfade_player.stream = music_player.stream
	music_crossfade_player.volume_db = music_player.volume_db
	if music_player.playing:
		music_crossfade_player.play(music_player.get_playback_position())

	music_player.stream = stream
	music_player.volume_db = -40.0
	music_player.play()

	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.tween_property(music_player, "volume_db", music_volume_db, fade_duration)
	_crossfade_tween.tween_property(music_crossfade_player, "volume_db", -40.0, fade_duration)
	_crossfade_tween.chain().tween_callback(music_crossfade_player.stop)


func stop_music(fade_duration: float = 1.0) -> void:
	if _crossfade_tween:
		_crossfade_tween.kill()
	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(music_player, "volume_db", -40.0, fade_duration)
	_crossfade_tween.chain().tween_callback(music_player.stop)


func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = volume_db + sfx_volume_db
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
