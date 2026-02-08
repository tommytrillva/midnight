## Pre-race pink slip wagering screen.
## Displays player's car vs opponent's car side-by-side, fairness indicator,
## stakes summary, and accept/decline buttons. Players can switch which vehicle
## they wager via a vehicle selector scroll list.
class_name PinkSlipUI
extends CanvasLayer

signal challenge_accepted(challenge_id: String, player_vehicle_id: String)
signal challenge_declined(challenge_id: String)

# --- Node references (assigned in _ready from scene tree) ---
var _title_label: Label = null
var _player_panel: PanelContainer = null
var _opponent_panel: PanelContainer = null
var _vs_label: Label = null
var _fairness_bar: ProgressBar = null
var _fairness_label: Label = null
var _stakes_label: Label = null
var _warning_label: Label = null
var _accept_button: Button = null
var _decline_button: Button = null
var _vehicle_selector: ScrollContainer = null
var _vehicle_list: VBoxContainer = null
var _confirmation_overlay: PanelContainer = null
var _confirm_yes_button: Button = null
var _confirm_no_button: Button = null
var _opponent_dialogue_label: Label = null

# Player panel stat labels
var _player_name_label: Label = null
var _player_hp_label: Label = null
var _player_weight_label: Label = null
var _player_speed_label: Label = null
var _player_value_label: Label = null
var _player_parts_label: Label = null
var _player_color_rect: ColorRect = null

# Opponent panel stat labels
var _opponent_name_label: Label = null
var _opponent_hp_label: Label = null
var _opponent_weight_label: Label = null
var _opponent_speed_label: Label = null
var _opponent_value_label: Label = null
var _opponent_parts_label: Label = null
var _opponent_color_rect: ColorRect = null

# --- State ---
var _current_challenge: Dictionary = {}
var _selected_player_vehicle_id: String = ""
var _accept_pulse_tween: Tween = null


func _ready() -> void:
	_bind_nodes()
	_connect_buttons()
	visible = false


func _bind_nodes() -> void:
	## Find and cache all UI node references from the scene tree.
	_title_label = _find_node("TitleLabel") as Label
	_vs_label = _find_node("VSLabel") as Label
	_fairness_bar = _find_node("FairnessBar") as ProgressBar
	_fairness_label = _find_node("FairnessLabel") as Label
	_stakes_label = _find_node("StakesLabel") as Label
	_warning_label = _find_node("WarningLabel") as Label
	_accept_button = _find_node("AcceptButton") as Button
	_decline_button = _find_node("DeclineButton") as Button
	_vehicle_selector = _find_node("VehicleSelector") as ScrollContainer
	_vehicle_list = _find_node("VehicleList") as VBoxContainer
	_confirmation_overlay = _find_node("ConfirmationOverlay") as PanelContainer
	_confirm_yes_button = _find_node("ConfirmYesButton") as Button
	_confirm_no_button = _find_node("ConfirmNoButton") as Button
	_opponent_dialogue_label = _find_node("OpponentDialogueLabel") as Label

	# Player panel
	_player_panel = _find_node("PlayerPanel") as PanelContainer
	_player_name_label = _find_node("PlayerNameLabel") as Label
	_player_hp_label = _find_node("PlayerHPLabel") as Label
	_player_weight_label = _find_node("PlayerWeightLabel") as Label
	_player_speed_label = _find_node("PlayerSpeedLabel") as Label
	_player_value_label = _find_node("PlayerValueLabel") as Label
	_player_parts_label = _find_node("PlayerPartsLabel") as Label
	_player_color_rect = _find_node("PlayerColorRect") as ColorRect

	# Opponent panel
	_opponent_panel = _find_node("OpponentPanel") as PanelContainer
	_opponent_name_label = _find_node("OpponentNameLabel") as Label
	_opponent_hp_label = _find_node("OpponentHPLabel") as Label
	_opponent_weight_label = _find_node("OpponentWeightLabel") as Label
	_opponent_speed_label = _find_node("OpponentSpeedLabel") as Label
	_opponent_value_label = _find_node("OpponentValueLabel") as Label
	_opponent_parts_label = _find_node("OpponentPartsLabel") as Label
	_opponent_color_rect = _find_node("OpponentColorRect") as ColorRect


func _find_node(node_name: String) -> Node:
	## Recursively search for a named node in the scene tree.
	return _find_node_recursive(self, node_name)


func _find_node_recursive(parent: Node, node_name: String) -> Node:
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found := _find_node_recursive(child, node_name)
		if found:
			return found
	return null


