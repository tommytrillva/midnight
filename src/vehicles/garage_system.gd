## Manages the player's garage: vehicle collection, part installation,
## and vehicle acquisition/loss including pink slip outcomes.
class_name GarageSystem
extends Node

var vehicles: Dictionary = {} # vehicle_id -> VehicleData


func _ready() -> void:
	EventBus.pink_slip_won.connect(_on_pink_slip_won)
	EventBus.pink_slip_lost.connect(_on_pink_slip_lost)
	EventBus.vehicle_impounded.connect(_on_vehicle_impounded)


func add_vehicle(vehicle: VehicleData, source: String = "purchased") -> void:
	vehicle.acquired_method = source
	vehicle.acquired_timestamp = Time.get_datetime_string_from_system()
	vehicles[vehicle.vehicle_id] = vehicle
	GameManager.player_data.owned_vehicle_ids.append(vehicle.vehicle_id)
	EventBus.vehicle_acquired.emit(vehicle.vehicle_id, source)
	print("[Garage] Vehicle acquired: %s (%s)" % [vehicle.display_name, source])


func remove_vehicle(vehicle_id: String, reason: String = "sold") -> void:
	if vehicles.has(vehicle_id):
		var vehicle := vehicles[vehicle_id]
		vehicles.erase(vehicle_id)
		GameManager.player_data.owned_vehicle_ids.erase(vehicle_id)
		EventBus.vehicle_lost.emit(vehicle_id, reason)
		print("[Garage] Vehicle lost: %s (%s)" % [vehicle.display_name, reason])


func get_vehicle(vehicle_id: String) -> VehicleData:
	return vehicles.get(vehicle_id)


func get_all_vehicles() -> Array:
	return vehicles.values()


func get_vehicle_count() -> int:
	return vehicles.size()


func install_part(vehicle_id: String, slot: String, part_id: String) -> bool:
	var vehicle := get_vehicle(vehicle_id)
	if vehicle == null:
		push_error("[Garage] Vehicle not found: %s" % vehicle_id)
		return false

	var part := PartDatabase.get_part(part_id)
	if part.is_empty():
		push_error("[Garage] Part not found: %s" % part_id)
		return false

	# Check prerequisites
	var requires: Array = part.get("requires", [])
	for req_id in requires:
		var has_req := false
		for s in vehicle.installed_parts:
			if vehicle.installed_parts[s] == req_id:
				has_req = true
				break
		if not has_req:
			push_warning("[Garage] Missing prerequisite: %s for part %s" % [req_id, part_id])
			return false

	vehicle.installed_parts[slot] = part_id
	_recalculate_vehicle_power(vehicle)
	EventBus.part_installed.emit(vehicle_id, slot, part)
	EventBus.vehicle_stats_changed.emit(vehicle_id, vehicle.get_effective_stats())
	return true


func remove_part(vehicle_id: String, slot: String) -> void:
	var vehicle := get_vehicle(vehicle_id)
	if vehicle == null:
		return
	vehicle.installed_parts[slot] = ""
	_recalculate_vehicle_power(vehicle)
	EventBus.part_removed.emit(vehicle_id, slot)
	EventBus.vehicle_stats_changed.emit(vehicle_id, vehicle.get_effective_stats())


func _recalculate_vehicle_power(vehicle: VehicleData) -> void:
	## Recalculate HP/torque based on installed parts.
	var hp := vehicle.stock_hp
	var torque := vehicle.stock_torque
	for slot in vehicle.installed_parts:
		var part_id: String = vehicle.installed_parts[slot]
		if part_id.is_empty():
			continue
		var part := PartDatabase.get_part(part_id)
		if part.has("hp_bonus"):
			hp += part.hp_bonus
		if part.has("torque_bonus"):
			torque += part.torque_bonus
		# Percentage bonuses (ECU tunes, etc.)
		if part.has("hp_mult"):
			hp *= part.hp_mult
		if part.has("torque_mult"):
			torque *= part.torque_mult
	vehicle.current_hp = hp
	vehicle.current_torque = torque


func get_worst_vehicle_id() -> String:
	## Returns the lowest-value vehicle — used for Act 3 Fall.
	var worst_id := ""
	var worst_value := INF
	for vid in vehicles:
		var v: VehicleData = vehicles[vid]
		var val := v.calculate_value()
		if val < worst_value:
			worst_value = val
			worst_id = vid
	return worst_id


func seize_all_except(keep_vehicle_id: String) -> void:
	## Act 3: The Fall — remove all vehicles except one.
	var to_remove: Array[String] = []
	for vid in vehicles:
		if vid != keep_vehicle_id:
			to_remove.append(vid)
	for vid in to_remove:
		remove_vehicle(vid, "seized_act3")


func repair_vehicle(vehicle_id: String) -> int:
	## Repair a vehicle. Returns the cost.
	var vehicle := get_vehicle(vehicle_id)
	if vehicle == null:
		return 0
	var cost := int(vehicle.damage_percentage * vehicle.calculate_value() * 0.01)
	vehicle.repair(vehicle.damage_percentage)
	return cost


