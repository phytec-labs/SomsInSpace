# obstacle.gd
extends GameObject
class_name Obstacle

# Export variables for configuration
@export var damage: float = 20.0  # Damage dealt to player on collision
@export var movement_speed: float = 100.0  # Base movement speed
@export var rotation_speed: float = 0.0  # Rotation speed in radians/sec

# Movement variables
var movement_direction: Vector2 = Vector2.DOWN
var target_position: Vector2

func _ready() -> void:
	super._ready()

func _process(delta: float) -> void:
	if not is_active:
		return

	# If we're part of a formation, let the formation handle our movement
	if get_parent() is Formation:
		return

	# Independent movement when not part of formation
	position += movement_direction * movement_speed * delta

	if rotation_speed != 0:
		rotate(rotation_speed * delta)

	# Check if off screen
	var viewport_rect = get_viewport_rect()
	if position.y > viewport_rect.size.y + 50 or \
	   position.x < -50 or \
	   position.x > viewport_rect.size.x + 50:
		deactivate()