func _connect_buttons() -> void:
	if _accept_button:
		_accept_button.pressed.connect(_on_accept_pressed)
	if _decline_button:
		_decline_button.pressed.connect(_on_decline_pressed)
	if _confirm_yes_button:
		_confirm_yes_button.pressed.connect(_on_confirm_yes)
	if _confirm_no_button:
		_confirm_no_button.pressed.connect(_on_confirm_no)


# ---------------------------------------------------------------------------
# Show / Hide
# ---------------------------------------------------------------------------

func show_challenge(challenge: Dictionary) -> void:
	## Display the pink slip wagering screen for a given challenge.
	_current_challenge = challenge
	_selected_player_vehicle_id = challenge.get("player_vehicle_id", "")
	visible = true

	if _confirmation_overlay:
		_confirmation_overlay.visible = false

	_populate_opponent_panel(challenge)
	_populate_player_panel(_selected_player_vehicle_id)
	_update_fairness(challenge)
	_update_stakes(challenge)
	_update_warning()
	_populate_vehicle_selector()
	_show_opponent_dialogue(challenge.get("opponent_dialogue_pre", ""))
	_update_decline_button(challenge)
	_start_accept_pulse()

	# Entrance animation
	_animate_entrance()

	print("[PinkSlip] UI shown for challenge: %s" % challenge.get("challenge_id", ""))


func hide_ui() -> void:
	_stop_accept_pulse()
	visible = false


# ---------------------------------------------------------------------------
# Panel Population
# ---------------------------------------------------------------------------

func _populate_player_panel(vehicle_id: String) -> void:
	var vehicle: VehicleData = GameManager.garage.get_vehicle(vehicle_id)
	if vehicle == null:
		return

	if _player_name_label:
		_player_name_label.text = vehicle.display_name
	if _player_color_rect:
		_player_color_rect.color = vehicle.paint_color

	var stats := vehicle.get_effective_stats()
	if _player_hp_label:
		_player_hp_label.text = "%d HP" % int(stats.get("hp", vehicle.current_hp))
	if _player_weight_label:
		_player_weight_label.text = "%d kg" % int(stats.get("weight", vehicle.weight_kg))
	if _player_speed_label:
		_player_speed_label.text = "SPD: %.0f" % stats.get("speed", vehicle.base_speed)

	var value := vehicle.calculate_value()
	if _player_value_label:
		_player_value_label.text = "$%s" % _format_number(value)

	# List installed parts
	if _player_parts_label:
		var parts_text := ""
		var part_count := 0
		for slot in vehicle.installed_parts:
			var part_id: String = vehicle.installed_parts[slot]
			if not part_id.is_empty():
				if part_count > 0:
					parts_text += "\n"
				parts_text += "- %s" % part_id.replace("_", " ").capitalize()
				part_count += 1
		if part_count == 0:
			parts_text = "Stock"
		_player_parts_label.text = parts_text


func _populate_opponent_panel(challenge: Dictionary) -> void:
	if _opponent_name_label:
		_opponent_name_label.text = challenge.get("opponent_vehicle_name", "???")
	if _opponent_color_rect:
		_opponent_color_rect.color = Color(0.2, 0.2, 0.2) # Unknown car, dark silhouette

	var opponent_value: int = challenge.get("opponent_vehicle_value", 0)

	# Show some stats as hidden (builds tension)
	var challenge_type: int = challenge.get("challenge_type", PinkSlipSystem.ChallengeType.VOLUNTARY)
	var reveal_stats: bool = challenge_type == PinkSlipSystem.ChallengeType.STORY

	if _opponent_hp_label:
		if reveal_stats:
			_opponent_hp_label.text = "??? HP" # Even story shows some mystery
		else:
			_opponent_hp_label.text = "??? HP"

	if _opponent_weight_label:
		_opponent_weight_label.text = "??? kg"

	if _opponent_speed_label:
		if reveal_stats:
			_opponent_speed_label.text = "SPD: ???"
		else:
			_opponent_speed_label.text = "SPD: ???"

	if _opponent_value_label:
		# Show estimated value range instead of exact
		if opponent_value > 0:
			var low := int(opponent_value * 0.8)
			var high := int(opponent_value * 1.2)
			_opponent_value_label.text = "~$%s - $%s" % [_format_number(low), _format_number(high)]
		else:
			_opponent_value_label.text = "$???"

	if _opponent_parts_label:
		_opponent_parts_label.text = "Unknown mods"


