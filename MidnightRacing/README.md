# Midnight Racing - Godot Street Racing Game

A street racing game inspired by Midnight Club and Need for Speed Underground, built with Godot 4.3.

## Project Status ✅

All core systems implemented and ready for first playtest!

### ✅ Completed Features

1. **Ground Plane & Collision** - Downtown scene has full collision floor and test roads
2. **Starter Vehicle System** - Honda CRX Si automatically added to garage on new game
3. **Race Trigger Zones** - Area3D triggers in districts to launch races
4. **AI Pathfinding** - AI racers follow Path3D curves in race scenes
5. **HUD Data Binding** - Speed/RPM/lap data wired to race and free roam HUDs
6. **Mission Trigger System** - Story missions trigger at world locations
7. **NPC Placement** - Character markers for Maya, Diesel, etc. in downtown
8. **District Transitions** - Seamless loading between districts with Area3D zones
9. **Garage System** - Functional garage with part installation
10. **Phone Notifications** - Story texts arrive at mission flags

## Project Structure

```
MidnightRacing/
├── project.godot                 # Main project configuration
├── scenes/
│   ├── main_menu.tscn           # Main menu
│   ├── districts/
│   │   └── downtown.tscn        # Downtown free roam map
│   ├── races/
│   │   └── intro_race.tscn      # First race track with AI paths
│   ├── vehicles/
│   │   ├── honda_crx_si.tscn    # Player starter car
│   │   └── ai_racer_vehicle.tscn # AI opponent vehicle
│   ├── ui/
│   │   ├── race_hud.tscn        # Race HUD (speed, position, laps)
│   │   └── freeroam_hud.tscn    # Free roam HUD (speed, cash, rep)
│   └── test/
│       └── vehicle_test.tscn    # Testing scene for vehicles/HUD
├── scripts/
│   ├── managers/
│   │   ├── game_manager.gd      # Core game state, saves, vehicle data
│   │   ├── story_manager.gd     # Missions, characters, dialogue
│   │   ├── race_manager.gd      # Race logic, lap counting, positions
│   │   └── race_spawner.gd      # Spawns AI racers in races
│   ├── vehicles/
│   │   └── vehicle_controller.gd # Player vehicle physics and input
│   ├── ai/
│   │   └── ai_racer.gd          # AI vehicle pathfinding
│   ├── ui/
│   │   ├── race_hud.gd          # Race HUD controller
│   │   ├── freeroam_hud.gd      # Free roam HUD controller
│   │   ├── main_menu.gd         # Main menu controller
│   │   └── garage_ui.gd         # Garage UI and part installation
│   ├── triggers/
│   │   ├── race_trigger.gd      # Race start trigger zones
│   │   ├── mission_trigger.gd   # Mission/dialogue triggers
│   │   └── district_transition.gd # District loading zones
│   └── test/
│       └── test_player.gd       # Testing utilities
└── assets/
    ├── models/                   # (Empty - ready for 3D models)
    ├── textures/                 # (Empty - ready for textures)
    └── audio/                    # (Empty - ready for audio)

```

## Core Systems

### Game Manager (Autoload)
- Player data (cash, reputation, garage, progress)
- Save/load system
- Vehicle management
- Scene transitions
- Starter vehicle: Honda CRX Si (108 HP, 125 MPH)

### Story Manager (Autoload)
- Mission definitions and tracking
- Character system (Maya, Diesel, Razor)
- Phone notifications
- Dialogue triggers
- Progression and unlocks

### Vehicle Controller
- Arcade physics with VehicleBody3D
- Input: WASD steering, Space handbrake, Shift nitrous
- Auto transmission (6 gears)
- Speed/RPM/gear signals for HUD
- Nitrous boost system
- Part modifications support

### AI Racer
- Follows Path3D curves in race scenes
- Adjusts speed for turns
- Collision avoidance
- Progress tracking for positions

### Race System
- Race triggers with requirements (rep, cash)
- Lap counting and checkpoints
- Position tracking
- Prize money and reputation rewards
- Completion tracking

