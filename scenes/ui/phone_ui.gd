## Full phone interface with contact list, conversation view, chat bubbles,
## reply buttons, and notification badge. Styled as an in-game smartphone.
## Open/close with the "phone" input action.
class_name PhoneUI
extends CanvasLayer

# ---------------------------------------------------------------------------
# Character Colors — used for chat bubbles and contact highlights
# ---------------------------------------------------------------------------

const CHAR_COLORS := {
	"maya": Color(1.0, 0.6, 0.2),       # warm orange
	"nikko": Color(1.0, 0.2, 0.2),      # sharp red
	"diesel": Color(0.6, 0.6, 0.6),     # muted gray
	"jade": Color(0.3, 0.5, 1.0),       # corporate blue
	"echo": Color(0.6, 0.2, 0.9),       # void purple
	"zero": Color(0.6, 0.2, 0.9),       # void purple
	"unknown": Color(0.4, 0.9, 0.4),    # eerie green
	"player": Color(0.0, 0.85, 0.85),   # cyan
}

const PLAYER_BUBBLE_COLOR := Color(0.0, 0.85, 0.85, 0.15)
const NPC_BUBBLE_COLOR := Color(0.15, 0.15, 0.18, 0.9)
const PHONE_BG_COLOR := Color(0.08, 0.08, 0.1, 0.95)
const HEADER_BG_COLOR := Color(0.12, 0.12, 0.15, 1.0)
const CONTACT_HOVER_COLOR := Color(0.18, 0.18, 0.22, 1.0)
const REPLY_BUTTON_COLOR := Color(0.0, 0.65, 0.65, 0.25)

# ---------------------------------------------------------------------------
# Node References
# ---------------------------------------------------------------------------

var _phone_panel: PanelContainer
var _contact_list: VBoxContainer
var _conversation_panel: PanelContainer
var _conversation_scroll: ScrollContainer
var _conversation_vbox: VBoxContainer
var _reply_container: VBoxContainer
var _header_label: Label
var _back_button: Button
var _header_bar: HBoxContainer
var _notification_badge: Label
var _typing_label: Label
var _contact_scroll: ScrollContainer

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _is_open: bool = false
var _current_contact: String = ""
var _typing_timer: float = 0.0
var _typing_visible: bool = false
var _pending_typing_sender: String = ""
var _scroll_to_bottom_next_frame: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 100
	_build_ui()
	_connect_signals()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[Phone] PhoneUI ready.")


func _process(delta: float) -> void:
	# Typing indicator animation
	if _typing_timer > 0.0:
		_typing_timer -= delta
		if _typing_timer <= 0.0:
			_typing_label.visible = false
			_typing_visible = false

	# Deferred scroll to bottom
	if _scroll_to_bottom_next_frame:
		_scroll_to_bottom_next_frame = false
		await get_tree().process_frame
		_conversation_scroll.scroll_vertical = int(_conversation_scroll.get_v_scroll_bar().max_value)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		if _is_open:
			close_phone()
		else:
			open_phone()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _is_open:
		if _current_contact != "":
			_show_contact_list()
		else:
			close_phone()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# Open / Close
# ---------------------------------------------------------------------------

func open_phone() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_show_contact_list()
	_update_badge()
	EventBus.phone_opened.emit()
	print("[Phone] Phone opened.")


func close_phone() -> void:
	if not _is_open:
		return
	_is_open = false
	_current_contact = ""
	visible = false
	EventBus.phone_closed.emit()
	print("[Phone] Phone closed.")

# ---------------------------------------------------------------------------
# Contact List View
# ---------------------------------------------------------------------------

func _show_contact_list() -> void:
	_current_contact = ""
	_header_label.text = "MESSAGES"
	_back_button.visible = false
	_conversation_panel.visible = false
	_contact_scroll.visible = true
	_reply_container.visible = false
	_typing_label.visible = false

	_refresh_contact_list()


func _refresh_contact_list() -> void:
	# Clear existing children
	for child in _contact_list.get_children():
		child.queue_free()

	var phone: PhoneSystem = GameManager.phone
	if not phone:
		return

	var contacts: Array = phone.get_contacts_with_messages()
	if contacts.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No messages yet."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		_contact_list.add_child(empty_label)
		return

	for sender in contacts:
		var btn := _create_contact_button(sender)
		_contact_list.add_child(btn)


