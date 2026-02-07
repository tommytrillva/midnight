## Data container for race configuration.
## Defines everything needed to set up and run a race event.
class_name RaceData
extends Resource

@export var race_id: String = ""
@export var race_name: String = ""
@export var race_type: RaceManager.RaceType = RaceManager.RaceType.STREET_SPRINT
@export var tier: int = 1

# Track
@export var track_id: String = ""
@export var district: String = "downtown"
@export var lap_count: int = 1
@export var track_length_km: float = 2.0

# Participants
@export var ai_count: int = 3
@export var ai_names: Array[String] = []
@export var ai_difficulty: float = 0.5 # 0.0-1.0

# Stakes
@export var entry_fee: int = 0
@export var base_payout: int = 500
@export var is_pink_slip: bool = false
@export var opponent_vehicle_data: Dictionary = {} # For pink slips

# Story integration
@export var is_story_mission: bool = false
@export var mission_id: String = ""
@export var pre_race_dialogue_id: String = ""
@export var post_race_win_dialogue_id: String = ""
@export var post_race_lose_dialogue_id: String = ""

# Conditions
@export var required_rep_tier: int = 0
@export var weather_override: String = "" # Empty = use current weather
@export var time_override: String = "" # Empty = use current time
@export var police_enabled: bool = true


func to_dict() -> Dictionary:
	return {
		"race_id": race_id,
		"race_name": race_name,
		"race_type": race_type,
		"tier": tier,
		"track_id": track_id,
		"district": district,
		"is_pink_slip": is_pink_slip,
		"is_story_mission": is_story_mission,
		"mission_id": mission_id,
	}
