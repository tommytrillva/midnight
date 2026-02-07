## Manages district loading, unloading, transitions, and unlock requirements.
## Districts are gated by REP tier per GDD Section 3.4.
class_name DistrictManager
extends Node


# --- District Scenes ---
const DISTRICT_SCENES := {
	"downtown": "res://scenes/world/downtown.tscn",
	"harbor": "res://scenes/world/harbor.tscn",
	"industrial": "res://scenes/world/industrial.tscn",
	"hillside": "res://scenes/world/hillside.tscn",
}

# --- REP Tier Requirements (from GDD) ---
# Tier 0 = UNKNOWN, 1 = NEWCOMER, 2 = KNOWN, 3 = RESPECTED
const DISTRICT_UNLOCK_TIERS := {
	"downtown": 0,    # Always available
	"harbor": 1,      # NEWCOMER (1000 REP)
	"industrial": 2,  # KNOWN (5000 REP)
	"hillside": 3,    # RESPECTED (15000 REP)
}

# --- Display Names ---
const DISTRICT_NAMES := {
	"downtown": "Downtown",
	"harbor": "Harbor District",
	"industrial": "Industrial Zone",
	"hillside": "Hillside / Route 9",
}

# --- State ---
var current_district_id: String = "downtown"
var _current_district_node: Node3D = null
var _district_parent: Node3D = null
var _player_vehicle: Node3D = null
var _transitioning: bool = false
var _unlocked_districts: Array[String] = ["downtown"]

## Set by transition zone detection — read by FreeRoam for interact input.
var in_transition_zone: bool = false
var pending_target_id: String = ""

# --- Preloaded Scene Cache ---
var _scene_cache: Dictionary = {}


func _ready() -> void:
	# Listen for rep tier changes to unlock districts
	EventBus.rep_tier_changed.connect(_on_rep_tier_changed)
	# Check initial unlocks based on current rep
	_refresh_unlocked_districts()
	print("[District] DistrictManager initialized. Current: %s" % current_district_id)


func setup(district_parent: Node3D, player_vehicle: Node3D) -> void:
	## Call this from FreeRoam after spawning the player.
	## district_parent is the Node3D that district scenes are added to.
	## player_vehicle is the player's vehicle node for repositioning.
	_district_parent = district_parent
	_player_vehicle = player_vehicle
	print("[District] Setup complete. Parent: %s" % district_parent.name)


func set_initial_district(district_node: Node3D, district_id: String) -> void:
	## Register the already-loaded starting district (e.g., Downtown in FreeRoam).
	_current_district_node = district_node
	current_district_id = district_id
	_connect_transition_zones(district_node)
	EventBus.district_entered.emit(district_id)
	print("[District] Initial district set: %s" % district_id)


func get_current_district_name() -> String:
	return DISTRICT_NAMES.get(current_district_id, "Unknown")


func is_district_unlocked(district_id: String) -> bool:
	return district_id in _unlocked_districts


func get_unlocked_districts() -> Array[String]:
	return _unlocked_districts.duplicate()


func get_required_tier(district_id: String) -> int:
	return DISTRICT_UNLOCK_TIERS.get(district_id, 0)


func get_required_tier_name(district_id: String) -> String:
	var tier: int = get_required_tier(district_id)
	var tier_names := {0: "UNKNOWN", 1: "NEWCOMER", 2: "KNOWN", 3: "RESPECTED", 4: "FEARED", 5: "LEGENDARY"}
	return tier_names.get(tier, "UNKNOWN")


func transition_to_district(target_district_id: String) -> void:
	## Begin a district transition. Handles unlock check, fade, load, and repositioning.
	if _transitioning:
		print("[District] Transition already in progress, ignoring.")
		return

	if target_district_id == current_district_id:
		print("[District] Already in %s, ignoring." % target_district_id)
		return

	if not target_district_id in DISTRICT_SCENES:
		print("[District] ERROR: Unknown district '%s'" % target_district_id)
		return

	# Check unlock requirement
	if not is_district_unlocked(target_district_id):
		var required := get_required_tier_name(target_district_id)
		var msg := "District locked! Reach %s tier to access %s" % [required, DISTRICT_NAMES.get(target_district_id, target_district_id)]
		EventBus.hud_message.emit(msg, 3.0)
		print("[District] %s is locked. Need tier: %s" % [target_district_id, required])
		return

	_transitioning = true
	print("[District] Transitioning: %s -> %s" % [current_district_id, target_district_id])

	# Fade out
	EventBus.screen_fade_out.emit(0.5)
	await get_tree().create_timer(0.5).timeout

	# Unload current district
	_unload_current_district()

	# Load new district
	var new_district := _load_district_scene(target_district_id)
	if new_district == null:
		print("[District] ERROR: Failed to load district '%s'" % target_district_id)
		_transitioning = false
		EventBus.screen_fade_in.emit(0.3)
		return

	_district_parent.add_child(new_district)
	_current_district_node = new_district
	current_district_id = target_district_id

	# Reposition player at the new district's spawn point
	_reposition_player(new_district)

	# Connect transition zones in the new district
	_connect_transition_zones(new_district)

	# Emit signals
	EventBus.district_entered.emit(target_district_id)

	# Fade in
	EventBus.screen_fade_in.emit(0.5)
	await get_tree().create_timer(0.5).timeout

	_transitioning = false
	print("[District] Arrived at %s" % DISTRICT_NAMES.get(target_district_id, target_district_id))


