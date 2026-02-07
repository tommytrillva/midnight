## Post-race pink slip result screen.
## Shows a dramatic win (celebration + car reveal) or gut-punch loss
## (car fading away + somber tone). Displays the transferred vehicle
## stats and remaining garage info.
class_name PinkSlipResult
extends CanvasLayer

signal result_acknowledged()

# --- Node references ---
var _overlay: ColorRect = null
var _result_container: VBoxContainer = null
var _result_title: Label = null
var _car_name_label: Label = null
var _car_color_rect: ColorRect = null
var _car_silhouette: ColorRect = null
var _stats_grid: GridContainer = null
var _hp_label: Label = null
var _weight_label: Label = null
var _speed_label: Label = null
var _value_label: Label = null
var _message_label: Label = null
var _opponent_reaction_label: Label = null
var _remaining_label: Label = null
var _continue_button: Button = null

# --- State ---
var _is_win: bool = false
var _displayed_vehicle: VehicleData = null


func _ready() -> void:
	_bind_nodes()
	if _continue_button:
		_continue_button.pressed.connect(_on_continue)
	visible = false


func _bind_nodes() -> void:
	_overlay = _find_node("ResultOverlay") as ColorRect
	_result_container = _find_node("ResultContainer") as VBoxContainer
	_result_title = _find_node("ResultTitle") as Label
	_car_name_label = _find_node("CarNameLabel") as Label
	_car_color_rect = _find_node("CarColorRect") as ColorRect
	_car_silhouette = _find_node("CarSilhouette") as ColorRect
	_stats_grid = _find_node("ResultStatsGrid") as GridContainer
	_hp_label = _find_node("ResultHPLabel") as Label
	_weight_label = _find_node("ResultWeightLabel") as Label
	_speed_label = _find_node("ResultSpeedLabel") as Label
	_value_label = _find_node("ResultValueLabel") as Label
	_message_label = _find_node("MessageLabel") as Label
	_opponent_reaction_label = _find_node("OpponentReactionLabel") as Label
	_remaining_label = _find_node("RemainingLabel") as Label
	_continue_button = _find_node("ContinueButton") as Button


func _find_node(node_name: String) -> Node:
	return _find_node_recursive(self, node_name)


func _find_node_recursive(parent: Node, node_name: String) -> Node:
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found := _find_node_recursive(child, node_name)
		if found:
			return found
	return null


# ---------------------------------------------------------------------------
# Show Win
# ---------------------------------------------------------------------------

func show_win(won_vehicle: VehicleData, opponent_dialogue: String = "") -> void:
	## Display the victory screen with the won car revealed dramatically.
	_is_win = true
	_displayed_vehicle = won_vehicle
	visible = true

	# Set overlay to gold/celebration tone
	if _overlay:
		_overlay.color = Color(0.05, 0.02, 0.0, 0.9)

	# Title
	if _result_title:
		_result_title.text = "YOU WON"
		_result_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))

	# Car name
	if _car_name_label:
		_car_name_label.text = won_vehicle.display_name
		_car_name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))

	# Car visual
	if _car_color_rect:
		_car_color_rect.color = won_vehicle.paint_color
		_car_color_rect.visible = true
	if _car_silhouette:
		_car_silhouette.visible = false

	# Stats (reveal one by one via animation)
	_populate_stats(won_vehicle)

	# Message
	if _message_label:
		_message_label.text = "Added to your garage"
		_message_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.6))

	# Opponent reaction
	if _opponent_reaction_label:
		if opponent_dialogue.is_empty():
			_opponent_reaction_label.visible = false
		else:
			_opponent_reaction_label.text = "\"%s\"" % opponent_dialogue
			_opponent_reaction_label.visible = true
			_opponent_reaction_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))

	# Hide remaining vehicles label for wins
	if _remaining_label:
		_remaining_label.visible = false

	# Continue button
	if _continue_button:
		_continue_button.text = "COLLECT YOUR PRIZE"
		_continue_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))

	# Play victory animation
	_animate_win()
	print("[PinkSlip] Win screen displayed: %s" % won_vehicle.display_name)


