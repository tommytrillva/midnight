## Driver skill tree system per GDD Section 7.3.
## Four trees: Speed Demon, Ghost Line, Street Survivor, Technician.
## XP earned through racing; skill points spent on trees.
## Skill tree progress is KEPT through Act 3's Fall.
class_name SkillTreeSystem
extends Node

var xp: int = 0
var level: int = 1
var skill_points: int = 0
var total_skill_points_earned: int = 0
var unlocked_skills: Dictionary = {} # tree_id -> Array of skill_ids

# XP required per level (exponential curve)
const XP_PER_LEVEL := [
	0, 100, 250, 500, 800, 1200, 1700, 2300, 3000, 4000, 5000
]
const MAX_LEVEL := 10

# Skill tree definitions from GDD
const TREES := {
	"speed_demon": {
		"name": "Speed Demon",
		"description": "Top speed, straight-line performance",
		"skills": [
			{"id": "sd_1", "level": 1, "name": "+2% Top Speed Bonus", "type": "passive", "effect": {"stat": "speed", "mult": 1.02}},
			{"id": "sd_3", "level": 3, "name": "Improved Slipstream", "type": "passive", "effect": {"slipstream_mult": 1.3}},
			{"id": "sd_5", "level": 5, "name": "Nitro Mastery", "type": "passive", "effect": {"nitro_duration_mult": 1.5}},
			{"id": "sd_7", "level": 7, "name": "Reduced Drag", "type": "passive", "effect": {"drag_mult": 0.9}},
			{"id": "sd_10", "level": 10, "name": "Terminal Velocity", "type": "passive", "effect": {"speed_limit_break": true}},
		],
	},
	"ghost_line": {
		"name": "Ghost Line",
		"description": "Handling, cornering, precision",
		"skills": [
			{"id": "gl_1", "level": 1, "name": "+2% Cornering Grip", "type": "passive", "effect": {"stat": "handling", "mult": 1.02}},
			{"id": "gl_3", "level": 3, "name": "Improved Trail Braking", "type": "passive", "effect": {"trail_brake_mult": 1.2}},
			{"id": "gl_5", "level": 5, "name": "Perfect Apex", "type": "active", "effect": {"racing_line_visible": true}},
			{"id": "gl_7", "level": 7, "name": "Weight Transfer Control", "type": "passive", "effect": {"weight_transfer_mult": 1.3}},
			{"id": "gl_10", "level": 10, "name": "Flow State", "type": "active", "effect": {"time_slow_corners": true}},
		],
	},
	"street_survivor": {
		"name": "Street Survivor",
		"description": "Durability, recovery, adaptability",
		"skills": [
			{"id": "ss_1", "level": 1, "name": "+5% Damage Resistance", "type": "passive", "effect": {"stat": "durability", "mult": 1.05}},
			{"id": "ss_3", "level": 3, "name": "Faster Tire Recovery", "type": "passive", "effect": {"tire_recovery_mult": 1.3}},
			{"id": "ss_5", "level": 5, "name": "Quick Recovery", "type": "passive", "effect": {"crash_recovery_mult": 1.5}},
			{"id": "ss_7", "level": 7, "name": "Reduced Police Attention", "type": "passive", "effect": {"heat_gain_mult": 0.7}},
			{"id": "ss_10", "level": 10, "name": "Phoenix", "type": "active", "effect": {"survive_fatal_crash": true}},
		],
	},
	"technician": {
		"name": "Technician",
		"description": "Car knowledge, optimization, efficiency",
		"skills": [
			{"id": "tc_1", "level": 1, "name": "-5% Repair Costs", "type": "passive", "effect": {"repair_cost_mult": 0.95}},
			{"id": "tc_3", "level": 3, "name": "Better Part Discovery", "type": "passive", "effect": {"part_discovery_bonus": true}},
			{"id": "tc_5", "level": 5, "name": "Field Fix", "type": "active", "effect": {"mid_race_repair": true}},
			{"id": "tc_7", "level": 7, "name": "Hidden Tuning Parameters", "type": "passive", "effect": {"hidden_tuning": true}},
			{"id": "tc_10", "level": 10, "name": "Master Tuner", "type": "passive", "effect": {"exclusive_part_combos": true}},
		],
	},
}


