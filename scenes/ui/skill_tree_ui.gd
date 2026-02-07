## Skill tree UI screen. Shows 4 skill trees side by side with
## detail panel, XP bar, skill points, and unlock functionality.
## Reads from GameManager.skills (SkillTreeSystem).
class_name SkillTreeUI
extends CanvasLayer

# --- Tree color constants ---
const TREE_COLORS := {
	"speed_demon": Color(1.0, 0.2, 0.2),
	"ghost_line": Color(0.2, 0.8, 1.0),
	"street_survivor": Color(1.0, 0.8, 0.0),
	"technician": Color(0.2, 1.0, 0.4),
}

# Tree display order
const TREE_ORDER := ["speed_demon", "ghost_line", "street_survivor", "technician"]

# --- Background ---
const BG_COLOR := Color(0.02, 0.02, 0.06, 0.95)

# --- Node references (assigned in _ready from scene tree) ---
@onready var background: ColorRect = $Background
@onready var title_label: Label = $MainPanel/TopSection/TitleRow/Title
@onready var level_label: Label = $MainPanel/TopSection/TitleRow/LevelLabel
@onready var xp_bar: ProgressBar = $MainPanel/TopSection/XPBar
@onready var xp_label: Label = $MainPanel/TopSection/XPLabel
@onready var skill_points_label: Label = $MainPanel/TopSection/SkillPointsLabel
@onready var trees_container: HBoxContainer = $MainPanel/ContentSection/TreesScroll/TreesContainer
@onready var detail_panel: PanelContainer = $MainPanel/ContentSection/DetailPanel
@onready var detail_name: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailName
@onready var detail_type: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailType
@onready var detail_desc: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailDesc
@onready var detail_current: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailCurrent
@onready var detail_next: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailNext
@onready var detail_prereqs: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailPrereqs
@onready var detail_req_level: Label = $MainPanel/ContentSection/DetailPanel/DetailVBox/DetailReqLevel
@onready var unlock_button: Button = $MainPanel/ContentSection/DetailPanel/DetailVBox/UnlockButton
@onready var back_button: Button = $MainPanel/BottomSection/BackButton

# --- Internal State ---
var _skill_nodes: Dictionary = {} # skill_id -> SkillNodeUI
var _connection_lines: Array[ColorRect] = []
var _selected_tree_id: String = ""
var _selected_skill: Dictionary = {}
var _tree_columns: Dictionary = {} # tree_id -> VBoxContainer


func _ready() -> void:
	# Wire up signals
	back_button.pressed.connect(_on_back_pressed)
	unlock_button.pressed.connect(_on_unlock_pressed)

	# EventBus connections
	EventBus.skill_unlocked.connect(_on_skill_unlocked)
	EventBus.xp_earned.connect(_on_xp_earned)
	EventBus.level_up.connect(_on_level_up)
	EventBus.skill_point_earned.connect(_on_skill_point_earned)

	# Hide detail panel until a skill is selected
	detail_panel.visible = false

	# Build the skill tree columns
	_build_trees()

	# Initial refresh
	_refresh_all()

	print("[SkillUI] Skill tree UI ready.")


func _build_trees() -> void:
	# Clear existing children in trees_container (they are built dynamically)
	for child in trees_container.get_children():
		child.queue_free()

	_skill_nodes.clear()
	_connection_lines.clear()
	_tree_columns.clear()

	for tree_id in TREE_ORDER:
		var tree_data: Dictionary = SkillTreeSystem.TREES.get(tree_id, {})
		var tree_color: Color = TREE_COLORS.get(tree_id, Color.WHITE)
		var tree_name: String = tree_data.get("name", tree_id)

		# Column container for this tree
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.custom_minimum_size = Vector2(180, 0)
		trees_container.add_child(column)
		_tree_columns[tree_id] = column

		# Tree header
		var header := Label.new()
		header.text = tree_name.to_upper()
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 16)
		header.add_theme_color_override("font_color", tree_color)
		header.custom_minimum_size = Vector2(0, 36)
		column.add_child(header)

		# Tree description
		var desc_label := Label.new()
		desc_label.text = tree_data.get("description", "")
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.add_theme_color_override("font_color", tree_color.lerp(Color(0.4, 0.4, 0.5), 0.5))
		desc_label.custom_minimum_size = Vector2(0, 20)
		column.add_child(desc_label)

		# Separator
		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator", _make_colored_separator(tree_color))
		sep.custom_minimum_size = Vector2(0, 8)
		column.add_child(sep)

		# Skills container with spacing for connection lines
		var skills_box := VBoxContainer.new()
		skills_box.add_theme_constant_override("separation", 4)
		skills_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(skills_box)

		var skills: Array = tree_data.get("skills", [])
		for i in range(skills.size()):
			var skill: Dictionary = skills[i]
			var skill_id: String = skill.get("id", "")

			# Connection line above (except first skill)
			if i > 0:
				var line := ColorRect.new()
				line.custom_minimum_size = Vector2(2, 12)
				line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				line.color = tree_color.lerp(Color(0.1, 0.1, 0.15), 0.6)
				skills_box.add_child(line)
				_connection_lines.append(line)

			# Skill node widget
			var node_ui := SkillNodeUI.new()
			skills_box.add_child(node_ui)
			node_ui.setup(tree_id, skill, tree_color)
			node_ui.skill_selected.connect(_on_skill_node_selected)
			_skill_nodes[skill_id] = node_ui


