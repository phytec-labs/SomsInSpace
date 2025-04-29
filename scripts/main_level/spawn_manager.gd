# spawn_manager_updated.gd
extends Node2D

signal object_spawned(game_object)

# Node references
@onready var formation_manager = $FormationManager
@onready var wave_manager = $WaveManager
@onready var collectible_timer = $CollectibleTimer

# Export variables
@export var base_collectible_time: float = 5.0
@export var min_collectible_time: float = 2.0
@export var collectible_time_decrease_rate: float = 0.01
@export_range(0.0, 1.0) var initial_collectible_chance: float = 0.7  # Higher chance for collectibles

@export var energy_collectible_scene: PackedScene
# Keep obstacle scenes for backward compatibility and direct spawning
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

# Game state variables
var current_collectible_time: float
var current_collectible_chance: float
var current_zone: String = "ground"
var is_spawning: bool = false
var rng = RandomNumberGenerator.new()

# Object pools
var obstacle_pool = {}
var collectible_pool = []

func _ready() -> void:
	rng.randomize()

	# Set initial collectible time
	current_collectible_time = base_collectible_time
	current_collectible_chance = initial_collectible_chance
	collectible_timer.wait_time = current_collectible_time

	# Connect signals
	collectible_timer.timeout.connect(_on_collectible_timer_timeout)

	# Ensure formation manager is ready
	if not formation_manager:
		push_error("SpawnManager: FormationManager not found!")

	# Ensure wave manager is ready
	if not wave_manager:
		push_error("SpawnManager: WaveManager not found!")

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
	
	# Start collectible timer
	collectible_timer.start()
	
	# Start wave manager
	if wave_manager:
		wave_manager.start_spawning()
	
	print("SpawnManager started spawning with collectibles and wave-based enemies")

# Stop spawning objects
func stop_spawning() -> void:
	is_spawning = false
	collectible_timer.stop()
	
	if wave_manager:
		wave_manager.stop_spawning()
	
	print("SpawnManager stopped spawning")

# Set the current zone to adjust spawn behavior
func set_spawn_zone(zone: String) -> void:
	current_zone = zone
	print("SpawnManager zone set to: ", zone)

	# Update formation manager
	if formation_manager:
		formation_manager.set_zone(zone)
	
	# Update wave manager
	if wave_manager:
		wave_manager.set_zone(zone)

	# Adjust collectible spawn time based on zone
	match zone:
		"ground":
			current_collectible_time = base_collectible_time
			current_collectible_chance = initial_collectible_chance
		"atmosphere":
			current_collectible_time = base_collectible_time * 0.8
			current_collectible_chance = initial_collectible_chance * 0.9
		"upper_atmosphere":
			current_collectible_time = base_collectible_time * 0.7
			current_collectible_chance = initial_collectible_chance * 0.8
		"space":
			current_collectible_time = base_collectible_time * 0.6
			current_collectible_chance = initial_collectible_chance * 0.7

	# Ensure we don't go below minimum time
	current_collectible_time = max(current_collectible_time, min_collectible_time)
	collectible_timer.wait_time = current_collectible_time

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

# Collectible timer callback - handles ONLY collectibles now
func _on_collectible_timer_timeout() -> void:
	if not is_spawning:
		return

	# Determine if we spawn a collectible based on chance
	var random_value = randf()
	if random_value < current_collectible_chance:
		spawn_collectible()
	
	# Gradually decrease collectible spawn time, but not below minimum
	current_collectible_time = max(current_collectible_time - collectible_time_decrease_rate, min_collectible_time)
	collectible_timer.wait_time = current_collectible_time
	collectible_timer.start()

# Get a random spawn position specifically for collectibles
func get_collectible_spawn_position() -> Vector2:
	var viewport_rect = get_viewport_rect()

	# Ensure collectibles spawn within horizontal screen bounds
	var margin = 50.0
	var x_pos = randf_range(margin, viewport_rect.size.x - margin)

	# Spawn just above the visible screen, but close enough to quickly enter view
	var y_pos = -30  # Reduced from -50 to -30 to enter screen faster

	return Vector2(x_pos, y_pos)

# Spawn a collectible
func spawn_collectible() -> Node2D:
	if not energy_collectible_scene:
		return null

	# Get collectible from pool or create new
	var collectible = null
	if not collectible_pool.is_empty():
		collectible = collectible_pool.pop_back()
	else:
		collectible = energy_collectible_scene.instantiate()
		add_child(collectible)

	# Use the collectible-specific spawn position
	var spawn_position = get_collectible_spawn_position()
	collectible.initialize(spawn_position)

	emit_signal("object_spawned", collectible)
	return collectible

# This function is called by the wave manager to spawn obstacles in formations
func spawn_obstacle(spawn_position: Vector2) -> Node2D:
	var obstacle_scenes = get_obstacle_scenes_for_zone()
	if obstacle_scenes.is_empty():
		push_warning("No obstacle scenes available for the current zone!")
		return null

	# Select a random obstacle type for this zone
	var selected_scene = obstacle_scenes[randi() % obstacle_scenes.size()]
	if not selected_scene:
		return null

	# Get or create obstacle instance
	var obstacle = get_from_pool(selected_scene.resource_path)
	if not obstacle:
		obstacle = selected_scene.instantiate()
		add_child(obstacle)

	# Set random speed multiplier if the obstacle supports it
	if obstacle.has_method("set_speed_multiplier"):
		var speed_multi = randf_range(enemy_speed_multi_min, enemy_speed_multi_max)
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

		var rand_val = randf() * total_weight
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
	# Handle collectibles
	if object is EnergyCollectible:
		object.deactivate()
		collectible_pool.append(object)
		return
		
	# Handle obstacles
	var scene_path = object.scene_file_path
	if scene_path and obstacle_pool.has(scene_path):
		object.deactivate()
		obstacle_pool[scene_path].append(object)
