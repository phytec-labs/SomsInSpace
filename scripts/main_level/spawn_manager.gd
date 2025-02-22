# spawn_manager.gd
extends Node2D
class_name SpawnManager

signal object_spawned(object: Node2D)

# Export variables
@export var base_spawn_rate: float = 1.0
@export var spawn_height_offset: float = -100.0
@export var pool_size: int = 30
@export var formation_spacing: float = 40.0

# Spawn zones and configurations
var spawn_zones = {
	"ground": {
		"formation_types": [Formation.FormationType.LINE],
		"movement_patterns": [Formation.MovementPattern.STRAIGHT],
		"spawn_rate_multiplier": 1.0,
		"speed_multiplier": 1.0
	},
	"atmosphere": {
		"formation_types": [Formation.FormationType.LINE, Formation.FormationType.V_SHAPE],
		"movement_patterns": [Formation.MovementPattern.STRAIGHT, Formation.MovementPattern.SINE_WAVE],
		"spawn_rate_multiplier": 1.2,
		"speed_multiplier": 1.3
	},
	"upper_atmosphere": {
		"formation_types": [Formation.FormationType.V_SHAPE, Formation.FormationType.CIRCLE],
		"movement_patterns": [Formation.MovementPattern.SINE_WAVE, Formation.MovementPattern.ZIGZAG],
		"spawn_rate_multiplier": 1.4,
		"speed_multiplier": 1.5
	},
	"space": {
		"formation_types": [Formation.FormationType.CIRCLE, Formation.FormationType.WAVE],
		"movement_patterns": [Formation.MovementPattern.ZIGZAG],
		"spawn_rate_multiplier": 1.6,
		"speed_multiplier": 1.8
	}
}

# Object pools
var obstacle_pool: Array[Obstacle] = []
var formation_pool: Array[Formation] = []
var active_formations: Array[Formation] = []

# State variables
var current_zone: String = "ground"
var spawn_timer: float = 0.0
var is_spawning: bool = false
var obstacle_scene: PackedScene
var formation_scene: PackedScene

func _ready() -> void:
	# Load scenes
	obstacle_scene = preload("res://scenes/obstacles/balloon_obstacle_1.tscn")

	# Initialize pools
	initialize_pools()

func initialize_pools() -> void:
	# Initialize obstacle pool
	for i in range(pool_size):
		var obstacle = obstacle_scene.instantiate() as Obstacle
		obstacle_pool.append(obstacle)
		add_child(obstacle)
		obstacle.deactivate()

	# Initialize formation pool
	for i in range(pool_size / 5):  # Fewer formations than obstacles
		var formation = Formation.new()
		formation_pool.append(formation)
		add_child(formation)
		formation.formation_completed.connect(_on_formation_completed.bind(formation))

func _process(delta: float) -> void:
	if not is_spawning:
		return

	spawn_timer += delta
	if spawn_timer >= get_current_spawn_interval():
		spawn_timer = 0.0
		spawn_formation()

func get_current_spawn_interval() -> float:
	var zone_config = spawn_zones[current_zone]
	return base_spawn_rate / zone_config["spawn_rate_multiplier"]

func spawn_formation() -> void:
	if formation_pool.is_empty():
		return

	var formation = formation_pool.pop_back()

	# Configure formation based on current zone
	var zone_config = spawn_zones[current_zone]
	var formation_type = zone_config["formation_types"].pick_random()
	var movement_pattern = zone_config["movement_patterns"].pick_random()

	# Set formation properties
	formation.formation_type = formation_type
	formation.movement_pattern = movement_pattern
	formation.obstacle_count = randi_range(3, 6)
	formation.spacing = formation_spacing
	formation.speed = 100.0 * zone_config["speed_multiplier"]

	# Calculate spawn position
	var viewport_size = get_viewport_rect().size
	var spawn_x = viewport_size.x / 2  # Default to center

	match formation_type:
		Formation.FormationType.LINE, Formation.FormationType.WAVE:
			spawn_x = randf_range(200, viewport_size.x - 200)  # Give more space for wide formations
		Formation.FormationType.V_SHAPE, Formation.FormationType.CIRCLE:
			spawn_x = viewport_size.x / 2  # Center these formations

	var spawn_position = Vector2(spawn_x, spawn_height_offset)

	# Initialize and activate formation
	formation.initialize(spawn_position)
	active_formations.append(formation)

func get_obstacle_from_pool() -> Obstacle:
	if obstacle_pool.is_empty():
		return null
	var obstacle = obstacle_pool.pop_back()
	obstacle.initialize(Vector2.ZERO)  # Position will be set by formation
	emit_signal("object_spawned", obstacle)
	return obstacle

func return_obstacle_to_pool(obstacle: Obstacle) -> void:
	obstacle.deactivate()
	obstacle_pool.append(obstacle)

func return_formation_to_pool(formation: Formation) -> void:
	if formation in active_formations:
		active_formations.erase(formation)
		# Reset formation properties
		formation.position = Vector2.ZERO
		formation.formation_active = false
		formation.obstacles_spawned = 0
		formation.time_elapsed = 0.0
		formation_pool.append(formation)

func _on_formation_completed(formation: Formation) -> void:
	return_formation_to_pool(formation)

func set_spawn_zone(zone: String) -> void:
	if spawn_zones.has(zone):
		current_zone = zone

func start_spawning() -> void:
	is_spawning = true
	spawn_timer = 0.0

func stop_spawning() -> void:
	is_spawning = false