func _refresh_all() -> void:
	_refresh_xp_display()
	_refresh_skill_points()
	_refresh_skill_states()
	_refresh_connection_lines()
	if not _selected_skill.is_empty():
		_refresh_detail_panel()


func _refresh_xp_display() -> void:
	var skills_sys: SkillTreeSystem = GameManager.skills
	var current_level: int = skills_sys.level
	var current_xp: int = skills_sys.xp

	level_label.text = "LEVEL %d" % current_level
	level_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

	# XP progress toward next level
	if current_level >= SkillTreeSystem.MAX_LEVEL:
		xp_bar.value = 100.0
		xp_label.text = "MAX LEVEL"
	else:
		var xp_current_level: int = skills_sys._get_xp_for_level(current_level)
		var xp_next_level: int = skills_sys._get_xp_for_level(current_level + 1)
		var xp_in_level: int = current_xp - xp_current_level
		var xp_needed: int = xp_next_level - xp_current_level
		if xp_needed > 0:
			xp_bar.value = (float(xp_in_level) / float(xp_needed)) * 100.0
		else:
			xp_bar.value = 0.0
		xp_label.text = "%d / %d XP" % [xp_in_level, xp_needed]


func _refresh_skill_points() -> void:
	var sp: int = GameManager.skills.skill_points
	skill_points_label.text = "SKILL POINTS: %d" % sp
	if sp > 0:
		skill_points_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		skill_points_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))


func _refresh_skill_states() -> void:
	var skills_sys: SkillTreeSystem = GameManager.skills

	for tree_id in TREE_ORDER:
		var tree_data: Dictionary = SkillTreeSystem.TREES[tree_id]
		var skills: Array = tree_data.get("skills", [])
		var unlocked: Array = skills_sys.unlocked_skills.get(tree_id, [])

		for i in range(skills.size()):
			var skill: Dictionary = skills[i]
			var skill_id: String = skill.get("id", "")
			var node_ui: SkillNodeUI = _skill_nodes.get(skill_id)
			if node_ui == null:
				continue

			if skill_id in unlocked:
				node_ui.set_state(SkillNodeUI.State.UNLOCKED)
			elif _can_unlock_skill(tree_id, skill, skills, unlocked):
				node_ui.set_state(SkillNodeUI.State.AVAILABLE)
			else:
				node_ui.set_state(SkillNodeUI.State.LOCKED)


func _can_unlock_skill(tree_id: String, skill: Dictionary, all_skills: Array, unlocked: Array) -> bool:
	var skills_sys: SkillTreeSystem = GameManager.skills

	# Check level requirement
	var req_level: int = skill.get("level", 1)
	if skills_sys.level < req_level:
		return false

	# Check prerequisites (all lower-level skills must be unlocked)
	for s in all_skills:
		if s.get("level", 0) < req_level and s.get("id", "") not in unlocked:
			return false

	# Check skill points
	if skills_sys.skill_points <= 0:
		return false

	return true


func _refresh_connection_lines() -> void:
	var skills_sys: SkillTreeSystem = GameManager.skills
	var line_idx: int = 0

	for tree_id in TREE_ORDER:
		var tree_data: Dictionary = SkillTreeSystem.TREES[tree_id]
		var tree_color: Color = TREE_COLORS.get(tree_id, Color.WHITE)
		var skills: Array = tree_data.get("skills", [])
		var unlocked: Array = skills_sys.unlocked_skills.get(tree_id, [])

		for i in range(1, skills.size()):
			if line_idx >= _connection_lines.size():
				break
			var line: ColorRect = _connection_lines[line_idx]
			var prev_skill_id: String = skills[i - 1].get("id", "")

			if prev_skill_id in unlocked:
				# Previous skill unlocked - bright line
				line.color = tree_color.lerp(Color.WHITE, 0.2)
			else:
				# Dim line for locked path
				line.color = tree_color.lerp(Color(0.1, 0.1, 0.15), 0.7)

			line_idx += 1


