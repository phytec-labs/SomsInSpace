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
@export_range(0.0, 1.0) var obstacle_spawn_chance: float = 0.7

# Zone multipliers for spawn rates
var zone_multipliers = {
	SpawnZone.GROUND: 1.0,
	SpawnZone.ATMOSPHERE: 0.8,
	SpawnZone.UPPER_ATMOSPHERE: 0.6,
	SpawnZone.SPACE: 0.5
}

# Scene paths for different object types
const SCENE_PATHS = {
	"energy_1": "res://scenes/collectibles/energy_collectible_1.tscn",
	"bird_1": "res://scenes/obstacles/bird_obstacle_1.tscn",
	"cloud_1": "res://scenes/obstacles/cloud_obstacle_1.tscn",
	"cloud_2": "res://scenes/obstacles/cloud_obstacle_2.tscn",
	"cloud_3": "res://scenes/obstacles/cloud_obstacle_3.tscn",
	"cloud_4": "res://scenes/obstacles/cloud_obstacle_4.tscn",
	"jet_1": "res://scenes/obstacles/jet_obstacle_1.tscn",
	"jet_2": "res://scenes/obstacles/jet_obstacle_2.tscn",
	"plane_1": "res://scenes/obstacles/plane_obstacle_1.tscn",
	"satellite_1": "res://scenes/obstacles/satellite_obstacle_1.tscn",
	"meteor_1": "res://scenes/obstacles/meteor_obstacle_1.tscn"
}

# Available objects per zone with weights
var zone_objects = {
	SpawnZone.GROUND: {
		"collectibles": {"energy_1": 1.0},
		"obstacles": {
			"bird_1": 1.0,
			"cloud_1": 1.0,
			"cloud_2": 1.0
		}
	},
	SpawnZone.ATMOSPHERE: {
		"collectibles": {"energy_1": 1.0},
		"obstacles": {
			"bird_1": 0.5,
			"cloud_2": 1.0,
			"cloud_3": 1.0,
			"cloud_4": 1.0,
			"jet_1": 1.0,
			"plane_1": 1.0
		}
	},
	SpawnZone.UPPER_ATMOSPHERE: {
		"collectibles": {"energy_1": 1.0},
		"obstacles": {
			"cloud_3": 0.5,
			"cloud_4": 0.5,
			"jet_1": 1.0,
			"jet_2": 1.0,
			"satellite_1": 1.0
		}
	},
	SpawnZone.SPACE: {
		"collectibles": {"energy_1": 1.0},
		"obstacles": {
			"meteor_1": 1.0,
			"satellite_1": 1.0
		}
	}
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
	for type in SCENE_PATHS:
		var scene = load(SCENE_PATHS[type])
		object_pools[type] = []
		for _i in range(pool_size):
			var object = scene.instantiate()
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
	var zone_data = zone_objects[current_zone]

	# Determine if we're spawning a collectible or obstacle
	var spawn_category = "obstacles" if randf() > energy_spawn_chance else "collectibles"
	var available_objects = zone_data[spawn_category]

	if available_objects.is_empty():
		return

	# Calculate total weight for available objects
	var total_weight = 0.0
	for obj in available_objects:
		total_weight += available_objects[obj]

	# Select object based on weights
	var random_value = randf() * total_weight
	var cumulative_weight = 0.0
	var selected_type = ""

	for obj in available_objects:
		cumulative_weight += available_objects[obj]
		if random_value <= cumulative_weight:
			selected_type = obj
			break

	if selected_type.is_empty():
		return

	var object = get_inactive_object(selected_type)
	if not object:
		return

	setup_object(object)

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
