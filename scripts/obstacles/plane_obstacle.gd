# plane_obstacle.gd
extends Obstacle
class_name PlaneObstacle

func _ready() -> void:
	super._ready()
	# Planes are slower but wider
	damage = 15.0
	base_speed = 80.0
	movement_pattern = "linear"
	rotation_speed = 0.0  # Planes don't rotate
