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
@onready var ship_name_label: Label = $StatsPanel/MarginContainer/StatsContainer/ShipNameLabel
@onready var zone_marker = $ZoneProgressContainer/ZoneIndicator/ZoneMarker
@onready var zone_progress_container: Control = $ZoneProgressContainer
@onready var pause_button: Button = $PauseButton

# Combo multiplier (next to points): "x2".."x4" plus a thin bar showing the
# time left in the combo window; hidden at x1
@onready var combo_box: Control = $StatsPanel/MarginContainer/StatsContainer/PointsContainer/ComboBox
@onready var combo_label: Label = $StatsPanel/MarginContainer/StatsContainer/PointsContainer/ComboBox/ComboLabel
@onready var combo_bar: ProgressBar = $StatsPanel/MarginContainer/StatsContainer/PointsContainer/ComboBox/ComboBar
var _combo_fill_style: StyleBoxFlat
var _last_combo: int = 1

# Zone labels: generated from config.zones in configure() (zone id -> Label;
# highlighted by update_zone)
@onready var zone_labels_container: HBoxContainer = $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels
var zone_labels := {}
const ZONE_LABEL_COLOR := Color(0.7, 0.7, 0.7)
const ZONE_LABEL_HIGHLIGHT_COLOR := Color(1, 1, 0.5)
const ZONE_LABEL_FONT := preload("res://fonts/m5x7.ttf")
const ZONE_LABEL_FONT_SIZE := 16
const ZONE_LABEL_MIN_WIDTH := 64.0

# Boss health bar (top center; hidden unless a boss fight is on)
@onready var boss_bar: Control = $BossBar
@onready var boss_name_label: Label = $BossBar/BossNameLabel
@onready var boss_health_bar: ProgressBar = $BossBar/BossHealthBar

# Weapon panel references
@onready var weapon_sprite = $WeaponsPanel/MarginContainer/WeaponsContainer/WeaponSlot/WeaponSprite
@onready var weapon_name = $WeaponsPanel/MarginContainer/WeaponsContainer/WeaponName

# Weapon textures / names per tier (index = tier - 1). Tier 3 has no art of
# its own: it reuses the twin laser icon tinted with SPREAD_WEAPON_TINT.
@export var basic_weapon_texture: Texture = preload("res://sprites/weapon_laser.png")
@export var upgraded_weapon_texture: Texture = preload("res://sprites/weapon_twin_laser.png")
const WEAPON_NAMES: Array[String] = ["Laser", "Twin Laser", "Spread Laser"]
const SPREAD_WEAPON_TINT := Color(0.45, 1.0, 1.0)
var current_weapon_tier: int = 0

# Threat indicator (next to the zone bar): wave ramp level as filled pips.
# The level rises every ZoneDefinition.ramp_interval_seconds (25 s) spent in
# a zone and resets to 0 on a zone change (WaveManager.get_ramp_level()).
@onready var threat_indicator: Control = $ThreatIndicator
@onready var threat_label: Label = $ThreatIndicator/ThreatLabel
@onready var threat_pips_container: HBoxContainer = $ThreatIndicator/ThreatPips
const THREAT_PIP_COUNT := 5
const THREAT_PIP_SIZE := Vector2(18, 10)
const THREAT_PIP_EMPTY_COLOR := Color(0.25, 0.25, 0.25, 0.8)
const THREAT_LOW_COLOR := Color(1.0, 0.9, 0.2)   # Yellow (level 1)
const THREAT_HIGH_COLOR := Color(1.0, 0.15, 0.1)  # Red (level THREAT_PIP_COUNT+)
const THREAT_IDLE_LABEL_COLOR := Color(0.7, 0.7, 0.7)
var threat_pips: Array[ColorRect] = []
var current_threat_level: int = -1

# Game config (zones / thresholds / progress bar range); set via configure()
var config: GameConfigScript

# Max expected height (for progress bar); from config.progress_bar_max_height
var max_height: float = 40000.0

# Zone progress marker positions
var zone_positions = {}

