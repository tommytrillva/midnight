## Orchestrates scripted cinematic sequences combining camera movements,
## dialogue, screen effects, music/audio, character animation, environment
## changes, UI control, and transitions.
##
## Cinematics are defined as sequences of CinematicStep data loaded from
## JSON files in res://data/cinematics/. Each step has a type, data payload,
## duration, and a parallel flag (run alongside the next step).
##
## During playback the system hides the HUD, shows letterbox bars, switches
## to the cinematic camera, and disables player input. It emits signals
## through EventBus for other systems to react to.
class_name CinematicSystem
extends Node

# ---------------------------------------------------------------------------
# Signals (local — also mirrored to EventBus)
# ---------------------------------------------------------------------------
signal cinematic_started(cinematic_id: String)
signal cinematic_step(step_index: int, step_data: Dictionary)
signal cinematic_finished(cinematic_id: String)

# ---------------------------------------------------------------------------
# Inner class — CinematicStep
# ---------------------------------------------------------------------------
class CinematicStep:
	## The step type: "camera", "dialogue", "effect", "wait", "transition",
	## "spawn", "move_to", "audio", "animate", "environment".
	var type: String = ""
	## Payload dictionary whose keys depend on the type.
	var data: Dictionary = {}
	## How long this step takes (seconds). 0 means instant / event-driven.
	var duration: float = 0.0
	## If true, this step runs alongside the *next* step instead of blocking.
	var parallel: bool = false

	func _init(dict: Dictionary = {}) -> void:
		type = dict.get("type", "")
		data = dict.get("data", {})
		duration = dict.get("duration", 0.0)
		parallel = dict.get("parallel", false)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _playing: bool = false
var _paused: bool = false
var _skipping: bool = false
var _current_id: String = ""
var _steps: Array[CinematicStep] = []
var _step_index: int = 0

## Cached cinematic JSON data to avoid reloading.
var _cache: Dictionary = {}

## Child nodes created at _ready.
var _camera: CinematicCamera = null
var _letterbox: Letterbox = null
var _slow_motion: SlowMotion = null

## Reference to the dialogue system (fetched from GameManager).
var _dialogue_system: DialogueSystem = null

## The gameplay camera that was active before the cinematic started.
var _previous_camera: Camera3D = null

## Tracks parallel tasks so we can await them when a blocking step is hit.
var _parallel_tasks: Array = []

## Whether input was disabled by us (so we can restore it).
var _input_was_disabled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "CinematicSystem"

	# Create child nodes
	_camera = CinematicCamera.new()
	_camera.name = "CinematicCamera"
	add_child(_camera)

	_letterbox = Letterbox.new()
	add_child(_letterbox)

	_slow_motion = SlowMotion.new()
	add_child(_slow_motion)

	print("[Cinematic] System initialized.")


func _input(event: InputEvent) -> void:
	if not _playing:
		return

	# Allow skip with a dedicated input action or ui_cancel
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cinematic_skip"):
		skip_cinematic()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Load and play a cinematic sequence by its ID (matches JSON filename).
