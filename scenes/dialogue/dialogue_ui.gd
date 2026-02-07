## Dialogue UI controller. Presents dialogue lines, character portraits,
## and player choices in a visual novel-inspired interface.
## Per GDD reference: Persona 5 UI + VA-11 HALL-A intimacy.
extends CanvasLayer

@onready var dialogue_panel: Panel = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/SpeakerName
@onready var text_label: RichTextLabel = $DialoguePanel/DialogueText
@onready var portrait_rect: TextureRect = $DialoguePanel/Portrait
@onready var choice_container: VBoxContainer = $DialoguePanel/ChoiceContainer
@onready var continue_indicator: Label = $DialoguePanel/ContinueIndicator

var _dialogue_system: DialogueSystem = null
var _text_tween: Tween = null
var _text_revealing: bool = false
var _full_text: String = ""

const TEXT_SPEED := 30.0 # Characters per second


func _ready() -> void:
	visible = false
	continue_indicator.visible = false
	choice_container.visible = false

	# Connect to story manager's dialogue system
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)


func setup(dialogue_sys: DialogueSystem) -> void:
	_dialogue_system = dialogue_sys
	_dialogue_system.dialogue_line_displayed.connect(_on_line_displayed)
	_dialogue_system.choices_displayed.connect(_on_choices_displayed)
	_dialogue_system.dialogue_completed.connect(_on_completed)


func _on_dialogue_started(_id: String) -> void:
	visible = true
	dialogue_panel.visible = true
	choice_container.visible = false


func _on_dialogue_ended(_id: String) -> void:
	visible = false


func _on_line_displayed(speaker: String, text: String, portrait: String) -> void:
	choice_container.visible = false
	continue_indicator.visible = false

	# Speaker name
	if speaker.is_empty():
		speaker_label.text = ""
		speaker_label.visible = false
	else:
		speaker_label.text = speaker
		speaker_label.visible = true

	# Portrait
	if portrait.is_empty():
		portrait_rect.visible = false
	else:
		portrait_rect.visible = true
		var tex_path := "res://assets/ui/portraits/%s.png" % portrait
		if ResourceLoader.exists(tex_path):
			portrait_rect.texture = load(tex_path)

	# Text reveal (typewriter effect)
	_full_text = text
	text_label.text = ""
	text_label.visible_characters = 0
	text_label.text = text
	_text_revealing = true

	if _text_tween:
		_text_tween.kill()
	_text_tween = create_tween()
	var duration := float(text.length()) / TEXT_SPEED
	_text_tween.tween_property(text_label, "visible_characters", text.length(), duration)
	_text_tween.tween_callback(_on_text_revealed)


func _on_text_revealed() -> void:
	_text_revealing = false
	continue_indicator.visible = true


func _on_choices_displayed(choices: Array) -> void:
	continue_indicator.visible = false
	choice_container.visible = true

	# Clear old choice buttons
	for child in choice_container.get_children():
		child.queue_free()

	# Create choice buttons
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = choice.get("text", "...")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := i
		btn.pressed.connect(func(): _select_choice(idx))
		choice_container.add_child(btn)

	# Focus first choice
	await get_tree().process_frame
	if choice_container.get_child_count() > 0:
		choice_container.get_child(0).grab_focus()


func _select_choice(index: int) -> void:
	choice_container.visible = false
	if _dialogue_system:
		_dialogue_system.select_choice(index)


func _on_completed(_id: String) -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _dialogue_system:
		return

	if event.is_action_pressed("ui_select_choice") or event.is_action_pressed("interact"):
		if _text_revealing:
			# Skip to full text
			if _text_tween:
				_text_tween.kill()
			text_label.visible_characters = -1
			_on_text_revealed()
		elif continue_indicator.visible:
			_dialogue_system.advance()
