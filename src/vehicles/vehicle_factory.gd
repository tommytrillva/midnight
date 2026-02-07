## Factory for creating VehicleData instances from JSON data files.
## Bridges the data layer (JSON) to the runtime layer (VehicleData Resource).
class_name VehicleFactory
extends RefCounted


static func create_from_json(vehicle_id: String) -> VehicleData:
	var path := "res://data/vehicles/%s.json" % vehicle_id
	if not FileAccess.file_exists(path):
		push_error("[VehicleFactory] Vehicle data not found: %s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[VehicleFactory] Failed to parse: %s" % path)
		return null
	file.close()

	var data: Dictionary = json.data
	return create_from_dict(data)


static func create_from_dict(data: Dictionary) -> VehicleData:
	var v := VehicleData.new()
	v.vehicle_id = data.get("vehicle_id", "")
	v.display_name = data.get("display_name", "Unknown")
	v.manufacturer = data.get("manufacturer", "")
	v.year = data.get("year", 1995)
	v.body_style = data.get("body_style", "")
	v.culture = data.get("culture", "jdm")
	v.description = data.get("description", "")
	v.base_speed = data.get("base_speed", 50.0)
	v.base_acceleration = data.get("base_acceleration", 50.0)
	v.base_handling = data.get("base_handling", 50.0)
	v.base_braking = data.get("base_braking", 50.0)
	v.base_durability = data.get("base_durability", 100.0)
	v.engine_type = data.get("engine_type", "i4")
	v.displacement_cc = data.get("displacement_cc", 2000)
	v.stock_hp = data.get("stock_hp", 150.0)
	v.stock_torque = data.get("stock_torque", 140.0)
	v.redline_rpm = data.get("redline_rpm", 7000)
	v.weight_kg = data.get("weight_kg", 1200.0)
	v.drivetrain = data.get("drivetrain", "rwd")
	v.current_hp = v.stock_hp
	v.current_torque = v.stock_torque
	v.estimated_value = data.get("starting_value", 500)
	v.wear_percentage = data.get("starting_wear", 0.0)
	v.damage_percentage = data.get("starting_damage", 0.0)
	return v
