## Loading screen displayed during scene transitions and async resource loads.
## Shows game title, progress bar, random tips, and a spinning gear icon.
## Works with ResourceLoader threaded loading for smooth async loads.
class_name LoadingScreen
extends CanvasLayer

## Emitted when loading is complete and the screen has faded out.
signal loading_finished(resource: Resource)

# --- Node References (set by _ready from the scene tree) ---
@onready var background: ColorRect = $Background
@onready var title_label: Label = $Content/Title
@onready var progress_bar: ProgressBar = $Content/ProgressBar
@onready var tip_label: Label = $Content/TipLabel
@onready var spinner: ColorRect = $Spinner

# --- Configuration ---
const MINIMUM_DISPLAY_TIME: float = 1.5
const FADE_DURATION: float = 0.4

# --- State ---
var _is_loading: bool = false
var _load_path: String = ""
var _elapsed: float = 0.0
var _load_progress: Array[float] = [0.0]
var _loaded_resource: Resource = null
var _fade_tween: Tween = null

# --- Loading Tips Pool ---
var _tips: Array[String] = [
	"Downshift before a turn for better control.",
	"Your reputation opens doors... and closes some.",
	"Torres Garage has the best prices in Downtown.",
	"Night races pay more but attract police.",
	"Drifting earns style points and bonus REP.",
	"Keep Maya on your side. She knows everyone.",
	"Nitro is best saved for the final stretch.",
	"Upgrade your suspension before chasing top speed.",
	"The harbor district hides secrets after midnight.",
	"Every choice you make shapes Nova Pacifica.",
	"Diesel's parts are expensive, but they never fail.",
	"Street racing is illegal. Police heat is real.",
	"The mountain pass separates amateurs from legends.",
	"Pink slip races: high risk, ultimate reward.",
	"Your car tells your story. Make it count.",
	"Engine swaps change everything about a build.",
	"Trust is earned slowly and lost in an instant.",
	"The underground scene runs on respect, not money.",
]


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_set_initial_alpha(0.0)
	print("[LoadingScreen] Ready.")


func _process(delta: float) -> void:
	if not _is_loading:
		return

	_elapsed += delta

	# Spin the gear icon
	if spinner:
		spinner.rotation += delta * 3.0

	# Poll threaded load status
	if not _load_path.is_empty():
		var status := ResourceLoader.load_threaded_get_status(_load_path, _load_progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if progress_bar:
					progress_bar.value = _load_progress[0] * 100.0
			ResourceLoader.THREAD_LOAD_LOADED:
				_loaded_resource = ResourceLoader.load_threaded_get(_load_path)
				progress_bar.value = 100.0
				_finish_loading()
			ResourceLoader.THREAD_LOAD_FAILED:
				push_error("[LoadingScreen] Failed to load: %s" % _load_path)
				_finish_loading()
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("[LoadingScreen] Invalid resource: %s" % _load_path)
				_finish_loading()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Start loading a scene/resource asynchronously with the loading screen visible.
func load_resource(path: String) -> void:
	_load_path = path
	_loaded_resource = null
	_elapsed = 0.0
	_is_loading = true
	_load_progress[0] = 0.0

	# Pick a random tip
	if tip_label and _tips.size() > 0:
		tip_label.text = _tips[randi() % _tips.size()]

	# Reset progress bar
	if progress_bar:
		progress_bar.value = 0.0

	# Start threaded load
	ResourceLoader.load_threaded_request(path)

	# Fade in
	visible = true
	await _fade_in()

	print("[LoadingScreen] Loading: %s" % path)


## Show the loading screen for a manual operation (no ResourceLoader).
## Call finish_manual() when done.
func show_manual(tip_text: String = "") -> void:
	_load_path = ""
	_loaded_resource = null
	_elapsed = 0.0
	_is_loading = true
	_load_progress[0] = 0.0

	if tip_label:
		tip_label.text = tip_text if not tip_text.is_empty() else _tips[randi() % _tips.size()]
	if progress_bar:
		progress_bar.value = 0.0

	visible = true
	await _fade_in()

	print("[LoadingScreen] Manual loading screen shown.")


## Update the progress bar manually (0.0 to 1.0).
func set_progress(value: float) -> void:
	if progress_bar:
		progress_bar.value = clampf(value, 0.0, 1.0) * 100.0


## Finish a manual loading session.
func finish_manual() -> void:
	if progress_bar:
		progress_bar.value = 100.0
	_finish_loading()


## Returns the loaded resource after loading_finished is emitted.
func get_loaded_resource() -> Resource:
	return _loaded_resource


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _finish_loading() -> void:
	if not _is_loading:
		return

	# Enforce minimum display time
	var remaining := MINIMUM_DISPLAY_TIME - _elapsed
	if remaining > 0.0:
		# Animate progress bar to 100% over remaining time
		if progress_bar and progress_bar.value < 100.0:
			var bar_tween := create_tween()
			bar_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			bar_tween.tween_property(progress_bar, "value", 100.0, remaining * 0.8)
		await get_tree().create_timer(remaining).timeout

	_is_loading = false

	# Fade out
	await _fade_out()
	visible = false
	_set_initial_alpha(0.0)

	loading_finished.emit(_loaded_resource)
	print("[LoadingScreen] Loading complete.")


func _fade_in() -> void:
	_kill_fade()
	_set_initial_alpha(0.0)
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_method(_set_initial_alpha, 0.0, 1.0, FADE_DURATION)
	await _fade_tween.finished


func _fade_out() -> void:
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_method(_set_initial_alpha, 1.0, 0.0, FADE_DURATION)
	await _fade_tween.finished


func _set_initial_alpha(alpha: float) -> void:
	if background:
		background.modulate.a = alpha
	var content := get_node_or_null("Content")
	if content:
		content.modulate.a = alpha
	if spinner:
		spinner.modulate.a = alpha


func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
