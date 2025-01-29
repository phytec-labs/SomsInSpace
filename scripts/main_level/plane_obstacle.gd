# plane_obstacle.gd
extends Obstacle
class_name PlaneObstacle

@export var horizontal_speed: float = 150.0  # Slower than jets
@export var vertical_speed: float = 40.0    # Steady downward movement

var move_direction: Vector2

func _ready() -> void:
	super._ready()
	damage = 15.0
	speed_multiplier = randf_range(0.8, 1.2)

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	
	# Randomly choose direction and set appropriate scale
	var viewport_size = get_viewport_rect().size
	var from_left = randf() > 0.5
	
	if from_left:
		position.x = -50  # Start left of screen
		move_direction = Vector2.RIGHT
		scale.x = 1
	else:
		position.x = viewport_size.x + 50  # Start right of screen
		move_direction = Vector2.LEFT
		scale.x = -1
		
	scale.y = 1

func _process(delta: float) -> void:
	if not is_active:
		return
	
	# Move horizontally
	position.x += move_direction.x * horizontal_speed * speed_multiplier * delta
	
	# Move downward at steady pace
	position.y += vertical_speed * delta
	
	# Check if plane has moved off screen
	var viewport_size = get_viewport_rect().size
	if (move_direction.x > 0 and position.x > viewport_size.x + 50) or \
	   (move_direction.x < 0 and position.x < -50) or \
	   position.y > viewport_size.y + 100:
		deactivate()
