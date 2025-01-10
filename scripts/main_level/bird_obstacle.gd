# bird_obstacle.gd
extends Obstacle
class_name BirdObstacle

func _ready() -> void:
	super._ready()
	# Configure bird-specific properties
	damage = 15.0
	movement_pattern = "sine"  # Birds move in a wavy pattern
	pattern_amplitude = 75.0   # How far it moves side to side
	pattern_frequency = 2.0    # How fast it moves side to side
	speed_multiplier = 1.2     # Slightly faster than base speed
