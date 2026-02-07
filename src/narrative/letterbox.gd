## Cinematic letterbox bars (top and bottom black bars).
## Animates in/out to frame cutscenes in a widescreen aspect ratio.
## Sits on CanvasLayer 150 — above HUD, below ScreenTransition (200).
class_name Letterbox
extends CanvasLayer

## Bar height as a fraction of viewport height. 2.35:1 ~= 0.12 per bar.
const CINEMATIC_BAR_RATIO: float = 0.12
## 16:9 bar ratio — much thinner, used for minor framing.
const STANDARD_BAR_RATIO: float = 0.0

var _top_bar: ColorRect = null
var _bottom_bar: ColorRect = null
var _tween: Tween = null
var _bar_ratio: float = CINEMATIC_BAR_RATIO
var _visible: bool = false


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "Letterbox"

	# Top bar — anchored to top, starts off-screen (negative Y)
	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.anchor_left = 0.0
	_top_bar.anchor_right = 1.0
	_top_bar.anchor_top = 0.0
	_top_bar.anchor_bottom = 0.0
	_top_bar.offset_left = 0.0
	_top_bar.offset_right = 0.0
	_top_bar.offset_top = -200.0
	_top_bar.offset_bottom = 0.0
	add_child(_top_bar)

	# Bottom bar — anchored to bottom, starts off-screen (past bottom edge)
	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_bar.anchor_left = 0.0
	_bottom_bar.anchor_right = 1.0
	_bottom_bar.anchor_top = 1.0
	_bottom_bar.anchor_bottom = 1.0
	_bottom_bar.offset_left = 0.0
	_bottom_bar.offset_right = 0.0
	_bottom_bar.offset_top = 0.0
	_bottom_bar.offset_bottom = 200.0
	add_child(_bottom_bar)

	print("[Cinematic] Letterbox initialized on layer 150.")


## Show the letterbox bars, animating them in over duration.
## aspect can be "cinematic" (2.35:1) or "standard" (16:9).
func show_bars(duration: float = 0.5, aspect: String = "cinematic") -> void:
	if _visible:
		return

	_kill_tween()
	_visible = true

	match aspect:
		"cinematic":
			_bar_ratio = CINEMATIC_BAR_RATIO
		"standard":
			_bar_ratio = STANDARD_BAR_RATIO
		_:
			_bar_ratio = CINEMATIC_BAR_RATIO

	var viewport_height := float(get_viewport().get_visible_rect().size.y)
	var bar_height := viewport_height * _bar_ratio

	_tween = _top_bar.create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)

	# Top bar: slide down from off-screen to 0
	_tween.tween_property(_top_bar, "offset_top", 0.0, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_top_bar, "offset_bottom", bar_height, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Bottom bar: slide up from off-screen
	_tween.tween_property(_bottom_bar, "offset_top", -bar_height, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_bottom_bar, "offset_bottom", 0.0, duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	await _tween.finished
	EventBus.letterbox_shown.emit()
	print("[Cinematic] Letterbox shown (aspect: %s, bar_height: %.0f)." % [aspect, bar_height])


## Hide the letterbox bars, animating them out over duration.
func hide_bars(duration: float = 0.5) -> void:
	if not _visible:
		return

	_kill_tween()

	_tween = _top_bar.create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)

	# Top bar: slide back up off-screen
	_tween.tween_property(_top_bar, "offset_top", -200.0, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_top_bar, "offset_bottom", 0.0, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Bottom bar: slide back down off-screen
	_tween.tween_property(_bottom_bar, "offset_top", 0.0, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_bottom_bar, "offset_bottom", 200.0, duration) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	await _tween.finished
	_visible = false
	EventBus.letterbox_hidden.emit()
	print("[Cinematic] Letterbox hidden.")


## Instantly hide bars without animation.
func hide_immediate() -> void:
	_kill_tween()
	_top_bar.offset_top = -200.0
	_top_bar.offset_bottom = 0.0
	_bottom_bar.offset_top = 0.0
	_bottom_bar.offset_bottom = 200.0
	_visible = false


## Instantly show bars without animation.
func show_immediate(aspect: String = "cinematic") -> void:
	_kill_tween()
	match aspect:
		"cinematic":
			_bar_ratio = CINEMATIC_BAR_RATIO
		_:
			_bar_ratio = STANDARD_BAR_RATIO

	var viewport_height := float(get_viewport().get_visible_rect().size.y)
	var bar_height := viewport_height * _bar_ratio

	_top_bar.offset_top = 0.0
	_top_bar.offset_bottom = bar_height
	_bottom_bar.offset_top = -bar_height
	_bottom_bar.offset_bottom = 0.0
	_visible = true


## Returns true if the letterbox bars are currently visible.
func is_showing() -> bool:
	return _visible


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