func _ready() -> void:
	for tree_id in TREES:
		unlocked_skills[tree_id] = []


func earn_xp(amount: int, source: String = "") -> void:
	xp += amount
	EventBus.xp_earned.emit(amount, source)

	# Check for level up
	while level < MAX_LEVEL and xp >= _get_xp_for_level(level + 1):
		level += 1
		skill_points += 1
		total_skill_points_earned += 1
		EventBus.level_up.emit(level)
		EventBus.skill_point_earned.emit(skill_points)
		print("[Skills] Level up! Now level %d (%d skill points available)" % [level, skill_points])


func unlock_skill(tree_id: String, skill_id: String) -> bool:
	if skill_points <= 0:
		return false
	if not TREES.has(tree_id):
		return false

	var tree: Dictionary = TREES[tree_id]
	var skill: Dictionary = {}
	for s in tree.skills:
		if s.id == skill_id:
			skill = s
			break

	if skill.is_empty():
		return false

	# Check level requirement
	if level < skill.level:
		return false

	# Check not already unlocked
	if skill_id in unlocked_skills[tree_id]:
		return false

	# Check prerequisite (must have all lower-level skills in this tree)
	for s in tree.skills:
		if s.level < skill.level and s.id not in unlocked_skills[tree_id]:
			return false

	skill_points -= 1
	unlocked_skills[tree_id].append(skill_id)
	EventBus.skill_unlocked.emit(tree_id, skill_id)
	print("[Skills] Unlocked: %s in %s" % [skill.name, tree.name])
	return true


func has_skill(skill_id: String) -> bool:
	for tree_id in unlocked_skills:
		if skill_id in unlocked_skills[tree_id]:
			return true
	return false


func get_skill_effect(skill_id: String) -> Dictionary:
	for tree_id in TREES:
		for skill in TREES[tree_id].skills:
			if skill.id == skill_id and has_skill(skill_id):
				return skill.get("effect", {})
	return {}


func get_all_active_effects() -> Array[Dictionary]:
	## Returns all effects from unlocked skills.
	var effects: Array[Dictionary] = []
	for tree_id in unlocked_skills:
		for skill_id in unlocked_skills[tree_id]:
			var effect := get_skill_effect(skill_id)
			if not effect.is_empty():
				effects.append(effect)
	return effects


func get_stat_multiplier(stat_name: String) -> float:
	## Get cumulative multiplier for a stat from all unlocked skills.
	var mult := 1.0
	for effect in get_all_active_effects():
		if effect.get("stat", "") == stat_name:
			mult *= effect.get("mult", 1.0)
	return mult


func _get_xp_for_level(lv: int) -> int:
	if lv < 0 or lv >= XP_PER_LEVEL.size():
		return 999999
	return XP_PER_LEVEL[lv]


func reset_all() -> void:
	# Note: per GDD, skills are NOT reset during The Fall.
	# This is only for new game.
	xp = 0
	level = 1
	skill_points = 0
	total_skill_points_earned = 0
	for tree_id in TREES:
		unlocked_skills[tree_id] = []


func serialize() -> Dictionary:
	return {
		"xp": xp,
		"level": level,
		"skill_points": skill_points,
		"total_skill_points_earned": total_skill_points_earned,
		"unlocked_skills": unlocked_skills,
	}


func deserialize(data: Dictionary) -> void:
	xp = data.get("xp", 0)
	level = data.get("level", 1)
	skill_points = data.get("skill_points", 0)
	total_skill_points_earned = data.get("total_skill_points_earned", 0)
	unlocked_skills = data.get("unlocked_skills", {})
	if unlocked_skills.is_empty():
		for tree_id in TREES:
			unlocked_skills[tree_id] = []
