## Static character data definitions for all major characters.
## Per GDD Section 5.
class_name CharacterData
extends RefCounted

# Character profiles loaded from data or defined here for MVP
const CHARACTERS := {
	"maya": {
		"id": "maya",
		"display_name": "Maya Torres",
		"role": "The Heart",
		"personality": "Warm but guarded, fiercely independent, gifted with engines",
		"location": "Torres Garage",
		"portrait": "res://assets/ui/portraits/maya.png",
		"voice_style": "warm_determined",
		"key_missions": [
			"torres_garage", "rosas_legacy", "mayas_choice",
			"the_call", "together", "letting_go"
		],
	},
	"diesel": {
		"id": "diesel",
		"display_name": "Diesel",
		"role": "The Mentor",
		"personality": "Quiet authority, haunted, wisdom earned through pain",
		"location": "Various — watches from shadows",
		"portrait": "res://assets/ui/portraits/diesel.png",
		"voice_style": "low_gravelly",
		"key_missions": [
			"the_watcher", "marcus_ghost", "one_last_ride", "the_old_guard"
		],
	},
	"nikko": {
		"id": "nikko",
		"display_name": "Nikko Cross",
		"role": "The Rival",
		"personality": "Cocky, talented, driven by desperation masked as arrogance",
		"location": "The racing scene",
		"portrait": "res://assets/ui/portraits/nikko.png",
		"voice_style": "aggressive_young",
		"key_missions": [
			"first_blood", "the_cross_family", "nikkos_choice", "brothers_in_arms"
		],
	},
	"jade": {
		"id": "jade",
		"display_name": "Jade Winters",
		"role": "The Temptation",
		"personality": "Professional, calculating, unexpectedly deep",
		"location": "Corporate events, sponsor offices",
		"portrait": "res://assets/ui/portraits/jade.png",
		"voice_style": "polished_corporate",
		"key_missions": [
			"the_offer", "the_gala", "jades_cage", "breaking_free"
		],
	},
	"zero": {
		"id": "zero",
		"display_name": "Zero",
		"role": "The Antagonist",
		"personality": "Unknowable — an unseen force",
		"location": "Everywhere and nowhere",
		"portrait": "res://assets/ui/portraits/zero.png",
		"voice_style": "distorted_echo",
		"key_missions": [],
	},
	"ghost": {
		"id": "ghost",
		"display_name": "Ghost",
		"role": "The Legend",
		"personality": "Never speaks. Only races.",
		"location": "Random night encounters",
		"portrait": "res://assets/ui/portraits/ghost.png",
		"voice_style": "silent",
		"key_missions": [],
	},
}

# Supporting cast
const SUPPORTING := {
	"elena": {
		"id": "elena",
		"display_name": "Elena Vance",
		"role": "Bar owner, Diesel's former love",
	},
	"victor": {
		"id": "victor",
		"display_name": "Victor Cross",
		"role": "Nikko's father, gambling addict",
	},
	"alejandro": {
		"id": "alejandro",
		"display_name": "Alejandro Torres",
		"role": "Maya's broken father",
	},
	"rusty": {
		"id": "rusty",
		"display_name": "Rusty",
		"role": "Diner owner, scene historian",
	},
	"carmen": {
		"id": "carmen",
		"display_name": "Carmen",
		"role": "Underground information broker",
	},
}


static func get_character(id: String) -> Dictionary:
	if CHARACTERS.has(id):
		return CHARACTERS[id]
	if SUPPORTING.has(id):
		return SUPPORTING[id]
	return {}


static func get_display_name(id: String) -> String:
	var data := get_character(id)
	return data.get("display_name", id)


static func get_all_main_character_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in CHARACTERS:
		ids.append(key)
	return ids