func _update_fairness(challenge: Dictionary) -> void:
	var label: String = challenge.get("fairness_label", "FAIR MATCH")
	var ratio: float = challenge.get("fairness_ratio", 1.0)

	if _fairness_label:
		_fairness_label.text = label

	if _fairness_bar:
		# Map ratio to 0-100 where 50 is perfectly fair
		var bar_value := clampf(ratio * 50.0, 0.0, 100.0)
		_fairness_bar.value = bar_value

		# Color the bar based on fairness
		var style := StyleBoxFlat.new()
		match label:
			"FAIR MATCH":
				style.bg_color = Color(0.0, 0.8, 0.2) # Green
				if _fairness_label:
					_fairness_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.3))
			"RISKY":
				style.bg_color = Color(0.9, 0.7, 0.0) # Yellow
				if _fairness_label:
					_fairness_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
			"SUICIDE":
				style.bg_color = Color(0.9, 0.1, 0.1) # Red
				if _fairness_label:
					_fairness_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))
		_fairness_bar.add_theme_stylebox_override("fill", style)


func _update_stakes(challenge: Dictionary) -> void:
	if _stakes_label == null:
		return

	var player_name: String = challenge.get("player_vehicle_name", "your car")
	var opponent_name: String = challenge.get("opponent_vehicle_name", "their car")
	var story_protected: bool = challenge.get("story_protected", false)

	if story_protected:
		_stakes_label.text = "You win: %s. You lose: nothing (story race)." % opponent_name
	else:
		_stakes_label.text = "You win: %s. You lose: %s." % [opponent_name, player_name]


func _update_warning() -> void:
	if _warning_label == null:
		return

	var pink_slip_sys: PinkSlipSystem = _get_pink_slip_system()
	if pink_slip_sys == null:
		_warning_label.visible = false
		return

	if pink_slip_sys.is_wagering_last_vehicle(_selected_player_vehicle_id):
		_warning_label.text = "!! WARNING: This is your ONLY vehicle. You CANNOT wager it. !!"
		_warning_label.visible = true
		_warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		if _accept_button:
			_accept_button.disabled = true
	elif GameManager.garage.get_vehicle_count() == 2:
		_warning_label.text = "CAUTION: You only have 2 vehicles. Losing means you're down to one."
		_warning_label.visible = true
		_warning_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.0))
		if _accept_button:
			_accept_button.disabled = false
	else:
		_warning_label.visible = false
		if _accept_button:
			_accept_button.disabled = false


func _update_decline_button(challenge: Dictionary) -> void:
	if _decline_button == null:
		return

	var pink_slip_sys: PinkSlipSystem = _get_pink_slip_system()
	if pink_slip_sys == null:
		return

	var rep_cost := pink_slip_sys.get_rep_cost_for_decline(challenge)
	if rep_cost > 0:
		_decline_button.text = "DECLINE (-%d REP)" % rep_cost
	else:
		_decline_button.text = "DECLINE"


func _show_opponent_dialogue(dialogue_text: String) -> void:
	if _opponent_dialogue_label == null:
		return
	if dialogue_text.is_empty():
		_opponent_dialogue_label.visible = false
	else:
		_opponent_dialogue_label.text = "\"%s\"" % dialogue_text
		_opponent_dialogue_label.visible = true


# ---------------------------------------------------------------------------
# Vehicle Selector
# ---------------------------------------------------------------------------

func _populate_vehicle_selector() -> void:
	if _vehicle_list == null:
		return

	# Clear existing entries
	for child in _vehicle_list.get_children():
		child.queue_free()

	var garage: GarageSystem = GameManager.garage
	var vehicles := garage.get_all_vehicles()

	for vehicle in vehicles:
		if vehicle is VehicleData:
			var btn := Button.new()
			var value := vehicle.calculate_value()
			btn.text = "%s — $%s" % [vehicle.display_name, _format_number(value)]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

			# Style the button
			btn.add_theme_font_size_override("font_size", 14)
			if vehicle.vehicle_id == _selected_player_vehicle_id:
				btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8))
			else:
				btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

			# Cannot select if it's the only vehicle
			if garage.get_vehicle_count() <= 1:
				btn.disabled = true
				btn.tooltip_text = "Cannot wager your only vehicle"

			var vid: String = vehicle.vehicle_id
			btn.pressed.connect(_on_vehicle_selected.bind(vid))
			_vehicle_list.add_child(btn)


