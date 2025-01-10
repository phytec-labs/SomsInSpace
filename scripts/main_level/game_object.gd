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

func _ready() -> void:
	# Connect collision signal
	connect("area_entered", _on_area_entered)
	connect("body_entered", _on_body_entered)

func initialize(spawn_position: Vector2) -> void:
	position = spawn_position
	is_active = true
	show()

func deactivate() -> void:
	is_active = false
	hide()
	# Additional cleanup if needed

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player"):
		handle_player_collision()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		handle_player_collision()

func handle_player_collision() -> void:
	if points >= 0:
		emit_signal("object_collected")
	else:
		emit_signal("object_hit")
	deactivate()
