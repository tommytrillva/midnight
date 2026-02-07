## Global screen transition manager. Provides multiple retro-styled transitions
## (fade, wipe, pixelate, scanline) for seamless scene swaps.
## Add as an autoload or instantiate in main scene at CanvasLayer 200.
class_name ScreenTransition
extends CanvasLayer

## Emitted at the midpoint of a full transition (caller should swap scenes here).
signal transition_midpoint
## Emitted when the entire transition sequence is finished.
signal transition_finished

enum TransitionType { FADE_BLACK, FADE_WHITE, WIPE_HORIZONTAL, PIXELATE, SCANLINE_SWEEP }

# --- Shader Resources ---
var _pixelate_shader: Shader = preload("res://assets/shaders/transition_pixelate.gdshader")
var _wipe_shader: Shader = preload("res://assets/shaders/transition_wipe.gdshader")
var _scanline_shader: Shader = preload("res://assets/shaders/transition_scanline.gdshader")

# --- Internal Nodes ---
var _color_rect: ColorRect = null
var _tween: Tween = null

# --- State ---
var _is_transitioning: bool = false


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "ScreenTransition"

	# Create full-screen ColorRect
	_color_rect = ColorRect.new()
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.visible = false
	_color_rect.color = Color(0, 0, 0, 0)
	add_child(_color_rect)

	print("[ScreenTransition] Initialized on layer 200.")


## Returns true while a transition is in progress.
func is_transitioning() -> bool:
	return _is_transitioning


# ---------------------------------------------------------------------------
# Public API — Full Transitions (in → midpoint signal → out)
# ---------------------------------------------------------------------------

## Full fade-to-black and back. Duration is total (half in, half out).
func fade_black(duration: float = 1.0) -> void:
	await _run_full_transition(TransitionType.FADE_BLACK, duration)


## Full flash-white and back. Good for "GO!" moments.
func fade_white(duration: float = 0.6) -> void:
	await _run_full_transition(TransitionType.FADE_WHITE, duration)


## Horizontal wipe with neon cyan edge, then wipe back.
func wipe_horizontal(duration: float = 1.0) -> void:
	await _run_full_transition(TransitionType.WIPE_HORIZONTAL, duration)


## PSX-style pixelation — blocks grow then shrink.
func pixelate(duration: float = 1.2) -> void:
	await _run_full_transition(TransitionType.PIXELATE, duration)


## CRT scanline sweep across the screen and back.
func scanline_sweep(duration: float = 1.0) -> void:
	await _run_full_transition(TransitionType.SCANLINE_SWEEP, duration)


# ---------------------------------------------------------------------------
# Public API — Half Transitions (for manual control)
# ---------------------------------------------------------------------------

## Transition in only (screen becomes obscured). Await this, do your swap, then call transition_out.
func transition_in(type: TransitionType, duration: float = 0.5) -> void:
	_kill_tween()
	_is_transitioning = true
	_setup_for_type(type)
	_color_rect.visible = true

	match type:
		TransitionType.FADE_BLACK:
			await _animate_fade_in(Color.BLACK, duration)
		TransitionType.FADE_WHITE:
			await _animate_fade_in(Color.WHITE, duration)
		TransitionType.WIPE_HORIZONTAL:
			await _animate_shader_in("progress", duration)
		TransitionType.PIXELATE:
			await _animate_shader_in("progress", duration, 0.0, 0.5)
		TransitionType.SCANLINE_SWEEP:
			await _animate_shader_in("progress", duration)


## Transition out (screen becomes visible again).
func transition_out(type: TransitionType, duration: float = 0.5) -> void:
	match type:
		TransitionType.FADE_BLACK:
			await _animate_fade_out(duration)
		TransitionType.FADE_WHITE:
			await _animate_fade_out(duration)
		TransitionType.WIPE_HORIZONTAL:
			await _animate_shader_out("progress", duration)
		TransitionType.PIXELATE:
			await _animate_shader_out("progress", duration, 0.5, 1.0)
		TransitionType.SCANLINE_SWEEP:
			await _animate_shader_out("progress", duration)

	_color_rect.visible = false
	_is_transitioning = false
	transition_finished.emit()


# ---------------------------------------------------------------------------
# Internal — Full Transition Runner
# ---------------------------------------------------------------------------

func _run_full_transition(type: TransitionType, duration: float) -> void:
	var half := duration * 0.5
	await transition_in(type, half)
	transition_midpoint.emit()
	# Brief pause at midpoint so caller's connected code can run
	await get_tree().create_timer(0.05).timeout
	await transition_out(type, half)


# ---------------------------------------------------------------------------
# Internal — Type Setup
# ---------------------------------------------------------------------------

func _setup_for_type(type: TransitionType) -> void:
	# Reset material
	_color_rect.material = null
	_color_rect.color = Color(0, 0, 0, 0)

	match type:
		TransitionType.FADE_BLACK:
			_color_rect.color = Color(0, 0, 0, 0)
		TransitionType.FADE_WHITE:
			_color_rect.color = Color(1, 1, 1, 0)
		TransitionType.WIPE_HORIZONTAL:
			var mat := ShaderMaterial.new()
			mat.shader = _wipe_shader
			mat.set_shader_parameter("progress", 0.0)
			mat.set_shader_parameter("direction", Vector2(1.0, 0.0))
			_color_rect.material = mat
			_color_rect.color = Color.WHITE
		TransitionType.PIXELATE:
			var mat := ShaderMaterial.new()
			mat.shader = _pixelate_shader
			mat.set_shader_parameter("progress", 0.0)
			mat.set_shader_parameter("max_pixel_size", 64.0)
			_color_rect.material = mat
			_color_rect.color = Color.WHITE
		TransitionType.SCANLINE_SWEEP:
			var mat := ShaderMaterial.new()
			mat.shader = _scanline_shader
			mat.set_shader_parameter("progress", 0.0)
			_color_rect.material = mat
			_color_rect.color = Color.WHITE


# ---------------------------------------------------------------------------
# Internal — Animation Helpers
# ---------------------------------------------------------------------------

func _animate_fade_in(color: Color, duration: float) -> void:
	_color_rect.color = Color(color.r, color.g, color.b, 0.0)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_color_rect, "color:a", 1.0, duration).set_ease(Tween.EASE_IN)
	await _tween.finished


func _animate_fade_out(duration: float) -> void:
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_color_rect, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)
	await _tween.finished


func _animate_shader_in(param: String, duration: float, from: float = 0.0, to: float = 1.0) -> void:
	var mat := _color_rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(param, from)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(func(val: float): mat.set_shader_parameter(param, val), from, to, duration)
	await _tween.finished


func _animate_shader_out(param: String, duration: float, from: float = 1.0, to: float = 0.0) -> void:
	var mat := _color_rect.material as ShaderMaterial
	if mat == null:
		# Fallback: just hide
		_color_rect.visible = false
		return
	mat.set_shader_parameter(param, from)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(func(val: float): mat.set_shader_parameter(param, val), from, to, duration)
	await _tween.finished


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
