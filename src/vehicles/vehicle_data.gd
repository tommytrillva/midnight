## Data class representing a vehicle's complete state.
## Includes base specs, installed parts, cosmetics, wear, and affinity.
class_name VehicleData
extends Resource

# --- Identity ---
@export var vehicle_id: String = ""
@export var display_name: String = ""
@export var manufacturer: String = ""
@export var year: int = 1995
@export var body_style: String = "" # coupe, sedan, hatchback
@export var culture: String = "jdm" # jdm, american, euro
@export var description: String = ""

# --- Base Stats (before mods) ---
@export var base_speed: float = 100.0
@export var base_acceleration: float = 50.0
@export var base_handling: float = 50.0
@export var base_braking: float = 50.0
@export var base_durability: float = 100.0

# --- Engine Specs ---
@export var engine_type: String = "i4" # i4, i6, v6, v8, rotary, boxer
@export var displacement_cc: int = 2000
@export var stock_hp: float = 150.0
@export var stock_torque: float = 140.0
@export var redline_rpm: int = 7000
@export var weight_kg: float = 1200.0
@export var drivetrain: String = "rwd" # fwd, rwd, awd

# --- Installed Parts (slot -> part_id) ---
@export var installed_parts: Dictionary = {
	"engine_internals": "",
	"turbo": "",
	"exhaust": "",
	"intake": "",
	"ecu": "",
	"transmission": "",
	"clutch": "",
	"differential": "",
	"suspension": "",
	"brakes": "",
	"tires": "",
	"wheels": "",
	"body_kit": "",
	"spoiler": "",
	"roll_cage": "",
	"nitrous": "",
}

# --- Cosmetics ---
@export var paint_color: Color = Color(0.5, 0.5, 0.5)
@export var decal_ids: Array[String] = []
@export var interior_style: String = "stock"
@export var headlight_style: String = "stock"
@export var exhaust_tip_style: String = "stock"

# --- Dynamic State ---
@export var current_hp: float = 150.0
@export var current_torque: float = 140.0
@export var wear_percentage: float = 0.0 # 0-100, affects performance
@export var damage_percentage: float = 0.0 # 0-100, from collisions
@export var odometer_km: float = 0.0
@export var affinity: float = 0.0 # 0-100, improves with use

# --- Provenance ---
@export var acquired_method: String = "purchased" # purchased, won_pink_slip, story, built
@export var acquired_timestamp: String = ""
@export var race_history: Array[Dictionary] = [] # [{race_id, result, date}]
@export var estimated_value: int = 0


func get_effective_stats() -> Dictionary:
	## Returns stats after applying mods, wear, and damage penalties.
	var wear_mult := 1.0 - (wear_percentage * 0.002) # Max 20% penalty at 100% wear
	var damage_mult := 1.0 - (damage_percentage * 0.005) # Max 50% penalty at 100% damage
	var affinity_bonus := affinity * 0.001 # Max 10% bonus at 100 affinity
	var total_mult := wear_mult * damage_mult * (1.0 + affinity_bonus)

	# "speed" and "top_speed" are treated as the same stat for part bonuses
	var speed_bonus := _get_part_bonus("speed") + _get_part_bonus("top_speed")

	return {
		"speed": base_speed * total_mult + speed_bonus,
		"top_speed": base_speed * total_mult + speed_bonus,
		"acceleration": base_acceleration * total_mult + _get_part_bonus("acceleration"),
		"handling": base_handling * total_mult + _get_part_bonus("handling"),
		"braking": base_braking * total_mult + _get_part_bonus("braking"),
		"durability": base_durability * (1.0 - damage_percentage * 0.005),
		"hp": current_hp * wear_mult,
		"torque": current_torque * wear_mult,
		"weight": weight_kg + _get_part_weight_delta(),
		"drift_bonus": _get_part_bonus("drift_bonus"),
		"nitro_capacity": _get_part_bonus("nitro_capacity"),
	}


func _get_part_bonus(stat_name: String) -> float:
	var bonus := 0.0
	for slot in installed_parts:
		var part_id: String = installed_parts[slot]
		if part_id.is_empty():
			continue
		var part := PartDatabase.get_part(part_id)
		if part and part.has("stat_bonuses") and part.stat_bonuses.has(stat_name):
			bonus += part.stat_bonuses[stat_name]
	return bonus


func _get_part_weight_delta() -> float:
	var delta := 0.0
	for slot in installed_parts:
		var part_id: String = installed_parts[slot]
		if part_id.is_empty():
			continue
		var part := PartDatabase.get_part(part_id)
		if part and part.has("weight_delta"):
			delta += part.weight_delta
	return delta


func apply_wear(amount: float) -> void:
	wear_percentage = clampf(wear_percentage + amount, 0.0, 100.0)


func apply_damage(amount: float) -> void:
	damage_percentage = clampf(damage_percentage + amount, 0.0, 100.0)
	if damage_percentage >= 100.0:
		EventBus.vehicle_totaled.emit(vehicle_id.hash())


func repair(amount: float) -> void:
	damage_percentage = clampf(damage_percentage - amount, 0.0, 100.0)


func service() -> void:
	## Full service: resets wear, costs money (handled by economy).
	wear_percentage = 0.0


func add_affinity(amount: float) -> void:
	affinity = clampf(affinity + amount, 0.0, 100.0)


func add_race_to_history(race_id: String, result: String) -> void:
	race_history.append({
		"race_id": race_id,
		"result": result,
		"date": Time.get_datetime_string_from_system(),
	})
	odometer_km += randf_range(2.0, 15.0)
	add_affinity(1.0)


func calculate_value() -> int:
	## Estimate vehicle market value based on base + mods - wear.
	var base_value := int(stock_hp * 50 + base_speed * 20)
	var mod_value := 0
	for slot in installed_parts:
		var part_id: String = installed_parts[slot]
		if not part_id.is_empty():
			var part := PartDatabase.get_part(part_id)
			if part:
				mod_value += part.get("price", 0)
	var condition_mult := 1.0 - (wear_percentage * 0.003) - (damage_percentage * 0.005)
	estimated_value = int((base_value + mod_value) * maxf(condition_mult, 0.1))
	return estimated_value
