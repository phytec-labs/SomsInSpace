# game_hud.gd
extends CanvasLayer

# Node references
@onready var health_label = $StatsPanel/MarginContainer/StatsContainer/HealthContainer/HealthLabel
@onready var health_bar = $StatsPanel/MarginContainer/StatsContainer/HealthContainer/HealthBar
@onready var height_label = $StatsPanel/MarginContainer/StatsContainer/HeightContainer/HeightLabel
@onready var points_label = $StatsPanel/MarginContainer/StatsContainer/PointsContainer/PointsLabel
@onready var zone_marker = $ZoneProgressContainer/ZoneIndicator/ZoneMarker

# Zone thresholds (matching main_level.gd values)
var zone_thresholds = {
	"ground": 0,
	"atmosphere": 3000,
	"upper_atmosphere": 10000,
	"space": 30000
}

# Max expected height (for progress bar)
var max_height = 40000

# Zone progress marker positions
var zone_positions = {}

func _ready() -> void:
	# Initialize zone marker positions based on container width
	var container_width = $ZoneProgressContainer.size.x
	var left_margin = 0
	var usable_width = container_width
	
	# Calculate position for each zone threshold
	for zone in zone_thresholds:
		var threshold = zone_thresholds[zone]
		var position_ratio = float(threshold) / max_height
		zone_positions[zone] = left_margin + (position_ratio * usable_width)
	
	# Set initial UI state
	update_health(100)
	update_height(0)
	update_points(0)
	update_zone("ground")
	
	# Connect to the window size changed signal
	get_tree().root.size_changed.connect(_on_window_resized)

func update_health(value: float) -> void:
	var health_percent = int(value)
	health_label.text = "♥ Health: " + str(health_percent) + "%"
	health_bar.value = value
	
	# Update health bar color based on value
	var health_style = health_bar.get_theme_stylebox("fill")
	if value > 60:
		health_style.bg_color = Color(0.2, 0.8, 0.2) # Green
	elif value > 30:
		health_style.bg_color = Color(0.9, 0.7, 0.1) # Yellow
	else:
		health_style.bg_color = Color(0.9, 0.2, 0.2) # Red

func update_height(value: float) -> void:
	var height_meters = int(value)
	height_label.text = "⬆ Height: " + str(height_meters) + " m"
	
	# Make sure ZoneProgressContainer is properly sized
	await get_tree().process_frame
	
	# Update zone marker position based on height
	var container_width = $ZoneProgressContainer.size.x
	var progress_ratio = min(value / max_height, 1.0)
	var marker_x_pos = progress_ratio * container_width
	zone_marker.position.x = marker_x_pos
	
	# Update the current zone label highlighting
	update_zone_progress(value)

func update_points(value: int) -> void:
	points_label.text = "✧ Points: " + str(value)

func update_zone(zone_name: String) -> void:
	# Reset all zone labels
	var ground_label = $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/GroundLabel
	var atmosphere_label = $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/AtmosphereLabel
	var upper_atmo_label = $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/UpperAtmoLabel
	var space_label = $ZoneProgressContainer/ZoneBackground/MarginContainer/ZoneLabels/SpaceLabel
	
	# Reset all to default color
	ground_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	atmosphere_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	upper_atmo_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	space_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	
	# Highlight current zone
	match zone_name:
		"ground":
			ground_label.add_theme_color_override("font_color", Color(1, 1, 0.5))
		"atmosphere":
			atmosphere_label.add_theme_color_override("font_color", Color(1, 1, 0.5))
		"upper_atmosphere":
			upper_atmo_label.add_theme_color_override("font_color", Color(1, 1, 0.5))
		"space":
			space_label.add_theme_color_override("font_color", Color(1, 1, 0.5))

func update_zone_progress(height: float) -> void:
	var current_zone = "ground"
	
	# Determine current zone based on height
	for zone in zone_thresholds:
		if height >= zone_thresholds[zone]:
			current_zone = zone
	
	update_zone(current_zone)

func _on_window_resized() -> void:
	# Get updated container width after resize
	await get_tree().process_frame
	var container_width = $ZoneProgressContainer.size.x
	
	# Recalculate zone positions
	for zone in zone_thresholds:
		var threshold = zone_thresholds[zone]
		var position_ratio = float(threshold) / max_height
		zone_positions[zone] = position_ratio * container_width
		
	# Update the zone marker position based on current height
	update_height(height_label.text.split(" ")[2].to_int())