func _unload_current_district() -> void:
	if _current_district_node and is_instance_valid(_current_district_node):
		# Disconnect any signals from transition zones
		_disconnect_transition_zones(_current_district_node)
		_current_district_node.queue_free()
		_current_district_node = null
		print("[District] Unloaded previous district.")


func _load_district_scene(district_id: String) -> Node3D:
	var scene_path: String = DISTRICT_SCENES.get(district_id, "")
	if scene_path.is_empty():
		return null

	# Check cache first
	if district_id in _scene_cache:
		var cached_scene: PackedScene = _scene_cache[district_id]
		return cached_scene.instantiate() as Node3D

	# Load the scene
	var scene := load(scene_path) as PackedScene
	if scene == null:
		print("[District] ERROR: Could not load scene at '%s'" % scene_path)
		return null

	# Cache it for future use
	_scene_cache[district_id] = scene
	return scene.instantiate() as Node3D


func _reposition_player(district_node: Node3D) -> void:
	if _player_vehicle == null or not is_instance_valid(_player_vehicle):
		print("[District] WARNING: No player vehicle to reposition.")
		return

	var spawn := district_node.get_node_or_null("PlayerSpawn") as Marker3D
	if spawn:
		_player_vehicle.global_transform = spawn.global_transform
		# Reset velocity if the vehicle supports it
		if _player_vehicle.has_method("reset_velocity"):
			_player_vehicle.reset_velocity()
		elif _player_vehicle is RigidBody3D:
			(_player_vehicle as RigidBody3D).linear_velocity = Vector3.ZERO
			(_player_vehicle as RigidBody3D).angular_velocity = Vector3.ZERO
		print("[District] Player repositioned to spawn point.")
	else:
		_player_vehicle.global_transform.origin = Vector3(0, 1, 0)
		print("[District] WARNING: No PlayerSpawn in district, using default position.")


func _connect_transition_zones(district_node: Node3D) -> void:
	var transitions := district_node.get_node_or_null("DistrictTransitions")
	if transitions == null:
		return

	for child in transitions.get_children():
		if child is Area3D:
			var area := child as Area3D
			if not area.body_entered.is_connected(_on_transition_zone_entered):
				area.body_entered.connect(_on_transition_zone_entered.bind(area))
			if not area.body_exited.is_connected(_on_transition_zone_exited):
				area.body_exited.connect(_on_transition_zone_exited.bind(area))


func _disconnect_transition_zones(district_node: Node3D) -> void:
	var transitions := district_node.get_node_or_null("DistrictTransitions")
	if transitions == null:
		return

	for child in transitions.get_children():
		if child is Area3D:
			var area := child as Area3D
			if area.body_entered.is_connected(_on_transition_zone_entered):
				area.body_entered.disconnect(_on_transition_zone_entered)
			if area.body_exited.is_connected(_on_transition_zone_exited):
				area.body_exited.disconnect(_on_transition_zone_exited)


func _on_transition_zone_entered(body: Node3D, area: Area3D) -> void:
	if body != _player_vehicle:
		return

	var target_id: String = area.get_meta("target_district", "")
	if target_id.is_empty():
		print("[District] WARNING: Transition zone has no target_district metadata.")
		return

	if not is_district_unlocked(target_id):
		var required := get_required_tier_name(target_id)
		var district_name: String = DISTRICT_NAMES.get(target_id, target_id)
		EventBus.hud_message.emit("Reach %s tier to access %s" % [required, district_name], 3.0)
		return

	# Track for interact input in FreeRoam
	in_transition_zone = true
	pending_target_id = target_id

	var district_name: String = DISTRICT_NAMES.get(target_id, target_id)
	EventBus.hud_message.emit("Press [F] to travel to %s" % district_name, 3.0)


func _on_transition_zone_exited(body: Node3D, _area: Area3D) -> void:
	if body != _player_vehicle:
		return
	in_transition_zone = false
	pending_target_id = ""


func request_transition(target_district_id: String) -> void:
	## Called by FreeRoam when the player presses interact in a transition zone.
	transition_to_district(target_district_id)


func _on_rep_tier_changed(old_tier: int, new_tier: int) -> void:
	# Check if new districts are unlocked
	var previous_unlocked := _unlocked_districts.duplicate()
	_refresh_unlocked_districts()

	for district_id in _unlocked_districts:
		if district_id not in previous_unlocked:
			EventBus.district_unlocked.emit(district_id)
			var district_name: String = DISTRICT_NAMES.get(district_id, district_id)
			EventBus.notification_popup.emit("District Unlocked!", "%s is now accessible" % district_name, "district")
			print("[District] Unlocked: %s (tier %d)" % [district_id, new_tier])


func _refresh_unlocked_districts() -> void:
	var player_tier: int = GameManager.reputation.get_tier()
	_unlocked_districts.clear()
	for district_id in DISTRICT_UNLOCK_TIERS:
		if player_tier >= DISTRICT_UNLOCK_TIERS[district_id]:
			if district_id not in _unlocked_districts:
				_unlocked_districts.append(district_id)


func serialize() -> Dictionary:
	return {
		"current_district": current_district_id,
		"unlocked_districts": _unlocked_districts.duplicate(),
	}


func deserialize(data: Dictionary) -> void:
	current_district_id = data.get("current_district", "downtown")
	var unlocked: Array = data.get("unlocked_districts", ["downtown"])
	_unlocked_districts.clear()
	for d in unlocked:
		_unlocked_districts.append(d as String)
	# Ensure downtown is always unlocked
	if "downtown" not in _unlocked_districts:
		_unlocked_districts.append("downtown")
