# spawn_manager.gd
extends Node2D

# Node references
@onready var level: Node2D = $".."

# Spawn zone types and their associated objects
enum SpawnZone {GROUND, ATMOSPHERE, UPPER_ATMOSPHERE, SPACE}
var current_zone: SpawnZone = SpawnZone.GROUND

# Spawn settings
var spawn_timer: float = 0.0
var base_spawn_rate: float = 2.0
var current_spawn_rate: float = base_spawn_rate
var is_spawning: bool = false

# Object pools
var object_pools: Dictionary = {}
var active_objects: Array[Node2D] = []

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
	# Initialize pools for each object type
	# This will be implemented when we create the object scenes
	pass

func spawn_object() -> void:
	# Randomly select and spawn appropriate object for current zone
	# This will be implemented when we create the object scenes
	pass

func update_active_objects(delta: float) -> void:
	for object in active_objects:
		if object == null:
			continue

		# Move object down
		object.position.y += level.scroll_speed * delta

		# Remove if off screen
		if object.position.y > get_viewport_rect().size.y + 100:
			retire_object(object)

func retire_object(object: Node2D) -> void:
	if object in active_objects:
		active_objects.erase(object)
		# Return to appropriate pool or queue free
		# This will be implemented when we create the object scenes
		object.queue_free()

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