func service_vehicle(vehicle_id: String) -> int:
	## Service a vehicle (reset wear). Returns the cost.
	var vehicle := get_vehicle(vehicle_id)
	if vehicle == null:
		return 0
	var cost := int(vehicle.wear_percentage * 5)
	vehicle.service()
	return cost


func reset() -> void:
	vehicles.clear()


func _on_pink_slip_won(won_vehicle_data: Dictionary) -> void:
	var vehicle := VehicleData.new()
	vehicle.vehicle_id = won_vehicle_data.get("vehicle_id", "")
	vehicle.display_name = won_vehicle_data.get("display_name", "Unknown")
	add_vehicle(vehicle, "won_pink_slip")


func _on_pink_slip_lost(lost_vehicle_data: Dictionary) -> void:
	var lost_id: String = lost_vehicle_data.get("vehicle_id", "")
	remove_vehicle(lost_id, "lost_pink_slip")


func _on_vehicle_impounded(vehicle_id: String) -> void:
	# Vehicle is impounded but not yet lost — player can retrieve it
	print("[Garage] Vehicle impounded: %s" % vehicle_id)


func serialize() -> Dictionary:
	var vehicle_data := {}
	for vid in vehicles:
		# VehicleData is a Resource, serialize its properties manually
		var v: VehicleData = vehicles[vid]
		vehicle_data[vid] = {
			"vehicle_id": v.vehicle_id,
			"display_name": v.display_name,
			"manufacturer": v.manufacturer,
			"year": v.year,
			"body_style": v.body_style,
			"culture": v.culture,
			"base_speed": v.base_speed,
			"base_acceleration": v.base_acceleration,
			"base_handling": v.base_handling,
			"base_braking": v.base_braking,
			"base_durability": v.base_durability,
			"engine_type": v.engine_type,
			"displacement_cc": v.displacement_cc,
			"stock_hp": v.stock_hp,
			"stock_torque": v.stock_torque,
			"redline_rpm": v.redline_rpm,
			"weight_kg": v.weight_kg,
			"drivetrain": v.drivetrain,
			"installed_parts": v.installed_parts,
			"paint_color": [v.paint_color.r, v.paint_color.g, v.paint_color.b],
			"wear_percentage": v.wear_percentage,
			"damage_percentage": v.damage_percentage,
			"odometer_km": v.odometer_km,
			"affinity": v.affinity,
			"acquired_method": v.acquired_method,
			"acquired_timestamp": v.acquired_timestamp,
			"race_history": v.race_history,
			"current_hp": v.current_hp,
			"current_torque": v.current_torque,
		}
	return {"vehicles": vehicle_data}


func deserialize(data: Dictionary) -> void:
	vehicles.clear()
	var vehicle_data: Dictionary = data.get("vehicles", {})
	for vid in vehicle_data:
		var vd: Dictionary = vehicle_data[vid]
		var v := VehicleData.new()
		v.vehicle_id = vd.get("vehicle_id", vid)
		v.display_name = vd.get("display_name", "")
		v.manufacturer = vd.get("manufacturer", "")
		v.year = vd.get("year", 1995)
		v.body_style = vd.get("body_style", "")
		v.culture = vd.get("culture", "jdm")
		v.base_speed = vd.get("base_speed", 100.0)
		v.base_acceleration = vd.get("base_acceleration", 50.0)
		v.base_handling = vd.get("base_handling", 50.0)
		v.base_braking = vd.get("base_braking", 50.0)
		v.base_durability = vd.get("base_durability", 100.0)
		v.engine_type = vd.get("engine_type", "i4")
		v.displacement_cc = vd.get("displacement_cc", 2000)
		v.stock_hp = vd.get("stock_hp", 150.0)
		v.stock_torque = vd.get("stock_torque", 140.0)
		v.redline_rpm = vd.get("redline_rpm", 7000)
		v.weight_kg = vd.get("weight_kg", 1200.0)
		v.drivetrain = vd.get("drivetrain", "rwd")
		v.installed_parts = vd.get("installed_parts", {})
		var pc: Array = vd.get("paint_color", [0.5, 0.5, 0.5])
		v.paint_color = Color(pc[0], pc[1], pc[2])
		v.wear_percentage = vd.get("wear_percentage", 0.0)
		v.damage_percentage = vd.get("damage_percentage", 0.0)
		v.odometer_km = vd.get("odometer_km", 0.0)
		v.affinity = vd.get("affinity", 0.0)
		v.acquired_method = vd.get("acquired_method", "loaded")
		v.acquired_timestamp = vd.get("acquired_timestamp", "")
		v.race_history = vd.get("race_history", [])
		v.current_hp = vd.get("current_hp", v.stock_hp)
		v.current_torque = vd.get("current_torque", v.stock_torque)
		vehicles[vid] = v
