## Displays ambient NPC dialogue as a subtitle bar at the bottom of the screen.
## Listens to EventBus.ambient_line_started/finished signals and shows
## speaker tag + text with a typewriter-style reveal and fade out.
## This is separate from the full dialogue UI — it is lightweight,
## non-blocking, and does not pause gameplay.
class_name AmbientSubtitleUI
extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/VBox/SpeakerLabel
@onready var text_label: RichTextLabel = $Panel/VBox/TextLabel

const FADE_IN_DURATION: float = 0.25
const FADE_OUT_DURATION: float = 0.5
const TEXT_SPEED: float = 40.0 # Characters per second

var _text_tween: Tween = null
var _fade_tween: Tween = null
var _hide_timer: float = 0.0
var _is_showing: bool = false


func _ready() -> void:
	panel.modulate.a = 0.0
	panel.visible = false

	EventBus.ambient_line_started.connect(_on_ambient_line_started)
	EventBus.ambient_line_finished.connect(_on_ambient_line_finished)
	EventBus.ambient_exchange_finished.connect(_on_ambient_exchange_finished)


func _process(delta: float) -> void:
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_fade_out()


func _on_ambient_line_started(_group_id: String, line_data: Dictionary) -> void:
	var speaker_tag: String = line_data.get("speaker_tag", "")
	var text: String = line_data.get("text", "")

	if text.is_empty():
		return

	# Set speaker name
	if speaker_tag.is_empty():
		speaker_label.visible = false
	else:
		speaker_label.text = speaker_tag
		speaker_label.visible = true

	# Set up text with typewriter reveal
	text_label.text = text
	text_label.visible_characters = 0

	# Show panel with fade in
	_show_panel()

	# Typewriter effect
	if _text_tween:
		_text_tween.kill()
	_text_tween = create_tween()
	var duration := float(text.length()) / TEXT_SPEED
	_text_tween.tween_property(text_label, "visible_characters", text.length(), duration)

	# Set hide timer for when exchange system sends next line
	# (AmbientDialogue manages timing between lines; we just display what arrives)
	_hide_timer = AmbientDialogue.LINE_DISPLAY_DURATION


func _on_ambient_line_finished(_group_id: String) -> void:
	_hide_timer = 0.0
	_fade_out()


func _on_ambient_exchange_finished(_group_id: String) -> void:
	# Give a brief moment for the last line to linger, then fade
	_hide_timer = 0.5


func _show_panel() -> void:
	if _fade_tween:
		_fade_tween.kill()

	panel.visible = true
	_is_showing = true

	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 1.0, FADE_IN_DURATION)


func _fade_out() -> void:
	if not _is_showing:
		return

	if _fade_tween:
		_fade_tween.kill()

	_is_showing = false
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 0.0, FADE_OUT_DURATION)
	_fade_tween.tween_callback(func(): panel.visible = false)