func play_cinematic(cinematic_id: String) -> void:
	if _playing:
		push_warning("[Cinematic] Already playing '%s'. Ignoring request for '%s'." % [_current_id, cinematic_id])
		return

	var cinematic_data := _load_cinematic(cinematic_id)
	if cinematic_data.is_empty():
		push_error("[Cinematic] Failed to load cinematic: %s" % cinematic_id)
		return

	# Parse steps
	_steps.clear()
	var raw_steps: Array = cinematic_data.get("steps", [])
	for raw in raw_steps:
		_steps.append(CinematicStep.new(raw))

	if _steps.is_empty():
		push_warning("[Cinematic] Cinematic '%s' has no steps." % cinematic_id)
		return

	_current_id = cinematic_id
	_step_index = 0
	_playing = true
	_paused = false
	_skipping = false
	_parallel_tasks.clear()

	# Resolve dialogue system reference
	if GameManager and GameManager.has_node("DialogueSystem"):
		_dialogue_system = GameManager.get_node("DialogueSystem") as DialogueSystem
	elif GameManager:
		# Might be added as a direct child with a different name — search
		for child in GameManager.get_children():
			if child is DialogueSystem:
				_dialogue_system = child
				break

	# Enter cinematic state
	_enter_cinematic_mode()

	# Emit signals
	cinematic_started.emit(cinematic_id)
	EventBus.cinematic_started.emit(cinematic_id)
	print("[Cinematic] Playing: %s (%d steps)" % [cinematic_id, _steps.size()])

	# Run the sequence
	await _run_sequence()

	# Finished
	_exit_cinematic_mode()
	_playing = false
	var finished_id := _current_id
	_current_id = ""

	cinematic_finished.emit(finished_id)
	EventBus.cinematic_finished.emit(finished_id)
	print("[Cinematic] Finished: %s" % finished_id)


## Skip the current cinematic (for replays / impatient players).
func skip_cinematic() -> void:
	if not _playing or _skipping:
		return

	_skipping = true
	print("[Cinematic] Skipping: %s" % _current_id)
	EventBus.cinematic_skipped.emit(_current_id)


## Pause the cinematic (e.g. if the game is paused).
func pause_cinematic() -> void:
	if not _playing or _paused:
		return
	_paused = true
	get_tree().paused = true
	print("[Cinematic] Paused.")


## Resume a paused cinematic.
func resume_cinematic() -> void:
	if not _paused:
		return
	_paused = false
	get_tree().paused = false
	print("[Cinematic] Resumed.")


## Returns true if a cinematic is currently playing.
func is_playing() -> bool:
	return _playing


## Returns the ID of the currently playing cinematic, or empty string.
func get_current_id() -> String:
	return _current_id


## Direct access to child nodes for external configuration.
func get_camera() -> CinematicCamera:
	return _camera


func get_letterbox() -> Letterbox:
	return _letterbox


func get_slow_motion() -> SlowMotion:
	return _slow_motion


# ---------------------------------------------------------------------------
# Sequence Runner
# ---------------------------------------------------------------------------

func _run_sequence() -> void:
	while _step_index < _steps.size():
		if _skipping:
			_apply_skip_state()
			return

		var step: CinematicStep = _steps[_step_index]
		cinematic_step.emit(_step_index, {"type": step.type, "data": step.data})

		if step.parallel:
			# Fire this step without waiting, move to next
			var task := _execute_step(step)
			_parallel_tasks.append(task)
			_step_index += 1
			continue

		# Blocking step — first await any pending parallel tasks
		if not _parallel_tasks.is_empty():
			for task in _parallel_tasks:
				await task
			_parallel_tasks.clear()

		# Execute and await the blocking step
		await _execute_step(step)
		_step_index += 1

	# Await any remaining parallel tasks
	if not _parallel_tasks.is_empty():
		for task in _parallel_tasks:
			await task
		_parallel_tasks.clear()


## Execute a single step. Returns when the step is complete.
func _execute_step(step: CinematicStep) -> void:
	match step.type:
		"camera":
			await _step_camera(step.data, step.duration)
		"dialogue":
			await _step_dialogue(step.data)
		"effect":
			await _step_effect(step.data, step.duration)
		"wait":
			await _step_wait(step.duration)
		"transition":
			await _step_transition(step.data, step.duration)
		"spawn":
			_step_spawn(step.data)
		"move_to":
			await _step_move_to(step.data, step.duration)
		"audio":
			_step_audio(step.data)
		"animate":
			await _step_animate(step.data, step.duration)
		"environment":
			_step_environment(step.data)
		_:
			push_warning("[Cinematic] Unknown step type: %s" % step.type)
			if step.duration > 0.0:
				await _wait_seconds(step.duration)


# ---------------------------------------------------------------------------
# Step Implementations
# ---------------------------------------------------------------------------

