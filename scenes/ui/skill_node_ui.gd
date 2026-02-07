## Individual skill node widget for the skill tree UI.
## Represents one skill with locked/available/unlocked states.
## Tree-specific color theming and pulsing glow when available.
class_name SkillNodeUI
extends PanelContainer

signal skill_selected(tree_id: String, skill_data: Dictionary)

enum State { LOCKED, AVAILABLE, UNLOCKED }

# --- Skill Data ---
var tree_id: String = ""
var skill_data: Dictionary = {}
var tree_color: Color = Color.WHITE
var current_state: State = State.LOCKED

# --- Node References (built in code) ---
var _icon_rect: ColorRect = null
var _icon_label: Label = null
var _name_label: Label = null
var _level_label: Label = null
var _glow_panel: PanelContainer = null

# --- Glow animation ---
var _glow_time: float = 0.0
var _base_style: StyleBoxFlat = null
var _glow_style: StyleBoxFlat = null

# --- Abbreviation map ---
const TREE_ABBREVIATIONS := {
	"speed_demon": "SD",
	"ghost_line": "GL",
	"street_survivor": "SS",
	"technician": "TC",
}


func _ready() -> void:
	_build_ui()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func setup(p_tree_id: String, p_skill_data: Dictionary, p_tree_color: Color) -> void:
	tree_id = p_tree_id
	skill_data = p_skill_data
	tree_color = p_tree_color
	_update_display()


func set_state(new_state: State) -> void:
	current_state = new_state
	_update_display()


func _build_ui() -> void:
	custom_minimum_size = Vector2(160, 60)

	# Base style
	_base_style = StyleBoxFlat.new()
	_base_style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	_base_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	_base_style.set_border_width_all(1)
	_base_style.set_corner_radius_all(3)
	_base_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _base_style)

	# Main HBox: icon + text
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# Icon area
	var icon_container := Control.new()
	icon_container.custom_minimum_size = Vector2(40, 40)
	hbox.add_child(icon_container)

	_icon_rect = ColorRect.new()
	_icon_rect.custom_minimum_size = Vector2(40, 40)
	_icon_rect.size = Vector2(40, 40)
	_icon_rect.color = Color.WHITE
	icon_container.add_child(_icon_rect)

	_icon_label = Label.new()
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.size = Vector2(40, 40)
	_icon_label.text = "?"
	_icon_label.add_theme_font_size_override("font_size", 16)
	_icon_label.add_theme_color_override("font_color", Color(0.02, 0.02, 0.06))
	icon_container.add_child(_icon_label)

	# Text area
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.text = "Skill Name"
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(_name_label)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 10)
	_level_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_level_label.text = "Lv. 1 required"
	vbox.add_child(_level_label)


func _update_display() -> void:
	if skill_data.is_empty():
		return

	var abbrev: String = TREE_ABBREVIATIONS.get(tree_id, "??")
	if _icon_label:
		_icon_label.text = abbrev

	if _name_label:
		_name_label.text = skill_data.get("name", "Unknown")

	var req_level: int = skill_data.get("level", 1)
	if _level_label:
		_level_label.text = "Req. Lv. %d" % req_level

	match current_state:
		State.LOCKED:
			_apply_locked_style()
		State.AVAILABLE:
			_apply_available_style()
		State.UNLOCKED:
			_apply_unlocked_style()


func _apply_locked_style() -> void:
	# Desaturated, 30% opacity
	modulate = Color(1.0, 1.0, 1.0, 0.3)
	if _icon_rect:
		_icon_rect.color = Color(0.3, 0.3, 0.3)
	if _base_style:
		_base_style.border_color = Color(0.2, 0.2, 0.25, 0.3)
		_base_style.bg_color = Color(0.06, 0.06, 0.08, 0.7)
	if _name_label:
		_name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	if _level_label:
		_level_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))


func _apply_available_style() -> void:
	# Full color with pulsing border (neon glow)
	modulate = Color.WHITE
	if _icon_rect:
		_icon_rect.color = tree_color
	if _base_style:
		_base_style.border_color = tree_color
		_base_style.set_border_width_all(2)
		_base_style.bg_color = Color(
			tree_color.r * 0.15,
			tree_color.g * 0.15,
			tree_color.b * 0.15,
			0.9
		)
	if _name_label:
		_name_label.add_theme_color_override("font_color", Color.WHITE)
	if _level_label:
		_level_label.add_theme_color_override("font_color", tree_color.lerp(Color.WHITE, 0.5))
	_glow_time = 0.0


func _apply_unlocked_style() -> void:
	# Full color, solid fill
	modulate = Color.WHITE
	if _icon_rect:
		_icon_rect.color = tree_color
	if _base_style:
		_base_style.border_color = tree_color.lerp(Color.WHITE, 0.3)
		_base_style.set_border_width_all(2)
		_base_style.bg_color = Color(
			tree_color.r * 0.25,
			tree_color.g * 0.25,
			tree_color.b * 0.25,
			0.95
		)
	if _name_label:
		_name_label.add_theme_color_override("font_color", tree_color.lerp(Color.WHITE, 0.6))
	if _level_label:
		_level_label.add_theme_color_override("font_color", tree_color.lerp(Color.WHITE, 0.4))
		_level_label.text = "UNLOCKED"


func _process(delta: float) -> void:
	if current_state != State.AVAILABLE:
		return

	# Pulsing glow effect for available skills
	_glow_time += delta * 2.5
	var pulse: float = (sin(_glow_time) + 1.0) * 0.5 # 0..1
	var glow_alpha: float = lerp(0.4, 1.0, pulse)

	if _base_style:
		_base_style.border_color = Color(
			tree_color.r,
			tree_color.g,
			tree_color.b,
			glow_alpha
		)
		# Subtle shadow glow
		_base_style.shadow_color = Color(
			tree_color.r,
			tree_color.g,
			tree_color.b,
			pulse * 0.3
		)
		_base_style.shadow_size = int(pulse * 6)


func _on_mouse_entered() -> void:
	if current_state == State.LOCKED:
		# Brighten slightly on hover even when locked
		modulate = Color(1.0, 1.0, 1.0, 0.5)
	elif current_state != State.UNLOCKED:
		if _base_style:
			_base_style.bg_color = Color(
				tree_color.r * 0.2,
				tree_color.g * 0.2,
				tree_color.b * 0.2,
				0.95
			)


func _on_mouse_exited() -> void:
	_update_display()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skill_selected.emit(tree_id, skill_data)
		print("[SkillUI] Skill selected: %s (%s)" % [skill_data.get("name", ""), tree_id])
		accept_event()

	# Keyboard / controller confirm
	if event.is_action_pressed("ui_accept"):
		skill_selected.emit(tree_id, skill_data)
		print("[SkillUI] Skill selected (keyboard): %s (%s)" % [skill_data.get("name", ""), tree_id])
		accept_event()
