# spawn_manager.gd
extends Node2D

signal object_spawned(game_object)

# Node references
@onready var formation_manager = $FormationManager
@onready var spawn_timer = $SpawnTimer

# Export variables
@export var base_spawn_time: float = 3.0
@export var min_spawn_time: float = 0.5
@export var spawn_time_decrease_rate: float = 0.05

@export var energy_collectible_scene: PackedScene
# Keep this for backward compatibility
@export var obstacle_scenes: Array[PackedScene] = []

@export_group("Obstacle Scenes by Zone")
@export var ground_obstacle_scenes: Array[PackedScene] = []
@export var atmosphere_obstacle_scenes: Array[PackedScene] = []
@export var upper_atmosphere_obstacle_scenes: Array[PackedScene] = []
@export var space_obstacle_scenes: Array[PackedScene] = []

# Enemy-specific properties
@export_group("Enemy Settings")
@export var enemy_speed_multi_min: float = 0.8
@export var enemy_speed_multi_max: float = 1.2
@export_range(0.0, 1.0) var formation_chance: float = 0.3

# Game state variables
var current_spawn_time: float
var current_zone: String = "ground"
var is_spawning: bool = false
var rng = RandomNumberGenerator.new()

# Object pools
var obstacle_pool = {}

func _ready() -> void:
	rng.randomize()

	# Set initial spawn time
	current_spawn_time = base_spawn_time
	spawn_timer.wait_time = current_spawn_time

	# Connect signals
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	# Ensure formation manager is ready
	if formation_manager:
		formation_manager.formation_created.connect(_on_formation_created)
	else:
		push_error("FormationManager not found!")

	# Initialize object pools
	initialize_obstacle_pools()

func initialize_obstacle_pools() -> void:
	# Create pools for each obstacle type to improve performance
	for scene_array in [obstacle_scenes, ground_obstacle_scenes, atmosphere_obstacle_scenes,
						upper_atmosphere_obstacle_scenes, space_obstacle_scenes]:
		for i in range(scene_array.size()):
			var scene = scene_array[i]
			if scene:
				var scene_path = scene.resource_path
				if not obstacle_pool.has(scene_path):
					obstacle_pool[scene_path] = []

# Start spawning objects
func start_spawning() -> void:
	is_spawning = true
	spawn_timer.start()

# Stop spawning objects
func stop_spawning() -> void:
	is_spawning = false
	spawn_timer.stop()

# Set the current zone to adjust spawn behavior
func set_spawn_zone(zone: String) -> void:
	current_zone = zone

	if formation_manager:
		formation_manager.set_zone(zone)

	# Adjust spawn time based on zone
	match zone:
		"ground":
			current_spawn_time = base_spawn_time
		"atmosphere":
			current_spawn_time = base_spawn_time * 0.8
		"upper_atmosphere":
			current_spawn_time = base_spawn_time * 0.6
		"space":
			current_spawn_time = base_spawn_time * 0.4

	current_spawn_time = max(current_spawn_time, min_spawn_time)
	spawn_timer.wait_time = current_spawn_time

# Get appropriate obstacle scenes for current zone
func get_obstacle_scenes_for_zone() -> Array[PackedScene]:
	match current_zone:
		"ground":
			return ground_obstacle_scenes if not ground_obstacle_scenes.is_empty() else [obstacle_scenes[0]] if not obstacle_scenes.is_empty() else []
		"atmosphere":
			return atmosphere_obstacle_scenes if not atmosphere_obstacle_scenes.is_empty() else obstacle_scenes
		"upper_atmosphere":
			return upper_atmosphere_obstacle_scenes if not upper_atmosphere_obstacle_scenes.is_empty() else obstacle_scenes
		"space":
			return space_obstacle_scenes if not space_obstacle_scenes.is_empty() else obstacle_scenes
		_:
			return obstacle_scenes if not obstacle_scenes.is_empty() else []

# Spawn timer callback
func _on_spawn_timer_timeout() -> void:
	if not is_spawning:
		return

	# Determine if we're spawning a formation or single object
	var is_formation = randf() < formation_chance

	if is_formation:
		spawn_formation()
	else:
		spawn_single_object()

	# Decrease spawn time gradually, but not below minimum
	current_spawn_time = max(current_spawn_time - spawn_time_decrease_rate, min_spawn_time)
	spawn_timer.wait_time = current_spawn_time
	spawn_timer.start()

# Get a random spawn position based on viewport size
func get_random_spawn_position() -> Vector2:
	var viewport_rect = get_viewport_rect()

	if formation_manager:
		return formation_manager.generate_spawn_position(viewport_rect.size)

	# Default implementation if formation manager isn't available
	var x_pos = rng.randf_range(50, viewport_rect.size.x - 50)
	var y_pos = -100.0 # Just above the screen

	# In upper zones, enemies can come from sides too
	if current_zone == "upper_atmosphere" or current_zone == "space":
		var come_from_side = rng.randi() % 3 == 0 # 33% chance
		if come_from_side:
			x_pos = rng.randi() % 2 * (viewport_rect.size.x + 200) - 100 # Either -100 or viewport+100
			y_pos = rng.randf_range(100, viewport_rect.size.y / 2)

	return Vector2(x_pos, y_pos)