func _step_camera(data: Dictionary, duration: float) -> void:
	var move: String = data.get("move", "")
	var ease_type: String = data.get("ease", "ease_in_out")

	match move:
		"pan":
			var from: Array = data.get("from", [])
			var to: Array = data.get("to", [])
			if from.size() == 3:
				_camera.global_position = Vector3(from[0], from[1], from[2])
			if to.size() == 3:
				var target: Vector3 = Vector3(to[0], to[1], to[2])
				# If there's a look_at specified, face it during the pan
				var look_at_arr: Array = data.get("look_at", [])
				if look_at_arr.size() == 3:
					_camera.look_at(Vector3(look_at_arr[0], look_at_arr[1], look_at_arr[2]), Vector3.UP)
				await _camera.pan_to(target, duration, ease_type)
			else:
				await _wait_seconds(duration)

		"dolly":
			var distance: float = data.get("distance", 0.0)
			await _camera.dolly(distance, duration, ease_type)

		"orbit":
			var target_arr: Array = data.get("target", [0, 0, 0])
			var target: Vector3 = Vector3(target_arr[0], target_arr[1], target_arr[2])
			var angle: float = data.get("angle", 90.0)
			await _camera.orbit(target, angle, duration, ease_type)

		"crane":
			var height: float = data.get("height", 0.0)
			await _camera.crane(height, duration, ease_type)

		"shake":
			var intensity: float = data.get("intensity", 0.3)
			_camera.shake(intensity, duration)
			# Shake is non-blocking by design, but we wait the duration
			await _wait_seconds(duration)

		"focus":
			var target_path: String = data.get("target_node", "")
			if not target_path.is_empty():
				var target_node := get_tree().root.get_node_or_null(target_path) as Node3D
				if target_node:
					await _camera.focus_on(target_node, duration)
				else:
					push_warning("[Cinematic] Focus target not found: %s" % target_path)
					await _wait_seconds(duration)
			else:
				await _wait_seconds(duration)

		"teleport":
			var pos_arr: Array = data.get("position", [0, 0, 0])
			var pos: Vector3 = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
			var look_arr: Array = data.get("look_at", [])
			if look_arr.size() == 3:
				_camera.teleport(pos, Vector3(look_arr[0], look_arr[1], look_arr[2]))
			else:
				_camera.teleport(pos)

		"path":
			var raw_points: Array = data.get("points", [])
			var points: Array = []
			for p in raw_points:
				if p is Array and p.size() == 3:
					points.append(Vector3(p[0], p[1], p[2]))
			var look_arr: Array = data.get("look_at", [])
			var look_target := Vector3.INF
			if look_arr.size() == 3:
				look_target = Vector3(look_arr[0], look_arr[1], look_arr[2])
			await _camera.follow_path(points, duration, look_target, ease_type)

		"dof":
			var focal: float = data.get("focal_distance", 5.0)
			var blur: float = data.get("blur", 0.5)
			_camera.set_dof(focal, blur)

		_:
			push_warning("[Cinematic] Unknown camera move: %s" % move)
			if duration > 0.0:
				await _wait_seconds(duration)


func _step_dialogue(data: Dictionary) -> void:
	var dialogue_id: String = data.get("dialogue_id", "")
	if dialogue_id.is_empty():
		push_warning("[Cinematic] Dialogue step missing dialogue_id.")
		return

	if _dialogue_system == null:
		push_warning("[Cinematic] No DialogueSystem available. Skipping dialogue: %s" % dialogue_id)
		return

	# Start the dialogue and wait for it to complete
	_dialogue_system.start_dialogue(dialogue_id)
	await _dialogue_system.dialogue_completed
	print("[Cinematic] Dialogue complete: %s" % dialogue_id)