func _on_vehicle_selected(vehicle_id: String) -> void:
	_selected_player_vehicle_id = vehicle_id

	# Recalculate challenge values with new player vehicle
	var vehicle: VehicleData = GameManager.garage.get_vehicle(vehicle_id)
	if vehicle:
		var pink_slip_sys: PinkSlipSystem = _get_pink_slip_system()
		if pink_slip_sys:
			var player_value := pink_slip_sys.get_vehicle_value(vehicle)
			_current_challenge["player_vehicle_id"] = vehicle_id
			_current_challenge["player_vehicle_name"] = vehicle.display_name
			_current_challenge["player_vehicle_value"] = player_value

			var opponent_value: int = _current_challenge.get("opponent_vehicle_value", 0)
			var ratio := pink_slip_sys._calculate_fairness(player_value, opponent_value)
			_current_challenge["fairness_ratio"] = ratio
			_current_challenge["fairness_label"] = pink_slip_sys._get_fairness_label(ratio)

	_populate_player_panel(vehicle_id)
	_update_fairness(_current_challenge)
	_update_stakes(_current_challenge)
	_update_warning()
	_populate_vehicle_selector() # Refresh selection highlight

	print("[PinkSlip] Vehicle selected for wager: %s" % vehicle_id)


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_accept_pressed() -> void:
	## Show confirmation overlay before accepting.
	if _confirmation_overlay:
		_confirmation_overlay.visible = true
		_animate_confirmation_in()


func _on_decline_pressed() -> void:
	var challenge_id: String = _current_challenge.get("challenge_id", "")
	challenge_declined.emit(challenge_id)
	hide_ui()
	print("[PinkSlip] Player declined challenge: %s" % challenge_id)


func _on_confirm_yes() -> void:
	## Player confirmed — accept the challenge.
	if _confirmation_overlay:
		_confirmation_overlay.visible = false

	var challenge_id: String = _current_challenge.get("challenge_id", "")
	challenge_accepted.emit(challenge_id, _selected_player_vehicle_id)
	hide_ui()
	print("[PinkSlip] Player confirmed acceptance: %s" % challenge_id)


func _on_confirm_no() -> void:
	## Player backed out of confirmation.
	if _confirmation_overlay:
		_confirmation_overlay.visible = false


# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

func _animate_entrance() -> void:
	## Dramatic entrance animation for the pink slip screen.
	# Fade in the dark overlay
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)

	# Slide panels in from sides
	if _player_panel:
		var target_x := _player_panel.position.x
		_player_panel.position.x -= 200.0
		_player_panel.modulate.a = 0.0
		var p_tween := create_tween()
		p_tween.set_parallel(true)
		p_tween.tween_property(_player_panel, "position:x", target_x, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.2)
		p_tween.tween_property(_player_panel, "modulate:a", 1.0, 0.3).set_delay(0.2)

	if _opponent_panel:
		var target_x := _opponent_panel.position.x
		_opponent_panel.position.x += 200.0
		_opponent_panel.modulate.a = 0.0
		var o_tween := create_tween()
		o_tween.set_parallel(true)
		o_tween.tween_property(_opponent_panel, "position:x", target_x, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.2)
		o_tween.tween_property(_opponent_panel, "modulate:a", 1.0, 0.3).set_delay(0.2)

	# VS label punch-in
	if _vs_label:
		_vs_label.scale = Vector2(3.0, 3.0)
		_vs_label.modulate.a = 0.0
		var vs_tween := create_tween()
		vs_tween.set_parallel(true)
		vs_tween.tween_property(_vs_label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.5)
		vs_tween.tween_property(_vs_label, "modulate:a", 1.0, 0.2).set_delay(0.5)


func _animate_confirmation_in() -> void:
	if _confirmation_overlay == null:
		return
	_confirmation_overlay.modulate.a = 0.0
	_confirmation_overlay.scale = Vector2(0.8, 0.8)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_confirmation_overlay, "modulate:a", 1.0, 0.2)
	tween.tween_property(_confirmation_overlay, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _start_accept_pulse() -> void:
	## Pulsing red glow on accept button to convey danger.
	if _accept_button == null:
		return
	_stop_accept_pulse()
	_accept_pulse_tween = create_tween()
	_accept_pulse_tween.set_loops()
	_accept_pulse_tween.tween_property(
		_accept_button, "modulate",
		Color(1.0, 0.5, 0.5, 1.0), 0.6
	).set_ease(Tween.EASE_IN_OUT)
	_accept_pulse_tween.tween_property(
		_accept_button, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), 0.6
	).set_ease(Tween.EASE_IN_OUT)


func _stop_accept_pulse() -> void:
	if _accept_pulse_tween and _accept_pulse_tween.is_valid():
		_accept_pulse_tween.kill()
		_accept_pulse_tween = null
	if _accept_button:
		_accept_button.modulate = Color(1.0, 1.0, 1.0, 1.0)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _get_pink_slip_system() -> PinkSlipSystem:
	if GameManager.has_node("PinkSlipSystem"):
		return GameManager.get_node("PinkSlipSystem") as PinkSlipSystem
	return null


func _format_number(value: int) -> String:
	## Format number with commas: 15000 -> "15,000"
	var s := str(value)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
