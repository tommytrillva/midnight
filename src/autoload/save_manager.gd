## Handles save/load operations with multiple save slots.
## Saves include full game state: story progress, vehicles, relationships, etc.
extends Node

const SAVE_DIR := "user://saves/"
const SAVE_PREFIX := "midnight_save_"
const SAVE_EXT := ".sav"
const MAX_SLOTS := 5
const AUTOSAVE_SLOT := 0


func _ready() -> void:
	_ensure_save_dir()


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func save_game(slot: int = AUTOSAVE_SLOT) -> bool:
	if slot < 0 or slot > MAX_SLOTS:
		push_error("[SaveManager] Invalid save slot: %d" % slot)
		EventBus.save_failed.emit("Invalid save slot")
		return false

	var save_data := GameManager.get_save_data()
	save_data["timestamp"] = Time.get_datetime_string_from_system()
	save_data["slot"] = slot

	var path := _get_save_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err_msg := "Failed to open save file: %s" % path
		push_error("[SaveManager] %s" % err_msg)
		EventBus.save_failed.emit(err_msg)
		return false

	var json_string := JSON.stringify(save_data, "\t")
	file.store_string(json_string)
	file.close()

	EventBus.game_saved.emit(slot)
	print("[SaveManager] Game saved to slot %d" % slot)
	return true


func load_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var path := _get_save_path(slot)
	if not FileAccess.file_exists(path):
		push_error("[SaveManager] No save file at slot %d" % slot)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to open save file: %s" % path)
		return false

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		push_error("[SaveManager] Failed to parse save data: %s" % json.get_error_message())
		return false

	var save_data: Dictionary = json.data
	GameManager.load_save_data(save_data)
	EventBus.game_loaded.emit(slot)
	print("[SaveManager] Game loaded from slot %d" % slot)
	return true


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_get_save_path(slot))


func get_save_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(_get_save_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	file.close()
	var data: Dictionary = json.data
	return {
		"slot": slot,
		"timestamp": data.get("timestamp", "Unknown"),
		"version": data.get("version", "0.0.0"),
		"story_act": data.get("story", {}).get("current_act", 1),
		"story_chapter": data.get("story", {}).get("current_chapter", 1),
	}


func delete_save(slot: int) -> bool:
	var path := _get_save_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	dir.remove(path.get_file())
	print("[SaveManager] Deleted save slot %d" % slot)
	return true


func autosave() -> void:
	save_game(AUTOSAVE_SLOT)


func _get_save_path(slot: int) -> String:
	return SAVE_DIR + SAVE_PREFIX + str(slot) + SAVE_EXT