func _refresh_detail_panel() -> void:
	if _selected_skill.is_empty():
		detail_panel.visible = false
		return

	detail_panel.visible = true

	var skill_id: String = _selected_skill.get("id", "")
	var skill_name: String = _selected_skill.get("name", "Unknown")
	var skill_type: String = _selected_skill.get("type", "passive")
	var req_level: int = _selected_skill.get("level", 1)
	var effect: Dictionary = _selected_skill.get("effect", {})

	var is_unlocked: bool = GameManager.skills.has_skill(skill_id)

	# Name
	var tree_color: Color = TREE_COLORS.get(_selected_tree_id, Color.WHITE)
	detail_name.text = skill_name
	detail_name.add_theme_color_override("font_color", tree_color)

	# Type
	detail_type.text = "[%s]" % skill_type.to_upper()
	detail_type.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))

	# Description
	detail_desc.text = _get_skill_description(_selected_tree_id, _selected_skill)

	# Current effect
	if is_unlocked:
		detail_current.text = "Status: ACTIVE"
		detail_current.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		detail_next.text = ""
	else:
		detail_current.text = "Status: LOCKED"
		detail_current.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		detail_next.text = "Effect: %s" % _format_effect(effect)
		detail_next.add_theme_color_override("font_color", tree_color.lerp(Color.WHITE, 0.4))

	# Required level
	if GameManager.skills.level >= req_level:
		detail_req_level.text = "Required Level: %d (met)" % req_level
		detail_req_level.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		detail_req_level.text = "Required Level: %d (need %d more)" % [req_level, req_level - GameManager.skills.level]
		detail_req_level.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	# Prerequisites
	var prereq_text := _get_prereq_text(_selected_tree_id, _selected_skill)
	detail_prereqs.text = prereq_text
	if "missing" in prereq_text.to_lower():
		detail_prereqs.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	else:
		detail_prereqs.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))

	# Unlock button
	if is_unlocked:
		unlock_button.text = "UNLOCKED"
		unlock_button.disabled = true
	else:
		unlock_button.text = "UNLOCK (1 SP)"
		var tree_data: Dictionary = SkillTreeSystem.TREES.get(_selected_tree_id, {})
		var all_skills: Array = tree_data.get("skills", [])
		var unlocked: Array = GameManager.skills.unlocked_skills.get(_selected_tree_id, [])
		unlock_button.disabled = not _can_unlock_skill(_selected_tree_id, _selected_skill, all_skills, unlocked)


func _get_skill_description(tree_id: String, skill: Dictionary) -> String:
	var skill_id: String = skill.get("id", "")
	var effect: Dictionary = skill.get("effect", {})

	# Build a readable description from the effect data
	var descriptions := {
		"sd_1": "Increases your vehicle's top speed by 2%. Every bit of straight-line advantage counts on the streets.",
		"sd_3": "Slipstream drafting behind opponents is 30% more effective. Stick close and slingshot past.",
		"sd_5": "Nitrous oxide burns 50% longer. Extended boost windows for critical overtakes.",
		"sd_7": "Aerodynamic drag reduced by 10%. Higher top speeds and better high-speed stability.",
		"sd_10": "Break through the normal speed limiter. Terminal velocity unleashed.",
		"gl_1": "Cornering grip increased by 2%. Maintain more speed through turns.",
		"gl_3": "Trail braking technique improved by 20%. Carry more speed into corners.",
		"gl_5": "Reveals the optimal racing line during races. See the path the pros take.",
		"gl_7": "Weight transfer between tires is 30% more responsive. Sharper transitions.",
		"gl_10": "Enter a flow state in corners — time slows briefly for perfect inputs.",
		"ss_1": "Vehicle takes 5% less damage from collisions. Built different.",
		"ss_3": "Tires recover from lockup and wheelspin 30% faster. Stay planted.",
		"ss_5": "Recover from crashes 50% faster. Back on the road before they know it.",
		"ss_7": "Police attention gain reduced by 30%. Stay under the radar.",
		"ss_10": "Survive one fatal crash per race. Rise from the wreckage and keep driving.",
		"tc_1": "Repair costs reduced by 5%. Save cash for what matters — parts.",
		"tc_3": "Higher chance of discovering rare parts at shops and through contacts.",
		"tc_5": "Perform emergency repairs during a race. Quick fix to keep you running.",
		"tc_7": "Access hidden tuning parameters for deeper vehicle customization.",
		"tc_10": "Unlock exclusive part combinations that push beyond normal limits.",
	}

	return descriptions.get(skill_id, "A powerful skill in the %s tree." % SkillTreeSystem.TREES.get(tree_id, {}).get("name", tree_id))