func _create_contact_button(sender: String) -> Button:
	var phone: PhoneSystem = GameManager.phone
	var display_name: String = PhoneSystem.CHARACTER_NAMES.get(sender, sender.capitalize())
	var unread: int = phone.get_unread_count_for(sender)
	var convo: Array = phone.get_conversation(sender)
	var last_msg_text: String = ""
	if convo.size() > 0:
		last_msg_text = convo.back().text
		if last_msg_text.length() > 40:
			last_msg_text = last_msg_text.substr(0, 40) + "..."

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 60)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var label_text := display_name
	if unread > 0:
		label_text += "  [%d]" % unread
	if not last_msg_text.is_empty():
		label_text += "\n  %s" % last_msg_text

	btn.text = label_text

	# Style
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.12, 0.12, 0.15, 0.8)
	stylebox.border_color = CHAR_COLORS.get(sender, Color.WHITE).darkened(0.5)
	stylebox.border_width_bottom = 1
	stylebox.content_margin_left = 12
	stylebox.content_margin_right = 12
	stylebox.content_margin_top = 8
	stylebox.content_margin_bottom = 8
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", stylebox)

	var hover_style := stylebox.duplicate()
	hover_style.bg_color = CONTACT_HOVER_COLOR
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)

	var font_color := Color.WHITE if unread > 0 else Color(0.7, 0.7, 0.7)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_font_size_override("font_size", 14)

	btn.pressed.connect(_on_contact_pressed.bind(sender))
	return btn

# ---------------------------------------------------------------------------
# Conversation View
# ---------------------------------------------------------------------------

func _show_conversation(sender: String) -> void:
	_current_contact = sender
	var display_name: String = PhoneSystem.CHARACTER_NAMES.get(sender, sender.capitalize())
	_header_label.text = display_name
	_back_button.visible = true
	_contact_scroll.visible = false
	_conversation_panel.visible = true
	_reply_container.visible = false
	_typing_label.visible = false

	_refresh_conversation()

	# Mark messages as read
	var phone: PhoneSystem = GameManager.phone
	if phone:
		phone.mark_conversation_read(sender)
	_update_badge()


func _refresh_conversation() -> void:
	# Clear existing bubbles
	for child in _conversation_vbox.get_children():
		child.queue_free()

	var phone: PhoneSystem = GameManager.phone
	if not phone:
		return

	var convo: Array = phone.get_conversation(_current_contact)
	if convo.is_empty():
		return

	var last_npc_msg_id: String = ""
	for msg in convo:
		var bubble := _create_chat_bubble(msg)
		_conversation_vbox.add_child(bubble)
		if msg.sender != "player":
			last_npc_msg_id = msg.id

	# Show reply options for the last NPC message if it has pending replies
	if not last_npc_msg_id.is_empty() and phone.has_pending_reply(last_npc_msg_id):
		_show_reply_options(last_npc_msg_id)

	_scroll_to_bottom_next_frame = true


func _create_chat_bubble(msg: Dictionary) -> PanelContainer:
	var is_player: bool = msg.sender == "player"
	var container := PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	if is_player:
		style.bg_color = PLAYER_BUBBLE_COLOR
		style.border_color = CHAR_COLORS["player"].darkened(0.3)
		style.border_width_left = 2
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 2
	else:
		style.bg_color = NPC_BUBBLE_COLOR
		var char_color: Color = CHAR_COLORS.get(msg.sender, Color.WHITE)
		style.border_color = char_color.darkened(0.4)
		style.border_width_left = 2
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 8

	container.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	container.add_child(vbox)

	# Message text
	var text_label := Label.new()
	text_label.text = msg.text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 13)

	if is_player:
		text_label.add_theme_color_override("font_color", CHAR_COLORS["player"])
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		var char_color: Color = CHAR_COLORS.get(msg.sender, Color.WHITE)
		text_label.add_theme_color_override("font_color", char_color.lightened(0.3))

	vbox.add_child(text_label)

	# Outer margin container for alignment
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10 if is_player else 0)
	margin.add_theme_constant_override("margin_right", 0 if is_player else 10)
	# We wrap the PanelContainer in a MarginContainer, but since we're adding
	# directly to the VBox, we'll use the container's size flags instead.
	if is_player:
		container.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	return container

