# formation.gd
extends Node2D
class_name Formation

# Formation types
enum FormationType {
	LINE,           # Simple line of obstacles
	V_SHAPE,        # V-shaped formation
	CIRCLE,         # Circular formation
	WAVE           # Wave-like pattern
}

# Export variables
@export var formation_type: FormationType = FormationType.LINE
@export var obstacle_count: int = 5
@export var spacing: float = 40.0
@export var speed: float = 100.0
@export var spawn_time: float = 0.1  # Time between each obstacle spawn

# Movement patterns
enum MovementPattern {
	STRAIGHT,       # Move in a straight line
	SINE_WAVE,     # Sine wave movement
	ZIGZAG         # Zigzag pattern
}

@export var movement_pattern: MovementPattern = MovementPattern.STRAIGHT
@export var pattern_amplitude: float = 50.0  # For sine and zigzag patterns
@export var pattern_frequency: float = 2.0   # For sine and zigzag patterns

# Internal variables
var obstacles: Array[Obstacle] = []
var spawn_timer: float = 0.0
var obstacles_spawned: int = 0
var formation_active: bool = false
var initial_position: Vector2
var time_elapsed: float = 0.0
var obstacle_relative_positions: Array[Vector2] = []

signal formation_completed
signal formation_destroyed

func initialize(start_pos: Vector2) -> void:
	initial_position = start_pos
	position = start_pos
	formation_active = true
	obstacles_spawned = 0
	spawn_timer = 0.0
	time_elapsed = 0.0
	obstacle_relative_positions.clear()

func _process(delta: float) -> void:
	if not formation_active:
		return

	time_elapsed += delta

	# Spawn obstacles over time
	if obstacles_spawned < obstacle_count:
		spawn_timer += delta
		if spawn_timer >= spawn_time:
			spawn_timer = 0.0
			spawn_next_obstacle()

	# Update movement for formation and all obstacles
	update_movement(delta)
	update_obstacle_positions()

	# Check if formation is complete
	check_formation_status()

func spawn_next_obstacle() -> void:
	var relative_position = calculate_spawn_position(obstacles_spawned)

	var obstacle = create_obstacle()
	if obstacle:
		obstacle_relative_positions.append(relative_position)
		obstacle.position = position + relative_position
		obstacles.append(obstacle)
		obstacles_spawned += 1

func calculate_spawn_position(index: int) -> Vector2:
	var pos = Vector2.ZERO

	match formation_type:
		FormationType.LINE:
			pos.x = index * spacing - (obstacle_count * spacing / 2)
		FormationType.V_SHAPE:
			var half_count = obstacle_count / 2
			if index < half_count:
				pos = Vector2(-spacing * index, spacing * index)
			else:
				var adjusted_index = index - half_count
				pos = Vector2(spacing * adjusted_index, spacing * adjusted_index)
		FormationType.CIRCLE:
			var angle = (2 * PI * index) / obstacle_count
			pos = Vector2(
				cos(angle) * spacing,
				sin(angle) * spacing
			)
		FormationType.WAVE:
			pos.x = index * spacing - (obstacle_count * spacing / 2)
			pos.y = sin(index * 0.5) * spacing * 0.5

	return pos

func update_movement(delta: float) -> void:
	match movement_pattern:
		MovementPattern.STRAIGHT:
			position.y += speed * delta
		MovementPattern.SINE_WAVE:
			position.y += speed * delta
			position.x = initial_position.x + sin(time_elapsed * pattern_frequency) * pattern_amplitude
		MovementPattern.ZIGZAG:
			position.y += speed * delta
			position.x = initial_position.x + fmod(time_elapsed * pattern_frequency, 2.0 - 1.0) * pattern_amplitude

func update_obstacle_positions() -> void:
	for i in range(obstacles.size()):
		if i < obstacle_relative_positions.size() and obstacles[i] != null:
			obstacles[i].position = position + obstacle_relative_positions[i]

func check_formation_status() -> void:
	# Update active obstacles list and check if any are off screen
	var viewport_rect = get_viewport_rect()
	var viewport_bottom = viewport_rect.position.y + viewport_rect.size.y

	# If formation is off screen, clean up
	if position.y > viewport_bottom + 100:
		# Signal parent to clean up obstacles
		formation_completed.emit()
		formation_active = false

func create_obstacle() -> Obstacle:
	# Get obstacle from spawn manager
	if get_parent() is SpawnManager:
		return get_parent().get_obstacle_from_pool()
	return null
