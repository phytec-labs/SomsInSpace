# spawn_manager.gd
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

# Obstacles this manager spawned that count toward
# GameConfig.max_active_obstacles (every obstacle except bosses). Added on
# spawn, removed in return_to_pool(); used as a set (values unused).
var _active_obstacles: Dictionary = {}
# Everything this manager spawned that has not been returned yet (obstacles,
# bosses, collectibles); makes return_to_pool() idempotent.
var _live_objects: Dictionary = {}

func _ready() -> void:
	# Lets other systems (e.g. the boss summoning minions) find this manager
	add_to_group("spawn_manager")
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

# Spawn a collectible at a random position above the screen
func spawn_collectible() -> Node2D:
	return spawn_collectible_at(get_collectible_spawn_position())

# Spawn a (pooled) energy collectible at spawn_position, in this manager's
# coordinates (e.g. an enemy's `position` when it drops loot on death)
func spawn_collectible_at(spawn_position: Vector2) -> Node2D:
	if not energy_collectible_scene:
		return null

	var collectible = _acquire(energy_collectible_scene)

	# Return it to the pool once it leaves the screen or is collected
	if _needs_connections(collectible):
		collectible.screen_exited.connect(_on_object_exited.bind(collectible))
		collectible.object_collected.connect(_on_object_exited.bind(collectible))

	collectible.initialize(spawn_position)
	_live_objects[collectible] = true

	emit_signal("object_spawned", collectible)
	return collectible

# Legacy: a random obstacle from the zone's obstacle_scenes with a random
# movement pattern and speed. Wave groups no longer use this (they always name
# their enemy scene; see spawn_scene()).
func spawn_obstacle(spawn_position: Vector2) -> Node2D:
	var scenes = get_obstacle_scenes_for_zone()
	if scenes.is_empty():
		push_warning("No obstacle scenes available for the current zone!")
		return null

	# Checked before picking a scene so a capped spawn costs nothing
	if _is_at_obstacle_cap():
		return null

	# Select a random obstacle type for this zone
	return _spawn_capped_obstacle(scenes[randi() % scenes.size()], spawn_position, true)

# Spawn a specific obstacle scene (wave formation members, scene_override
# singles, splitting asteroids, ...). Respects max_active_obstacles (returns
# null at the cap). spawn_position is in this manager's coordinates.
# random_movement: roll a random speed multiplier and movement pattern (for
# enemies that fly on the base movement code, e.g. boss minions). Off by
# default: formation members are driven by FormationManager, and the
# self-moving singles (blimp, UFO, mine, asteroid pieces) set their own; the
# speed multiplier is reset to 1.0 instead (pooled instances keep old values).
func spawn_scene(scene: PackedScene, spawn_position: Vector2, random_movement: bool = false) -> Node2D:
	return _spawn_capped_obstacle(scene, spawn_position, random_movement)

# Minions summoned by the boss: spawn_scene() with random movement, as before
func spawn_minion(scene: PackedScene, spawn_position: Vector2) -> Node2D:
	return spawn_scene(scene, spawn_position, true)

# Spawn a boss: not subject to max_active_obstacles and never culled for
# leaving the screen (only its destroyed signal returns it to the pool).
# The boss drives its own entrance from initialize().
func spawn_boss(scene: PackedScene) -> Node2D:
	if not scene:
		return null

	var boss = _acquire(scene)

	var spawn_position = Vector2(get_viewport_rect().size.x / 2.0, -250.0)
	boss.initialize(spawn_position)
	# Tracked for return_to_pool(), but never counted toward the cap
	_live_objects[boss] = true

	# Connected once per instance and manager; reused instances keep them
	if _needs_connections(boss):
		if boss.has_signal("destroyed"):
			boss.destroyed.connect(_on_object_exited.bind(boss))

	emit_signal("object_spawned", boss)
	return boss

# Safety valve: too many obstacles alive to spawn another
# (FormationManager / WaveManager tolerate a null spawn result)
func _is_at_obstacle_cap() -> bool:
	if config == null or config.max_active_obstacles <= 0:
		return false
	if _active_obstacles.size() >= config.max_active_obstacles:
		_prune_freed()
	return _active_obstacles.size() >= config.max_active_obstacles

# Defensive: drop entries for nodes freed without going through
# return_to_pool() (nothing does that today; pooled overflow is only freed
# after it was returned, so it is no longer tracked here)
func _prune_freed() -> void:
	for dict in [_active_obstacles, _live_objects]:
		for key in dict.keys():
			if not is_instance_valid(key):
				dict.erase(key)

# Shared path of spawn_obstacle() / spawn_scene() / spawn_minion()
func _spawn_capped_obstacle(scene: PackedScene, spawn_position: Vector2, random_movement: bool) -> Node2D:
	if not scene or _is_at_obstacle_cap():
		return null

	var obstacle = _acquire(scene)

	if obstacle.has_method("set_speed_multiplier"):
		var speed_multi := 1.0
		if random_movement:
			speed_multi = randf_range(enemy_speed_multi_min, enemy_speed_multi_max)
		obstacle.set_speed_multiplier(speed_multi)

	# Random movement pattern (opt-in) if the obstacle supports it
	if random_movement and obstacle.has_method("set_movement_pattern"):
		obstacle.set_movement_pattern(_pick_movement_pattern())

	# Initialize the obstacle (sets position, resets formation_id to -1, shows it)
	obstacle.initialize(spawn_position)
	_live_objects[obstacle] = true
	_active_obstacles[obstacle] = true

	# Return it to the pool once it leaves the screen or is destroyed
	# (connected once per instance and manager; reused instances keep them)
	if _needs_connections(obstacle):
		obstacle.screen_exited.connect(_on_object_exited.bind(obstacle))
		if obstacle.has_signal("destroyed"):
			obstacle.destroyed.connect(_on_object_exited.bind(obstacle))

	emit_signal("object_spawned", obstacle)
	return obstacle

# Take an instance of `scene` from the ObjectPool autoload (or a new one),
# parented under this manager. It stays hidden until the caller runs
# initialize(), which positions and shows it (acquire() re-shows reused nodes
# before initialize() has moved them away from where they were released).
func _acquire(scene: PackedScene) -> Node2D:
	var node = ObjectPool.acquire(scene, self)
	node.hide()
	return node

# True the first time `object` is spawned by THIS manager. Pooled instances
# outlive a scene reload, and connections to the previous (freed) manager are
# gone, so the flag stores the owning manager's instance id.
func _needs_connections(object: Node) -> bool:
	if object.get_meta("_spawn_pool_connected", 0) == get_instance_id():
		return false
	object.set_meta("_spawn_pool_connected", get_instance_id())
	return true

# Weighted random movement pattern for the current zone (uniform if no zone)
func _pick_movement_pattern() -> String:
	var patterns = MOVEMENT_PATTERNS
	if current_zone == null:
		return patterns[randi() % patterns.size()]

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

	return selected_pattern

# Obstacles currently alive and counted toward max_active_obstacles
# (bosses excluded)
func get_active_obstacle_count() -> int:
	return _active_obstacles.size()

# Object exited screen callback
func _on_object_exited(object: Node2D) -> void:
	return_to_pool(object)

# Deactivate a spawned object and hand it back to the ObjectPool autoload,
# which detaches it from the tree (deferred) until it is acquired again.
# Idempotent: e.g. destroyed and exited in the same frame returns it once.
func return_to_pool(object: Node2D) -> void:
	if not _live_objects.has(object):
		return
	_live_objects.erase(object)
	_active_obstacles.erase(object)
	if not is_instance_valid(object):
		return
	object.deactivate()
	ObjectPool.release(object)
