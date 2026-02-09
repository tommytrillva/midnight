## Manages in-game time and weather per GDD Section 8.2.
## 1 real minute = 4 game minutes. Game operates 7PM-6AM (night cycle).
class_name WorldTimeSystem
extends Node

# Time periods
const PERIOD_DUSK := "dusk" # 7PM-9PM
const PERIOD_NIGHT := "night" # 9PM-4AM
const PERIOD_LATE_NIGHT := "late_night" # 12AM-3AM (subset of night)
const PERIOD_DAWN := "dawn" # 4AM-6AM
const PERIOD_DAY := "day" # 6AM-7PM (not normally reachable in gameplay)

# Weather conditions with frequencies from GDD
const WEATHER_TABLE := {
	"clear": 0.70,
	"light_rain": 0.15,
	"heavy_rain": 0.08,
	"fog": 0.05,
	"storm": 0.02,
}

const WEATHER_GRIP := {
	"clear": 1.0,
	"light_rain": 0.85,
	"heavy_rain": 0.70,
	"fog": 0.95,
	"storm": 0.65,
}

const WEATHER_VISIBILITY := {
	"clear": 1.0,
	"light_rain": 0.9,
	"heavy_rain": 0.7,
	"fog": 0.5,
	"storm": 0.6,
}

# Time scale: 1 real minute = 4 game minutes
const TIME_SCALE := 4.0

# Game starts at 7PM (19:00)
var game_hour: float = 19.0 # 0.0-24.0
var current_period: String = PERIOD_DUSK
var current_weather: String = "clear"
var weather_change_timer: float = 0.0
var day_count: int = 1
var _days_per_month: int = 7 # 7 in-game nights = 1 game month

const WEATHER_CHANGE_INTERVAL := 600.0 # Check weather every 10 real minutes


func _process(delta: float) -> void:
	if GameManager.current_state == GameManager.GameState.MENU:
		return
	if GameManager.current_state == GameManager.GameState.PAUSED:
		return

	# Advance time
	var game_delta := delta * TIME_SCALE / 60.0 # Convert to game hours
	game_hour += game_delta

	# Wrap around (6AM -> 7PM next night)
	if game_hour >= 30.0: # 6AM = 30 (24+6)
		game_hour = 19.0
		day_count += 1
		# Emit month_start every _days_per_month days for rent collection
		if day_count % _days_per_month == 0:
			EventBus.time_period_changed.emit("month_start")

	# Handle midnight wrap
	if game_hour >= 24.0 and game_hour < 30.0:
		pass # Keep going, we treat hours > 24 as next day AM

	# Update period
	var new_period := _calculate_period()
	if new_period != current_period:
		current_period = new_period
		EventBus.time_period_changed.emit(current_period)

	# Weather changes
	weather_change_timer += delta
	if weather_change_timer >= WEATHER_CHANGE_INTERVAL:
		weather_change_timer = 0.0
		_roll_weather()


func get_display_time() -> String:
	## Returns formatted time string (e.g., "11:30 PM").
	var hour := int(game_hour) % 24
	var minute := int((game_hour - int(game_hour)) * 60.0)
	var ampm := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, ampm]


func get_grip_multiplier() -> float:
	return WEATHER_GRIP.get(current_weather, 1.0)


func get_visibility() -> float:
	return WEATHER_VISIBILITY.get(current_weather, 1.0)


func get_rain_intensity() -> float:
	## Returns 0.0-1.0 rain intensity for vehicle weather effects.
	match current_weather:
		"light_rain": return 0.3
		"heavy_rain": return 0.7
		"storm": return 1.0
		_: return 0.0


func get_normalized_hour() -> float:
	## Returns current time as a 0.0-24.0 float for lighting calculations.
	return fmod(game_hour, 24.0)


func is_ghost_encounter_possible() -> bool:
	## Ghost has higher chance during late night + fog per GDD.
	var base_chance := 0.01
	if current_period == PERIOD_LATE_NIGHT:
		base_chance *= 2.0
	if current_weather == "fog":
		base_chance *= 3.0
	return randf() < base_chance


func _calculate_period() -> String:
	var h := fmod(game_hour, 24.0)
	if h < 0:
		h += 24.0
	if h >= 19.0 and h < 21.0:
		return PERIOD_DUSK
	elif h >= 21.0 or h < 4.0:
		if (h >= 24.0 or h < 3.0):
			return PERIOD_LATE_NIGHT
		return PERIOD_NIGHT
	elif h >= 4.0 and h < 6.0:
		return PERIOD_DAWN
	return PERIOD_NIGHT


func _roll_weather() -> void:
	var roll := randf()
	var cumulative := 0.0
	var new_weather := "clear"
	for condition in WEATHER_TABLE:
		cumulative += WEATHER_TABLE[condition]
		if roll <= cumulative:
			new_weather = condition
			break

	if new_weather != current_weather:
		current_weather = new_weather
		EventBus.weather_changed.emit(current_weather)
		print("[WorldTime] Weather changed: %s" % current_weather)


func serialize() -> Dictionary:
	return {
		"game_hour": game_hour,
		"current_weather": current_weather,
		"day_count": day_count,
	}


func deserialize(data: Dictionary) -> void:
	game_hour = data.get("game_hour", 19.0)
	current_weather = data.get("current_weather", "clear")
	day_count = data.get("day_count", 1)
	current_period = _calculate_period()
