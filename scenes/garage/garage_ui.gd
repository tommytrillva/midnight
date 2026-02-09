## Garage UI for viewing vehicle stats, installing parts, and managing
## the player's ride. Connects to GarageSystem, EconomySystem, and PartDatabase.
extends Control

@onready var vehicle_name_label: Label = $VehicleName
@onready var stats_panel: VBoxContainer = $StatsPanel
@onready var part_slots: VBoxContainer = $PartsList/PartsScroll/PartSlots
@onready var shop_panel: VBoxContainer = $ShopPanel
@onready var shop_items: VBoxContainer = $ShopPanel/ShopScroll/ShopItems
@onready var cash_label: Label = $CashLabel
@onready var repair_btn: Button = $Buttons/RepairBtn
@onready var service_btn: Button = $Buttons/ServiceBtn
@onready var exit_btn: Button = $Buttons/ExitBtn

var _current_vehicle: VehicleData = null
var _selected_slot: String = ""


func _ready() -> void:
	repair_btn.pressed.connect(_on_repair)
	service_btn.pressed.connect(_on_service)
	exit_btn.pressed.connect(_on_exit)
	EventBus.cash_changed.connect(func(_o, n): cash_label.text = "$%d" % n)


func refresh() -> void:
	var vid := GameManager.player_data.current_vehicle_id
	_current_vehicle = GameManager.garage.get_vehicle(vid)
	if _current_vehicle == null:
		return

	vehicle_name_label.text = "%s %s" % [_current_vehicle.manufacturer, _current_vehicle.display_name]
	cash_label.text = "$%d" % GameManager.economy.cash

	_refresh_stats()
	_refresh_parts()
	shop_panel.visible = false


func _refresh_stats() -> void:
	if _current_vehicle == null:
		return
	var stats := _current_vehicle.get_effective_stats()
	var labels := stats_panel.get_children()
	if labels.size() >= 8:
		labels[0].text = "SPEED: %.0f" % stats.speed
		labels[1].text = "ACCEL: %.0f" % stats.acceleration
		labels[2].text = "HANDLING: %.0f" % stats.handling
		labels[3].text = "BRAKING: %.0f" % stats.braking
		labels[4].text = "HP: %.0f" % stats.hp
		labels[5].text = "WEIGHT: %.0f KG" % stats.weight
		labels[6].text = "WEAR: %.0f%%" % _current_vehicle.wear_percentage
		labels[7].text = "DAMAGE: %.0f%%" % _current_vehicle.damage_percentage


func _refresh_parts() -> void:
	# Clear existing
	for child in part_slots.get_children():
		child.queue_free()

	if _current_vehicle == null:
		return

	# Create a button per part slot
	for slot_name in _current_vehicle.installed_parts:
		var part_id: String = _current_vehicle.installed_parts[slot_name]
		var display: String = slot_name.replace("_", " ").capitalize()
		var part_name := "Empty"
		if not part_id.is_empty():
			var part := PartDatabase.get_part(part_id)
			if not part.is_empty():
				part_name = part.get("name", part_id)

		var btn := Button.new()
		btn.text = "%s: %s" % [display, part_name]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var slot: String = slot_name
		btn.pressed.connect(func(): _on_slot_selected(slot))
		part_slots.add_child(btn)


func _on_slot_selected(slot: String) -> void:
	_selected_slot = slot
	_show_shop(slot)


func _show_shop(slot: String) -> void:
	shop_panel.visible = true

	for child in shop_items.get_children():
		child.queue_free()

	var vid := _current_vehicle.vehicle_id
	var available := PartDatabase.get_parts_for_slot(slot, PartDatabase.TIER_SPORT) # MVP: max Sport tier
	var current_part_id: String = _current_vehicle.installed_parts.get(slot, "")

	for part_data in available:
		var pid: String = part_data.get("id", "")
		if pid == current_part_id:
			continue # Don't show already installed part

		var price: int = part_data.get("price", 0)
		var name: String = part_data.get("name", pid)
		var tier: int = part_data.get("tier", 1)
		var tier_label: String = ["", "Stock", "Street", "Sport", "Race", "Elite", "Legendary"][clampi(tier, 0, 6)]

		var btn := Button.new()
		btn.text = "%s [%s] — $%d" % [name, tier_label, price]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = not GameManager.economy.can_afford(price)

		var part_id := pid
		btn.pressed.connect(func(): _buy_and_install(part_id, price))
		shop_items.add_child(btn)


func _buy_and_install(part_id: String, price: int) -> void:
	if not GameManager.economy.can_afford(price):
		EventBus.hud_message.emit("Not enough cash!", 2.0)
		return

	GameManager.economy.spend(price, "part_%s" % part_id)
	var success := GameManager.garage.install_part(
		_current_vehicle.vehicle_id, _selected_slot, part_id
	)
	if success:
		EventBus.hud_message.emit("Part installed!", 2.0)
		refresh()
	else:
		# Refund
		GameManager.economy.earn(price, "refund_%s" % part_id)
		EventBus.hud_message.emit("Missing prerequisite!", 2.0)


func _on_repair() -> void:
	if _current_vehicle == null:
		return
	var cost := GameManager.garage.repair_vehicle(_current_vehicle.vehicle_id)
	if cost > 0 and GameManager.economy.can_afford(cost):
		GameManager.economy.spend(cost, "repair")
		_refresh_stats()
		EventBus.hud_message.emit("Vehicle repaired! -$%d" % cost, 2.0)
	elif cost == 0:
		EventBus.hud_message.emit("No damage to repair.", 2.0)
	else:
		EventBus.hud_message.emit("Not enough cash!", 2.0)


func _on_service() -> void:
	if _current_vehicle == null:
		return
	var cost := GameManager.garage.service_vehicle(_current_vehicle.vehicle_id)
	if cost > 0 and GameManager.economy.can_afford(cost):
		GameManager.economy.spend(cost, "service")
		_refresh_stats()
		EventBus.hud_message.emit("Vehicle serviced! -$%d" % cost, 2.0)
	elif cost == 0:
		EventBus.hud_message.emit("No wear to service.", 2.0)
	else:
		EventBus.hud_message.emit("Not enough cash!", 2.0)


func _on_exit() -> void:
	# Tell the free roam parent to close garage
	var parent := get_parent()
	if parent and parent.has_method("close_garage"):
		parent.close_garage()