# ---------------------------------------------------------------------------
# Reply Options
# ---------------------------------------------------------------------------

func _show_reply_options(message_id: String) -> void:
	_clear_reply_buttons()

	var phone: PhoneSystem = GameManager.phone
	if not phone or not phone.messages.has(message_id):
		return

	var msg: Dictionary = phone.messages[message_id]
	if msg.reply_options.is_empty() or msg.replied:
		_reply_container.visible = false
		return

	_reply_container.visible = true

	var divider := Label.new()
	divider.text = "-- Reply --"
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	divider.add_theme_font_size_override("font_size", 11)
	_reply_container.add_child(divider)

	for i in range(msg.reply_options.size()):
		var option: Dictionary = msg.reply_options[i]
		var btn := Button.new()
		btn.text = option.get("text", "...")
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_size_override("font_size", 13)

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = REPLY_BUTTON_COLOR
		btn_style.border_color = CHAR_COLORS["player"].darkened(0.3)
		btn_style.border_width_bottom = 1
		btn_style.corner_radius_top_left = 6
		btn_style.corner_radius_top_right = 6
		btn_style.corner_radius_bottom_left = 6
		btn_style.corner_radius_bottom_right = 6
		btn_style.content_margin_left = 10
		btn_style.content_margin_right = 10
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover := btn_style.duplicate()
		hover.bg_color = Color(0.0, 0.65, 0.65, 0.4)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)

		btn.add_theme_color_override("font_color", CHAR_COLORS["player"])
		btn.pressed.connect(_on_reply_pressed.bind(message_id, i))
		_reply_container.add_child(btn)


func _clear_reply_buttons() -> void:
	for child in _reply_container.get_children():
		child.queue_free()
	_reply_container.visible = false

# ---------------------------------------------------------------------------
# Typing Indicator
# ---------------------------------------------------------------------------

func _show_typing_indicator(sender: String) -> void:
	if _current_contact == sender and _conversation_panel.visible:
		_typing_label.text = "%s is typing..." % PhoneSystem.CHARACTER_NAMES.get(sender, sender)
		_typing_label.visible = true
		_typing_timer = 2.0
		_typing_visible = true

# ---------------------------------------------------------------------------
# Notification Badge
# ---------------------------------------------------------------------------

func _update_badge() -> void:
	var phone: PhoneSystem = GameManager.phone
	if not phone:
		_notification_badge.visible = false
		return
	var count: int = phone.get_unread_count()
	if count > 0:
		_notification_badge.text = str(count)
		_notification_badge.visible = true
	else:
		_notification_badge.visible = false

# ---------------------------------------------------------------------------
# Signal Handlers
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	EventBus.message_received.connect(_on_message_received)
	EventBus.message_replied.connect(_on_message_replied)


func _on_message_received(sender: String, _message_id: String) -> void:
	_update_badge()

	# Show typing indicator then refresh if viewing this conversation
	if _is_open and _current_contact == sender:
		_show_typing_indicator(sender)
		# Short delay then refresh conversation
		await get_tree().create_timer(1.5).timeout
		_refresh_conversation()
	elif _is_open and _current_contact == "":
		# On contact list, refresh it
		_refresh_contact_list()


func _on_message_replied(_message_id: String, _reply_index: int) -> void:
	if _is_open and _current_contact != "":
		_clear_reply_buttons()
		_refresh_conversation()

# ---------------------------------------------------------------------------
# Button Callbacks
# ---------------------------------------------------------------------------

func _on_contact_pressed(sender: String) -> void:
	_show_conversation(sender)


func _on_reply_pressed(message_id: String, reply_index: int) -> void:
	var phone: PhoneSystem = GameManager.phone
	if phone:
		phone.reply(message_id, reply_index)


func _on_back_pressed() -> void:
	_show_contact_list()

# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Root phone panel
	_phone_panel = PanelContainer.new()
	_phone_panel.name = "PhonePanel"
	_phone_panel.anchor_left = 0.5
	_phone_panel.anchor_top = 0.5
	_phone_panel.anchor_right = 0.5
	_phone_panel.anchor_bottom = 0.5
	_phone_panel.offset_left = -200
	_phone_panel.offset_top = -280
	_phone_panel.offset_right = 200
	_phone_panel.offset_bottom = 280
	_phone_panel.custom_minimum_size = Vector2(400, 560)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PHONE_BG_COLOR
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.border_color = Color(0.25, 0.25, 0.3, 0.8)
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_phone_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_phone_panel)

	# Main VBox inside phone
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	_phone_panel.add_child(main_vbox)

	# --- Header Bar ---
	_header_bar = HBoxContainer.new()
	_header_bar.custom_minimum_size = Vector2(0, 36)
	_header_bar.add_theme_constant_override("separation", 8)

	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = HEADER_BG_COLOR
	header_style.corner_radius_top_left = 10
	header_style.corner_radius_top_right = 10
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header_style.content_margin_top = 4
	header_style.content_margin_bottom = 4
	header_panel.add_theme_stylebox_override("panel", header_style)
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(header_panel)
	header_panel.add_child(_header_bar)

	_back_button = Button.new()
	_back_button.text = "<"
	_back_button.custom_minimum_size = Vector2(32, 0)
	_back_button.add_theme_font_size_override("font_size", 16)
	_back_button.add_theme_color_override("font_color", Color(0.0, 0.85, 0.85))
	_back_button.flat = true
	_back_button.visible = false
	_back_button.pressed.connect(_on_back_pressed)
	_header_bar.add_child(_back_button)

	_header_label = Label.new()
	_header_label.text = "MESSAGES"
	_header_label.add_theme_font_size_override("font_size", 16)
	_header_label.add_theme_color_override("font_color", Color(0.0, 0.85, 0.85))
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_bar.add_child(_header_label)

	# Notification badge in header
	_notification_badge = Label.new()
	_notification_badge.text = "0"
	_notification_badge.add_theme_font_size_override("font_size", 12)
	_notification_badge.add_theme_color_override("font_color", Color.WHITE)
	_notification_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_badge.custom_minimum_size = Vector2(24, 24)
	_notification_badge.visible = false
	_header_bar.add_child(_notification_badge)

	# --- Contact List (left panel) ---
	_contact_scroll = ScrollContainer.new()
	_contact_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_contact_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_contact_scroll)

	_contact_list = VBoxContainer.new()
	_contact_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contact_list.add_theme_constant_override("separation", 4)
	_contact_scroll.add_child(_contact_list)

	# --- Conversation Panel ---
	_conversation_panel = PanelContainer.new()
	_conversation_panel.visible = false
	_conversation_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conversation_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var convo_style := StyleBoxFlat.new()
	convo_style.bg_color = Color(0.06, 0.06, 0.08, 0.9)
	convo_style.corner_radius_bottom_left = 10
	convo_style.corner_radius_bottom_right = 10
	convo_style.content_margin_left = 4
	convo_style.content_margin_right = 4
	convo_style.content_margin_top = 4
	convo_style.content_margin_bottom = 4
	_conversation_panel.add_theme_stylebox_override("panel", convo_style)
	main_vbox.add_child(_conversation_panel)

	var convo_vbox := VBoxContainer.new()
	convo_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	convo_vbox.add_theme_constant_override("separation", 4)
	_conversation_panel.add_child(convo_vbox)

	_conversation_scroll = ScrollContainer.new()
	_conversation_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_conversation_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	convo_vbox.add_child(_conversation_scroll)

	_conversation_vbox = VBoxContainer.new()
	_conversation_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conversation_vbox.add_theme_constant_override("separation", 6)
	_conversation_scroll.add_child(_conversation_vbox)

	# Typing indicator
	_typing_label = Label.new()
	_typing_label.text = "..."
	_typing_label.add_theme_font_size_override("font_size", 11)
	_typing_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_typing_label.visible = false
	convo_vbox.add_child(_typing_label)

	# Reply container
	_reply_container = VBoxContainer.new()
	_reply_container.visible = false
	_reply_container.add_theme_constant_override("separation", 4)
	convo_vbox.add_child(_reply_container)
