## Police heat and pursuit system per GDD Section 6.4.
## Tracks heat level (0-4), manages pursuit state, and applies bust consequences.
class_name PoliceSystem
extends Node

enum HeatLevel { CLEAN, NOTICED, WANTED, PURSUIT, MANHUNT }

const HEAT_NAMES := ["Clean", "Noticed", "Wanted", "Pursuit", "Manhunt"]

var heat_level: int = HeatLevel.CLEAN
var heat_decay_timer: float = 0.0
var in_pursuit: bool = false
var pursuit_duration: float = 0.0

# Heat decay rates (seconds between decay ticks)
const HEAT_DECAY_INTERVAL := 30.0
const PURSUIT_TIMEOUT := 120.0 # Escape after 2 min without being spotted


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.FREE_ROAM:
		return

	if in_pursuit:
		pursuit_duration += delta
		if pursuit_duration >= PURSUIT_TIMEOUT:
			escape_pursuit()
	elif heat_level > HeatLevel.CLEAN:
		heat_decay_timer += delta
		if heat_decay_timer >= HEAT_DECAY_INTERVAL:
			heat_decay_timer = 0.0
			_decay_heat()


func add_heat(amount: int) -> void:
	# Apply skill modifier
	var mult := 1.0
	if GameManager.skills.has_skill("ss_7"):
		mult = 0.7
	amount = int(float(amount) * mult)

	var old := heat_level
	heat_level = clampi(heat_level + amount, HeatLevel.CLEAN, HeatLevel.MANHUNT)
	if heat_level != old:
		EventBus.heat_level_changed.emit(old, heat_level)

	if heat_level >= HeatLevel.PURSUIT and not in_pursuit:
		_start_pursuit()


func _decay_heat() -> void:
	if heat_level > HeatLevel.CLEAN:
		var old := heat_level
		heat_level -= 1
		EventBus.heat_level_changed.emit(old, heat_level)


func _start_pursuit() -> void:
	in_pursuit = true
	pursuit_duration = 0.0
	EventBus.pursuit_started.emit()
	print("[Police] Pursuit started! Heat: %s" % HEAT_NAMES[heat_level])


func escape_pursuit() -> void:
	in_pursuit = false
	pursuit_duration = 0.0
	heat_level = HeatLevel.NOTICED
	EventBus.pursuit_escaped.emit()
	print("[Police] Pursuit escaped!")


func get_busted() -> void:
	in_pursuit = false
	pursuit_duration = 0.0

	var vehicle_id := GameManager.player_data.current_vehicle_id
	var vehicle := GameManager.garage.get_vehicle(vehicle_id)
	var fine := 500
	if vehicle:
		fine = int(vehicle.calculate_value() * randf_range(0.05, 0.15))

	GameManager.economy.spend(fine, "police_fine")
	GameManager.reputation.lose_rep(randi_range(200, 1000), "busted")
	EventBus.vehicle_impounded.emit(vehicle_id)
	EventBus.busted.emit(fine)

	heat_level = HeatLevel.CLEAN
	print("[Police] BUSTED! Fine: $%d" % fine)


func get_heat_name() -> String:
	return HEAT_NAMES[heat_level]


func reset() -> void:
	heat_level = HeatLevel.CLEAN
	heat_decay_timer = 0.0
	in_pursuit = false
	pursuit_duration = 0.0


func serialize() -> Dictionary:
	return {
		"heat_level": heat_level,
	}


func deserialize(data: Dictionary) -> void:
	heat_level = data.get("heat_level", HeatLevel.CLEAN)
	in_pursuit = false
	pursuit_duration = 0.0
