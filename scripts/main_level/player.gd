# player.gd
extends CharacterBody2D

# Export variables
@export var speed: float = 300.0

# Node references
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var area: Area2D = $CollisionArea

# State variables
var can_move: bool = false
var initial_position: Vector2

func _ready() -> void:
	# Store initial position for reset functionality
	initial_position = position
	# Ensure all required nodes are present
	assert(sprite != null, "Sprite node not found")
	assert(collision_shape != null, "CollisionShape node not found")
	assert(area != null, "CollisionArea node not found")

	# Set up collision properties
	area.collision_layer = 1  # Layer 1 for player
	area.collision_mask = 2   # Mask 2 to detect game objects

	disable_movement()

func _physics_process(delta: float) -> void:
	if not can_move:
		return

	# Get input for movement
	var direction: Vector2 = Vector2.ZERO
	direction.x = Input.get_axis("ui_left", "ui_right")
	direction.y = Input.get_axis("ui_up", "ui_down")

	# Normalize diagonal movement
	if direction.length() > 1.0:
		direction = direction.normalized()

	# Set velocity
	velocity = direction * speed

	# Move and constrain to viewport
	move_and_slide()
	constrain_to_viewport()

func constrain_to_viewport() -> void:
	var viewport_rect: Rect2 = get_viewport_rect()
	position.x = clamp(position.x, 0, viewport_rect.size.x)
	position.y = clamp(position.y, 0, viewport_rect.size.y)

func enable_movement() -> void:
	can_move = true

func disable_movement() -> void:
	can_move = false
	velocity = Vector2.ZERO

func reset_position() -> void:
	position = initial_position
	velocity = Vector2.ZERO
