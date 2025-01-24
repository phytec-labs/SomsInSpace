# cloud_obstacle.gd
extends GameObject
class_name CloudObstacle

@export var horizontal_speed: float = 100.0  # Speed of horizontal movement
@export var vertical_speed_factor: float = 0.01  # How fast clouds drift down (fraction of horizontal speed)
@export var size_variation: float = 0.3  # Random size variation (±30%)

var move_direction: Vector2  # Will store normalized movement direction
var base_scale: Vector2

func _ready() -> void:
	super._ready()
	speed_multiplier = randf_range(0.8, 1.2)  # Vary speed slightly
	
	# Random size variation
	var scale_factor = 1.0 + randf_range(-size_variation, size_variation)
	base_scale = Vector2(scale_factor, scale_factor)
	scale = base_scale

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	modulate.a = randf_range(0.5, 0.8)  # Random opacity
	scale = base_scale
	
	# Determine if cloud should move left to right or right to left
	var viewport_width = get_viewport_rect().size.x
	var from_left = randf() > 0.5
	
	if from_left:
		# Start left of screen, move right
		position.x = -100  # Start off-screen
		move_direction = Vector2(1, vertical_speed_factor).normalized()
	else:
		# Start right of screen, move left
		position.x = viewport_width + 100  # Start off-screen
		move_direction = Vector2(-1, vertical_speed_factor).normalized()
	
	# Keep the Y position from spawn_position
	position.y = spawn_position.y

func _process(delta: float) -> void:
	if not is_active:
		return
	
	# Move in the determined direction
	position += move_direction * horizontal_speed * delta * speed_multiplier
