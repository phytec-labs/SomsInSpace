# spawn_manager.gd
extends Node2D

# Node references
@onready var level: Node2D = $".."

# Spawn zone types and their associated objects
enum SpawnZone {GROUND, ATMOSPHERE, UPPER_ATMOSPHERE, SPACE}
var current_zone: SpawnZone = SpawnZone.GROUND

# Preload scenes
var scenes = {
	"energy": preload("res://scenes/collectibles/energy_collectible.tscn"),
	"bird": preload("res://scenes/obstacles/bird_obstacle.tscn"),
	"plane": preload("res://scenes/obstacles/plane_obstacle.tscn"),
	# Add other obstacles as you create them
}

# Zone configurations
var zone_objects = {
	SpawnZone.GROUND: ["bird", "energy"],
	SpawnZone.ATMOSPHERE: ["plane", "energy"],
	SpawnZone.UPPER_ATMOSPHERE: ["satellite", "energy"],
	SpawnZone.SPACE: ["asteroid", "energy"]
}

# Spawn settings
var spawn_timer: float = 0.0
var base_spawn_rate: float = 2.0
var current_spawn_rate: float = base_spawn_rate
var is_spawning: bool = false

# Object pools
var object_pools: Dictionary = {}
var active_objects: Array[Node2D] = []

# Pool settings
const POOL_SIZE: int = 10
const ENERGY_SPAWN_CHANCE: float = 0.3

func _ready() -> void:
	initialize_object_pools()

func _process(delta: float) -> void:
	if not is_spawning:
		return
		
	spawn_timer += delta
	if spawn_timer >= current_spawn_rate:
		spawn_timer = 0.0
		spawn_object()
		
	update_active_objects(delta)

func initialize_object_pools() -> void:
	# Create pools for each object type
	for scene_key in scenes.keys():
		object_pools[scene_key] = []
		for i in range(POOL_SIZE):
			var object = scenes[scene_key].instantiate()
			object.deactivate()  # Start deactivated
			add_child(object)
			object_pools[scene_key].append(object)

func get_object_from_pool(type: String) -> Node2D:
	if not object_pools.has(type):
		return null
		
	# Find inactive object in pool
	for object in object_pools[type]:
		if not object.is_active:
			return object
			
	# If no inactive objects, return null
	return null

func spawn_object() -> void:
	var available_objects = zone_objects[current_zone]
	if available_objects.is_empty():
		return
		
	# Decide whether to spawn energy or obstacle
	var spawn_type = "energy" if randf() < ENERGY_SPAWN_CHANCE else available_objects[0]
	
	var object = get_object_from_pool(spawn_type)
	if object == null:
		return
		
	# Calculate spawn position
	var viewport_size = get_viewport_rect().size
	var spawn_x = randf_range(0, viewport_size.x)
	var spawn_position = Vector2(spawn_x, -50)  # Spawn above screen
	
	# Initialize object
	object.initialize(spawn_position)
	active_objects.append(object)

func update_active_objects(delta: float) -> void:
	var viewport_bottom = get_viewport_rect().size.y + 100
	
	for object in active_objects:
		if object == null or not object.is_active:
			continue
			
		# Move object down
		object.position.y += level.scroll_speed * delta * object.speed_multiplier
		
		# Remove if off screen
		if object.position.y > viewport_bottom:
			retire_object(object)

func retire_object(object: Node2D) -> void:
	if object in active_objects:
		active_objects.erase(object)
		object.deactivate()

func start_spawning() -> void:
	is_spawning = true
	spawn_timer = 0.0

func stop_spawning() -> void:
	is_spawning = false
	# Clear all active objects
	for object in active_objects:
		if object != null:
			retire_object(object)
	active_objects.clear()

func set_spawn_zone(zone_name: String) -> void:
	match zone_name:
		"ground":
			current_zone = SpawnZone.GROUND
			current_spawn_rate = base_spawn_rate
		"atmosphere":
			current_zone = SpawnZone.ATMOSPHERE
			current_spawn_rate = base_spawn_rate * 0.8
		"upper_atmosphere":
			current_zone = SpawnZone.UPPER_ATMOSPHERE
			current_spawn_rate = base_spawn_rate * 0.6
		"space":
			current_zone = SpawnZone.SPACE
			current_spawn_rate = base_spawn_rate * 0.5
