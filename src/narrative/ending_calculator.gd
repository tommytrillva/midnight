## Evaluates all game state to determine which of the 6+ endings the player gets.
## Calculated on demand, does not need persistence.
## Per GDD Section 4.4: endings are determined by cumulative choices, relationships,
## moral alignment, path, and specific story flags.
class_name EndingCalculator
extends Node

# Ending IDs
const ENDING_LEGEND := "legend"           # ENDING_A: High overall relationships + Legend path
const ENDING_EMPIRE := "empire"           # ENDING_B: Owner path + business success
const ENDING_FAMILY := "family"           # ENDING_C: High Maya + Nikko + Diesel (all 60+)
const ENDING_GHOST := "ghost"             # ENDING_D: Beat Ghost in Act 4 + specific choices
const ENDING_CONTRADICTION := "contradiction" # ENDING_E: Mixed choices, balanced paths
const ENDING_PRICE := "price"             # ENDING_F: Moral compromises + Zero alliance
const ENDING_SECRET := "secret_beginning"  # SECRET: <120h + all high + selfless + all car types

# Minimum score to qualify for an ending
const QUALIFICATION_THRESHOLD := 50

# Weights for ending score calculation
const SCORE_WEIGHTS := {
	"relationship": 1.0,
	"moral": 1.5,
	"path": 2.0,
	"flag": 1.0,
}


func _ready() -> void:
	print("[Ending] EndingCalculator initialized.")


func calculate_ending() -> String:
	## Determine the player's ending based on all game state.
	## Returns the ending ID string.
	var scores := get_ending_scores()

	# Secret ending has highest priority (hardest to achieve)
	if scores[ENDING_SECRET] >= QUALIFICATION_THRESHOLD:
		EventBus.ending_determined.emit(ENDING_SECRET)
		print("[Ending] SECRET ENDING qualified!")
		return ENDING_SECRET

	# Find the ending with the highest score
	var best_ending := ENDING_LEGEND
	var best_score := -1.0
	for ending_id in scores:
		if scores[ending_id] > best_score:
			best_score = scores[ending_id]
			best_ending = ending_id

	EventBus.ending_determined.emit(best_ending)
	print("[Ending] Calculated ending: %s (score: %.1f)" % [best_ending, best_score])
	return best_ending


func get_ending_scores() -> Dictionary:
	## Returns a score (0-100) for each ending based on current game state.
	## Higher score = closer to qualifying for that ending.
	var scores := {
		ENDING_LEGEND: _score_legend(),
		ENDING_EMPIRE: _score_empire(),
		ENDING_FAMILY: _score_family(),
		ENDING_GHOST: _score_ghost(),
		ENDING_CONTRADICTION: _score_contradiction(),
		ENDING_PRICE: _score_price(),
		ENDING_SECRET: _score_secret(),
	}
	return scores


func get_closest_ending() -> String:
	## Returns the ending the player is closest to achieving.
	## Useful for mid-game narrative hints.
	var scores := get_ending_scores()

	# Exclude the secret ending from hints
	scores.erase(ENDING_SECRET)

	var best_ending := ENDING_LEGEND
	var best_score := -1.0
	for ending_id in scores:
		if scores[ending_id] > best_score:
			best_score = scores[ending_id]
			best_ending = ending_id

	return best_ending


func _score_legend() -> float:
	## ENDING_A "legend": High overall relationships + Legend path
	## The classic "good ending" — respected by all, proved yourself on the streets.
	var score := 0.0
	var rels := GameManager.relationships

	# Average relationship level across main characters (excluding Zero)
	var total_affinity := 0.0
	var char_count := 0
	for char_id in ["maya", "diesel", "nikko", "jade"]:
		total_affinity += rels.get_affinity(char_id)
		char_count += 1
	var avg_affinity: float = total_affinity / max(char_count, 1)
	score += remap(avg_affinity, 0, 80, 0, 40) # Up to 40 points from relationships

	# Reputation matters
	var rep_tier: int = GameManager.reputation.get_tier()
	score += remap(rep_tier, 0, 5, 0, 20) # Up to 20 points from rep

	# Moral alignment: moderate positive preferred
	var moral := _get_moral_alignment()
	if moral > 0:
		score += remap(moral, 0, 100, 0, 20) # Up to 20 from positive moral
	else:
		score += remap(moral, -100, 0, 0, 5) # Small amount even if negative

	# Path: underground preferred for legend status
	if GameManager.story.chosen_path == "underground":
		score += 15.0
	elif GameManager.story.chosen_path == "corporate":
		score += 5.0

	# Beat Ghost bonus
	if GameManager.story.story_flags.get("beat_ghost", false):
		score += 5.0

	return clampf(score, 0, 100)