# Spawn a single object (obstacle or collectible)
func spawn_single_object() -> void:
	var is_collectible = randf() < 0.3 # 30% chance to spawn collectible

	if is_collectible and energy_collectible_scene:
		spawn_collectible()
	else:
		spawn_obstacle()

# Spawn a collectible
func spawn_collectible() -> Node2D:
	if not energy_collectible_scene:
		return null

	var collectible = energy_collectible_scene.instantiate()
	add_child(collectible)

	var spawn_position = get_random_spawn_position()
	collectible.initialize(spawn_position)

	emit_signal("object_spawned", collectible)
	return collectible

# Spawn an obstacle from the appropriate zone
func spawn_obstacle(custom_position = null) -> Node2D:
	var obstacle_scenes = get_obstacle_scenes_for_zone()
	if obstacle_scenes.is_empty():
		push_warning("No obstacle scenes available for the current zone!")
		return null

	# Select a random obstacle type for this zone
	var selected_scene = obstacle_scenes[rng.randi() % obstacle_scenes.size()]
	if not selected_scene:
		return null

	# Get or create obstacle instance
	var obstacle = get_from_pool(selected_scene.resource_path)
	if not obstacle:
		obstacle = selected_scene.instantiate()
		add_child(obstacle)

	# Initialize with random properties
	var spawn_position = custom_position if custom_position else get_random_spawn_position()

	# Set random speed multiplier if the obstacle supports it
	if obstacle.has_method("set_speed_multiplier"):
		var speed_multi = rng.randf_range(enemy_speed_multi_min, enemy_speed_multi_max)
		obstacle.set_speed_multiplier(speed_multi)

	# Set random movement pattern if the obstacle supports it
	if obstacle.has_method("set_movement_pattern"):
		var patterns = ["linear", "sine", "zigzag"]
		var weights = [0.5, 0.3, 0.2] # Higher weight = more common

		# Adjust pattern weights based on zone
		if current_zone == "upper_atmosphere":
			weights = [0.3, 0.4, 0.3]
		elif current_zone == "space":
			weights = [0.2, 0.4, 0.4]

		var total_weight = 0.0
		for w in weights:
			total_weight += w

		var rand_val = rng.randf() * total_weight
		var cumulative_weight = 0.0
		var selected_pattern = patterns[0]

		for i in range(patterns.size()):
			cumulative_weight += weights[i]
			if rand_val <= cumulative_weight:
				selected_pattern = patterns[i]
				break

		obstacle.set_movement_pattern(selected_pattern)

	# Initialize the obstacle
	obstacle.initialize(spawn_position)

	# Connect signals if not already connected
	if not obstacle.is_connected("screen_exited", Callable(self, "_on_object_exited")):
		obstacle.screen_exited.connect(_on_object_exited.bind(obstacle))

	emit_signal("object_spawned", obstacle)
	return obstacle

# Spawn a formation of obstacles
func spawn_formation() -> void:
	if not formation_manager:
		spawn_single_object()
		return

	var base_position = get_random_spawn_position()

	# Create a formation using the formation manager
	formation_manager.create_random_formation(base_position, func(pos): return spawn_obstacle(pos))

# Formation created callback
func _on_formation_created(formation_objects: Array) -> void:
	if formation_objects.is_empty():
		return

	# Determine common settings for the formation
	var base_speed = 0.0
	var pattern = ""
	var pattern_weights = {"linear": 0.6, "sine": 0.3, "zigzag": 0.1}

	# Adjust pattern weights based on zone
	if current_zone == "upper_atmosphere":
		pattern_weights = {"linear": 0.4, "sine": 0.4, "zigzag": 0.2}
	elif current_zone == "space":
		pattern_weights = {"linear": 0.3, "sine": 0.4, "zigzag": 0.3}

	# Select a pattern for the whole formation
	var total_weight = 0.0
	for w in pattern_weights.values():
		total_weight += w

	var rand_val = rng.randf() * total_weight
	var cumulative_weight = 0.0
	var selected_pattern = "linear"  # Default

	for p in pattern_weights.keys():
		cumulative_weight += pattern_weights[p]
		if rand_val <= cumulative_weight:
			selected_pattern = p
			break

	# Determine formation speed
	base_speed = rng.randf_range(enemy_speed_multi_min, enemy_speed_multi_max) * 100.0  # Base speed

	# Apply common settings to all formation members
	for obj in formation_objects:
		if obj.has_method("set_formation_member"):
			obj.set_formation_member(true)

		if obj.has_method("set_speed_multiplier"):
			obj.set_speed_multiplier(base_speed / 100.0)  # Normalized to base

		# Override individual patterns with formation pattern
		if obj.has_method("set_movement_pattern"):
			obj.set_movement_pattern("linear")  # Individual objects move straight but maintain formation

# Object exited screen callback
func _on_object_exited(object: Node2D) -> void:
	return_to_pool(object)

# Object pool management
func get_from_pool(scene_path: String) -> Node2D:
	if obstacle_pool.has(scene_path) and not obstacle_pool[scene_path].is_empty():
		var obj = obstacle_pool[scene_path].pop_back()
		return obj
	return null

func return_to_pool(object: Node2D) -> void:
	var scene_path = object.scene_file_path
	if scene_path and obstacle_pool.has(scene_path):
		object.deactivate()
		obstacle_pool[scene_path].append(object)
