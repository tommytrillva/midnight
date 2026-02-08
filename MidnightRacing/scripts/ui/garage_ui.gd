extends Control

# Garage UI - Vehicle customization and upgrades

@onready var vehicle_name_label = $VehicleInfo/NameLabel
@onready var stats_panel = $VehicleInfo/StatsPanel
@onready var parts_list = $PartsPanel/PartsList
@onready var install_button = $PartsPanel/InstallButton
@onready var exit_button = $ExitButton

var current_vehicle = null
var selected_part = null

var available_parts = {
	"engine": [
		{"name": "Stage 1 Turbo", "cost": 2000, "hp_boost": 50, "id": "engine_stage1"},
		{"name": "Stage 2 Turbo", "cost": 5000, "hp_boost": 100, "id": "engine_stage2"},
		{"name": "Stage 3 Turbo", "cost": 10000, "hp_boost": 200, "id": "engine_stage3"}
	],
	"nitrous": [
		{"name": "NOS Kit", "cost": 1500, "boost": 50, "id": "nitrous_basic"},
		{"name": "NOS Pro Kit", "cost": 3000, "boost": 100, "id": "nitrous_pro"}
	],
	"suspension": [
		{"name": "Sport Suspension", "cost": 1000, "handling_boost": 1.5, "id": "suspension_sport"},
		{"name": "Race Suspension", "cost": 2500, "handling_boost": 2.5, "id": "suspension_race"}
	]
}

func _ready():
	# Load current vehicle
	current_vehicle = GameManager.get_current_vehicle()
	if current_vehicle:
		update_vehicle_display()
		populate_parts_list()

	# Connect buttons
	install_button.pressed.connect(_on_install_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func update_vehicle_display():
	"""Update vehicle info display"""
	if vehicle_name_label:
		vehicle_name_label.text = current_vehicle.name

	if stats_panel:
		var stats_text = ""
		stats_text += "HP: %d\n" % current_vehicle.hp
		stats_text += "Torque: %d\n" % current_vehicle.torque
		stats_text += "Top Speed: %d MPH\n" % current_vehicle.top_speed
		stats_text += "Handling: %.1f\n" % current_vehicle.handling

		if stats_panel.has_node("StatsLabel"):
			stats_panel.get_node("StatsLabel").text = stats_text

func populate_parts_list():
	"""Populate the parts list with available upgrades"""
	if not parts_list:
		return

	# Clear existing items
	for child in parts_list.get_children():
		child.queue_free()

	# Add engine parts
	add_category_header("Engine Upgrades")
	for part in available_parts.engine:
		add_part_item(part, "engine")

	# Add nitrous parts
	add_category_header("Nitrous Systems")
	for part in available_parts.nitrous:
		add_part_item(part, "nitrous")

	# Add suspension parts
	add_category_header("Suspension")
	for part in available_parts.suspension:
		add_part_item(part, "suspension")

func add_category_header(category_name: String):
	"""Add a category header to the parts list"""
	var header = Label.new()
	header.text = "=== " + category_name + " ==="
	header.add_theme_font_size_override("font_size", 24)
	parts_list.add_child(header)

func add_part_item(part: Dictionary, category: String):
	"""Add a part item to the list"""
	var button = Button.new()
	var already_installed = current_vehicle.parts[category] == part.id

	if already_installed:
		button.text = "%s - INSTALLED" % part.name
		button.disabled = true
	else:
		button.text = "%s - $%d" % [part.name, part.cost]

	button.pressed.connect(_on_part_selected.bind(part, category))
	parts_list.add_child(button)

func _on_part_selected(part: Dictionary, category: String):
	"""Handle part selection"""
	selected_part = {"part": part, "category": category}
	print("Selected part: ", part.name)

	if install_button:
		install_button.disabled = false
		install_button.text = "Install %s ($%d)" % [part.name, part.cost]

func _on_install_pressed():
	"""Install the selected part"""
	if not selected_part:
		return

	var part = selected_part.part
	var category = selected_part.category

	# Check if player has enough cash
	if GameManager.spend_cash(part.cost):
		# Install the part
		current_vehicle.parts[category] = part.id

		# Apply stat boosts
		if part.has("hp_boost"):
			current_vehicle.hp += part.hp_boost
		if part.has("handling_boost"):
			current_vehicle.handling += part.handling_boost

		print("Installed: ", part.name)

		# Update displays
		update_vehicle_display()
		populate_parts_list()

		# Clear selection
		selected_part = null
		install_button.disabled = true
		install_button.text = "Install Part"

		# Complete "first_upgrade" mission if exists
		if StoryManager.is_mission_available("first_upgrade"):
			StoryManager.complete_mission("first_upgrade")
	else:
		print("Not enough cash!")

func _on_exit_pressed():
	"""Exit garage and return to free roam"""
	GameManager.load_scene("res://scenes/districts/downtown.tscn")
