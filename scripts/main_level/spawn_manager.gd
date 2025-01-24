# spawn_manager.gd
extends Node2D

signal object_spawned(object: Node2D)

# Zone configuration
enum SpawnZone {GROUND, ATMOSPHERE, UPPER_ATMOSPHERE, SPACE}

@export_group("Spawn Configuration")
@export var base_spawn_rate: float = 2.0
@export var spawn_height_offset: float = -50.0
@export_range(5, 50) var pool_size: int = 10

@export_group("Spawn Chances")
@export_range(0.0, 1.0) var energy_spawn_chance: float = 0.3
@export_range(0.0, 1.0) var cloud_spawn_chance: float = 0.4

# Zone multipliers for spawn rates
var zone_multipliers = {
	SpawnZone.GROUND: 1.0,
	SpawnZone.ATMOSPHERE: 0.8,
	SpawnZone.UPPER_ATMOSPHERE: 0.6,
	SpawnZone.SPACE: 0.5
}

# Scene paths for different object types
var scene_paths = {
	"cloud": "res://scenes/obstacles/cloud_obstacle_1.tscn",
	"bird": "res://scenes/obstacles/bird_obstacle_1.tscn",
	"plane": "res://scenes/obstacles/plane_obstacle_1.tscn",
	"jet": "res://scenes/obstacles/jet_obstacle_1.tscn",
	"satellite": "res://scenes/obstacles/satellite_obstacle_1.tscn",
	"meteor": "res://scenes/obstacles/meteor_obstacle_1.tscn",
	"energy": "res://scenes/collectibles/energy_collectible_1.tscn"
}

# Available objects per zone
var zone_objects = {
	SpawnZone.GROUND: ["bird", "cloud", "energy"],
	SpawnZone.ATMOSPHERE: ["bird", "cloud", "energy", "jet", "plane"],
	SpawnZone.UPPER_ATMOSPHERE: ["cloud", "energy", "jet", "satellite"],
	SpawnZone.SPACE: ["energy", "meteor", "satellite"]
}

var object_pools = {}
var active_objects: Array[Node2D] = []
var current_zone: SpawnZone = SpawnZone.GROUND
var spawn_timer: float = 0.0
var is_spawning: bool = false
var viewport_size: Vector2

func _ready() -> void:
	viewport_size = get_viewport_rect().size
	initialize_pools()
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	viewport_size = get_viewport_rect().size

func initialize_pools() -> void:
	# Pre-load scenes
	var scenes = {}
	for type in scene_paths:
		scenes[type] = load(scene_paths[type])

	# Initialize pools
	for type in scenes:
		object_pools[type] = []
		for _i in range(pool_size):
			var object = scenes[type].instantiate()
			object.deactivate()
			add_child(object)
			object_pools[type].append(object)

func _process(delta: float) -> void:
	if not is_spawning:
		return

	spawn_timer += delta
	if spawn_timer >= base_spawn_rate * zone_multipliers[current_zone]:
		spawn_timer = 0.0
		spawn_object()

	update_active_objects(delta)

func spawn_object() -> void:
	var available_objects = zone_objects[current_zone]
	if available_objects.is_empty():
		return

	var spawn_type = determine_spawn_type(available_objects)
	if spawn_type.is_empty():
		return

	var object = get_inactive_object(spawn_type)
	if not object:
		return

	setup_object(object)

func determine_spawn_type(available: Array) -> String:
	if randf() < energy_spawn_chance and "energy" in available:
		return "energy"
	elif randf() < cloud_spawn_chance and "cloud" in available:
		return "cloud"

	var obstacles = available.filter(func(obj): return obj != "energy" and obj != "cloud")
	return obstacles[0] if not obstacles.is_empty() else ""

func get_inactive_object(type: String) -> Node2D:
	if not object_pools.has(type):
		return null

	for object in object_pools[type]:
		if not object.is_active:
			return object
	return null

func setup_object(object: Node2D) -> void:
	var spawn_position = Vector2(
		randf_range(0, viewport_size.x),
		spawn_height_offset
	)

	object.initialize(spawn_position)
	active_objects.append(object)
	object_spawned.emit(object)

func update_active_objects(delta: float) -> void:
	var scroll_speed = get_parent().scroll_speed
	var viewport_bottom = viewport_size.y + 100.0

	for i in range(active_objects.size() - 1, -1, -1):
		var object = active_objects[i]
		if not object.is_active:
			continue

		object.position.y += scroll_speed * delta * object.speed_multiplier

		if object.position.y > viewport_bottom:
			retire_object(i)

func retire_object(index: int) -> void:
	var object = active_objects[index]
	object.deactivate()
	active_objects.remove_at(index)

func start_spawning() -> void:
	is_spawning = true
	spawn_timer = 0.0

func stop_spawning() -> void:
	is_spawning = false
	for i in range(active_objects.size() - 1, -1, -1):
		retire_object(i)

func set_spawn_zone(zone_name: String) -> void:
	# Convert zone name to enum and update spawn configuration
	var new_zone: SpawnZone
	match zone_name:
		"ground":
			new_zone = SpawnZone.GROUND
		"atmosphere":
			new_zone = SpawnZone.ATMOSPHERE
		"upper_atmosphere":
			new_zone = SpawnZone.UPPER_ATMOSPHERE
		"space":
			new_zone = SpawnZone.SPACE
		_:
			new_zone = SpawnZone.GROUND

	if new_zone != current_zone:
		current_zone = new_zone
		spawn_timer = 0.0  # Reset spawn timer when changing zones