func _score_empire() -> float:
	## ENDING_B "empire": Owner path + business success flags
	## The corporate/business ending — built an empire.
	var score := 0.0

	# Corporate path is essential
	if GameManager.story.chosen_path == "corporate":
		score += 30.0
	elif GameManager.story.chosen_path == "underground":
		score += 5.0 # Can still build a business underground, harder

	# Jade relationship is key for this ending
	var jade_affinity: int = GameManager.relationships.get_affinity("jade")
	score += remap(jade_affinity, 0, 100, 0, 25)

	# Business success flags
	var flags := GameManager.player_data
	if flags.has_choice_flag("business_owner"):
		score += 10.0
	if flags.has_choice_flag("sponsor_deal"):
		score += 5.0
	if flags.has_choice_flag("corporate_networked"):
		score += 5.0
	if flags.has_choice_flag("garage_upgraded_max"):
		score += 5.0

	# Wealth matters
	var cash: int = GameManager.economy.cash
	score += remap(cash, 0, 50000, 0, 10)

	# High reputation
	var rep_tier: int = GameManager.reputation.get_tier()
	score += remap(rep_tier, 0, 5, 0, 10)

	return clampf(score, 0, 100)


func _score_family() -> float:
	## ENDING_C "family": High Maya + Nikko + Diesel relationships (all 60+)
	## The heart ending — it was always about the people.
	var score := 0.0
	var rels := GameManager.relationships

	var maya_aff: int = rels.get_affinity("maya")
	var nikko_aff: int = rels.get_affinity("nikko")
	var diesel_aff: int = rels.get_affinity("diesel")

	# All three must be high. Each contributes up to 25 points.
	score += remap(maya_aff, 0, 100, 0, 25)
	score += remap(nikko_aff, 0, 100, 0, 25)
	score += remap(diesel_aff, 0, 100, 0, 25)

	# Bonus if ALL are at 60+
	if maya_aff >= 60 and nikko_aff >= 60 and diesel_aff >= 60:
		score += 15.0

	# Moral alignment: compassionate helps
	var moral := _get_moral_alignment()
	if moral > 0:
		score += remap(moral, 0, 100, 0, 10)

	return clampf(score, 0, 100)


func _score_ghost() -> float:
	## ENDING_D "ghost": Specific choices + beat Ghost in Act 4
	## The mystery ending — becoming the next Ghost.
	var score := 0.0
	var flags := GameManager.player_data
	var story_flags := GameManager.story.story_flags

	# Must beat Ghost
	if story_flags.get("beat_ghost", false):
		score += 30.0

	# Ghost-specific story flags
	if story_flags.get("ghost_secret_conditions", false):
		score += 20.0
	if flags.has_choice_flag("ghost_origin"):
		score += 10.0
	if story_flags.get("ghost_identity_known", false):
		score += 10.0
	if story_flags.get("ghost_challenged", false):
		score += 5.0

	# Zero awareness helps understand Ghost's nature
	var zero_awareness := _get_zero_awareness()
	score += remap(zero_awareness, 0, 5, 0, 15)

	# Moderate relationships (not too attached)
	var avg_rel := _get_average_relationship()
	if avg_rel >= 30 and avg_rel <= 60:
		score += 10.0 # The ghost walks between worlds

	return clampf(score, 0, 100)


func _score_contradiction() -> float:
	## ENDING_E "contradiction": Mixed choices, balanced paths, no clear moral lean
	## The ambiguous ending — the player couldn't commit to one path.
	var score := 0.0

	# Moral alignment near zero (balanced)
	var moral := _get_moral_alignment()
	var moral_balance: float = 100.0 - absf(moral) # Higher when closer to 0
	score += remap(moral_balance, 0, 100, 0, 30)

	# Mixed relationship levels (not all high, not all low)
	var rels := GameManager.relationships
	var affinities: Array = []
	for char_id in ["maya", "diesel", "nikko", "jade"]:
		affinities.append(rels.get_affinity(char_id))

	# High variance in relationships suggests contradictory behavior
	var avg: float = 0.0
	for a in affinities:
		avg += a
	avg /= max(affinities.size(), 1)

	var variance: float = 0.0
	for a in affinities:
		variance += (a - avg) * (a - avg)
	variance /= max(affinities.size(), 1)
	# High variance (spread-out relationships) increases score
	score += remap(variance, 0, 2000, 0, 20)

	# Mixed choice categories in the choice system
	if GameManager.has_node("ChoiceSystem"):
		var cs: ChoiceSystem = GameManager.get_node("ChoiceSystem")
		var moral_count: int = cs.get_total_by_category(ChoiceSystem.TYPE_MORAL)
		var strat_count: int = cs.get_total_by_category(ChoiceSystem.TYPE_STRATEGIC)
		var rel_count: int = cs.get_total_by_category(ChoiceSystem.TYPE_RELATIONSHIP)
		var total: int = max(moral_count + strat_count + rel_count, 1)
		# More balanced distribution = higher score
		var ideal_ratio := 1.0 / 3.0
		var balance_score := 100.0 - (
			absf(float(moral_count) / total - ideal_ratio) +
			absf(float(strat_count) / total - ideal_ratio) +
			absf(float(rel_count) / total - ideal_ratio)
		) * 150.0
		score += clampf(remap(balance_score, 0, 100, 0, 20), 0, 20)

	# No clear path commitment
	if GameManager.story.chosen_path == "":
		score += 15.0
	else:
		score += 5.0

	# Not having beat the Ghost (unresolved)
	if not GameManager.story.story_flags.get("beat_ghost", false):
		score += 5.0

	return clampf(score, 0, 100)