func _step_effect(data: Dictionary, duration: float) -> void:
	# Letterbox
	if data.has("letterbox"):
		var show: bool = data.get("letterbox", true)
		var aspect: String = data.get("aspect", "cinematic")
		if show:
			await _letterbox.show_bars(duration if duration > 0.0 else 0.5, aspect)
		else:
			await _letterbox.hide_bars(duration if duration > 0.0 else 0.5)

	# Slow motion
	if data.has("slow_motion"):
		var slow_mo_data: Dictionary = data.get("slow_motion", {})
		var scale: float = slow_mo_data.get("scale", 0.5)
		var slo_duration: float = slow_mo_data.get("duration", 0.0)
		var active: bool = slow_mo_data.get("active", true)
		if active:
			await _slow_motion.activate(scale, slo_duration)
		else:
			await _slow_motion.deactivate()

	# Screen shake (full screen, not just camera)
	if data.has("screen_shake"):
		var shake_data: Dictionary = data.get("screen_shake", {})
		var intensity: float = shake_data.get("intensity", 0.3)
		var shake_dur: float = shake_data.get("duration", 0.5)
		_camera.shake(intensity, shake_dur)

	# Weather change
	if data.has("weather"):
		var weather: String = data.get("weather", "clear")
		EventBus.weather_changed.emit(weather)
		print("[Cinematic] Weather: %s" % weather)

	# Time of day change
	if data.has("time"):
		var time_period: String = data.get("time", "day")
		EventBus.time_period_changed.emit(time_period)
		print("[Cinematic] Time: %s" % time_period)

	# Color grading / post-processing hint
	if data.has("color_grade"):
		var grade: String = data.get("color_grade", "default")
		# Store as metadata for external systems to pick up
		set_meta("active_color_grade", grade)
		print("[Cinematic] Color grade: %s" % grade)

	# Fade effect
	if data.has("fade"):
		var fade_type: String = data.get("fade", "black")
		var fade_dir: String = data.get("direction", "in")
		var fade_dur: float = duration if duration > 0.0 else 0.5
		# Delegate to ScreenTransition if available
		var screen_transition := get_tree().root.get_node_or_null("ScreenTransition") as ScreenTransition
		if screen_transition:
			match fade_dir:
				"in":
					match fade_type:
						"black":
							await screen_transition.transition_in(ScreenTransition.TransitionType.FADE_BLACK, fade_dur)
						"white":
							await screen_transition.transition_in(ScreenTransition.TransitionType.FADE_WHITE, fade_dur)
				"out":
					match fade_type:
						"black":
							await screen_transition.transition_out(ScreenTransition.TransitionType.FADE_BLACK, fade_dur)
						"white":
							await screen_transition.transition_out(ScreenTransition.TransitionType.FADE_WHITE, fade_dur)

	# HUD message overlay
	if data.has("hud_message"):
		var msg_data: Dictionary = data.get("hud_message", {})
		var text: String = msg_data.get("text", "")
		var msg_dur: float = msg_data.get("duration", 3.0)
		EventBus.hud_message.emit(text, msg_dur)

	# If there was a duration and nothing above consumed it, wait
	if duration > 0.0 and not data.has("letterbox") and not data.has("slow_motion") and not data.has("fade"):
		await _wait_seconds(duration)


func _step_wait(duration: float) -> void:
	if duration <= 0.0:
		duration = 0.1
	await _wait_seconds(duration)


func _step_transition(data: Dictionary, duration: float) -> void:
	var transition_type: String = data.get("transition", "fade_black")
	var screen_transition := get_tree().root.get_node_or_null("ScreenTransition") as ScreenTransition
	if screen_transition == null:
		push_warning("[Cinematic] ScreenTransition not found. Waiting duration instead.")
		await _wait_seconds(duration)
		return

	var dur := duration if duration > 0.0 else 1.0

	match transition_type:
		"fade_black":
			await screen_transition.fade_black(dur)
		"fade_white":
			await screen_transition.fade_white(dur)
		"wipe":
			await screen_transition.wipe_horizontal(dur)
		"pixelate":
			await screen_transition.pixelate(dur)
		"scanline":
			await screen_transition.scanline_sweep(dur)
		_:
			await screen_transition.fade_black(dur)


