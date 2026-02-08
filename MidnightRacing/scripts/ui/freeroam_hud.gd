extends Control

# Free Roam HUD - Displays minimal info during free roam (speed, cash, rep)

@onready var speed_label = $SpeedLabel
@onready var cash_label = $CashLabel
@onready var rep_label = $RepLabel
@onready var notification_panel = $NotificationPanel

var vehicle: VehicleBody3D = null

func _ready():
	# Find the player vehicle
	await get_tree().process_frame
	find_player_vehicle()

	# Update cash and rep displays
	update_cash_display()
	update_rep_display()

	# Connect to StoryManager for notifications
	if StoryManager:
		StoryManager.phone_notification.connect(_on_phone_notification)

func find_player_vehicle():
	"""Find and connect to the player's vehicle"""
	var vehicles = get_tree().get_nodes_in_group("player_vehicle")
	if vehicles.size() > 0:
		vehicle = vehicles[0]
		if vehicle.has_signal("speed_changed"):
			vehicle.speed_changed.connect(_on_speed_changed)
		print("Free Roam HUD connected to vehicle")

func _on_speed_changed(speed: float):
	"""Update speed display"""
	if speed_label:
		speed_label.text = "%d MPH" % int(speed)

func update_cash_display():
	"""Update cash display"""
	if cash_label and GameManager:
		cash_label.text = "$%d" % GameManager.player_data.cash

func update_rep_display():
	"""Update reputation display"""
	if rep_label and GameManager:
		rep_label.text = "Rep: %d" % GameManager.player_data.reputation

func _on_phone_notification(notification: Dictionary):
	"""Show phone notification"""
	if notification_panel:
		notification_panel.visible = true
		# Show notification for 5 seconds
		await get_tree().create_timer(5.0).timeout
		notification_panel.visible = false