func _score_price() -> float:
	## ENDING_F "price": Moral compromises + Zero alliance
	## The dark ending — you won, but at what cost?
	var score := 0.0
	var flags := GameManager.player_data
	var story_flags := GameManager.story.story_flags

	# Negative moral alignment
	var moral := _get_moral_alignment()
	if moral < 0:
		score += remap(-moral, 0, 100, 0, 30)

	# Zero alliance
	if story_flags.get("accepted_zero_offer", false):
		score += 20.0
	if flags.has_choice_flag("zero_gift_accepted"):
		score += 5.0

	# Zero relationship level
	var zero_affinity: int = GameManager.relationships.get_affinity("zero")
	score += remap(zero_affinity, 0, 100, 0, 15)

	# Sabotage and cheating flags
	if flags.has_choice_flag("sabotage_accepted"):
		score += 5.0
	if flags.has_choice_flag("cheater_exposed"):
		score += 5.0
	if flags.has_choice_flag("reputation_ruthless"):
		score += 5.0

	# Low relationships with former allies
	var rels := GameManager.relationships
	var maya_aff: int = rels.get_affinity("maya")
	var diesel_aff: int = rels.get_affinity("diesel")
	if maya_aff < 30:
		score += 5.0
	if diesel_aff < 30:
		score += 5.0

	# Betrayal flags
	if flags.has_choice_flag("betrayed_maya"):
		score += 5.0
	if flags.has_choice_flag("betrayed_diesel"):
		score += 5.0

	return clampf(score, 0, 100)


func _score_secret() -> float:
	## ENDING_SECRET "secret_beginning": Complete in <120 hours + all high relationships +
	## selfless choices + beat Ghost with every car type.
	## The true ending — extremely hard to achieve.
	var score := 0.0
	var flags := GameManager.player_data
	var story_flags := GameManager.story.story_flags
	var rels := GameManager.relationships

	# Must beat Ghost
	if not story_flags.get("beat_ghost", false):
		return 0.0 # Hard requirement

	# Play time under 120 hours (432000 seconds)
	var play_time: float = flags.play_time_seconds
	if play_time < 432000.0:
		score += 20.0
	else:
		return 0.0 # Hard requirement

	# All high relationships (60+ affinity on all four main characters)
	var all_high := true
	for char_id in ["maya", "diesel", "nikko", "jade"]:
		var aff: int = rels.get_affinity(char_id)
		if aff >= 60:
			score += 10.0
		else:
			all_high = false
	if not all_high:
		return 0.0 # Hard requirement

	# Selfless choices (compassionate moral alignment)
	var moral := _get_moral_alignment()
	if moral >= 30:
		score += 15.0
	else:
		return 0.0 # Hard requirement

	# Beat Ghost with every car type
	if story_flags.get("ghost_beat_sedan", false):
		score += 3.0
	if story_flags.get("ghost_beat_coupe", false):
		score += 3.0
	if story_flags.get("ghost_beat_hatch", false):
		score += 3.0
	if story_flags.get("ghost_beat_muscle", false):
		score += 3.0
	if story_flags.get("ghost_beat_exotic", false):
		score += 3.0

	var beat_all_types: bool = (
		story_flags.get("ghost_beat_sedan", false)
		and story_flags.get("ghost_beat_coupe", false)
		and story_flags.get("ghost_beat_hatch", false)
		and story_flags.get("ghost_beat_muscle", false)
		and story_flags.get("ghost_beat_exotic", false)
	)
	if not beat_all_types:
		return 0.0 # Hard requirement

	return clampf(score, 0, 100)


# --- Helper methods ---

func _get_moral_alignment() -> float:
	if GameManager.has_node("MoralTracker"):
		var tracker: MoralTracker = GameManager.get_node("MoralTracker")
		return tracker.get_alignment()
	return GameManager.player_data._moral_alignment


func _get_zero_awareness() -> int:
	if GameManager.has_node("MoralTracker"):
		var tracker: MoralTracker = GameManager.get_node("MoralTracker")
		return tracker.get_zero_awareness()
	return GameManager.player_data._zero_awareness


func _get_average_relationship() -> float:
	var total := 0.0
	var count := 0
	for char_id in ["maya", "diesel", "nikko", "jade"]:
		total += GameManager.relationships.get_affinity(char_id)
		count += 1
	return total / max(count, 1)
