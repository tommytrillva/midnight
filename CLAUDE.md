# MIDNIGHT GRIND — Development Notes

## Project Overview
Narrative Arcade Racing / Car Culture RPG built in Godot 4.
PS1/PS2 retro aesthetic. 200-hour Harmon Circle story arc.

## Architecture
- **Autoloads**: EventBus (signals), GameManager (state), SaveManager, AudioManager
- **Subsystems**: Created as child nodes of GameManager, all serializable
- **Data-Driven**: Vehicles, parts, dialogue, and missions loaded from JSON in `data/`
- **Event-Driven**: All systems communicate through EventBus signals, not direct references

## Key Design Decisions
- All game-wide signals declared in EventBus (not on individual nodes)
- Subsystems are plain Nodes/RefCounted, not scenes, for easy instantiation
- VehicleData is a Resource for editor integration
- Dialogue system loads JSON with condition checking for branching
- Skill tree progress survives Act 3's Fall (by design per GDD)
- Police heat is per-session, not saved (resets on load)

## Code Conventions
- GDScript with static typing where practical
- class_name on all reusable classes
- Serialization via serialize()/deserialize() pattern on all subsystems
- Print statements prefixed with [SystemName] for debug logging

## MVP Focus
Act 1, Chapters 1-2. One vehicle (Sakura GTR). One district (Downtown).
Maya Torres relationship system fully functional.
