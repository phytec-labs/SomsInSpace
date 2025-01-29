# jet_obstacle.gd
extends Obstacle
class_name JetObstacle

@export var horizontal_speed: float = 600.0  # Fast horizontal speed
@export var vertical_speed: float = 30.0     # Base vertical movement
@export var spawn_offset: float = 200.0      # How far off-screen to spawn
@export var wave_amplitude: float = 80.0     # Height of sine wave
@export var wave_frequency: float = 3.0      # Speed of wave oscillation

var move_direction: Vector2
var initial_y: float

func _ready() -> void:
	super._ready()
	damage = 25.0  # Higher damage than planes
	speed_multiplier = randf_range(0.9, 1.1)  # Slight speed variation

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	
	var viewport_size = get_viewport_rect().size
	initial_y = spawn_position.y
	time_alive = 0.0  # Using parent class variable
	
	# Randomly choose to spawn from left or right
	var from_left = randf() > 0.5
	
	if from_left:
		position.x = -spawn_offset
		move_direction = Vector2.RIGHT
		scale.x = 1
	else:
		position.x = viewport_size.x + spawn_offset
		move_direction = Vector2.LEFT
		scale.x = -1
		
	scale.y = 1

func _process(delta: float) -> void:
	if not is_active:
		return
	
	super._process(delta)  # Let parent class update time_alive
		
	# Move horizontally at high speed
	position.x += move_direction.x * horizontal_speed * speed_multiplier * delta
	
	# Calculate vertical position using sine wave
	var wave_offset = sin(time_alive * wave_frequency) * wave_amplitude
	position.y = initial_y + vertical_speed * time_alive + wave_offset
	
	# Check if jet has moved off screen
	var viewport_size = get_viewport_rect().size
	if (move_direction.x > 0 and position.x > viewport_size.x + spawn_offset) or \
	   (move_direction.x < 0 and position.x < -spawn_offset) or \
	   position.y > viewport_size.y + 100:
		deactivate()