# ---------------------------------------------------------------------------
# Show Loss
# ---------------------------------------------------------------------------

func show_loss(lost_vehicle: VehicleData, opponent_dialogue: String = "") -> void:
	## Display the loss screen with the player's car fading away.
	_is_win = false
	_displayed_vehicle = lost_vehicle
	visible = true

	# Set overlay to dark/red somber tone
	if _overlay:
		_overlay.color = Color(0.08, 0.0, 0.0, 0.92)

	# Title
	if _result_title:
		_result_title.text = "YOU LOST"
		_result_title.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))

	# Car name
	if _car_name_label:
		_car_name_label.text = lost_vehicle.display_name
		_car_name_label.add_theme_color_override("font_color", Color(0.6, 0.2, 0.2))

	# Car visual — silhouette fading
	if _car_color_rect:
		_car_color_rect.color = lost_vehicle.paint_color
		_car_color_rect.visible = true
	if _car_silhouette:
		_car_silhouette.visible = true
		_car_silhouette.color = Color(0, 0, 0, 0.7)

	# Stats of lost car
	_populate_stats(lost_vehicle)

	# Message
	if _message_label:
		_message_label.text = "They're driving away in your car."
		_message_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3))

	# Opponent reaction
	if _opponent_reaction_label:
		if opponent_dialogue.is_empty():
			_opponent_reaction_label.visible = false
		else:
			_opponent_reaction_label.text = "\"%s\"" % opponent_dialogue
			_opponent_reaction_label.visible = true
			_opponent_reaction_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))

	# Show remaining vehicles
	if _remaining_label:
		var remaining := GameManager.garage.get_vehicle_count()
		if remaining <= 1:
			_remaining_label.text = "You have %d vehicle remaining. Don't lose it." % remaining
			_remaining_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		else:
			_remaining_label.text = "You have %d vehicles remaining." % remaining
			_remaining_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_remaining_label.visible = true

	# Continue button
	if _continue_button:
		_continue_button.text = "CONTINUE"
		_continue_button.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	# Play loss animation
	_animate_loss()
	print("[PinkSlip] Loss screen displayed: %s" % lost_vehicle.display_name)


# ---------------------------------------------------------------------------
# Stats Population
# ---------------------------------------------------------------------------

func _populate_stats(vehicle: VehicleData) -> void:
	var stats := vehicle.get_effective_stats()
	if _hp_label:
		_hp_label.text = "%d HP" % int(stats.get("hp", vehicle.current_hp))
	if _weight_label:
		_weight_label.text = "%d kg" % int(stats.get("weight", vehicle.weight_kg))
	if _speed_label:
		_speed_label.text = "SPD: %.0f" % stats.get("speed", vehicle.base_speed)
	if _value_label:
		var value := vehicle.calculate_value()
		_value_label.text = "$%s" % _format_number(value)


# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

func _animate_win() -> void:
	## Gold celebration animation: title slam, car reveal, staggered stats.
	# Fade in overlay
	if _overlay:
		_overlay.modulate.a = 0.0
		var overlay_tween := create_tween()
		overlay_tween.tween_property(_overlay, "modulate:a", 1.0, 0.4)

	# Title slam in
	if _result_title:
		_result_title.scale = Vector2(3.0, 3.0)
		_result_title.modulate.a = 0.0
		var title_tween := create_tween()
		title_tween.set_parallel(true)
		title_tween.tween_property(_result_title, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.3)
		title_tween.tween_property(_result_title, "modulate:a", 1.0, 0.3).set_delay(0.3)

	# Car name fade in
	if _car_name_label:
		_car_name_label.modulate.a = 0.0
		var name_tween := create_tween()
		name_tween.tween_property(_car_name_label, "modulate:a", 1.0, 0.4).set_delay(0.6)

	# Car color reveal
	if _car_color_rect:
		_car_color_rect.modulate.a = 0.0
		var car_tween := create_tween()
		car_tween.tween_property(_car_color_rect, "modulate:a", 1.0, 0.6).set_delay(0.8)

	# Stats stagger reveal
	_stagger_stats_reveal(1.2)

	# Message fade in
	if _message_label:
		_message_label.modulate.a = 0.0
		var msg_tween := create_tween()
		msg_tween.tween_property(_message_label, "modulate:a", 1.0, 0.3).set_delay(2.0)

	# Opponent reaction
	if _opponent_reaction_label and _opponent_reaction_label.visible:
		_opponent_reaction_label.modulate.a = 0.0
		var react_tween := create_tween()
		react_tween.tween_property(_opponent_reaction_label, "modulate:a", 1.0, 0.3).set_delay(2.3)

	# Continue button
	if _continue_button:
		_continue_button.modulate.a = 0.0
		var btn_tween := create_tween()
		btn_tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3).set_delay(2.8)