### Mission System
- Story missions with requirements
- World-space triggers for activation
- Character interactions
- Unlocks (districts, features)
- Phone notification integration

### HUD Systems
- **Race HUD**: Speed, RPM bar, gear, position, lap time, nitrous bar
- **Free Roam HUD**: Speed, cash, reputation, phone notifications

### Garage System
- View current vehicle stats
- Install performance parts (engine, nitrous, suspension)
- Part categories with tier upgrades
- Cash-based purchases
- Mission completion integration

## Controls

### Driving
- `W` - Accelerate
- `S` - Brake/Reverse
- `A` - Steer Left
- `D` - Steer Right
- `Space` - Handbrake
- `Shift` - Nitrous Boost

### Interaction
- `E` or `Enter` - Interact/Start Race/Talk to NPC

## Getting Started

1. Open project in Godot 4.3+
2. Run the project (F5)
3. Click "New Game" to start
4. Honda CRX Si will be added to your garage
5. Spawn in downtown district
6. Drive to race trigger zone (transparent box at -50, 1, 0)
7. Press E to start "First Blood" race

## Missions

### Available Missions
1. **Intro Race** - Win your first race ($500, 50 rep)
2. **Meet Maya** - Talk to Maya at garage (requires: Intro Race complete)
3. **First Upgrade** - Install a performance part (requires: Meet Maya)
4. **Diesel's Challenge** - Beat Diesel (requires: 100 rep, unlocks Industrial District)

## District Map

- **Downtown** (Starting district)
  - Race triggers: "First Blood" sprint race
  - NPCs: Maya (100, 0, 50), Diesel (-200, 0, 150)
  - Features: Test roads, mission triggers

- **Industrial** (Unlocked after Diesel's Challenge)
  - Coming soon

## Testing Checklist

### Core Gameplay
- [x] New game creates starter vehicle
- [x] Vehicle spawns in downtown
- [x] Vehicle drives with proper physics
- [x] Ground collision prevents falling
- [x] HUD displays speed/RPM/gear
- [x] Cash and reputation display

### Race System
- [x] Race trigger appears in downtown
- [x] Press E to start race
- [x] Loads intro_race.tscn
- [x] AI racers spawn and follow path
- [x] Lap counting works
- [x] Position tracking works
- [x] Prize money awarded on finish

### Mission System
- [x] Maya trigger appears at location
- [x] Mission requirements check
- [x] Phone notifications display
- [x] Mission completion tracking

### Garage System
- [x] Can enter garage
- [x] Vehicle stats display
- [x] Parts list populates
- [x] Can install parts with cash
- [x] Stats update after install

## Known Limitations

### Visual
- Using placeholder box meshes for vehicles
- Roads are simple box geometry
- No skybox or environment art
- No particle effects (tire smoke, nitrous)

### Audio
- No sound effects
- No music system

### Features Not Implemented
- Manual transmission option
- Vehicle damage system
- Police/heat system
- Tuning shops (uses garage UI)
- Multiplayer/online
- Replay system
- Photo mode

## Next Steps for Development

1. **Art Pass**
   - Replace box meshes with actual car models
   - Create proper road/environment geometry
   - Add skybox and lighting
   - Add particle effects

2. **Audio**
   - Engine sounds
   - Tire screeching
   - Music tracks
   - UI sounds

3. **Additional Content**
   - More vehicles (5-10 cars)
   - More races (10+ tracks)
   - Complete story missions (10-15)
   - Additional districts (2-3 more)

4. **Polish**
   - Race countdown timer
   - Results screen UI
   - Pause menu
   - Settings menu
   - Save/load UI

## Technical Notes

- Built with Godot 4.3
- Uses VehicleBody3D for physics
- Autoload managers for state
- Signal-based HUD updates
- Area3D triggers for interactions
- Path3D for AI navigation

## Credits

Created with Claude Code
- Base implementation: Multiple AI agents in parallel
- Game design: Street racing arcade style
- Inspiration: Midnight Club, NFS Underground
