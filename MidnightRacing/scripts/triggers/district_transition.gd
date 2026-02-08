extends Area3D

# District Transition - Handles seamless loading between districts

@export var target_district: String = "industrial"
@export var target_scene_path: String = "res://scenes/districts/industrial.tscn"
@export var spawn_point_name: String = "FromDowntown"
@export var minimum_reputation: int = 0
@export var transition_prompt: String = "Enter Industrial District"

var player_in_zone = false
var prompt_label: Label3D = null

func _ready():
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create prompt label
	prompt_label = Label3D.new()
	prompt_label.text = transition_prompt
	prompt_label.modulate = Color(1, 1, 1, 0)
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.font_size = 32
	add_child(prompt_label)
	prompt_label.position = Vector3(0, 3, 0)

	add_to_group("district_transition")

func _on_body_entered(body):
	"""Player entered transition zone"""
	if body.is_in_group("player_vehicle"):
		player_in_zone = true

		# Check if district is unlocked
		if target_district not in GameManager.player_data.unlocked_districts:
			if GameManager.player_data.reputation >= minimum_reputation:
				# Unlock district
				GameManager.unlock_district(target_district)
				show_prompt(transition_prompt, Color.GREEN)
			else:
				show_prompt("Locked - Need %d Rep" % minimum_reputation, Color.RED)
		else:
			show_prompt(transition_prompt, Color.GREEN)

func _on_body_exited(body):
	"""Player exited transition zone"""
	if body.is_in_group("player_vehicle"):
		player_in_zone = false
		hide_prompt()

func _process(_delta):
	"""Handle transition activation"""
	if player_in_zone and Input.is_action_just_pressed("interact"):
		if target_district in GameManager.player_data.unlocked_districts:
			transition_to_district()
		else:
			print("District locked! Need ", minimum_reputation, " reputation")

func transition_to_district():
	"""Load the target district"""
	print("Transitioning to ", target_district, "...")

	# Store spawn point for target scene
	GameManager.player_data["last_spawn_point"] = spawn_point_name

	# Load new scene
	GameManager.load_scene(target_scene_path)

func show_prompt(text: String, color: Color):
	"""Show transition prompt"""
	if prompt_label:
		prompt_label.text = "[E] " + text
		prompt_label.modulate = color
		# Fade in
		var tween = create_tween()
		tween.tween_property(prompt_label, "modulate:a", 1.0, 0.3)

func hide_prompt():
	"""Hide transition prompt"""
	if prompt_label:
		# Fade out
		var tween = create_tween()
		tween.tween_property(prompt_label, "modulate:a", 0.0, 0.3)
