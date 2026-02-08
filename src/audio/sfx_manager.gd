## Centralized SFX coordinator.  Listens to EventBus signals and
## plays the appropriate sound effects through the SFX audio bus.
## Handles tire screech, collisions, nitro, countdown, UI sounds,
## police sirens, and ambient one-shots.
##
## Add this as an autoload or a child of AudioManager.
class_name SFXManager
extends Node

# ═════════════════════════════════════════════════════════════════════
#  Stream Cache
# ═════════════════════════════════════════════════════════════════════
## All paths point to placeholder locations under assets/audio/sfx/.
## Swap in real .ogg/.wav files when available.

# Tire / Drift
var _tire_screech_stream: AudioStream = null
var _tire_screech_player: AudioStreamPlayer = null  ## Looping — volume driven by slip

# Collision
var _impact_light_stream: AudioStream = null
var _impact_heavy_stream: AudioStream = null

# Nitro
var _nitro_activate_stream: AudioStream = null
var _nitro_loop_stream: AudioStream = null
var _nitro_deplete_stream: AudioStream = null
var _nitro_loop_player: AudioStreamPlayer = null

# Race
var _countdown_beep_stream: AudioStream = null
var _countdown_go_stream: AudioStream = null
var _checkpoint_stream: AudioStream = null
var _lap_complete_stream: AudioStream = null
var _race_finish_stream: AudioStream = null

# UI
var _ui_navigate_stream: AudioStream = null
var _ui_select_stream: AudioStream = null
var _ui_back_stream: AudioStream = null
var _ui_purchase_stream: AudioStream = null  ## Cash register "ka-ching"
var _ui_error_stream: AudioStream = null

# Police
var _siren_distant_stream: AudioStream = null
var _siren_close_stream: AudioStream = null
var _siren_player: AudioStreamPlayer = null  ## Looping siren
var _busted_stream: AudioStream = null

# Ambient one-shots (layered on top of AudioManager ambient loops)
var _ambient_horn_stream: AudioStream = null
var _ambient_screech_stream: AudioStream = null

# ── Internal ─────────────────────────────────────────────────────────
const BUS_SFX := "SFX"
var _rng := RandomNumberGenerator.new()

## Cooldowns to prevent sound spam (signal name -> remaining cooldown)
var _cooldowns: Dictionary = {}
const DEFAULT_COOLDOWN := 0.1  ## seconds


# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_rng.randomize()
	_load_all_streams()
	_create_persistent_players()
	_connect_signals()
	print("[SFX] SFXManager ready — streams loaded.")


func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	_update_ambient_one_shots(delta)


# ═════════════════════════════════════════════════════════════════════
#  Stream Loading
# ═════════════════════════════════════════════════════════════════════

func _load_all_streams() -> void:
	# Tire / Drift
	_tire_screech_stream = _try_load("res://assets/audio/sfx/tire_screech_loop.ogg")

	# Collision
	_impact_light_stream = _try_load("res://assets/audio/sfx/impact_light.ogg")
	_impact_heavy_stream = _try_load("res://assets/audio/sfx/impact_heavy.ogg")

	# Nitro
	_nitro_activate_stream = _try_load("res://assets/audio/sfx/nitro_activate.ogg")
	_nitro_loop_stream = _try_load("res://assets/audio/sfx/nitro_loop.ogg")
	_nitro_deplete_stream = _try_load("res://assets/audio/sfx/nitro_deplete.ogg")

	# Race
	_countdown_beep_stream = _try_load("res://assets/audio/sfx/countdown_beep.ogg")
	_countdown_go_stream = _try_load("res://assets/audio/sfx/countdown_go.ogg")
	_checkpoint_stream = _try_load("res://assets/audio/sfx/checkpoint_ding.ogg")
	_lap_complete_stream = _try_load("res://assets/audio/sfx/lap_complete.ogg")
	_race_finish_stream = _try_load("res://assets/audio/sfx/race_finish.ogg")

	# UI
	_ui_navigate_stream = _try_load("res://assets/audio/sfx/ui_navigate.ogg")
	_ui_select_stream = _try_load("res://assets/audio/sfx/ui_select.ogg")
	_ui_back_stream = _try_load("res://assets/audio/sfx/ui_back.ogg")
	_ui_purchase_stream = _try_load("res://assets/audio/sfx/ui_purchase.ogg")
	_ui_error_stream = _try_load("res://assets/audio/sfx/ui_error.ogg")

	# Police
	_siren_distant_stream = _try_load("res://assets/audio/sfx/siren_distant.ogg")
	_siren_close_stream = _try_load("res://assets/audio/sfx/siren_close.ogg")
	_busted_stream = _try_load("res://assets/audio/sfx/busted.ogg")

	# Ambient one-shots
	_ambient_horn_stream = _try_load("res://assets/audio/sfx/ambient_horn.ogg")
	_ambient_screech_stream = _try_load("res://assets/audio/sfx/ambient_screech.ogg")


