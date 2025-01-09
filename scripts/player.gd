# player.gd
extends CharacterBody2D

@export var speed: float = 300.0
var can_move: bool = false

func _ready():
	disable_movement()

func _physics_process(_delta):
	if not can_move:
		return
		
	# Get input for movement
	var direction = Vector2.ZERO
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

func constrain_to_viewport():
	var viewport_rect = get_viewport_rect().size
	position.x = clamp(position.x, 0, viewport_rect.x)
	position.y = clamp(position.y, 0, viewport_rect.y)

func enable_movement():
	can_move = true

func disable_movement():
	can_move = false
	velocity = Vector2.ZERO
