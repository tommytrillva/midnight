## Free-roam HUD showing time, weather, cash, REP, heat level,
## and current district. Visible during exploration.
extends CanvasLayer

signal skills_button_pressed

@onready var time_label: Label = $HUD/TopBar/Time
@onready var weather_label: Label = $HUD/TopBar/Weather
@onready var cash_label: Label = $HUD/TopBar/Cash
@onready var rep_label: Label = $HUD/TopBar/REP
@onready var rep_bar: ProgressBar = $HUD/TopBar/REPBar
@onready var heat_indicator: Label = $HUD/BottomBar/Heat
@onready var district_label: Label = $HUD/BottomBar/District
@onready var speed_label: Label = $HUD/BottomBar/Speed
@onready var skills_button: Button = $HUD/TopBar/SkillsBtn
@onready var notification: Label = $HUD/Notification

var _notif_timer: float = 0.0

const HEAT_COLORS := {
	0: Color(0.3, 0.8, 0.3), # Green - clean
	1: Color(0.9, 0.9, 0.2), # Yellow - noticed
	2: Color(1.0, 0.5, 0.0), # Orange - wanted
	3: Color(1.0, 0.2, 0.2), # Red - pursuit
	4: Color(1.0, 0.0, 0.0), # Bright red - manhunt
}


func _ready() -> void:
	EventBus.cash_changed.connect(_on_cash_changed)
	EventBus.rep_changed.connect(_on_rep_changed)
	EventBus.rep_tier_changed.connect(_on_rep_tier_changed)
	EventBus.heat_level_changed.connect(_on_heat_changed)
	EventBus.time_period_changed.connect(_on_time_changed)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.district_entered.connect(_on_district_entered)
	EventBus.hud_message.connect(show_notification)
	EventBus.notification_popup.connect(_on_notification)

	# Skills button
	if skills_button:
		skills_button.pressed.connect(_on_skills_pressed)

	notification.visible = false
	_refresh_all()


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return

	# Update time display
	time_label.text = GameManager.world_time.get_display_time()

	# Notification timer
	if _notif_timer > 0:
		_notif_timer -= delta
		if _notif_timer <= 0:
			notification.visible = false


func _refresh_all() -> void:
	cash_label.text = "$%s" % _format_number(GameManager.economy.cash)
	rep_label.text = "%s — %s" % [
		GameManager.reputation.get_tier_name(),
		_format_number(GameManager.reputation.current_rep)
	]
	rep_bar.value = GameManager.reputation.get_tier_progress() * 100.0
	_update_heat(GameManager.police.heat_level)
	district_label.text = GameManager.player_data.current_district.capitalize()
	weather_label.text = GameManager.world_time.current_weather.replace("_", " ").capitalize()


func show_notification(text: String, duration: float = 3.0) -> void:
	notification.text = text
	notification.visible = true
	_notif_timer = duration


func _on_cash_changed(_old: int, new_val: int) -> void:
	cash_label.text = "$%s" % _format_number(new_val)


func _on_rep_changed(_old: int, new_val: int) -> void:
	rep_label.text = "%s — %s" % [
		GameManager.reputation.get_tier_name(),
		_format_number(new_val)
	]
	rep_bar.value = GameManager.reputation.get_tier_progress() * 100.0


func _on_rep_tier_changed(_old: int, _new: int) -> void:
	show_notification("REP TIER UP: %s" % GameManager.reputation.get_tier_name(), 5.0)


func _on_heat_changed(_old: int, new_level: int) -> void:
	_update_heat(new_level)


func _update_heat(level: int) -> void:
	heat_indicator.text = GameManager.police.get_heat_name().to_upper()
	heat_indicator.modulate = HEAT_COLORS.get(level, Color.WHITE)
	heat_indicator.visible = level > 0


func _on_time_changed(period: String) -> void:
	show_notification(period.replace("_", " ").capitalize(), 2.0)


func _on_weather_changed(condition: String) -> void:
	weather_label.text = condition.replace("_", " ").capitalize()


func _on_district_entered(district_id: String) -> void:
	district_label.text = district_id.capitalize()
	show_notification("Entering: %s" % district_id.replace("_", " ").capitalize(), 2.0)


func _on_notification(title: String, body: String, _icon: String) -> void:
	show_notification("%s: %s" % [title, body], 4.0)


func _on_skills_pressed() -> void:
	skills_button_pressed.emit()


func _format_number(num: int) -> String:
	var s := str(num)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		count += 1
		if count % 3 == 0 and i > 0:
			result = "," + result
	return result
