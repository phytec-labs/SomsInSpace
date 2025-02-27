# satellite_obstacle.gd
extends Obstacle
class_name SatelliteObstacle

@export var rotation_variation: float = 20.0
@export var min_rotation_speed: float = 5.0
@export var max_rotation_speed: float = 30.0

func _ready() -> void:
	super._ready()
	# Satellites are slow but do more damage
	damage = 25.0
	base_speed = 40.0
	movement_pattern = "linear"
	
	# Satellites almost always rotate
	rotation_speed = randf_range(min_rotation_speed, max_rotation_speed)
	rotation_speed *= -1 if randf() < 0.5 else 1  # Random direction
	
	# Random initial rotation
	rotation_degrees = randf_range(0, 360)