func _format_effect(effect: Dictionary) -> String:
	if effect.has("stat"):
		var stat: String = effect.get("stat", "")
		var mult: float = effect.get("mult", 1.0)
		var pct: float = (mult - 1.0) * 100.0
		if pct >= 0:
			return "+%.0f%% %s" % [pct, stat.capitalize()]
		else:
			return "%.0f%% %s" % [pct, stat.capitalize()]

	if effect.has("slipstream_mult"):
		return "+%.0f%% Slipstream" % [(effect.slipstream_mult - 1.0) * 100.0]
	if effect.has("nitro_duration_mult"):
		return "+%.0f%% Nitro Duration" % [(effect.nitro_duration_mult - 1.0) * 100.0]
	if effect.has("drag_mult"):
		return "%.0f%% Drag" % [(effect.drag_mult - 1.0) * 100.0]
	if effect.has("speed_limit_break"):
		return "Remove Speed Limiter"
	if effect.has("trail_brake_mult"):
		return "+%.0f%% Trail Braking" % [(effect.trail_brake_mult - 1.0) * 100.0]
	if effect.has("racing_line_visible"):
		return "Show Racing Line"
	if effect.has("weight_transfer_mult"):
		return "+%.0f%% Weight Transfer" % [(effect.weight_transfer_mult - 1.0) * 100.0]
	if effect.has("time_slow_corners"):
		return "Corner Time Slow"
	if effect.has("tire_recovery_mult"):
		return "+%.0f%% Tire Recovery" % [(effect.tire_recovery_mult - 1.0) * 100.0]
	if effect.has("crash_recovery_mult"):
		return "+%.0f%% Crash Recovery" % [(effect.crash_recovery_mult - 1.0) * 100.0]
	if effect.has("heat_gain_mult"):
		return "%.0f%% Heat Gain" % [(effect.heat_gain_mult - 1.0) * 100.0]
	if effect.has("survive_fatal_crash"):
		return "Survive Fatal Crash"
	if effect.has("repair_cost_mult"):
		return "%.0f%% Repair Costs" % [(effect.repair_cost_mult - 1.0) * 100.0]
	if effect.has("part_discovery_bonus"):
		return "Better Part Discovery"
	if effect.has("mid_race_repair"):
		return "Mid-Race Repair"
	if effect.has("hidden_tuning"):
		return "Hidden Tuning Access"
	if effect.has("exclusive_part_combos"):
		return "Exclusive Part Combos"

	return "Special Effect"


func _get_prereq_text(tree_id: String, skill: Dictionary) -> String:
	var req_level: int = skill.get("level", 1)
	var tree_data: Dictionary = SkillTreeSystem.TREES.get(tree_id, {})
	var all_skills: Array = tree_data.get("skills", [])
	var unlocked: Array = GameManager.skills.unlocked_skills.get(tree_id, [])

	var prereqs: Array[String] = []
	for s in all_skills:
		if s.get("level", 0) < req_level:
			var sid: String = s.get("id", "")
			var sname: String = s.get("name", sid)
			if sid in unlocked:
				prereqs.append(sname + " (done)")
			else:
				prereqs.append(sname + " (MISSING)")

	if prereqs.is_empty():
		return "Prerequisites: None"
	return "Prerequisites: " + ", ".join(prereqs)


# --- Signal Handlers ---

func _on_skill_node_selected(tree_id: String, skill_data: Dictionary) -> void:
	_selected_tree_id = tree_id
	_selected_skill = skill_data
	_refresh_detail_panel()


func _on_unlock_pressed() -> void:
	if _selected_skill.is_empty() or _selected_tree_id.is_empty():
		return

	var skill_id: String = _selected_skill.get("id", "")
	var success: bool = GameManager.skills.unlock_skill(_selected_tree_id, skill_id)

	if success:
		print("[SkillUI] Unlocked skill: %s" % skill_id)
		_refresh_all()
	else:
		print("[SkillUI] Failed to unlock skill: %s" % skill_id)
		EventBus.hud_message.emit("Cannot unlock this skill!", 2.0)


func _on_skill_unlocked(_tree: String, _skill_id: String) -> void:
	_refresh_all()


func _on_xp_earned(_amount: int, _source: String) -> void:
	_refresh_xp_display()


func _on_level_up(_new_level: int) -> void:
	_refresh_all()


func _on_skill_point_earned(_points: int) -> void:
	_refresh_skill_points()
	_refresh_skill_states()


func _on_back_pressed() -> void:
	close_skill_tree()


func close_skill_tree() -> void:
	print("[SkillUI] Closing skill tree.")
	var parent := get_parent()
	if parent and parent.has_method("close_skill_tree"):
		parent.close_skill_tree()
	else:
		visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on ESC
	if event.is_action_pressed("ui_cancel"):
		close_skill_tree()
		get_viewport().set_input_as_handled()


func _make_colored_separator(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.lerp(Color(0.1, 0.1, 0.15), 0.5)
	style.set_content_margin_all(0)
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style
