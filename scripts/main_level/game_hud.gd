# game_hud.gd
extends CanvasLayer

const GameConfigScript := preload("res://scripts/data/game_config.gd")

# Emitted when the on-screen pause button is touched/clicked
signal pause_requested

# Node references
@onready var health_label = $StatsPanel/MarginContainer/StatsContainer/HealthContainer/HealthLabel
@onready var health_bar = $StatsPanel/MarginContainer/StatsContainer/HealthContainer/HealthBar
@onready var height_label = $StatsPanel/MarginContainer/StatsContainer/HeightContainer/HeightLabel
@onready var points_label = $StatsPanel/MarginContainer/StatsContainer/PointsContainer/PointsLabel
@onready var zone_marker = $ZoneProgressContainer/ZoneIndicator/ZoneMarker
@onready var zone_progress_container: Control = $ZoneProgressContainer
@onready var pause_button: Button = $PauseButton

# Zone labels (cached; highlighted by update_zone)
@onready var zone_labels := {
	"ground": $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/GroundLabel,
	"atmosphere": $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/AtmosphereLabel,
	"upper_atmosphere": $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/UpperAtmoLabel,
	"space": $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/SpaceLabel,
}
const ZONE_LABEL_COLOR := Color(0.7, 0.7, 0.7)
const ZONE_LABEL_HIGHLIGHT_COLOR := Color(1, 1, 0.5)

# Weapon panel references
@onready var weapon_sprite = $WeaponsPanel/MarginContainer/WeaponsContainer/WeaponSlot/WeaponSprite
@onready var weapon_name = $WeaponsPanel/MarginContainer/WeaponsContainer/WeaponName

# Weapon textures
@export var basic_weapon_texture: Texture = preload("res://sprites/weapon_laser.png")
@export var upgraded_weapon_texture: Texture = preload("res://sprites/weapon_twin_laser.png")
var current_weapon_type: String = "basic"

# Game config (zones / thresholds / progress bar range); set via configure()
var config: GameConfigScript

# Max expected height (for progress bar); from config.progress_bar_max_height
var max_height: float = 40000.0

# Zone progress marker positions
var zone_positions = {}

# Cached layout / last displayed values (to skip redundant UI updates)
var _zone_container_width: float = 0.0
var _health_fill_style: StyleBoxFlat
var _last_health: float = NAN
var _last_health_int: int = -1
var _last_height: float = 0.0
var _last_height_int: int = -1
var _last_points: int = -1
var _current_zone: String = ""

func _ready() -> void:
	_health_fill_style = health_bar.get_theme_stylebox("fill")

	# Initialize zone marker positions based on container width, and keep
	# them in sync whenever the container is resized (window resize etc.)
	_refresh_zone_layout()
	zone_progress_container.resized.connect(_on_zone_container_resized)

	# Pause button is shown by main_level.gd only while playing. Input for it
	# is handled in _input (see below), not via the pressed signal.
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.visible = false

	# Set initial UI state
	update_health(100)
	update_height(0)
	update_points(0)
	update_zone("ground")

	# Set initial weapon
	update_weapon("basic")

# Called by main_level.gd with the GameConfig resource
func configure(game_config: GameConfigScript) -> void:
	config = game_config
	if config and config.progress_bar_max_height > 0:
		max_height = config.progress_bar_max_height
	_refresh_zone_layout()
	_update_zone_marker()
	update_zone_progress(_last_height)

func _input(event: InputEvent) -> void:
	# The pause button is hit-tested here, in _input, rather than through
	# Button.pressed: consuming the press here keeps the touch (and its
	# emulated mouse click) from also reaching player.gd's _unhandled_input
	# as a move/fire input. Every other HUD Control uses MOUSE_FILTER_IGNORE
	# so touches over the panels still reach the player.
	if not pause_button.is_visible_in_tree():
		return
	var is_press: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if is_press and pause_button.get_global_rect().has_point(event.position):
		get_viewport().set_input_as_handled()
		pause_requested.emit()

func set_pause_button_visible(value: bool) -> void:
	pause_button.visible = value

func update_health(value: float) -> void:
	if value == _last_health:
		return
	_last_health = value

	var health_percent = int(value)
	if health_percent != _last_health_int:
		_last_health_int = health_percent
		health_label.text = "♥ Health: " + str(health_percent) + "%"
	health_bar.value = value

	# Update health bar color based on value
	if value > 60:
		_health_fill_style.bg_color = Color(0.2, 0.8, 0.2) # Green
	elif value > 30:
		_health_fill_style.bg_color = Color(0.9, 0.7, 0.1) # Yellow
	else:
		_health_fill_style.bg_color = Color(0.9, 0.2, 0.2) # Red

func update_height(value: float) -> void:
	_last_height = value

	var height_meters = int(value)
	if height_meters != _last_height_int:
		_last_height_int = height_meters
		height_label.text = "⬆ Height: " + str(height_meters) + " m"

	# Update zone marker position based on height
	_update_zone_marker()

	# Update the current zone label highlighting (only re-styles on change)
	update_zone_progress(value)

func update_points(value: int) -> void:
	if value == _last_points:
		return
	_last_points = value
	points_label.text = "✧ Points: " + str(value)

func update_zone(zone_name: String) -> void:
	_current_zone = zone_name

	# Reset all to default color, then highlight the current zone
	for zone in zone_labels:
		var color: Color = ZONE_LABEL_HIGHLIGHT_COLOR if zone == zone_name else ZONE_LABEL_COLOR
		zone_labels[zone].add_theme_color_override("font_color", color)

func update_zone_progress(height: float) -> void:
	if not config:
		return
	var zone = config.get_zone_for_height(height)
	if zone and String(zone.id) != _current_zone:
		update_zone(String(zone.id))

func update_weapon(weapon_type: String) -> void:
	current_weapon_type = weapon_type

	match weapon_type:
		"basic":
			weapon_sprite.texture = basic_weapon_texture
			weapon_name.text = "Basic Laser"
		"upgraded":
			weapon_sprite.texture = upgraded_weapon_texture
			weapon_name.text = "Dual Laser"

			# Add a small animation to highlight the upgrade
			var tween = create_tween()
			tween.tween_property(weapon_name, "modulate", Color(1, 1, 0), 0.3)
			tween.tween_property(weapon_name, "modulate", Color(1, 1, 1), 0.3)

func _update_zone_marker() -> void:
	var progress_ratio = min(_last_height / max_height, 1.0)
	zone_marker.position.x = progress_ratio * _zone_container_width

func _refresh_zone_layout() -> void:
	_zone_container_width = zone_progress_container.size.x

	# Recalculate zone positions
	zone_positions.clear()
	if config:
		for zone in config.zones:
			var position_ratio = float(zone.start_height) / max_height
			zone_positions[String(zone.id)] = position_ratio * _zone_container_width

func _on_zone_container_resized() -> void:
	_refresh_zone_layout()
	# Update the zone marker position based on current height
	_update_zone_marker()