func _step_spawn(data: Dictionary) -> void:
	var scene_path: String = data.get("scene", "")
	var spawn_name: String = data.get("name", "")
	var pos_arr: Array = data.get("position", [0, 0, 0])
	var rot_arr: Array = data.get("rotation", [0, 0, 0])

	if scene_path.is_empty():
		push_warning("[Cinematic] Spawn step missing 'scene' path.")
		return

	if not ResourceLoader.exists(scene_path):
		push_warning("[Cinematic] Spawn scene not found: %s" % scene_path)
		return

	var scene := load(scene_path) as PackedScene
	if scene == null:
		return

	var instance := scene.instantiate()
	if not spawn_name.is_empty():
		instance.name = spawn_name

	if instance is Node3D:
		instance.global_position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		instance.rotation_degrees = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])

	# Add to the current scene tree
	get_tree().current_scene.add_child(instance)
	print("[Cinematic] Spawned: %s at %s" % [spawn_name, str(pos_arr)])


func _step_move_to(data: Dictionary, duration: float) -> void:
	var target_path: String = data.get("node", "")
	var pos_arr: Array = data.get("position", [])
	var rot_arr: Array = data.get("rotation", [])

	if target_path.is_empty():
		push_warning("[Cinematic] move_to step missing 'node' path.")
		return

	var target_node := get_tree().root.get_node_or_null(target_path)
	if target_node == null or not (target_node is Node3D):
		push_warning("[Cinematic] move_to target not found or not Node3D: %s" % target_path)
		return

	var node_3d := target_node as Node3D

	if duration <= 0.0:
		# Instant move
		if pos_arr.size() == 3:
			node_3d.global_position = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		if rot_arr.size() == 3:
			node_3d.rotation_degrees = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
		return

	# Animated move
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)

	if pos_arr.size() == 3:
		var target_pos: Vector3 = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		tween.tween_property(node_3d, "global_position", target_pos, duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	if rot_arr.size() == 3:
		var target_rot: Vector3 = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
		tween.tween_property(node_3d, "rotation_degrees", target_rot, duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

	await tween.finished
	print("[Cinematic] Moved '%s' complete." % target_path)


func _step_audio(data: Dictionary) -> void:
	# Music
	if data.has("music"):
		var music_data: Dictionary = data.get("music", {})
		var track: String = music_data.get("track", "")
		var artist: String = music_data.get("artist", "")
		var action: String = music_data.get("action", "play")
		match action:
			"play":
				EventBus.music_track_changed.emit(track, artist)
				print("[Cinematic] Music: %s — %s" % [artist, track])
			"stop":
				EventBus.music_track_changed.emit("", "")
				print("[Cinematic] Music stopped.")

	# Sound effect
	if data.has("sfx"):
		var sfx_path: String = data.get("sfx", "")
		# Signal the audio manager to play a one-shot
		EventBus.game_state_audio_changed.emit("sfx:" + sfx_path)
		print("[Cinematic] SFX: %s" % sfx_path)

	# Ambient
	if data.has("ambient"):
		var zone: String = data.get("ambient", "")
		EventBus.ambient_zone_entered.emit(zone)
		print("[Cinematic] Ambient zone: %s" % zone)


func _step_animate(data: Dictionary, duration: float) -> void:
	var target_path: String = data.get("node", "")
	var anim_name: String = data.get("animation", "")

	if target_path.is_empty() or anim_name.is_empty():
		push_warning("[Cinematic] Animate step missing 'node' or 'animation'.")
		return

	var target_node := get_tree().root.get_node_or_null(target_path)
	if target_node == null:
		push_warning("[Cinematic] Animate target not found: %s" % target_path)
		return

	# Try AnimationPlayer child
	var anim_player: AnimationPlayer = null
	if target_node is AnimationPlayer:
		anim_player = target_node
	else:
		anim_player = target_node.get_node_or_null("AnimationPlayer") as AnimationPlayer

	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
		if duration > 0.0:
			await _wait_seconds(duration)
		else:
			await anim_player.animation_finished
		print("[Cinematic] Animation '%s' complete on '%s'." % [anim_name, target_path])
	else:
		push_warning("[Cinematic] Animation '%s' not found on '%s'." % [anim_name, target_path])
		if duration > 0.0:
			await _wait_seconds(duration)


func _step_environment(data: Dictionary) -> void:
	if data.has("weather"):
		EventBus.weather_changed.emit(data.get("weather", "clear"))
	if data.has("time"):
		EventBus.time_period_changed.emit(data.get("time", "day"))
	if data.has("district"):
		EventBus.district_entered.emit(data.get("district", ""))

	print("[Cinematic] Environment change: %s" % str(data))


# ---------------------------------------------------------------------------
# Cinematic Mode Enter / Exit
# ---------------------------------------------------------------------------

func _enter_cinematic_mode() -> void:
	# Save reference to current active camera
	_previous_camera = get_viewport().get_camera_3d()

	# Switch game state
	GameManager.change_state(GameManager.GameState.CUTSCENE)

	# Make cinematic camera current
	_camera.make_current()

	# Show letterbox
	_letterbox.show_bars(0.4)

	print("[Cinematic] Entered cinematic mode.")


func _exit_cinematic_mode() -> void:
	# Hide letterbox
	_letterbox.hide_bars(0.4)

	# Reset slow motion
	_slow_motion.force_reset()

	# Clear camera tracking
	_camera.clear_focus()
	_camera.stop()

	# Restore previous camera
	if _previous_camera and is_instance_valid(_previous_camera):
		_previous_camera.make_current()

	# Clear any active color grading
	if has_meta("active_color_grade"):
		remove_meta("active_color_grade")

	# Restore game state
	GameManager.change_state(GameManager.previous_state)

	print("[Cinematic] Exited cinematic mode.")


## When skipping, jump to end state — apply final-state side effects without
## playing through every step.
func _apply_skip_state() -> void:
	print("[Cinematic] Applying skip state for '%s'." % _current_id)

	# Walk remaining steps and apply only "permanent" side effects
	while _step_index < _steps.size():
		var step: CinematicStep = _steps[_step_index]

		match step.type:
			"dialogue":
				# Skip dialogue but still mark it as encountered
				var dialogue_id: String = step.data.get("dialogue_id", "")
				if not dialogue_id.is_empty():
					EventBus.dialogue_ended.emit(dialogue_id)

			"effect":
				# Apply environment/weather changes instantly
				if step.data.has("weather"):
					EventBus.weather_changed.emit(step.data.get("weather", "clear"))
				if step.data.has("time"):
					EventBus.time_period_changed.emit(step.data.get("time", "day"))

			"environment":
				_step_environment(step.data)

			"audio":
				_step_audio(step.data)

			"spawn":
				_step_spawn(step.data)

		_step_index += 1


# ---------------------------------------------------------------------------
# Data Loading
# ---------------------------------------------------------------------------

func _load_cinematic(cinematic_id: String) -> Dictionary:
	if _cache.has(cinematic_id):
		return _cache[cinematic_id]

	var path := "res://data/cinematics/%s.json" % cinematic_id
	if not FileAccess.file_exists(path):
		push_error("[Cinematic] File not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[Cinematic] Cannot open: %s" % path)
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[Cinematic] JSON parse error in: %s — %s" % [path, json.get_error_message()])
		return {}
	file.close()

	var data: Dictionary = json.data
	_cache[cinematic_id] = data
	return data


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

## Await a given number of real-time seconds, respecting skip.
func _wait_seconds(seconds: float) -> void:
	if _skipping:
		return
	var timer := get_tree().create_timer(seconds, true, false, true)
	await timer.timeout