# Cached layout / last displayed values (to skip redundant UI updates)
var _zone_container_width: float = 0.0
var _health_fill_style: StyleBoxFlat
var _max_health: float = 100.0
var _last_health: float = NAN
var _last_health_int: int = -1
var _last_height: float = 0.0
var _last_height_int: int = -1
var _last_points: int = -1
var _current_zone: String = ""

func _ready() -> void:
	_health_fill_style = health_bar.get_theme_stylebox("fill")
	_combo_fill_style = combo_bar.get_theme_stylebox("fill")

	# Initialize zone marker positions based on container width, and keep
	# them in sync whenever the container is resized (window resize etc.)
	_refresh_zone_layout()
	zone_progress_container.resized.connect(_on_zone_container_resized)

	# Pause button is shown by main_level.gd only while playing. Input for it
	# is handled in _input (see below), not via the pressed signal.
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.visible = false

	# Set initial UI state
	set_ship_name("")
	update_health(100)
	update_height(0)
	update_points(0)
	update_zone("ground")
	hide_boss_bar()

	# Set initial weapon / threat
	update_weapon(1)
	_build_threat_pips()
	update_threat(0)

# Called by main_level.gd with the GameConfig resource
func configure(game_config: GameConfigScript) -> void:
	config = game_config
	if config and config.progress_bar_max_height > 0:
		max_height = config.progress_bar_max_height
	_build_zone_labels()
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

# Health range of the selected ship (the bar and "%" label are relative to it)
func set_max_health(max_value: float) -> void:
	_max_health = maxf(max_value, 0.001)
	health_bar.max_value = _max_health
	_last_health = NAN  # Force a redraw with the new range

# `max_value` (optional) also updates the range, as set_max_health()
func update_health(value: float, max_value: float = -1.0) -> void:
	if max_value > 0.0 and max_value != _max_health:
		set_max_health(max_value)
	if value == _last_health:
		return
	_last_health = value

	var percent: float = clampf(value / _max_health * 100.0, 0.0, 100.0)
	var health_percent := int(ceilf(percent)) if percent > 0.0 and percent < 1.0 else int(percent)
	if health_percent != _last_health_int:
		_last_health_int = health_percent
		health_label.text = "♥ Health: " + str(health_percent) + "%"
	health_bar.value = value

	# Update health bar color based on the percentage left
	if percent > 60:
		_health_fill_style.bg_color = Color(0.2, 0.8, 0.2) # Green
	elif percent > 30:
		_health_fill_style.bg_color = Color(0.9, 0.7, 0.1) # Yellow
	else:
		_health_fill_style.bg_color = Color(0.9, 0.2, 0.2) # Red

# Selected ship's name, shown at the top of the stats panel
func set_ship_name(ship_name: String) -> void:
	ship_name_label.text = ship_name
	ship_name_label.visible = not ship_name.is_empty()

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

# Combo multiplier: `combo` (1 hides it), `time_fraction` = time left in the
# combo window (0..1), `color` = the tier color. Called every frame while a
# combo is live; only the bar value changes then (no allocations).
func update_combo(combo: int, time_fraction: float, color: Color = Color.WHITE) -> void:
	if combo != _last_combo:
		var rising := combo > _last_combo
		_last_combo = combo
		combo_box.visible = combo > 1
		if combo > 1:
			combo_label.text = "x%d" % combo
			combo_label.add_theme_color_override("font_color", color)
			_combo_fill_style.bg_color = color
			if rising:
				combo_label.pivot_offset = combo_label.size / 2.0
				var tween = create_tween()
				tween.tween_property(combo_label, "scale", Vector2(1.4, 1.4), 0.06)
				tween.tween_property(combo_label, "scale", Vector2.ONE, 0.12)
	if combo > 1:
		combo_bar.value = clampf(time_fraction, 0.0, 1.0)

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

