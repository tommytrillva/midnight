# Vehicle Test Scene

## Purpose
This test scene (`vehicle_test.tscn`) is an integration test for verifying HUD data binding with the vehicle system.

## Location
`scenes/test/vehicle_test.tscn`

## What It Tests

### 1. Vehicle Signal Emissions
- **speed_changed** - Emitted every frame with current speed in MPH
- **rpm_changed** - Emitted every frame with current RPM (0-7000)
- **gear_changed** - Emitted when gear changes (1-6)

### 2. Race HUD Components
- Speed display (MPH)
- RPM bar (visual progress bar)
- Gear indicator
- Position label (race placement)
- Lap counter
- Lap time
- Nitrous bar

### 3. Free Roam HUD Components
- Speed display (MPH)
- Cash display (from GameManager)
- Reputation display (from GameManager)
- Notification panel

### 4. Vehicle Features
- Acceleration (W key)
- Braking (S key)
- Steering (A/D keys)
- Handbrake (Space)
- Nitrous boost (Shift)
- Automatic transmission (6 gears)

## How to Use

1. **Open the Scene**
   - In Godot Editor, open `scenes/test/vehicle_test.tscn`
   - Press F6 or click "Run Current Scene"

2. **Test Controls**
   - Drive the vehicle using WASD keys
   - Watch the HUD elements update in real-time
   - Use the test panel on the right side to:
     - Toggle between Race HUD and Free Roam HUD
     - Refill nitrous
     - Add cash (to test Free Roam HUD)
     - Add reputation (to test Free Roam HUD)

3. **Verify Signals**
   - The test panel shows signal status indicators:
     - "Speed Signal: OK (Receiving)" - Green when working
     - "RPM Signal: OK (Receiving)" - Green when working
     - "Gear Signal: OK (Receiving)" - Green when working

4. **Console Output**
   - Check the Godot console for detailed test logs
   - All test messages are prefixed with `[TEST]`
   - Errors are prefixed with `[TEST ERROR]`
   - Warnings are prefixed with `[TEST WARNING]`

## Expected Behavior

### On Scene Load
1. Vehicle spawns above ground plane and falls into place
2. GameManager is initialized with test data (cash: $5000, rep: 100)
3. Both HUDs connect to the vehicle automatically
4. Test script verifies all connections
5. Console shows connection status for all signals
6. Test panel shows "Status: Ready - Drive to test!"

### While Driving
1. Speed label updates in real-time (0-125 MPH)
2. RPM bar fills as speed increases (0-100%)
3. Gear indicator shows current gear (1-6)
4. Automatic gear shifts occur based on speed
5. Nitrous bar depletes when using boost (Shift key)
6. All signal indicators turn green when signals are received

### When Toggling HUDs
1. Race HUD shows: Speed, RPM, Gear, Position, Lap, Time, Nitrous
2. Free Roam HUD shows: Speed, Cash, Reputation
3. Only one HUD visible at a time

## Bug Fixes Applied

### 1. Missing gear_changed Signal Emission
**File:** `scripts/vehicles/vehicle_controller.gd`
**Issue:** The `gear_changed` signal was declared but never emitted
**Fix:** Added gear change detection in `auto_shift()` function to emit signal when gear changes

### 2. Incorrect RPM Bar Calculation
**File:** `scripts/ui/race_hud.gd`
**Issue:** RPM bar value calculation was incorrect (divided by 70.0 instead of 7000.0)
**Fix:** Changed to `(rpm / 7000.0) * 100.0` for correct percentage calculation

## Files Created

1. `scenes/test/vehicle_test.tscn` - Main test scene
2. `scenes/test/vehicle_test.gd` - Test script with verification logic
3. `scenes/test/README.md` - This documentation

## Integration Points

### Vehicle Controller (`vehicle_controller.gd`)
- Emits signals: `speed_changed`, `rpm_changed`, `gear_changed`
- Must be in "player_vehicle" group
- Provides getters: `get_speed()`, `get_rpm()`, `get_gear()`, `get_nitrous()`

### Race HUD (`race_hud.gd`)
- Connects to vehicle signals in `find_player_vehicle()`
- Updates display elements in `_process()` and signal callbacks
- Uses `@onready` variables for all UI elements

### Free Roam HUD (`freeroam_hud.gd`)
- Connects to vehicle `speed_changed` signal
- Reads from `GameManager.player_data` for cash/rep
- Provides update methods: `update_cash_display()`, `update_rep_display()`

### GameManager (`game_manager.gd`)
- Autoloaded singleton
- Stores player data: cash, reputation, garage, current vehicle
- Provides methods: `add_cash()`, `spend_cash()`, `add_reputation()`, `get_current_vehicle()`

## Notes

- The vehicle uses automatic transmission (no manual gear control)
- Nitrous depletes at 0.5 per frame when active
- Max speed is 125 MPH (configurable in vehicle scene)
- Max RPM is 7000 (used for gauge calculations)
- Ground plane is 100x100 units for testing
