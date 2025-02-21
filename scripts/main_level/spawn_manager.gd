# spawn_manager.gd
extends Node2D

signal object_spawned(object: Node2D)

enum SpawnZone {GROUND, ATMOSPHERE, UPPER_ATMOSPHERE, SPACE}
enum FormationType {NONE, V_FORMATION, LINE, WALL, DIAGONAL, CROSS}

@export_group("Spawn Configuration")
@export var base_spawn_rate: float = 2.0
@export var spawn_height_offset: float = -50.0
@export_range(5, 50) var pool_size: int = 10
@export var formation_spacing: float = 80.0  # Space between objects in formation

@export_group("Spawn Chances")
@export_range(0.0, 1.0) var formation_spawn_chance: float = 0.3
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

# Formation configurations using Callable instead of funcref
var formation_configs = {}

var object_pools = {}
var active_objects: Array[Node2D] = []
var current_zone: SpawnZone = SpawnZone.GROUND
var spawn_timer: float = 0.0
var is_spawning: bool = false
var viewport_size: Vector2

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

func _ready() -> void:
	viewport_size = get_viewport_rect().size
	initialize_pools()
	initialize_formation_configs()
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

func initialize_formation_configs() -> void:
	formation_configs = {
		FormationType.V_FORMATION: {
			"size": 5,
			"pattern": Callable(self, "get_v_formation_positions")
		},
		FormationType.LINE: {
			"size": 4,
			"pattern": Callable(self, "get_line_formation_positions")
		},
		FormationType.WALL: {
			"size": 3,
			"pattern": Callable(self, "get_wall_formation_positions")
		},
		FormationType.DIAGONAL: {
			"size": 4,
			"pattern": Callable(self, "get_diagonal_formation_positions")
		},
		FormationType.CROSS: {
			"size": 5,
			"pattern": Callable(self, "get_cross_formation_positions")
		}
	}

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
	# Determine if we should spawn a formation
	if randf() < formation_spawn_chance:
		spawn_formation()
	else:
		spawn_single_object()

func spawn_single_object() -> void:
	var selected_type = select_object_type()
	var object = get_inactive_object(selected_type)
	if object:
		var spawn_position = Vector2(
			randf_range(0, viewport_size.x),
			spawn_height_offset
		)
		setup_object(object, spawn_position)

func spawn_formation() -> void:
	var formation_type = FormationType.values()[randi() % FormationType.size()]
	if formation_type == FormationType.NONE:
		spawn_single_object()
		return

	var config = formation_configs[formation_type]
	var positions = config.pattern.call()
	var selected_type = select_object_type()

	for pos in positions:
		var object = get_inactive_object(selected_type)
		if object:
			setup_object(object, pos)

func select_object_type() -> String:
	var zone_data = zone_objects[current_zone]

	# Determine if we're spawning a collectible or obstacle
	var spawn_category = "obstacles" if randf() > energy_spawn_chance else "collectibles"
	var available_objects = zone_data[spawn_category]

	if available_objects.is_empty():
		return ""

	# Calculate total weight for available objects
	var total_weight = 0.0
	for obj in available_objects:
		total_weight += available_objects[obj]

	# Select object based on weights
	var random_value = randf() * total_weight
	var cumulative_weight = 0.0

	for obj in available_objects:
		cumulative_weight += available_objects[obj]
		if random_value <= cumulative_weight:
			return obj

	return ""

func get_inactive_object(type: String) -> Node2D:
	if not object_pools.has(type):
		return null

	for object in object_pools[type]:
		if not object.is_active:
			return object
	return null

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

func get_v_formation_positions() -> Array:
	var positions = []
	var center_x = viewport_size.x / 2
	var start_y = spawn_height_offset

	# Leader position
	positions.append(Vector2(center_x, start_y))

	# Wing positions
	for i in range(2):
		var offset = formation_spacing * (i + 1)
		positions.append(Vector2(center_x - offset, start_y + offset))
		positions.append(Vector2(center_x + offset, start_y + offset))

	return positions

func get_line_formation_positions() -> Array:
	var positions = []
	var start_x = viewport_size.x * 0.2
	var spacing = viewport_size.x * 0.6 / 3  # Divide remaining space

	for i in range(4):
		positions.append(Vector2(start_x + spacing * i, spawn_height_offset))

	return positions

func get_wall_formation_positions() -> Array:
	var positions = []
	var center_x = viewport_size.x / 2
	var spacing = formation_spacing

	for i in range(3):
		var x_offset = (i - 1) * spacing  # -spacing, 0, +spacing
		positions.append(Vector2(center_x + x_offset, spawn_height_offset))

	return positions

func get_diagonal_formation_positions() -> Array:
	var positions = []
	var start_x = viewport_size.x * 0.2
	var spacing_x = viewport_size.x * 0.6 / 3
	var spacing_y = formation_spacing

	for i in range(4):
		positions.append(Vector2(
			start_x + spacing_x * i,
			spawn_height_offset + spacing_y * i
		))

	return positions

func get_cross_formation_positions() -> Array:
	var positions = []
	var center = Vector2(viewport_size.x / 2, spawn_height_offset)

	# Center position
	positions.append(center)

	# Cardinal directions
	var offsets = [
		Vector2(0, -formation_spacing),  # Up
		Vector2(formation_spacing, 0),   # Right
		Vector2(0, formation_spacing),   # Down
		Vector2(-formation_spacing, 0)   # Left
	]

	for offset in offsets:
		positions.append(center + offset)

	return positions

func setup_object(object: Node2D, spawn_position: Vector2) -> void:
	object.initialize(spawn_position)
	active_objects.append(object)
	object_spawned.emit(object)
