# optimized_cloud_manager.gd
extends Node2D

# Cloud types enum
enum CloudType {
	SMALL,
	MEDIUM,
	LARGE
}

# Cloud spawn settings
@export var min_cloud_speed: float = 25.0
@export var max_cloud_speed: float = 35.0
@export var spawn_interval: float = 2.0
@export var cloud_fps: int = 30
@export var max_clouds: int = 8
@export var horizontal_drift_speed: float = 10.0

# Cloud configs
var cloud_configs = {
	CloudType.SMALL: {
		"scale_range": Vector2(0.6, 0.8),
		"opacity_range": Vector2(0.3, 0.4),
		"speed_multiplier": 1.2
	},
	CloudType.MEDIUM: {
		"scale_range": Vector2(0.8, 1.0),
		"opacity_range": Vector2(0.35, 0.45),
		"speed_multiplier": 1.0
	},
	CloudType.LARGE: {
		"scale_range": Vector2(1.0, 1.2),
		"opacity_range": Vector2(0.4, 0.5),
		"speed_multiplier": 0.8
	}
}

# Custom cloud class that extends Sprite2D
class Cloud extends Sprite2D:
	var speed: float = 0.0
	var drift_speed: float = 0.0
	var drift_offset: float = 0.0
	var cloud_type: CloudType
	
	func _init(texture: Texture2D):
		self.texture = texture
		z_index = -5  # Place behind most game elements

# Member variables
var available_clouds: Array[Cloud] = []
var active_clouds: Array[Cloud] = []
var is_spawning: bool = false
var current_zone: String = "ground"
var height_score: float = 0.0

# Cloud textures
var cloud_textures: Array[Texture2D] = []

# Timer reference
@onready var spawn_timer: Timer = $SpawnTimer
@onready var update_timer: Timer = $UpdateTimer

func _ready() -> void:
	# Create timers if they don't exist
	if not has_node("SpawnTimer"):
		spawn_timer = Timer.new()
		spawn_timer.name = "SpawnTimer"
		spawn_timer.one_shot = false
		add_child(spawn_timer)
	
	if not has_node("UpdateTimer"):
		update_timer = Timer.new()
		update_timer.name = "UpdateTimer"
		update_timer.one_shot = false
		add_child(update_timer)
	
	# Connect timer signals
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	update_timer.timeout.connect(_on_update_timer_timeout)
	
	# Start the update timer
	spawn_timer.wait_time = spawn_interval
	update_timer.wait_time = 1.0/cloud_fps
	update_timer.start()
	spawn_timer.start()
	
	# Load cloud textures (using preload for faster access)
	# This is done once at startup to avoid file loading overhead during gameplay
	cloud_textures = [
		preload("res://sprites/cloud_1.png") if ResourceLoader.exists("res://sprites/cloud_1.png") else null,
		preload("res://sprites/cloud_2.png") if ResourceLoader.exists("res://sprites/cloud_2.png") else null,
		preload("res://sprites/cloud_3.png") if ResourceLoader.exists("res://sprites/cloud_3.png") else null,
		preload("res://sprites/cloud_4.png") if ResourceLoader.exists("res://sprites/cloud_4.png") else null,
		preload("res://sprites/cloud_5.png") if ResourceLoader.exists("res://sprites/cloud_5.png") else null,
		preload("res://sprites/cloud_6.png") if ResourceLoader.exists("res://sprites/cloud_6.png") else null,
		preload("res://sprites/cloud_7.png") if ResourceLoader.exists("res://sprites/cloud_7.png") else null
	]
	print("Before filter - Available cloud textures: ", cloud_textures.size())
	# Filter out any null textures
	cloud_textures = cloud_textures.filter(func(tex): return tex != null)
	print("After filter - Available cloud textures: ", cloud_textures.size())
	if cloud_textures.is_empty():
		push_error("No cloud textures were loaded")
		return
	
	# Initialize cloud pool
	for i in range(max_clouds):
		var cloud = create_cloud()
		available_clouds.append(cloud)
		add_child(cloud)
		cloud.hide()

func create_cloud() -> Cloud:
	var texture = cloud_textures[0] if not cloud_textures.is_empty() else null
	var cloud = Cloud.new(texture)
	cloud.centered = true
	return cloud

