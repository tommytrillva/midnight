## Global event bus for decoupled communication between systems.
## All game-wide signals are declared here to avoid tight coupling.
extends Node

# --- Race Events ---
signal race_started(race_data: Dictionary)
signal race_finished(results: Dictionary)
signal race_countdown_tick(count: int)
signal lap_completed(racer_id: int, lap: int, time: float)
signal checkpoint_reached(racer_id: int, checkpoint_index: int)
signal race_position_changed(racer_id: int, new_position: int)

# --- Vehicle Events ---
signal vehicle_collision(vehicle_id: int, impact_force: float)
signal vehicle_damaged(vehicle_id: int, damage_amount: float)
signal vehicle_totaled(vehicle_id: int)
signal nitro_activated(vehicle_id: int)
signal nitro_depleted(vehicle_id: int)
signal gear_shifted(vehicle_id: int, gear: int)

# --- Economy Events ---
signal cash_changed(old_amount: int, new_amount: int)
signal cash_earned(amount: int, source: String)
signal cash_spent(amount: int, item: String)
signal insufficient_funds(cost: int)

# --- Reputation Events ---
signal rep_changed(old_rep: int, new_rep: int)
signal rep_tier_changed(old_tier: int, new_tier: int)
signal rep_earned(amount: int, source: String)
signal rep_lost(amount: int, source: String)

# --- Relationship Events ---
signal relationship_changed(character_id: String, old_value: int, new_value: int)
signal relationship_level_up(character_id: String, new_level: int)
signal relationship_level_down(character_id: String, new_level: int)

# --- Narrative Events ---
signal story_chapter_started(act: int, chapter: int)
signal story_chapter_completed(act: int, chapter: int)
signal mission_started(mission_id: String)
signal mission_completed(mission_id: String, outcome: Dictionary)
signal mission_failed(mission_id: String, reason: String)
signal choice_made(choice_id: String, option_index: int, option_data: Dictionary)
signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String)
signal dialogue_choice_presented(choices: Array)

# --- Garage/Customization Events ---
signal part_installed(vehicle_id: String, slot: String, part_data: Dictionary)
signal part_removed(vehicle_id: String, slot: String)
signal vehicle_acquired(vehicle_id: String, source: String)
signal vehicle_lost(vehicle_id: String, reason: String)
signal vehicle_stats_changed(vehicle_id: String, stats: Dictionary)

# --- Pink Slip Events ---
signal pink_slip_challenge_offered(challenger_data: Dictionary)
signal pink_slip_accepted(race_data: Dictionary)
signal pink_slip_won(won_vehicle: Dictionary)
signal pink_slip_lost(lost_vehicle: Dictionary)

# --- Police Events ---
signal heat_level_changed(old_level: int, new_level: int)
signal pursuit_started()
signal pursuit_escaped()
signal busted(fine: int)
signal vehicle_impounded(vehicle_id: String)

# --- Skill Events ---
signal xp_earned(amount: int, source: String)
signal level_up(new_level: int)
signal skill_point_earned(points: int)
signal skill_unlocked(tree: String, skill_id: String)

# --- World/Time Events ---
signal time_period_changed(period: String)
signal weather_changed(condition: String)
signal district_entered(district_id: String)
signal district_unlocked(district_id: String)

# --- UI Events ---
signal hud_message(text: String, duration: float)
signal notification_popup(title: String, body: String, icon: String)
signal screen_fade_in(duration: float)
signal screen_fade_out(duration: float)

# --- Save Events ---
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)

# --- Ghost Events ---
signal ghost_appeared()
signal ghost_race_started()
signal ghost_escaped()
