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
signal speed_changed(vehicle_id: int, speed_kmh: float)
signal gear_shifted(vehicle_id: int, gear: int)
signal nitro_activated(vehicle_id: int)
signal nitro_depleted(vehicle_id: int)
signal nitro_flame(vehicle_id: int, active: bool)

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
signal origin_chosen(origin_id: String)

# --- Choice/Consequence Events ---
signal choice_recorded(choice_id: String, category: String)
signal consequence_applied(consequence: Dictionary, source: String)
signal delayed_consequence_fired(mission_id: String, source_choice: String)
signal cumulative_threshold_reached(counter_id: String)
signal moral_alignment_shifted(old_value: float, new_value: float, reason: String)
signal zero_awareness_changed(old_level: int, new_level: int)
signal ending_determined(ending_id: String)
signal path_diverged(path: String)

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
signal save_screen_requested()
signal load_screen_requested()

# --- Save Events ---
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)

# --- Audio Events ---
signal music_track_changed(track_title: String, artist: String)
signal music_playlist_changed(playlist_id: String)
signal radio_next_track()
signal radio_previous_track()
signal radio_toggle()
signal game_state_audio_changed(state: String)
signal drift_started(vehicle_id: int)
signal drift_ended(vehicle_id: int, score: float)
signal tire_screech(vehicle_id: int, slip_intensity: float)
signal engine_rpm_updated(vehicle_id: int, rpm: float, throttle: float)
signal turbo_blowoff(vehicle_id: int)
signal exhaust_pop(vehicle_id: int)
signal countdown_beep(count: int)
signal countdown_go()
signal ambient_zone_entered(zone_type: String)

# --- Drift Scoring Events ---
signal drift_zone_entered(zone_name: String, multiplier: float)
signal drift_zone_exited(zone_name: String)
signal drift_combo_updated(combo_count: int, multiplier: float, current_score: float)
signal drift_combo_dropped()
signal drift_section_scored(section_index: int, score: float, rank: String)
signal drift_near_miss(distance: float, bonus: float)
signal drift_total_scored(total_score: float, rank: String, breakdown: Dictionary)

# --- Touge Events ---
signal touge_round_started(round_number: int, leader_id: int, chaser_id: int)
signal touge_round_ended(round_number: int, leader_id: int, gap_seconds: float)
signal touge_gap_updated(gap_meters: float, gap_seconds: float)
signal touge_overtake(chaser_id: int)
signal touge_leader_escaped(leader_id: int)
signal touge_match_result(winner_id: int, scores: Array)

# --- Circuit Events ---
signal circuit_lap_time(racer_id: int, lap: int, time: float)
signal circuit_best_lap(racer_id: int, lap: int, time: float)
signal circuit_pit_entered(racer_id: int)
signal circuit_pit_exited(racer_id: int, repairs: Dictionary)
signal circuit_dnf_warning(racer_id: int, seconds_behind: float)
signal circuit_dnf_timeout(racer_id: int)
signal circuit_leaderboard_updated(positions: Array)

# --- Ambient Dialogue Events ---
signal ambient_line_started(group_id: String, line_data: Dictionary)
signal ambient_line_finished(group_id: String)
signal ambient_exchange_started(group_id: String, exchange_data: Dictionary)
signal ambient_exchange_finished(group_id: String)
signal npc_group_entered(group_id: String)
signal npc_group_exited(group_id: String)

# --- Cinematic Events ---
signal cinematic_started(cinematic_id: String)
signal cinematic_finished(cinematic_id: String)
signal cinematic_skipped(cinematic_id: String)
signal letterbox_shown()
signal letterbox_hidden()
signal slow_motion_activated(scale: float)
signal slow_motion_deactivated()

# --- Ghost Events ---
signal ghost_appeared()
signal ghost_race_started()
signal ghost_escaped()

# --- Ending Events ---
signal ending_started(ending_id: String, ending_title: String)
signal ending_completed(ending_id: String, ending_title: String)
signal credits_started(ending_id: String, ending_title: String)
signal credits_finished(ending_id: String)