func _on_update_timer_timeout() -> void:
	# Update all active clouds
	var delta = update_timer.wait_time
	
	var clouds_to_recycle = []
	var viewport_size = get_viewport_rect().size
	
	for cloud in active_clouds:
		# Vertical movement
		cloud.position.y += cloud.speed * delta
		
		# Horizontal drift (simplified: less sin() calculations)
		cloud.drift_offset += cloud.drift_speed * delta
		cloud.position.x += sin(cloud.drift_offset * 0.5) * delta * horizontal_drift_speed
		
		# Check if cloud is off screen
		if (cloud.position.y > viewport_size.y + 100 or
			cloud.position.x < -100 or
			cloud.position.x > viewport_size.x + 100):
			clouds_to_recycle.append(cloud)
	
	# Recycle clouds that are now off-screen
	for cloud in clouds_to_recycle:
		recycle_cloud(cloud)

func _on_spawn_timer_timeout() -> void:
	if is_spawning and should_spawn_clouds() and not available_clouds.is_empty():
		spawn_cloud()
		print("Active clouds: ", active_clouds.size(), " Available: ", available_clouds.size())

func spawn_cloud() -> void:
	if available_clouds.is_empty() or not should_spawn_clouds():
		return
	
	var cloud = available_clouds.pop_back()
	
	# Set random cloud type
	var cloud_type = CloudType.values()[randi() % CloudType.size()]
	cloud.cloud_type = cloud_type
	
	# Always set a new random texture when spawning
	if not cloud_textures.is_empty():
		cloud.texture = cloud_textures[randi() % cloud_textures.size()]
	
	# Get config for this cloud type
	var config = cloud_configs[cloud_type]
	
	# Set position at top of screen
	var viewport_size = get_viewport_rect().size
	cloud.position = Vector2(
		randf_range(0, viewport_size.x),
		-100
	)
	
	# Set movement properties
	var base_speed = randf_range(min_cloud_speed, max_cloud_speed)
	cloud.speed = base_speed * config.speed_multiplier
	cloud.drift_speed = 1.0 if randf() > 0.5 else -1.0
	cloud.drift_offset = 0.0
	
	# Set appearance
	var scale_value = randf_range(config.scale_range.x, config.scale_range.y)
	cloud.scale = Vector2(scale_value, scale_value)
	cloud.modulate.a = randf_range(
		config.opacity_range.x,
		config.opacity_range.y
	)
	
	# Activate cloud
	cloud.show()
	active_clouds.append(cloud)

func recycle_cloud(cloud: Cloud) -> void:
	if cloud in active_clouds:
		active_clouds.erase(cloud)
	
	cloud.hide()
	available_clouds.append(cloud)

func should_spawn_clouds() -> bool:
	return current_zone in ["ground", "atmosphere"]

func set_zone(zone: String) -> void:
	current_zone = zone
	
	# If we're leaving the cloud zones, stop spawning new clouds
	# but let existing clouds continue until they move off screen
	if not should_spawn_clouds():
		is_spawning = false
		spawn_timer.stop()

func start_spawning() -> void:
	is_spawning = true
	spawn_timer.wait_time = spawn_interval
	spawn_timer.start()

func stop_spawning() -> void:
	is_spawning = false
	spawn_timer.stop()
	
	# Optional: Clear all clouds immediately if needed
	# for cloud in active_clouds.duplicate():
	#     recycle_cloud(cloud)

func update_height(height: float) -> void:
	height_score = height
	
	# Only update cloud appearance every 100 height units to save CPU
	if int(height_score) % 20 != 0:
		return
		
	# Adjust cloud appearance based on height
	var altitude_factor = clamp(height_score / 3000.0, 0.0, 1.0)
	
	# Pre-compute colors for efficiency
	var base_color = Color(1, 1, 1)
	var high_altitude_color = Color(0.9, 0.95, 1.0)
	var target_color = base_color.lerp(high_altitude_color, altitude_factor)
	
	# Update active clouds - batch updates for efficiency
	for cloud in active_clouds:
		# Fade out clouds as we get higher
		var base_opacity = cloud_configs[cloud.cloud_type].opacity_range.x
		cloud.modulate.a = lerp(base_opacity, base_opacity * 0.5, altitude_factor)
		# Calculate alpha first and store it
		var alpha_value = lerp(base_opacity, base_opacity * 0.5, altitude_factor)
		# Set the color 
		cloud.modulate = target_color
		# Then explicitly set the stored alpha value
		cloud.modulate.a = alpha_value
