# cloud_manager.gd
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
var cloud_pool: Array[Cloud] = []
var active_clouds: Array[Cloud] = []
var spawn_timer: float = 0.0
var is_spawning: bool = false
var current_zone: String = "ground"
var height_score: float = 0.0

# Cloud textures
var cloud_textures: Array[Texture2D] = []

func _ready() -> void:
	# Load cloud textures
	for i in range(1, 4):  # Assuming we have cloud1.png, cloud2.png, cloud3.png
		var texture = load("res://sprites/cloud_%d.png" % i)
		if texture:
			cloud_textures.append(texture)
		else:
			push_error("Failed to load cloud texture %d" % i)
	
	# Initialize cloud pool
	for i in range(max_clouds):
		var cloud = create_cloud()
		cloud_pool.append(cloud)
		add_child(cloud)
		cloud.hide()

func create_cloud() -> Cloud:
	var texture = cloud_textures[0] if cloud_textures.size() > 0 else null
	var cloud = Cloud.new(texture)
	cloud.centered = true
	return cloud

func _process(delta: float) -> void:
	# Handle cloud spawning
	if is_spawning:
		spawn_timer += delta
		if spawn_timer >= spawn_interval:
			spawn_timer = 0.0
			spawn_cloud()
	
	# Always update active clouds, even when not spawning new ones
	for cloud in active_clouds:
		# Vertical movement
		cloud.position.y += cloud.speed * delta
		
		# Horizontal drift
		cloud.drift_offset += cloud.drift_speed * delta
		cloud.position.x += sin(cloud.drift_offset * 0.5) * delta * horizontal_drift_speed
		
		# Check if cloud is off screen
		var viewport_size = get_viewport_rect().size
		if (cloud.position.y > viewport_size.y + 100 or
			cloud.position.x < -100 or
			cloud.position.x > viewport_size.x + 100):
			recycle_cloud(cloud)

func spawn_cloud() -> void:
	if cloud_pool.is_empty() or not should_spawn_clouds():
		return
		
	var cloud = cloud_pool.pop_back()
	
	# Set random cloud type
	var cloud_type = CloudType.values()[randi() % CloudType.size()]
	cloud.cloud_type = cloud_type
	
	# Set random texture
	if cloud_textures.size() > 0:
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
	var scale = randf_range(config.scale_range.x, config.scale_range.y)
	cloud.scale = Vector2(scale, scale)
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
	cloud_pool.append(cloud)

func should_spawn_clouds() -> bool:
	return current_zone in ["ground", "atmosphere"]

func set_zone(zone: String) -> void:
	current_zone = zone
	
	# If we're leaving the cloud zones, stop spawning new clouds
	# but let existing clouds continue until they move off screen
	if not should_spawn_clouds():
		is_spawning = false

func start_spawning() -> void:
	is_spawning = true
	spawn_timer = 0.0

func stop_spawning() -> void:
	is_spawning = false

func update_height(height: float) -> void:
	height_score = height
	
	# Optional: Adjust cloud appearance based on height
	var altitude_factor = clamp(height_score / 3000.0, 0.0, 1.0)
	
	# Update active clouds
	for cloud in active_clouds:
		# Fade out clouds as we get higher
		var base_opacity = cloud_configs[cloud.cloud_type].opacity_range.x
		cloud.modulate.a = lerp(base_opacity, base_opacity * 0.5, altitude_factor)
		
		# Optional: Add slight blue tint at higher altitudes
		var base_color = Color(1, 1, 1)
		var high_altitude_color = Color(0.9, 0.95, 1.0)
		cloud.modulate = base_color.lerp(high_altitude_color, altitude_factor)
