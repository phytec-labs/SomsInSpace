# spawn_manager_updated.gd
extends Node2D

signal object_spawned(game_object)

const GameConfigScript := preload("res://scripts/data/game_config.gd")
const ZoneDefinitionScript := preload("res://scripts/data/zone_definition.gd")

const MOVEMENT_PATTERNS: Array[String] = ["linear", "sine", "zigzag"]

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

# Enemy-specific properties
@export_group("Enemy Settings")
@export var enemy_speed_multi_min: float = 0.8
@export var enemy_speed_multi_max: float = 1.2

# Game state variables
var current_collectible_time: float
var current_collectible_chance: float
var config: GameConfigScript
var current_zone: ZoneDefinitionScript  # Obstacle scenes etc. come from here
var is_spawning: bool = false
var rng = RandomNumberGenerator.new()

# Object pools
var obstacle_pool = {}
var collectible_pool = []
# Every obstacle instance this manager created (active or pooled), used to
# count active obstacles for GameConfig.max_active_obstacles
var _obstacle_instances: Array[Node2D] = []

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

# Called by main_level.gd with the GameConfig before spawning starts.
# main_level then selects the starting zone via set_spawn_zone().
func configure(game_config: GameConfigScript) -> void:
	config = game_config
	initialize_obstacle_pools()

func initialize_obstacle_pools() -> void:
	# Create pools for each obstacle type used by any zone
	if not config:
		return
	for zone in config.zones:
		for scene in zone.obstacle_scenes:
			if scene and not obstacle_pool.has(scene.resource_path):
				obstacle_pool[scene.resource_path] = []

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

# Set the current zone (a ZoneDefinition) to adjust spawn behavior
func set_spawn_zone(zone: ZoneDefinitionScript) -> void:
	if zone == null:
		return
	current_zone = zone
	print("SpawnManager zone set to: ", zone.id)

	# Update formation manager
	if formation_manager:
		formation_manager.set_zone(zone)
	
	# Update wave manager
	if wave_manager:
		wave_manager.set_zone(zone)

	# Adjust collectible spawn time / chance based on zone
	current_collectible_time = base_collectible_time * zone.collectible_time_scale
	current_collectible_chance = initial_collectible_chance * zone.collectible_chance_scale

	# Ensure we don't go below minimum time
	current_collectible_time = max(current_collectible_time, min_collectible_time)
	collectible_timer.wait_time = current_collectible_time

# Get appropriate obstacle scenes for current zone
func get_obstacle_scenes_for_zone() -> Array[PackedScene]:
	if current_zone == null:
		return []
	return current_zone.obstacle_scenes

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
	var collectible = _take_reusable(collectible_pool)
	if not collectible:
		collectible = energy_collectible_scene.instantiate()
		add_child(collectible)

	# Return it to the pool once it leaves the screen or is collected
	if not collectible.has_meta("_spawn_pool_connected"):
		collectible.set_meta("_spawn_pool_connected", true)
		collectible.screen_exited.connect(_on_object_exited.bind(collectible))
		collectible.object_collected.connect(_on_object_exited.bind(collectible))

	# Use the collectible-specific spawn position
	var spawn_position = get_collectible_spawn_position()
	collectible.initialize(spawn_position)

	emit_signal("object_spawned", collectible)
	return collectible

# This function is called by the wave manager to spawn obstacles in formations
func spawn_obstacle(spawn_position: Vector2) -> Node2D:
	var scenes = get_obstacle_scenes_for_zone()
	if scenes.is_empty():
		push_warning("No obstacle scenes available for the current zone!")
		return null

	# Safety valve: skip this spawn while too many obstacles are alive
	# (FormationManager / WaveManager tolerate a null here)
	if config and config.max_active_obstacles > 0 \
			and get_active_obstacle_count() >= config.max_active_obstacles:
		return null

	# Select a random obstacle type for this zone
	var selected_scene = scenes[randi() % scenes.size()]
	if not selected_scene:
		return null

	# Get or create obstacle instance
	var obstacle = get_from_pool(selected_scene.resource_path)
	if not obstacle:
		obstacle = selected_scene.instantiate()
		add_child(obstacle)
		_obstacle_instances.append(obstacle)

	# Set random speed multiplier if the obstacle supports it
	if obstacle.has_method("set_speed_multiplier"):
		var speed_multi = randf_range(enemy_speed_multi_min, enemy_speed_multi_max)
		obstacle.set_speed_multiplier(speed_multi)

	# Set random movement pattern if the obstacle supports it
	if obstacle.has_method("set_movement_pattern"):
		var patterns = MOVEMENT_PATTERNS
		var weights = current_zone.get_pattern_weights() # Higher weight = more common

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

	# Return it to the pool once it leaves the screen or is destroyed
	# (connected once per instance; reused instances keep their connections)
	if not obstacle.has_meta("_spawn_pool_connected"):
		obstacle.set_meta("_spawn_pool_connected", true)
		obstacle.screen_exited.connect(_on_object_exited.bind(obstacle))
		if obstacle.has_signal("destroyed"):
			obstacle.destroyed.connect(_on_object_exited.bind(obstacle))

	emit_signal("object_spawned", obstacle)
	return obstacle

# Obstacles currently alive (is_active is cleared by deactivate(), which every
# destroy / exit / return-to-pool path goes through)
func get_active_obstacle_count() -> int:
	var count := 0
	for i in range(_obstacle_instances.size() - 1, -1, -1):
		var obstacle = _obstacle_instances[i]
		if not is_instance_valid(obstacle):
			_obstacle_instances.remove_at(i)
		elif obstacle.is_active:
			count += 1
	return count

# Object exited screen callback
func _on_object_exited(object: Node2D) -> void:
	return_to_pool(object)

# Object pool management
# Pooled objects are not reused until POOL_REUSE_DELAY_FRAMES frames after they
# were returned, so systems that still hold a reference (e.g. the formation
# manager, which drops inactive members during its own _process) let go first.
const POOL_REUSE_DELAY_FRAMES: int = 2

func get_from_pool(scene_path: String) -> Node2D:
	if obstacle_pool.has(scene_path):
		return _take_reusable(obstacle_pool[scene_path])
	return null

func _take_reusable(pool: Array) -> Node2D:
	var current_frame = Engine.get_process_frames()
	for i in range(pool.size() - 1, -1, -1):
		var obj = pool[i]
		if not is_instance_valid(obj):
			pool.remove_at(i)
			continue
		if current_frame - int(obj.get_meta("_pooled_frame", 0)) >= POOL_REUSE_DELAY_FRAMES:
			pool.remove_at(i)
			return obj
	return null

func return_to_pool(object: Node2D) -> void:
	var pool = null
	if object is EnergyCollectible:
		# Handle collectibles
		pool = collectible_pool
	else:
		# Handle obstacles
		var scene_path = object.scene_file_path
		if scene_path and obstacle_pool.has(scene_path):
			pool = obstacle_pool[scene_path]

	if pool == null:
		return

	object.deactivate()
	# Guard against double returns (e.g. destroyed and exited in the same frame)
	if not pool.has(object):
		object.set_meta("_pooled_frame", Engine.get_process_frames())
		pool.append(object)
