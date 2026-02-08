extends Control

# Race HUD - Displays speed, RPM, position, lap times during races

@onready var speed_label = $SpeedLabel
@onready var rpm_bar = $RPMBar
@onready var gear_label = $GearLabel
@onready var position_label = $PositionLabel
@onready var lap_label = $LapLabel
@onready var lap_time_label = $LapTimeLabel
@onready var nitrous_bar = $NitrousBar

var vehicle: VehicleBody3D = null
var current_lap = 1
var total_laps = 3
var lap_start_time = 0.0
var best_lap_time = 999.0

func _ready():
	# Find the player vehicle
	await get_tree().process_frame
	find_player_vehicle()

func find_player_vehicle():
	"""Find and connect to the player's vehicle"""
	# Look for vehicle in scene
	var vehicles = get_tree().get_nodes_in_group("player_vehicle")
	if vehicles.size() > 0:
		vehicle = vehicles[0]
		# Connect signals
		if vehicle.has_signal("speed_changed"):
			vehicle.speed_changed.connect(_on_speed_changed)
		if vehicle.has_signal("rpm_changed"):
			vehicle.rpm_changed.connect(_on_rpm_changed)
		if vehicle.has_signal("gear_changed"):
			vehicle.gear_changed.connect(_on_gear_changed)
		print("Race HUD connected to vehicle")
	else:
		print("Warning: No player vehicle found!")

func _process(_delta):
	if vehicle:
		# Update UI elements
		update_gear_display()
		update_nitrous_display()
		update_lap_time()

func _on_speed_changed(speed: float):
	"""Update speed display"""
	if speed_label:
		speed_label.text = "%d MPH" % int(speed)

func _on_rpm_changed(rpm: float):
	"""Update RPM bar"""
	if rpm_bar:
		rpm_bar.value = (rpm / 7000.0) * 100.0  # Convert to percentage (7000 max RPM)

func _on_gear_changed(gear: int):
	"""Update gear display"""
	if gear_label:
		gear_label.text = "GEAR: %d" % gear

func update_gear_display():
	"""Update gear display from vehicle"""
	if vehicle and gear_label:
		var gear = vehicle.get_gear()
		gear_label.text = "GEAR: %d" % gear

func update_nitrous_display():
	"""Update nitrous bar"""
	if vehicle and nitrous_bar:
		var nitrous = vehicle.get_nitrous()
		nitrous_bar.value = nitrous

func update_lap_time():
	"""Update lap time display"""
	if lap_time_label:
		var current_time = Time.get_ticks_msec() - lap_start_time
		var seconds = current_time / 1000.0
		lap_time_label.text = "Time: %.2f" % seconds

func update_position(position: int, total_racers: int):
	"""Update race position"""
	if position_label:
		var suffix = "th"
		if position == 1:
			suffix = "st"
		elif position == 2:
			suffix = "nd"
		elif position == 3:
			suffix = "rd"
		position_label.text = "%d%s / %d" % [position, suffix, total_racers]

func start_lap():
	"""Start a new lap"""
	lap_start_time = Time.get_ticks_msec()

func complete_lap():
	"""Complete current lap"""
	var lap_time = (Time.get_ticks_msec() - lap_start_time) / 1000.0

	if lap_time < best_lap_time:
		best_lap_time = lap_time
		print("New best lap: %.2f seconds!" % lap_time)

	current_lap += 1
	if current_lap <= total_laps:
		if lap_label:
			lap_label.text = "Lap: %d / %d" % [current_lap, total_laps]
		start_lap()
	else:
		print("Race finished!")

func set_total_laps(laps: int):
	"""Set total number of laps"""
	total_laps = laps
	current_lap = 1
	if lap_label:
		lap_label.text = "Lap: %d / %d" % [current_lap, total_laps]
