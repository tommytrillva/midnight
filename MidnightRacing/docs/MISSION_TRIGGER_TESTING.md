# Mission Trigger System - Testing Guide

## Overview
The mission trigger system enables story missions to be triggered when the player enters specific areas in the game world. This guide explains how to test the system.

## Files Created
1. **scripts/triggers/mission_trigger.gd** - Main trigger script
2. **scripts/test/test_player.gd** - Simple test player for trigger testing
3. **project.godot** - Updated with "interact" input action (E key)

## Mission Trigger Features

### Core Functionality
- **Player Detection**: Detects when player/vehicle enters trigger area
- **Mission Availability**: Checks if mission requirements are met via StoryManager
- **UI Indicators**: Shows visual marker and interaction prompt when mission available
- **Activation Modes**: Supports auto-trigger or manual activation (press E)
- **StoryManager Integration**: Connects to story system for mission state management

### Configurable Properties
- `mission_id` (String) - ID of mission from StoryManager.missions
- `character_name` (String) - Character to trigger dialogue with
- `auto_trigger` (bool) - Auto-activate vs. require player interaction
- `show_indicator` (bool) - Display visual indicator
- `interaction_key` (String) - Input action name (default: "interact")
- `indicator_color` (Color) - Color of visual marker
- `indicator_height` (float) - Height of marker above trigger
- `indicator_scale` (float) - Scale of visual indicator

## MayaTrigger Configuration

The MayaTrigger in downtown.tscn is configured as follows:
- **Position**: (100, 1, 50) - Matches Maya's NPC marker location
- **Mission ID**: "meet_maya"
- **Character Name**: "Maya"
- **Auto Trigger**: false (requires player to press E)
- **Show Indicator**: true

## Testing Methods

### Method 1: Using Test Player (Recommended for Trigger Testing)

1. **Add Test Player to Scene**:
   - Open `scenes/districts/downtown.tscn` in Godot
   - Add a CharacterBody3D node
   - Attach script: `res://scripts/test/test_player.gd`
   - Add a CollisionShape3D child (use CapsuleShape3D)
   - Add a MeshInstance3D child for visibility (use CapsuleMesh)
   - Position near Maya's location: (95, 1, 50)

2. **Run the Scene**:
   - Press F6 to run the current scene
   - Use WASD to move the test player
   - Hold Space to sprint

3. **Test Trigger Activation**:
   - Move toward Maya's position (100, 50)
   - Watch console for: "Player entered mission trigger: meet_maya"
   - Check if mission is available (requirements met)
   - If available, visual indicator should appear
   - Press E to interact and trigger the mission
   - Check console for: "Activating mission: meet_maya"
   - Verify StoryManager triggers the mission

### Method 2: Using Full Vehicle System

1. **Prerequisites**:
   - Vehicle system must be implemented
   - Player vehicle must be spawned in downtown
   - Vehicle must be in "player_vehicle" group

2. **Testing Process**:
   - Start game in free roam mode
   - Drive to Maya's location (100, 50)
   - Follow same trigger activation process

## Expected Behavior

### When Mission Requirements NOT Met
- Player can enter trigger area
- No visual indicator appears
- Interaction prompt does not show
- Console shows availability check result

### When Mission Requirements ARE Met
1. Player enters trigger area
2. Console: "Player entered mission trigger: meet_maya"
3. Console: "Mission available: Street Connections"
4. Visual indicator appears (yellow rotating cylinder)
5. Interaction prompt shows: "[E] Interact"
6. Player presses E
7. Console: "Activating mission: meet_maya"
8. StoryManager.trigger_dialogue() called with "Maya"
9. StoryManager.trigger_mission() called with "meet_maya"
10. Phone notification sent: "New Mission - Street Connections"
11. Indicator disappears

## Testing Mission Requirements

The "meet_maya" mission requires:
- `completed_missions: ["intro_race"]`

To test with requirements met:
```gdscript
# Add to test script or console:
StoryManager.missions["intro_race"].completed = true
```

To test without requirements:
```gdscript
# Default state - intro_race not completed
```

## Debugging

### Console Output to Watch For:
- "MissionTrigger initialized: meet_maya"
- "Player entered mission trigger: meet_maya"
- "Mission available: Street Connections"
- "Activating mission: meet_maya"
- "Dialogue triggered with: Maya"
- "Mission triggered: Street Connections"

### Visual Debugging:
- Enable "Visible Collision Shapes" in Godot editor (Debug menu)
- Check trigger collision shape size (3x2x3 box)
- Verify trigger position matches Maya's marker
- Check indicator visibility

### Common Issues:

1. **Trigger not detecting player**:
   - Verify player is in "player" or "player_vehicle" group
   - Check collision layers/masks
   - Ensure CollisionShape3D is present

2. **Mission not available**:
   - Check mission requirements in StoryManager
   - Verify mission hasn't already been completed
   - Check mission.triggered flag

3. **Indicator not showing**:
   - Verify show_indicator = true
   - Check if mission is available
   - Check indicator_height setting

4. **Interact key not working**:
   - Verify "interact" action in project.godot Input Map
   - Check auto_trigger setting
   - Ensure player is in trigger area

## Creating Additional Triggers

To add more mission triggers:

1. Add Area3D node to MissionTriggers group
2. Add CollisionShape3D child
3. Attach mission_trigger.gd script
4. Configure properties:
   - Set mission_id from StoryManager.missions
   - Set character_name if applicable
   - Choose auto_trigger or manual
   - Position at mission location

Example for Diesel trigger:
```gdscript
mission_id = "diesel_challenge"
character_name = "Diesel"
auto_trigger = false
show_indicator = true
# Position at (-200, 1, 150)
```

## Integration Checklist

- [x] Mission trigger script created
- [x] Attached to MayaTrigger in downtown.tscn
- [x] Input action "interact" added to project
- [x] StoryManager integration
- [x] Visual indicator system
- [x] Test player script created
- [ ] Test with actual vehicle system
- [ ] Test mission completion flow
- [ ] Test multiple triggers
- [ ] Add dialogue system integration
- [ ] Add UI notification display

## Next Steps

1. Implement dialogue system for character interactions
2. Create UI for mission notifications and prompts
3. Add more mission triggers for other story missions
4. Implement trigger disable/enable based on story progress
5. Add trigger state persistence (save/load)
6. Create trigger editor tool for easier placement