func _animate_loss() -> void:
	## Somber loss animation: title appears, car fades away, stats dim.
	# Fade in overlay
	if _overlay:
		_overlay.modulate.a = 0.0
		var overlay_tween := create_tween()
		overlay_tween.tween_property(_overlay, "modulate:a", 1.0, 0.6)

	# Title slowly appears
	if _result_title:
		_result_title.modulate.a = 0.0
		var title_tween := create_tween()
		title_tween.tween_property(_result_title, "modulate:a", 1.0, 0.8).set_delay(0.5)

	# Car name
	if _car_name_label:
		_car_name_label.modulate.a = 0.0
		var name_tween := create_tween()
		name_tween.tween_property(_car_name_label, "modulate:a", 1.0, 0.5).set_delay(1.0)

	# Car appears then fades away (drives off)
	if _car_color_rect:
		_car_color_rect.modulate.a = 0.0
		var car_tween := create_tween()
		car_tween.tween_property(_car_color_rect, "modulate:a", 1.0, 0.5).set_delay(1.3)
		car_tween.tween_property(_car_color_rect, "modulate:a", 0.2, 1.5).set_delay(0.8).set_ease(Tween.EASE_IN)

	# Silhouette overlay fades in as car leaves
	if _car_silhouette and _car_silhouette.visible:
		_car_silhouette.modulate.a = 0.0
		var sil_tween := create_tween()
		sil_tween.tween_property(_car_silhouette, "modulate:a", 1.0, 1.0).set_delay(2.5)

	# Stats briefly visible then dim
	_stagger_stats_reveal(1.5)

	# Message
	if _message_label:
		_message_label.modulate.a = 0.0
		var msg_tween := create_tween()
		msg_tween.tween_property(_message_label, "modulate:a", 1.0, 0.5).set_delay(3.5)

	# Opponent reaction
	if _opponent_reaction_label and _opponent_reaction_label.visible:
		_opponent_reaction_label.modulate.a = 0.0
		var react_tween := create_tween()
		react_tween.tween_property(_opponent_reaction_label, "modulate:a", 1.0, 0.4).set_delay(3.8)

	# Remaining vehicles
	if _remaining_label and _remaining_label.visible:
		_remaining_label.modulate.a = 0.0
		var rem_tween := create_tween()
		rem_tween.tween_property(_remaining_label, "modulate:a", 1.0, 0.4).set_delay(4.2)

	# Continue button
	if _continue_button:
		_continue_button.modulate.a = 0.0
		var btn_tween := create_tween()
		btn_tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3).set_delay(4.8)


func _stagger_stats_reveal(start_delay: float) -> void:
	## Reveal stat labels one by one with staggered delay.
	if _stats_grid == null:
		return
	var delay := start_delay
	for child in _stats_grid.get_children():
		if child is Label:
			child.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(delay)
			delay += 0.15


# ---------------------------------------------------------------------------
# Continue
# ---------------------------------------------------------------------------

func _on_continue() -> void:
	hide_result()
	result_acknowledged.emit()
	print("[PinkSlip] Result acknowledged (%s)" % ("WIN" if _is_win else "LOSS"))


func hide_result() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): visible = false; modulate.a = 1.0)


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _format_number(value: int) -> String:
	var s := str(value)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
