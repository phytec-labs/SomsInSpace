# launch_pad.gd
extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

var fall_speed: float = 100.0
var fall_acceleration: float = 200.0
var rotation_speed: float = 0
var started_launch: bool = false
var fall_direction: float  # -1 for left, 1 for right

func _ready() -> void:
	# Randomly choose fall direction
	fall_direction = -.25 if randf() < 0.5 else .25
	
func start_launch() -> void:
	started_launch = true
	# Optional: Play animation or sound effect here
	
func _process(delta: float) -> void:
	if started_launch:
		# Increase fall speed over time
		fall_speed += fall_acceleration * delta
		
		# Move downward and sideways
		position.y += fall_speed * delta
		position.x += fall_speed * fall_direction * delta * 0.5
		
		# Rotate based on fall direction
		rotation += rotation_speed * fall_direction * delta
		
		# If we are moved off screen, fade out
		if position.y > get_viewport_rect().size.y + 100:
			# Fade out
			modulate.a = max(0, modulate.a - delta)
			
		# Destroy when faded
		if modulate.a <= 0:
			queue_free()
