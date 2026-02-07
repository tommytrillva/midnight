## Represents a group of NPCs in the world that can speak ambient dialogue lines.
## Place in scenes as a Node3D. Configures an Area3D detection zone that triggers
## ambient dialogue when the player enters range.
class_name NPCGroup
extends Node3D

# --- Exports ---
@export var group_id: String = ""
@export var district: String = "downtown"
@export var max_npcs: int = 3
@export var detection_radius: float = 12.0
@export var enabled: bool = true

# --- Voice variation per NPC (pitch range for variety) ---
const VOICE_PITCH_MIN: float = 0.85
const VOICE_PITCH_MAX: float = 1.2
const VOICE_SPEED_MIN: float = 0.9
const VOICE_SPEED_MAX: float = 1.1

# --- Internal ---
var _detection_area: Area3D = null
var _collision_shape: CollisionShape3D = null
var _player_in_range: bool = false
var _npc_voice_profiles: Array[Dictionary] = [] # Per-NPC pitch/speed
var _active_bubble_text: String = ""
var _active_speaker_index: int = -1
var _bubble_timer: float = 0.0
var _retrigger_timer: float = 0.0
const RETRIGGER_COOLDOWN: float = 45.0 # Seconds before this group can trigger again


func _ready() -> void:
	if group_id.is_empty():
		group_id = "npc_group_%d" % get_instance_id()

	_setup_detection_area()
	_generate_voice_profiles()
	_register_with_system()

	# Listen for ambient line events to show bubbles
	EventBus.ambient_line_started.connect(_on_ambient_line_started)
	EventBus.ambient_exchange_finished.connect(_on_ambient_exchange_finished)


func _exit_tree() -> void:
	# Unregister when removed from scene
	if GameManager and GameManager.has_node("AmbientDialogue"):
		var ambient: AmbientDialogue = GameManager.get_node("AmbientDialogue")
		ambient.unregister_npc_group(group_id)


func _process(delta: float) -> void:
	# Fade out bubble text
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_clear_bubble()

	# Retrigger cooldown
	if _retrigger_timer > 0.0:
		_retrigger_timer -= delta


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _setup_detection_area() -> void:
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 1 # Player layer

	_collision_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = detection_radius
	_collision_shape.shape = sphere

	_detection_area.add_child(_collision_shape)
	add_child(_detection_area)

	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)


func _generate_voice_profiles() -> void:
	_npc_voice_profiles.clear()
	for i in range(max_npcs):
		_npc_voice_profiles.append({
			"pitch": randf_range(VOICE_PITCH_MIN, VOICE_PITCH_MAX),
			"speed": randf_range(VOICE_SPEED_MIN, VOICE_SPEED_MAX),
			"index": i,
		})


func _register_with_system() -> void:
	# Register this group with the AmbientDialogue system.
	# Deferred to ensure GameManager is ready.
	call_deferred("_deferred_register")


func _deferred_register() -> void:
	if not GameManager:
		return
	if not GameManager.has_node("AmbientDialogue"):
		return
	var ambient: AmbientDialogue = GameManager.get_node("AmbientDialogue")
	ambient.register_npc_group(group_id, global_position, district)


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not enabled:
		return
	if not _is_player(body):
		return

	_player_in_range = true

	if _retrigger_timer > 0.0:
		return

	_retrigger_timer = RETRIGGER_COOLDOWN
	_trigger_ambient_dialogue()


func _on_body_exited(body: Node3D) -> void:
	if not _is_player(body):
		return
	_player_in_range = false
	EventBus.npc_group_exited.emit(group_id)


func _is_player(body: Node3D) -> bool:
	# Check for player by group or name
	return body.is_in_group("player") or body.name == "Player"


func _trigger_ambient_dialogue() -> void:
	if not GameManager:
		return
	if not GameManager.has_node("AmbientDialogue"):
		return
	var ambient: AmbientDialogue = GameManager.get_node("AmbientDialogue")
	ambient.trigger_for_group(group_id)


# ---------------------------------------------------------------------------
# Bubble Display
# ---------------------------------------------------------------------------

func _on_ambient_line_started(incoming_group_id: String, line_data: Dictionary) -> void:
	if incoming_group_id != group_id:
		return

	var speaker_index: int = line_data.get("speaker_index", 0)
	var text: String = line_data.get("text", "")
	var speaker_tag: String = line_data.get("speaker_tag", "")

	_show_bubble(speaker_index, text, speaker_tag)


func _on_ambient_exchange_finished(incoming_group_id: String) -> void:
	if incoming_group_id != group_id:
		return
	# Final line fades on its own via _bubble_timer


func _show_bubble(speaker_index: int, text: String, speaker_tag: String) -> void:
	_active_speaker_index = clampi(speaker_index, 0, max_npcs - 1)
	_active_bubble_text = text
	_bubble_timer = AmbientDialogue.LINE_DISPLAY_DURATION

	var voice := get_voice_profile(_active_speaker_index)
	# The actual visual display is handled by the UI layer listening
	# to ambient_line_started. This node tracks state for the 3D world.
	print("[NPCGroup:%s] [%s] \"%s\" (pitch: %.2f)" % [
		group_id, speaker_tag, text, voice.pitch
	])


func _clear_bubble() -> void:
	_active_bubble_text = ""
	_active_speaker_index = -1


# ---------------------------------------------------------------------------
# Public Accessors
# ---------------------------------------------------------------------------

func get_voice_profile(npc_index: int) -> Dictionary:
	## Get the voice pitch/speed profile for an NPC in this group.
	if npc_index < 0 or npc_index >= _npc_voice_profiles.size():
		return {"pitch": 1.0, "speed": 1.0, "index": 0}
	return _npc_voice_profiles[npc_index]


func get_active_bubble_text() -> String:
	return _active_bubble_text


func get_active_speaker_index() -> int:
	return _active_speaker_index


func is_player_nearby() -> bool:
	return _player_in_range