func _create_persistent_players() -> void:
	## Create looping players that persist (screech, nitro, siren).
	## They stay at silence until activated.

	# Tire screech — looping, volume driven by drift slip angle
	_tire_screech_player = _make_loop_player("TireScreech", _tire_screech_stream)

	# Nitro loop
	_nitro_loop_player = _make_loop_player("NitroLoop", _nitro_loop_stream)

	# Police siren
	_siren_player = _make_loop_player("Siren", _siren_distant_stream)


func _make_loop_player(player_name: String, initial_stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = BUS_SFX
	player.name = player_name
	player.volume_db = -60.0
	if initial_stream:
		player.stream = initial_stream
	add_child(player)
	return player


# ═════════════════════════════════════════════════════════════════════
#  Signal Connections
# ═════════════════════════════════════════════════════════════════════

func _connect_signals() -> void:
	# Vehicle events
	EventBus.vehicle_collision.connect(_on_vehicle_collision)
	EventBus.nitro_activated.connect(_on_nitro_activated)
	EventBus.nitro_depleted.connect(_on_nitro_depleted)

	# Drift / tire
	EventBus.tire_screech.connect(_on_tire_screech)
	EventBus.drift_started.connect(_on_drift_started)
	EventBus.drift_ended.connect(_on_drift_ended)

	# Race events
	EventBus.race_countdown_tick.connect(_on_countdown_tick)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.race_finished.connect(_on_race_finished)

	# Economy / UI
	EventBus.cash_spent.connect(_on_cash_spent)
	EventBus.insufficient_funds.connect(_on_insufficient_funds)

	# Police
	EventBus.pursuit_started.connect(_on_pursuit_started)
	EventBus.pursuit_escaped.connect(_on_pursuit_escaped)
	EventBus.heat_level_changed.connect(_on_heat_level_changed)
	EventBus.busted.connect(_on_busted)

	print("[SFX] All EventBus signals connected.")


# ═════════════════════════════════════════════════════════════════════
#  Tire Screech / Drift
# ═════════════════════════════════════════════════════════════════════

func _on_tire_screech(_vehicle_id: int, slip_intensity: float) -> void:
	## Continuously called while the vehicle is sliding.
	## slip_intensity 0-1 maps to screech volume.
	if _tire_screech_player == null or _tire_screech_stream == null:
		return

	var target_vol := lerpf(-60.0, -6.0, clampf(slip_intensity, 0.0, 1.0))

	if not _tire_screech_player.playing:
		_tire_screech_player.volume_db = -60.0
		_tire_screech_player.play()

	# Smooth volume approach to avoid clicks
	_tire_screech_player.volume_db = lerpf(_tire_screech_player.volume_db, target_vol, 0.25)

	# Slight pitch variation with intensity for realism
	_tire_screech_player.pitch_scale = lerpf(0.9, 1.15, slip_intensity)


func _on_drift_started(_vehicle_id: int) -> void:
	## Begin looping tire screech.
	if _tire_screech_player and _tire_screech_stream and not _tire_screech_player.playing:
		_tire_screech_player.volume_db = -40.0
		_tire_screech_player.play()


func _on_drift_ended(_vehicle_id: int, _score: float) -> void:
	## Fade out tire screech.
	_fade_player(_tire_screech_player, -60.0, 0.3)


# ═════════════════════════════════════════════════════════════════════
#  Collision / Impact
# ═════════════════════════════════════════════════════════════════════

func _on_vehicle_collision(_vehicle_id: int, impact_force: float) -> void:
	if _is_on_cooldown("collision"):
		return
	_set_cooldown("collision", 0.15)

	if impact_force > 50.0 and _impact_heavy_stream:
		_play_oneshot(_impact_heavy_stream, clampf(impact_force / 200.0 * 6.0 - 6.0, -12.0, 0.0))
	elif _impact_light_stream:
		_play_oneshot(_impact_light_stream, clampf(impact_force / 100.0 * 6.0 - 12.0, -18.0, -3.0))


# ═════════════════════════════════════════════════════════════════════
#  Nitro
# ═════════════════════════════════════════════════════════════════════

func _on_nitro_activated(_vehicle_id: int) -> void:
	# Activation whoosh
	if _nitro_activate_stream:
		_play_oneshot(_nitro_activate_stream, -3.0)

	# Start loop
	if _nitro_loop_player and _nitro_loop_stream:
		_nitro_loop_player.stream = _nitro_loop_stream
		_nitro_loop_player.volume_db = -12.0
		if not _nitro_loop_player.playing:
			_nitro_loop_player.play()
		_fade_player(_nitro_loop_player, -6.0, 0.2)


func _on_nitro_depleted(_vehicle_id: int) -> void:
	# Depletion sound
	if _nitro_deplete_stream:
		_play_oneshot(_nitro_deplete_stream, -6.0)

	# Fade out loop
	if _nitro_loop_player and _nitro_loop_player.playing:
		_fade_player(_nitro_loop_player, -60.0, 0.4)


# ═════════════════════════════════════════════════════════════════════
#  Race Countdown & Events
# ═════════════════════════════════════════════════════════════════════

func _on_countdown_tick(count: int) -> void:
	if count > 0:
		# 3, 2, 1 beeps
		if _countdown_beep_stream:
			var pitch := 1.0 + (3 - count) * 0.1  # Rising pitch
			_play_oneshot(_countdown_beep_stream, -3.0, pitch)
		EventBus.countdown_beep.emit(count)
	else:
		# GO!
		if _countdown_go_stream:
			_play_oneshot(_countdown_go_stream, 0.0, 1.2)
		EventBus.countdown_go.emit()


func _on_checkpoint_reached(_racer_id: int, _checkpoint_index: int) -> void:
	if _checkpoint_stream:
		_play_oneshot(_checkpoint_stream, -6.0)


func _on_lap_completed(_racer_id: int, _lap: int, _time: float) -> void:
	if _lap_complete_stream:
		_play_oneshot(_lap_complete_stream, -3.0)


func _on_race_finished(_results: Dictionary) -> void:
	if _race_finish_stream:
		_play_oneshot(_race_finish_stream, 0.0)

	# Stop any looping SFX
	_fade_player(_tire_screech_player, -60.0, 0.5)
	_fade_player(_nitro_loop_player, -60.0, 0.5)


# ═════════════════════════════════════════════════════════════════════
#  UI Sounds
# ═════════════════════════════════════════════════════════════════════

func play_ui_navigate() -> void:
	if _ui_navigate_stream:
		_play_oneshot(_ui_navigate_stream, -12.0)


func play_ui_select() -> void:
	if _ui_select_stream:
		_play_oneshot(_ui_select_stream, -9.0)


func play_ui_back() -> void:
	if _ui_back_stream:
		_play_oneshot(_ui_back_stream, -12.0)


func play_ui_error() -> void:
	if _ui_error_stream:
		_play_oneshot(_ui_error_stream, -6.0)


func _on_cash_spent(_amount: int, _item: String) -> void:
	if _ui_purchase_stream:
		_play_oneshot(_ui_purchase_stream, -6.0)


func _on_insufficient_funds(_cost: int) -> void:
	play_ui_error()


# ═════════════════════════════════════════════════════════════════════
#  Police Siren
# ═════════════════════════════════════════════════════════════════════

func _on_pursuit_started() -> void:
	_start_siren(false)  ## Start with close siren


func _on_pursuit_escaped() -> void:
	_stop_siren(1.5)


func _on_heat_level_changed(_old_level: int, new_level: int) -> void:
	## Switch between distant and close siren based on heat level.
	if new_level >= 3:
		_start_siren(false)  # Close
	elif new_level >= 1:
		_start_siren(true)   # Distant
	else:
		_stop_siren(2.0)


func _on_busted(_fine: int) -> void:
	_stop_siren(0.5)
	if _busted_stream:
		_play_oneshot(_busted_stream, 0.0)


func _start_siren(distant: bool) -> void:
	if _siren_player == null:
		return
	var stream: AudioStream = _siren_distant_stream if distant else _siren_close_stream
	if stream == null:
		return

	if _siren_player.stream != stream:
		_siren_player.stream = stream
		_siren_player.play()

	var target_vol := -18.0 if distant else -6.0
	_fade_player(_siren_player, target_vol, 0.5)
	print("[SFX] Siren %s" % ("distant" if distant else "close"))


func _stop_siren(fade_out: float) -> void:
	if _siren_player and _siren_player.playing:
		_fade_player(_siren_player, -60.0, fade_out)


# ═════════════════════════════════════════════════════════════════════
#  Ambient One-Shots (random city sounds in free roam)
# ═════════════════════════════════════════════════════════════════════

var _ambient_oneshot_timer: float = 0.0
const AMBIENT_ONESHOT_INTERVAL_MIN := 4.0
const AMBIENT_ONESHOT_INTERVAL_MAX := 15.0

func _update_ambient_one_shots(delta: float) -> void:
	## Periodically play random ambient sounds when in free roam.
	## GameManager.current_state check ensures we only do this in the right mode.
	if not _is_free_roam():
		return

	_ambient_oneshot_timer -= delta
	if _ambient_oneshot_timer <= 0.0:
		_ambient_oneshot_timer = _rng.randf_range(AMBIENT_ONESHOT_INTERVAL_MIN, AMBIENT_ONESHOT_INTERVAL_MAX)
		_play_random_ambient_oneshot()


func _play_random_ambient_oneshot() -> void:
	var candidates: Array[AudioStream] = []
	if _ambient_horn_stream:
		candidates.append(_ambient_horn_stream)
	if _ambient_screech_stream:
		candidates.append(_ambient_screech_stream)

	if candidates.is_empty():
		return

	var stream: AudioStream = candidates[_rng.randi() % candidates.size()]
	var vol := _rng.randf_range(-24.0, -12.0)  ## Random distance feel
	var pitch := _rng.randf_range(0.85, 1.15)   ## Slight variation
	_play_oneshot(stream, vol, pitch)


func _is_free_roam() -> bool:
	## Check if the game is currently in free roam.
	if not Engine.has_singleton("GameManager"):
		return false
	# Use the GameManager autoload if available
	var gm: Node = Engine.get_singleton("GameManager")
	if gm and gm.has_method("get") and "current_state" in gm:
		return gm.current_state == 1  # FREE_ROAM enum value
	# Fallback: always allow ambient
	return true


# ═════════════════════════════════════════════════════════════════════
#  Playback Helpers
# ═════════════════════════════════════════════════════════════════════

func _play_oneshot(stream: AudioStream, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	## Fire-and-forget sound effect player.
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = vol_db
	player.pitch_scale = pitch
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _fade_player(player: AudioStreamPlayer, target_db: float, duration: float) -> void:
	## Tween a persistent player's volume.
	if player == null:
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, duration)
	if target_db <= -55.0:
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(player):
				player.stop()
		)


# ═════════════════════════════════════════════════════════════════════
#  Cooldown System
# ═════════════════════════════════════════════════════════════════════

func _set_cooldown(key: String, duration: float) -> void:
	_cooldowns[key] = duration


func _is_on_cooldown(key: String) -> bool:
	return _cooldowns.get(key, 0.0) > 0.0


func _tick_cooldowns(delta: float) -> void:
	var keys_to_remove: Array[String] = []
	for key: String in _cooldowns:
		_cooldowns[key] -= delta
		if _cooldowns[key] <= 0.0:
			keys_to_remove.append(key)
	for key: String in keys_to_remove:
		_cooldowns.erase(key)


# ═════════════════════════════════════════════════════════════════════
#  Utility
# ═════════════════════════════════════════════════════════════════════

func _try_load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is AudioStream:
			return res as AudioStream
	return null
