## Small radio display overlaid on the free-roam HUD.
## Shows station name, current song, volume, and decorative equalizer bars.
## Fades to a minimal display after a brief period of inactivity.
class_name RadioHUD
extends Control

# ── Configuration ────────────────────────────────────────────────────
const FULL_DISPLAY_DURATION := 3.0  ## seconds before fading to minimal
const FADE_DURATION := 0.6
const EQ_BAR_COUNT := 5
const EQ_BAR_WIDTH := 4.0
const EQ_BAR_MAX_HEIGHT := 18.0
const EQ_BAR_MIN_HEIGHT := 3.0
const EQ_BAR_SPACING := 3.0
const EQ_BOUNCE_SPEED := 8.0  ## speed of equalizer animation

# ── Node References ──────────────────────────────────────────────────
@onready var panel: PanelContainer = $Panel
@onready var station_name_label: Label = $Panel/VBox/HBox/StationName
@onready var song_label: Label = $Panel/VBox/HBox/SongInfo
@onready var prev_btn: Button = $Panel/VBox/HBox/PrevBtn
@onready var next_btn: Button = $Panel/VBox/HBox/NextBtn
@onready var volume_label: Label = $Panel/VBox/HBox/Volume
@onready var eq_container: HBoxContainer = $Panel/VBox/HBox/EQBars
@onready var dj_label: Label = $Panel/VBox/DJLine
@onready var fav_btn: Button = $Panel/VBox/HBox/FavBtn

# ── State ────────────────────────────────────────────────────────────
var _full_display_timer: float = 0.0
var _is_full_display: bool = false
var _is_visible: bool = false  ## whether the radio HUD should show at all
var _fade_tween: Tween = null

## Equalizer bar state
var _eq_bars: Array[ColorRect] = []
var _eq_phases: Array[float] = []  ## phase offsets for each bar
var _eq_active: bool = false

## DJ line state
var _dj_timer: float = 0.0

## Reference to radio system (set externally or found via GameManager)
var _radio: RadioSystem = null

## Cached station color
var _station_color: Color = Color.WHITE


# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Start hidden
	panel.modulate.a = 0.0
	visible = true  ## Control itself is visible; panel alpha handles show/hide

	# Create equalizer bars
	_create_eq_bars()

	# DJ line starts hidden
	if dj_label:
		dj_label.text = ""
		dj_label.visible = false

	# Connect EventBus signals
	EventBus.radio_station_changed.connect(_on_station_changed)
	EventBus.music_track_changed.connect(_on_track_changed)
	EventBus.radio_dj_line.connect(_on_dj_line)
	EventBus.radio_volume_changed.connect(_on_volume_changed)
	EventBus.radio_song_favorited.connect(_on_song_favorited)

	# Connect buttons
	if prev_btn:
		prev_btn.pressed.connect(_on_prev_pressed)
	if next_btn:
		next_btn.pressed.connect(_on_next_pressed)
	if fav_btn:
		fav_btn.pressed.connect(_on_fav_pressed)

	# Set initial state
	_update_off_state()

	print("[Radio] RadioHUD ready.")


func _process(delta: float) -> void:
	# Full display timer
	if _is_full_display:
		_full_display_timer -= delta
		if _full_display_timer <= 0.0:
			_fade_to_minimal()

	# Animate equalizer bars
	if _eq_active and _is_visible:
		_animate_eq_bars(delta)

	# DJ line timer
	if _dj_timer > 0.0:
		_dj_timer -= delta
		if _dj_timer <= 0.0 and dj_label:
			dj_label.visible = false
			dj_label.text = ""


# ═════════════════════════════════════════════════════════════════════
#  Equalizer Bars
# ═════════════════════════════════════════════════════════════════════

func _create_eq_bars() -> void:
	## Create decorative equalizer ColorRect bars in the EQ container.
	if not eq_container:
		return

	# Clear any existing children
	for child: Node in eq_container.get_children():
		child.queue_free()
	_eq_bars.clear()
	_eq_phases.clear()

	for i: int in range(EQ_BAR_COUNT):
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(EQ_BAR_WIDTH, EQ_BAR_MIN_HEIGHT)
		bar.size = Vector2(EQ_BAR_WIDTH, EQ_BAR_MIN_HEIGHT)
		bar.color = _station_color
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		eq_container.add_child(bar)
		_eq_bars.append(bar)
		_eq_phases.append(randf() * TAU)  ## random initial phase


func _animate_eq_bars(delta: float) -> void:
	## Bounce the equalizer bars up and down pseudo-randomly.
	for i: int in range(_eq_bars.size()):
		_eq_phases[i] += delta * EQ_BOUNCE_SPEED * (0.8 + randf() * 0.4)
		var height: float = lerpf(
			EQ_BAR_MIN_HEIGHT,
			EQ_BAR_MAX_HEIGHT,
			(sin(_eq_phases[i]) + 1.0) * 0.5
		)
		_eq_bars[i].custom_minimum_size.y = height


