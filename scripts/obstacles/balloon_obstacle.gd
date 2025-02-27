# balloon_obstacle.gd
extends Obstacle
class_name BalloonObstacle

func _ready() -> void:
	super._ready()
	# Balloons are very slow
	damage = 15.0
	base_speed = 30.0
	movement_pattern = "sine"  # Balloons drift side to side gently
	pattern_amplitude = 30.0
	pattern_frequency = 0.3
