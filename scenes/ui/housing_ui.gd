## Housing management UI screen. Shows current housing, available upgrades,
## rent information, and vehicle storage capacity. Apartment-listing style
## with dark panels and neon accents.
class_name HousingUI
extends CanvasLayer

# --- Node references (assigned in _ready from the .tscn tree) ---
@onready var background: ColorRect = %Background
@onready var current_name_label: Label = %CurrentNameLabel
@onready var current_desc_label: Label = %CurrentDescLabel
@onready var current_flavor_label: Label = %CurrentFlavorLabel
@onready var current_rent_label: Label = %CurrentRentLabel
@onready var current_rest_label: Label = %CurrentRestLabel
@onready var current_storage_label: Label = %CurrentStorageLabel
@onready var current_photo: ColorRect = %CurrentPhoto
@onready var options_container: VBoxContainer = %OptionsContainer
@onready var cash_label: Label = %CashLabel
@onready var expenses_label: Label = %ExpensesLabel
@onready var back_button: Button = %BackButton
@onready var confirm_dialog: PanelContainer = %ConfirmDialog
@onready var confirm_name_label: Label = %ConfirmNameLabel
@onready var confirm_rent_label: Label = %ConfirmRentLabel
@onready var confirm_yes_button: Button = %ConfirmYesButton
@onready var confirm_no_button: Button = %ConfirmNoButton

# --- State ---
var _pending_upgrade_level: int = -1

# Neon accent colors per housing level
const LEVEL_COLORS := {
	0: Color(0.4, 0.4, 0.5),   # CAR — dull grey
	1: Color(0.6, 0.45, 0.3),  # COUCH — warm amber
	2: Color(0.3, 0.5, 0.7),   # STUDIO — cool blue
	3: Color(0.8, 0.3, 0.6),   # APARTMENT — neon pink
	4: Color(1.0, 0.85, 0.2),  # PENTHOUSE — gold
	5: Color(0.3, 0.3, 0.35),  # BACK_TO_CAR — muted grey
	6: Color(0.35, 0.55, 0.45),# REBUILD_STUDIO — muted teal
}


func _ready() -> void:
	visible = false
	confirm_dialog.visible = false

	back_button.pressed.connect(_on_back_pressed)
	confirm_yes_button.pressed.connect(_on_confirm_yes)
	confirm_no_button.pressed.connect(_on_confirm_no)

	EventBus.housing_screen_requested.connect(_show)
	EventBus.housing_upgraded.connect(_on_housing_changed)
	EventBus.housing_downgraded.connect(_on_housing_changed)
	EventBus.cash_changed.connect(_on_cash_changed)

	print("[Housing] UI initialized.")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_hide()
		get_viewport().set_input_as_handled()


# =============================================================================
# SHOW / HIDE
# =============================================================================

func _show() -> void:
	_refresh()
	visible = true
	confirm_dialog.visible = false
	_pending_upgrade_level = -1


func _hide() -> void:
	visible = false


# =============================================================================
# REFRESH
# =============================================================================

func _refresh() -> void:
	_refresh_current_housing()
	_refresh_options()
	_refresh_bottom_bar()


func _refresh_current_housing() -> void:
	var housing: Dictionary = GameManager.housing.get_current_housing()
	var level: int = housing.get("level", 0)

	current_name_label.text = housing.get("name", "Unknown")
	current_desc_label.text = housing.get("description", "")
	current_flavor_label.text = "\"%s\"" % housing.get("flavor", "")

	var rent: int = housing.get("monthly_rent", 0)
	if rent > 0:
		current_rent_label.text = "RENT: $%s / month" % _format_number(rent)
	else:
		current_rent_label.text = "RENT: FREE"

	var rest: float = housing.get("rest_bonus", 0.0)
	if rest > 0.0:
		current_rest_label.text = "REST BONUS: +%d%%" % int(rest * 100)
	else:
		current_rest_label.text = "REST BONUS: None"

	var storage: int = housing.get("vehicle_storage", 0)
	if storage > 0:
		current_storage_label.text = "GARAGE SLOTS: +%d" % storage
	else:
		current_storage_label.text = "GARAGE SLOTS: None"

	# Tint the photo placeholder with the level's accent color
	current_photo.color = LEVEL_COLORS.get(level, Color(0.3, 0.3, 0.3))


func _refresh_options() -> void:
	# Clear previous option cards
	for child in options_container.get_children():
		child.queue_free()

	var upgrades: Array = GameManager.housing.get_available_upgrades()

	if upgrades.is_empty():
		var no_options := Label.new()
		no_options.text = "No upgrades available right now."
		no_options.add_theme_font_size_override("font_size", 13)
		no_options.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		no_options.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		options_container.add_child(no_options)
		return

	for upgrade in upgrades:
		var card := _create_option_card(upgrade)
		options_container.add_child(card)


