extends Node3D

# Vehicle Test Scene - Integration test for HUD data binding

@onready var vehicle = $HondaCRXSi
@onready var race_hud = $CanvasLayer/RaceHUD
@onready var freeroam_hud = $CanvasLayer/FreeRoamHUD
@onready var status_label = $CanvasLayer/TestControls/StatusLabel
@onready var speed_check = $CanvasLayer/TestControls/SpeedCheck
@onready var rpm_check = $CanvasLayer/TestControls/RPMCheck
@onready var gear_check = $CanvasLayer/TestControls/GearCheck

var using_race_hud = true
var speed_signal_received = false
var rpm_signal_received = false
var gear_signal_received = false

func _ready():
	# Initialize GameManager with test data
	initialize_test_data()

	# Wait a frame for HUDs to initialize
	await get_tree().process_frame
	await get_tree().process_frame

	# Verify vehicle exists and is in the correct group
	if vehicle:
		print("[TEST] Vehicle found: ", vehicle.name)
		print("[TEST] Vehicle in player_vehicle group: ", vehicle.is_in_group("player_vehicle"))
	else:
		print("[TEST ERROR] Vehicle not found!")
		status_label.text = "ERROR: Vehicle not found!"
		return

	# Connect to vehicle signals for testing
	if vehicle.has_signal("speed_changed"):
		vehicle.speed_changed.connect(_on_test_speed_changed)
		print("[TEST] Connected to speed_changed signal")
	else:
		print("[TEST ERROR] Vehicle missing speed_changed signal!")

	if vehicle.has_signal("rpm_changed"):
		vehicle.rpm_changed.connect(_on_test_rpm_changed)
		print("[TEST] Connected to rpm_changed signal")
	else:
		print("[TEST ERROR] Vehicle missing rpm_changed signal!")

	if vehicle.has_signal("gear_changed"):
		vehicle.gear_changed.connect(_on_test_gear_changed)
		print("[TEST] Connected to gear_changed signal")
	else:
		print("[TEST ERROR] Vehicle missing gear_changed signal!")

	# Wait another frame and check HUD connections
	await get_tree().process_frame
	verify_hud_connections()

	# Start test monitoring
	status_label.text = "Status: Ready - Drive to test!"
	print("[TEST] Test scene ready!")

func initialize_test_data():
	"""Initialize GameManager with test vehicle data"""
	if GameManager:
		# Set up player data for testing
		GameManager.player_data.cash = 5000
		GameManager.player_data.reputation = 100
		GameManager.player_data.garage = [{
			"id": "honda_crx_si",
			"name": "Honda CRX Si",
			"make": "Honda",
			"model": "CRX Si",
			"year": 1991,
			"hp": 108,
			"torque": 100,
			"weight": 2200,
			"top_speed": 125,
			"acceleration": 8.5,
			"handling": 7.5,
			"parts": {
				"engine": "stock",
				"transmission": "stock",
				"suspension": "stock",
				"tires": "stock",
				"brakes": "stock",
				"body": "stock",
				"nitrous": true
			},
			"visual_mods": {
				"paint": "red",
				"vinyl": null,
				"wheels": "stock",
				"spoiler": null,
				"body_kit": null
			}
		}]
		GameManager.player_data.current_vehicle = "honda_crx_si"
		print("[TEST] GameManager initialized with test data")
	else:
		print("[TEST WARNING] GameManager not found - HUD cash/rep may not work")

func verify_hud_connections():
	"""Verify that HUDs are properly connected to the vehicle"""
	print("\n[TEST] Verifying HUD connections...")

	# Check Race HUD
	if race_hud and race_hud.vehicle:
		print("[TEST] Race HUD connected to vehicle: ", race_hud.vehicle.name)
	else:
		print("[TEST WARNING] Race HUD not connected to vehicle!")

	# Check Free Roam HUD
	if freeroam_hud and freeroam_hud.vehicle:
		print("[TEST] Free Roam HUD connected to vehicle: ", freeroam_hud.vehicle.name)
	else:
		print("[TEST WARNING] Free Roam HUD not connected to vehicle!")

	# Verify all required HUD elements exist
	verify_hud_elements()

func verify_hud_elements():
	"""Verify all HUD UI elements exist"""
	print("\n[TEST] Verifying HUD UI elements...")

	# Race HUD elements
	var race_elements = [
		"SpeedLabel", "RPMBar", "GearLabel",
		"PositionLabel", "LapLabel", "LapTimeLabel", "NitrousBar"
	]
	for element in race_elements:
		var node = race_hud.get_node_or_null(element)
		if node:
			print("[TEST] Race HUD - %s: OK" % element)
		else:
			print("[TEST ERROR] Race HUD - %s: MISSING!" % element)

	# Free Roam HUD elements
	var freeroam_elements = ["SpeedLabel", "CashLabel", "RepLabel", "NotificationPanel"]
	for element in freeroam_elements:
		var node = freeroam_hud.get_node_or_null(element)
		if node:
			print("[TEST] Free Roam HUD - %s: OK" % element)
		else:
			print("[TEST ERROR] Free Roam HUD - %s: MISSING!" % element)

func _process(_delta):
	# Update signal status indicators
	if speed_signal_received:
		speed_check.text = "Speed Signal: OK (Receiving)"
		speed_check.modulate = Color.GREEN

	if rpm_signal_received:
		rpm_check.text = "RPM Signal: OK (Receiving)"
		rpm_check.modulate = Color.GREEN

	if gear_signal_received:
		gear_check.text = "Gear Signal: OK (Receiving)"
		gear_check.modulate = Color.GREEN

func _on_test_speed_changed(speed: float):
	"""Test callback for speed changes"""
	speed_signal_received = true
	if not speed_check.modulate == Color.GREEN:
		print("[TEST] Speed signal received: %.1f MPH" % speed)

func _on_test_rpm_changed(rpm: float):
	"""Test callback for RPM changes"""
	rpm_signal_received = true
	if not rpm_check.modulate == Color.GREEN:
		print("[TEST] RPM signal received: %.1f" % rpm)

func _on_test_gear_changed(gear: int):
	"""Test callback for gear changes"""
	gear_signal_received = true
	if not gear_check.modulate == Color.GREEN:
		print("[TEST] Gear signal received: %d" % gear)

func _on_toggle_hud_pressed():
	"""Toggle between Race HUD and Free Roam HUD"""
	using_race_hud = !using_race_hud
	race_hud.visible = using_race_hud
	freeroam_hud.visible = !using_race_hud

	var mode = "Race HUD" if using_race_hud else "Free Roam HUD"
	print("[TEST] Switched to: ", mode)
	status_label.text = "Status: " + mode

func _on_refill_nitrous_pressed():
	"""Refill vehicle nitrous"""
	if vehicle:
		vehicle.refill_nitrous()
		print("[TEST] Nitrous refilled")

func _on_add_cash_pressed():
	"""Add cash for testing Free Roam HUD"""
	if GameManager:
		GameManager.add_cash(1000)
		if freeroam_hud:
			freeroam_hud.update_cash_display()
		print("[TEST] Added $1000 cash")

func _on_add_rep_pressed():
	"""Add reputation for testing Free Roam HUD"""
	if GameManager:
		GameManager.add_reputation(50)
		if freeroam_hud:
			freeroam_hud.update_rep_display()
		print("[TEST] Added +50 reputation")
