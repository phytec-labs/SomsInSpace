# cloud_obstacle.gd
extends GameObject
class_name CloudObstacle

@export var horizontal_speed: float = 30.0      # Speed of horizontal movement
@export var vertical_base_speed: float = 50.0   # Base downward speed
@export var size_variation: float = 0.3         # Random size variation (±30%)

var horizontal_direction: float  # Will be either 1 or -1
var base_scale: Vector2

func _ready() -> void:
	super._ready()
	speed_multiplier = randf_range(0.8, 1.2)  # Vary speed between clouds

	# Random size variation
	var scale_factor = 1.0 + randf_range(-size_variation, size_variation)
	base_scale = Vector2(scale_factor, scale_factor)
	scale = base_scale

	# Randomly choose direction (-1 for left, 1 for right)
	horizontal_direction = 1.0 if randf() > 0.5 else -1.0

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	modulate.a = randf_range(0.8, 1.0)  # Random opacity
	scale = base_scale

func _process(delta: float) -> void:
	if not is_active:
		return

	# Apply steady horizontal and vertical movement
	position.y += vertical_base_speed * speed_multiplier * delta
	position.x += horizontal_speed * horizontal_direction * delta

	# Check if cloud has moved off screen
	var viewport_size = get_viewport_rect().size
	if position.y > viewport_size.y + 100:
		deactivate()
