# MIDNIGHT GRIND

**Narrative Arcade Racing / Car Culture RPG** | Godot 4

> *From Nothing to Everything to Nothing to Legend*

Set in the neon-drenched coastal city of **Nova Pacifica**, MIDNIGHT GRIND is a narrative-driven street racing RPG wrapped in a deliberate PS1/PS2 era aesthetic. Build your car from the ground up, forge unbreakable bonds with your crew, navigate the invisible force known as Zero, and risk everything in pink slip races where losing means losing your ride forever.

## Project Structure

```
midnight/
├── project.godot            # Godot 4 project configuration
├── src/                     # All game source code
│   ├── autoload/            # Global singletons
│   │   ├── event_bus.gd     # Decoupled signal bus
│   │   ├── game_manager.gd  # Central state + subsystem manager
│   │   ├── save_manager.gd  # Save/load system
│   │   ├── audio_manager.gd # Music, SFX, engine, voice
│   │   └── player_data.gd   # Player state container
│   ├── vehicles/            # Vehicle systems
│   │   ├── vehicle_data.gd      # Vehicle data resource
│   │   ├── vehicle_controller.gd # Physics controller (VehicleBody3D)
│   │   ├── part_database.gd     # Part definitions + lookup
│   │   └── garage_system.gd     # Collection management
│   ├── racing/              # Race management
│   │   ├── race_manager.gd  # Race lifecycle
│   │   ├── race_data.gd     # Race configuration
│   │   └── race_ai.gd       # AI racer controller
│   ├── narrative/           # Story + dialogue
│   │   ├── story_manager.gd    # 4-act Harmon Circle narrative
│   │   └── dialogue_system.gd  # Dialogue + choice engine
│   ├── characters/          # Character systems
│   │   ├── relationship_system.gd # Affinity tracking (0-100)
│   │   └── character_data.gd     # Character definitions
│   ├── progression/         # RPG systems
│   │   ├── reputation_system.gd  # REP tiers (0-5)
│   │   ├── economy_system.gd     # Cash flow
│   │   └── skill_tree_system.gd  # 4 skill trees
│   ├── police/              # Heat + pursuit
│   │   └── police_system.gd
│   └── world/               # World state
│       └── world_time_system.gd  # Time + weather
├── scenes/                  # Scene files
│   ├── main/                # Main menu + scene management
│   ├── hud/                 # Race HUD + free roam HUD
│   ├── dialogue/            # Dialogue UI
│   ├── race/                # Race scenes
│   ├── garage/              # Garage/customization scenes
│   └── menus/               # Pause, settings, etc.
├── data/                    # JSON data files
│   ├── vehicles/            # Vehicle definitions
│   ├── parts/               # Part definitions
│   ├── dialogue/            # Dialogue scripts
│   ├── missions/            # Mission definitions
│   ├── characters/          # Character data
│   └── skills/              # Skill tree data
├── assets/                  # Game assets
│   ├── shaders/             # PSX retro + post-process shaders
│   ├── models/              # 3D models
│   ├── textures/            # Textures
│   ├── audio/               # Music, SFX, engine, voice
│   ├── fonts/               # Fonts
│   └── ui/                  # UI assets
└── docs/                    # Design documentation
    └── GDD.md               # Game Design Document v3.0
```

## Core Systems

| System | Status | Description |
|--------|--------|-------------|
| Event Bus | Ready | Decoupled signal-based communication |
| Game Manager | Ready | Central state machine + subsystem orchestration |
| Vehicle Data | Ready | Full vehicle state with parts, wear, affinity |
| Part Database | Ready | 24 default parts across 3 tiers (Stock/Street/Sport) |
| Garage System | Ready | Vehicle collection, part installation, pink slip outcomes |
| Vehicle Controller | Ready | VehicleBody3D physics with arcade-sim handling |
| Race Manager | Ready | Full race lifecycle: setup, countdown, racing, results |
| Race AI | Ready | Path-following AI with rubber banding |
| Reputation | Ready | 6-tier REP system gating content access |
| Economy | Ready | Cash flow with race payouts and transaction log |
| Relationships | Ready | 5 characters with 0-100 affinity, 5 levels each |
| Skill Trees | Ready | 4 trees (Speed Demon, Ghost Line, Street Survivor, Technician) |
| Dialogue | Ready | JSON-driven dialogue with branching choices and consequences |
| Story Manager | Ready | 4-act Harmon Circle with mission tracking and 6+ endings |
| Police | Ready | 5 heat levels with pursuit and bust mechanics |
| World Time | Ready | Day/night cycle (1:4 real-to-game) with weather system |
| Save/Load | Ready | JSON save files with full game state serialization |
| Audio Manager | Ready | Music crossfade, SFX, engine audio, voice playback |
| PSX Shader | Ready | Vertex snapping, affine texture mapping, post-processing |

## MVP Scope

Act 1, Chapters 1-2 (~12 hours of content):
- 1 vehicle (Sakura GTR) + Starter Beater
- 3 part tiers (Stock, Street, Sport)
- 1 district (Downtown Nova Pacifica)
- Characters: Maya Torres (full), Nikko Cross (intro), Diesel (tease)
- Race types: Street Sprint, Drag Race, Time Attack, Pink Slip

## Development

Built with **Godot 4.2** (GL Compatibility renderer).

```bash
# Open in Godot Editor
godot project.godot
```

## Controls

| Action | Key |
|--------|-----|
| Accelerate | W / Up Arrow |
| Brake | S / Down Arrow |
| Steer Left | A / Left Arrow |
| Steer Right | D / Right Arrow |
| Handbrake | Space |
| Nitrous | Num Enter |
| Shift Up | E |
| Shift Down | Q |
| Interact | F |
| Pause | Escape |

## License

All rights reserved.
