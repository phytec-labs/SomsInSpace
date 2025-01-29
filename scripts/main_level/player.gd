# player.gd
extends CharacterBody2D

# Export variables
@export var speed: float = 300.0
@export var touch_offset: float = 100.0  # Distance to maintain above touch point
@export var smoothing_speed: float = 5.0  # Lower = smoother movement

# Node references
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var area: Area2D = $CollisionArea

# State variables
var can_move: bool = false
var initial_position: Vector2
var target_position: Vector2
var is_touch_active: bool = false

func _ready() -> void:
	# Store initial position for reset functionality
	initial_position = position
	target_position = position
	
	# Ensure all required nodes are present
	assert(sprite != null, "Sprite node not found")
	assert(collision_shape != null, "CollisionShape node not found")
	assert(area != null, "CollisionArea node not found")

	# Set up collision properties
	area.collision_layer = 1  # Layer 1 for player
	area.collision_mask = 2   # Mask 2 to detect game objects

	disable_movement()

func _input(event: InputEvent) -> void:
	if not can_move:
		return
		
	if event is InputEventScreenTouch:
		is_touch_active = event.pressed
		if is_touch_active:
			update_target_position(event.position)
	elif event is InputEventScreenDrag and is_touch_active:
		update_target_position(event.position)
	elif event is InputEventMouseButton:
		is_touch_active = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if is_touch_active:
			update_target_position(event.position)
	elif event is InputEventMouseMotion and is_touch_active:
		update_target_position(event.position)

func update_target_position(input_position: Vector2) -> void:
	# Set target position with vertical offset
	target_position = input_position
	target_position.y -= touch_offset  # Keep player above touch point

func _physics_process(delta: float) -> void:
	if not can_move:
		return

	var movement: Vector2 = Vector2.ZERO
	
	if is_touch_active:
		# Move towards target position with smoothing
		var direction = (target_position - position)
		if direction.length() > 1.0:  # Only move if we're not basically at the target
			movement = direction.normalized() * speed
			velocity = velocity.lerp(movement, smoothing_speed * delta)
		else:
			velocity = Vector2.ZERO
	else:
		# Traditional keyboard input as fallback
		movement.x = Input.get_axis("ui_left", "ui_right")
		movement.y = Input.get_axis("ui_up", "ui_down")
		
		# Normalize diagonal movement
		if movement.length() > 1.0:
			movement = movement.normalized()
			
		velocity = movement * speed

	# Move and constrain to viewport
	move_and_slide()
	constrain_to_viewport()

func constrain_to_viewport() -> void:
	var viewport_rect: Rect2 = get_viewport_rect()
	position.x = clamp(position.x, 0, viewport_rect.size.x)
	position.y = clamp(position.y, 0, viewport_rect.size.y)

func enable_movement() -> void:
	can_move = true
	is_touch_active = false
	target_position = position

func disable_movement() -> void:
	can_move = false
	is_touch_active = false
	velocity = Vector2.ZERO

func reset_position() -> void:
	position = initial_position
	target_position = initial_position
	velocity = Vector2.ZERO
	is_touch_active = false