# (Re)create one label per zone, separated by "|", from config.zones
func _build_zone_labels() -> void:
	for child in zone_labels_container.get_children():
		zone_labels_container.remove_child(child)
		child.queue_free()
	zone_labels.clear()
	if not config:
		return

	var first := true
	for zone in config.zones:
		if zone == null:
			continue
		if not first:
			zone_labels_container.add_child(_make_zone_label("|", 0.0))
		first = false
		var label := _make_zone_label(zone.get_short_name(), ZONE_LABEL_MIN_WIDTH)
		label.name = String(zone.id).to_pascal_case() + "Label"
		zone_labels_container.add_child(label)
		zone_labels[String(zone.id)] = label

	# Re-apply the highlight to the new labels
	var current := _current_zone
	_current_zone = ""
	update_zone(current)

func _make_zone_label(text: String, min_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ZONE_LABEL_FONT)
	label.add_theme_font_size_override("font_size", ZONE_LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", ZONE_LABEL_COLOR)
	return label

# --- Boss bar ---

func show_boss_bar(boss_name: String) -> void:
	boss_name_label.text = boss_name
	boss_health_bar.max_value = 100.0
	boss_health_bar.value = 100.0
	boss_bar.visible = true

func update_boss_health(current: float, max_health: float) -> void:
	boss_health_bar.max_value = maxf(max_health, 0.001)
	boss_health_bar.value = clampf(current, 0.0, boss_health_bar.max_value)

func hide_boss_bar() -> void:
	boss_bar.visible = false

# Weapon panel: tier 1 = Laser, 2 = Twin Laser, 3 = Spread Laser
func update_weapon(tier: int) -> void:
	tier = clampi(tier, 1, WEAPON_NAMES.size())
	var changed := current_weapon_tier > 0 and tier != current_weapon_tier
	current_weapon_tier = tier

	weapon_sprite.texture = basic_weapon_texture if tier == 1 else upgraded_weapon_texture
	weapon_sprite.self_modulate = SPREAD_WEAPON_TINT if tier >= 3 else Color(1, 1, 1)
	weapon_name.text = WEAPON_NAMES[tier - 1]

	# Small highlight animation whenever the weapon changes
	if changed:
		var tween = create_tween()
		tween.tween_property(weapon_name, "modulate", Color(1, 1, 0), 0.3)
		tween.tween_property(weapon_name, "modulate", Color(1, 1, 1), 0.3)

# --- Threat indicator ---

func _build_threat_pips() -> void:
	for child in threat_pips_container.get_children():
		threat_pips_container.remove_child(child)
		child.queue_free()
	threat_pips.clear()
	for i in THREAT_PIP_COUNT:
		var pip := ColorRect.new()
		pip.name = "Pip%d" % (i + 1)
		pip.custom_minimum_size = THREAT_PIP_SIZE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = THREAT_PIP_EMPTY_COLOR
		threat_pips_container.add_child(pip)
		threat_pips.append(pip)

# Color for a threat level (1 = yellow ... THREAT_PIP_COUNT+ = red)
func _threat_color(level: int) -> Color:
	var t := clampf(float(level - 1) / float(maxi(THREAT_PIP_COUNT - 1, 1)), 0.0, 1.0)
	return THREAT_LOW_COLOR.lerp(THREAT_HIGH_COLOR, t)

# Wave difficulty ramp level (0 = just entered the zone); fills one pip per level
func update_threat(level: int) -> void:
	level = maxi(level, 0)
	if level == current_threat_level:
		return
	var rising := current_threat_level >= 0 and level > current_threat_level
	current_threat_level = level

	var color := _threat_color(level)
	for i in threat_pips.size():
		threat_pips[i].color = color if i < level else THREAT_PIP_EMPTY_COLOR
	threat_label.text = "THREAT" if level <= THREAT_PIP_COUNT else "THREAT MAX"
	threat_label.add_theme_color_override("font_color", color if level > 0 else THREAT_IDLE_LABEL_COLOR)

	# Brief pulse when the threat goes up
	if rising and threat_indicator.visible:
		var tween = create_tween()
		tween.tween_property(threat_indicator, "modulate", Color(1.6, 1.6, 1.6), 0.15)
		tween.tween_property(threat_indicator, "modulate", Color(1, 1, 1), 0.35)

# Hidden in zones without waves (the boss zone shows the boss bar instead)
func set_threat_visible(value: bool) -> void:
	threat_indicator.visible = value

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
