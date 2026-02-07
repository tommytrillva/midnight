## In-race HUD showing speed, position, lap, time, and minimap.
## Adapts based on race type.
extends CanvasLayer

@onready var speed_label: Label = $HUD/SpeedPanel/Speed
@onready var gear_label: Label = $HUD/SpeedPanel/Gear
@onready var rpm_bar: ProgressBar = $HUD/SpeedPanel/RPMBar
@onready var position_label: Label = $HUD/RaceInfo/Position
@onready var lap_label: Label = $HUD/RaceInfo/Lap
@onready var time_label: Label = $HUD/RaceInfo/Time
@onready var countdown_label: Label = $HUD/Countdown
@onready var nitro_bar: ProgressBar = $HUD/NitroBar
@onready var message_label: Label = $HUD/Message

var _message_timer: float = 0.0


func _ready() -> void:
	EventBus.race_countdown_tick.connect(_on_countdown)
	EventBus.race_started.connect(_on_race_started)
	EventBus.race_finished.connect(_on_race_finished)
	EventBus.race_position_changed.connect(_on_position_changed)
	EventBus.lap_completed.connect(_on_lap_completed)
	EventBus.hud_message.connect(show_message)
	EventBus.gear_shifted.connect(_on_gear_shifted)
	countdown_label.visible = false
	message_label.visible = false


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.RACING:
		return

	# Update time
	if GameManager.race_manager.current_state == RaceManager.RaceState.RACING:
		time_label.text = _format_time(GameManager.race_manager.race_timer)

	# Message timer
	if _message_timer > 0:
		_message_timer -= delta
		if _message_timer <= 0:
			message_label.visible = false


func update_speed(speed_kmh: float) -> void:
	speed_label.text = "%d" % int(speed_kmh)


func update_rpm(rpm: float, max_rpm: float) -> void:
	rpm_bar.value = rpm / max_rpm * 100.0


func update_nitro(amount: float, max_amount: float) -> void:
	if max_amount > 0:
		nitro_bar.visible = true
		nitro_bar.value = amount / max_amount * 100.0
	else:
		nitro_bar.visible = false


func show_message(text: String, duration: float = 3.0) -> void:
	message_label.text = text
	message_label.visible = true
	_message_timer = duration


func _on_countdown(count: int) -> void:
	countdown_label.visible = true
	countdown_label.text = str(count)


func _on_race_started(_race_data: Dictionary) -> void:
	countdown_label.text = "GO!"
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(func(): countdown_label.visible = false)


func _on_race_finished(_results: Dictionary) -> void:
	var pos: int = _results.get("player_position", 0)
	show_message(_get_position_text(pos), 5.0)


func _on_position_changed(racer_id: int, new_position: int) -> void:
	if racer_id == 0: # Player
		position_label.text = _get_position_text(new_position)


func _on_lap_completed(racer_id: int, lap: int, _time: float) -> void:
	if racer_id == 0:
		var race := GameManager.race_manager.current_race
		if race:
			lap_label.text = "LAP %d/%d" % [lap, race.lap_count]


func _on_gear_shifted(racer_id: int, gear: int) -> void:
	if racer_id == 0:
		if gear == 0:
			gear_label.text = "N"
		elif gear == -1:
			gear_label.text = "R"
		else:
			gear_label.text = str(gear)


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	var ms := int((seconds - int(seconds)) * 1000)
	return "%d:%02d.%03d" % [mins, secs, ms]


func _get_position_text(pos: int) -> String:
	match pos:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return "%dTH" % pos