func _set_eq_color(color: Color) -> void:
	_station_color = color
	for bar: ColorRect in _eq_bars:
		bar.color = color


# ═════════════════════════════════════════════════════════════════════
#  Display Control
# ═════════════════════════════════════════════════════════════════════

func _show_full_display() -> void:
	## Show the full radio display (station name, song, EQ, etc.).
	_is_full_display = true
	_is_visible = true
	_full_display_timer = FULL_DISPLAY_DURATION
	_eq_active = true

	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 1.0, 0.3)

	# Show all elements
	if song_label:
		song_label.visible = true
	if prev_btn:
		prev_btn.visible = true
	if next_btn:
		next_btn.visible = true
	if volume_label:
		volume_label.visible = true
	if fav_btn:
		fav_btn.visible = true


func _fade_to_minimal() -> void:
	## Fade to minimal display — just station name and EQ bars, semi-transparent.
	_is_full_display = false

	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 0.5, FADE_DURATION)

	# Hide extra elements for minimal view
	if prev_btn:
		prev_btn.visible = false
	if next_btn:
		next_btn.visible = false
	if volume_label:
		volume_label.visible = false
	if fav_btn:
		fav_btn.visible = false


func _hide_display() -> void:
	## Fully hide the radio HUD (radio is off).
	_is_visible = false
	_is_full_display = false
	_eq_active = false

	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 0.0, FADE_DURATION)


func _update_off_state() -> void:
	## Set the display to the "radio off" state.
	if station_name_label:
		station_name_label.text = "RADIO OFF"
	if song_label:
		song_label.text = ""
	_set_eq_color(Color(0.4, 0.4, 0.4))
	_eq_active = false
	_hide_display()


# ═════════════════════════════════════════════════════════════════════
#  EventBus Callbacks
# ═════════════════════════════════════════════════════════════════════

func _on_station_changed(station_id: int, station_name: String) -> void:
	if station_id == 0:
		_update_off_state()
		return

	# Update station display
	if station_name_label:
		station_name_label.text = station_name

	# Try to get the station color
	if _radio:
		var station_data: Dictionary = _radio.get_current_station()
		var color_hex: String = station_data.get("color", "#FFFFFF")
		_station_color = Color.from_string(color_hex, Color.WHITE)
		_set_eq_color(_station_color)

		# Update station label with frequency
		var freq: String = station_data.get("frequency", "")
		if not freq.is_empty() and station_name_label:
			station_name_label.text = "%s %s" % [freq, station_name]
	else:
		_set_eq_color(Color.WHITE)

	_show_full_display()


func _on_track_changed(track_title: String, artist: String) -> void:
	if song_label:
		if artist.is_empty():
			song_label.text = track_title
		else:
			song_label.text = "%s - %s" % [artist, track_title]

	# Update favorite button state
	_update_fav_button()

	# Briefly show full display when track changes
	_show_full_display()


func _on_dj_line(dj_name: String, line: String) -> void:
	if dj_label:
		dj_label.text = "%s: \"%s\"" % [dj_name, line]
		dj_label.visible = true
		_dj_timer = 4.0  ## show for 4 seconds

	# Show full display during DJ line
	_show_full_display()


func _on_volume_changed(volume: float) -> void:
	if volume_label:
		volume_label.text = "VOL %d%%" % int(volume * 100.0)
	_show_full_display()


func _on_song_favorited(_track_id: String, _favorited: bool) -> void:
	_update_fav_button()


# ═════════════════════════════════════════════════════════════════════
#  Button Callbacks
# ═════════════════════════════════════════════════════════════════════

func _on_prev_pressed() -> void:
	if _radio:
		_radio.prev_station()
	_show_full_display()


func _on_next_pressed() -> void:
	if _radio:
		_radio.next_station()
	_show_full_display()


func _on_fav_pressed() -> void:
	if _radio:
		_radio.toggle_current_favorite()


func _update_fav_button() -> void:
	if not fav_btn or not _radio:
		return
	var track_id: String = _radio.get_current_track_id()
	if _radio.is_favorite(track_id):
		fav_btn.text = "[*]"
		fav_btn.tooltip_text = "Unfavorite"
	else:
		fav_btn.text = "[ ]"
		fav_btn.tooltip_text = "Favorite"


# ═════════════════════════════════════════════════════════════════════
#  Public
# ═════════════════════════════════════════════════════════════════════

func set_radio_system(radio: RadioSystem) -> void:
	## Set the reference to the RadioSystem (called by the parent HUD).
	_radio = radio
	print("[Radio] RadioHUD linked to RadioSystem.")


func handle_input(event: InputEvent) -> void:
	## Called by the parent HUD to handle radio-specific inputs.
	if event.is_action_pressed("radio_next_station"):
		if _radio:
			_radio.next_station()
	elif event.is_action_pressed("radio_prev_station"):
		if _radio:
			_radio.prev_station()
	elif event.is_action_pressed("radio_toggle"):
		if _radio:
			_radio.toggle_radio()
	elif event.is_action_pressed("radio_favorite"):
		if _radio:
			_radio.toggle_current_favorite()