func _refresh_bottom_bar() -> void:
	var cash: int = GameManager.economy.cash
	cash_label.text = "CASH: $%s" % _format_number(cash)

	var rent: int = GameManager.housing.get_monthly_rent()
	if rent > 0:
		expenses_label.text = "MONTHLY EXPENSES: $%s" % _format_number(rent)
	else:
		expenses_label.text = "MONTHLY EXPENSES: $0"


# =============================================================================
# OPTION CARDS
# =============================================================================

func _create_option_card(data: Dictionary) -> PanelContainer:
	var level: int = data.get("level", 0)
	var accent: Color = LEVEL_COLORS.get(level, Color(0.4, 0.4, 0.5))

	# Card container
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = accent * 0.6
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# Name
	var name_label := Label.new()
	name_label.text = data.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", accent)
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.text = data.get("description", "")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(desc_label)

	# Stats row
	var stats_hbox := HBoxContainer.new()
	stats_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(stats_hbox)

	var rent: int = data.get("monthly_rent", 0)
	var rent_label := Label.new()
	rent_label.text = "Rent: $%s/mo" % _format_number(rent) if rent > 0 else "Rent: FREE"
	rent_label.add_theme_font_size_override("font_size", 11)
	rent_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	stats_hbox.add_child(rent_label)

	var rest: float = data.get("rest_bonus", 0.0)
	var rest_label := Label.new()
	rest_label.text = "Rest: +%d%%" % int(rest * 100) if rest > 0 else "Rest: None"
	rest_label.add_theme_font_size_override("font_size", 11)
	rest_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	stats_hbox.add_child(rest_label)

	var storage: int = data.get("vehicle_storage", 0)
	var storage_label := Label.new()
	storage_label.text = "Garage: +%d" % storage if storage > 0 else "Garage: None"
	storage_label.add_theme_font_size_override("font_size", 11)
	storage_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	stats_hbox.add_child(storage_label)

	# Requirements
	var req_label := Label.new()
	req_label.text = _format_requirements(data)
	req_label.add_theme_font_size_override("font_size", 10)
	req_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vbox.add_child(req_label)

	# Upgrade button
	var button := Button.new()
	button.text = "MOVE IN"
	button.custom_minimum_size = Vector2(0, 34)
	button.pressed.connect(_on_upgrade_pressed.bind(level))
	vbox.add_child(button)

	return card


func _format_requirements(data: Dictionary) -> String:
	var unlock = data.get("unlock", "default")
	if unlock is String:
		return ""
	if not unlock is Dictionary:
		return ""

	var parts: Array[String] = []
	if unlock.has("cash_min"):
		parts.append("Cash: $%s+" % _format_number(unlock["cash_min"]))
	if unlock.has("rep_tier"):
		parts.append("Rep: %s" % unlock["rep_tier"])
	if unlock.has("flag"):
		parts.append("Story: %s" % unlock["flag"].replace("_", " ").capitalize())

	if parts.is_empty():
		return ""
	return "Requires: %s" % " | ".join(parts)


# =============================================================================
# CONFIRM DIALOG
# =============================================================================

func _on_upgrade_pressed(level: int) -> void:
	_pending_upgrade_level = level
	var data: Dictionary = GameManager.housing.get_housing_at_level(level)
	confirm_name_label.text = "Move to %s?" % data.get("name", "Unknown")
	var rent: int = data.get("monthly_rent", 0)
	if rent > 0:
		confirm_rent_label.text = "Monthly rent: $%s" % _format_number(rent)
	else:
		confirm_rent_label.text = "No rent."
	confirm_dialog.visible = true


func _on_confirm_yes() -> void:
	if _pending_upgrade_level >= 0:
		var success: bool = GameManager.housing.upgrade_housing(_pending_upgrade_level)
		if not success:
			EventBus.hud_message.emit("Cannot move there right now.", 3.0)
	confirm_dialog.visible = false
	_pending_upgrade_level = -1
	_refresh()


func _on_confirm_no() -> void:
	confirm_dialog.visible = false
	_pending_upgrade_level = -1


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_housing_changed(_old_level: int, _new_level: int, _data: Dictionary) -> void:
	if visible:
		_refresh()


func _on_cash_changed(_old: int, _new: int) -> void:
	if visible:
		_refresh_bottom_bar()


func _on_back_pressed() -> void:
	_hide()


# =============================================================================
# HELPERS
# =============================================================================

func _format_number(value: int) -> String:
	## Formats a number with comma separators: 10000 -> "10,000"
	var s := str(value)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
