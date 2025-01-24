# game_object.gd
extends Area2D
class_name GameObject

# Export variables for easy configuration in editor
@export var points: int = 0  # Positive for collectibles, negative for obstacles
@export var speed_multiplier: float = 1.0  # Allows for varying speeds

# Signals
signal object_collected
signal object_hit

# Node references
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Object state
var is_active: bool = false
var is_being_collected: bool = false  # Prevent multiple collisions during collection

func _ready() -> void:
	# Set up collision properties
	collision_layer = 2  # Layer 2 for game objects
	collision_mask = 1   # Layer 1 for player

	# We only need area_entered since we're using Area2D for the player too
	area_entered.connect(_on_area_entered)

func initialize(spawn_position: Vector2) -> void:
	position = spawn_position
	is_active = true
	is_being_collected = false
	show()
	if sprite:
		sprite.show()
	if collision_shape:
		collision_shape.set_deferred("disabled", false)

func deactivate() -> void:
	is_active = false
	if sprite:
		sprite.hide()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	hide()

func _on_area_entered(_area: Area2D) -> void:
	if not is_active or is_being_collected:
		return

	# Since we're using collision layers/masks, any area entering
	# must be the player's collision area
	call_deferred("handle_player_collision")

func handle_player_collision() -> void:
	if is_being_collected:
		return

	is_being_collected = true

	# Hide sprite and disable collisions immediately
	if sprite:
		sprite.hide()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	# Emit appropriate signal based on points value
	if points >= 0:
		emit_signal("object_collected")
	else:
		emit_signal("object_hit")

	# Finally deactivate the object
	deactivate()
