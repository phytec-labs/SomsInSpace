# meteor_obstacle.gd
extends Obstacle
class_name MeteorObstacle

@export var flaming_trail: bool = true
@export var min_size_variation: float = 0.7
@export var max_size_variation: float = 1.3
@onready var flame_particles: CPUParticles2D = $FlameParticles if has_node("FlameParticles") else null

func _ready() -> void:
	super._ready()
	# Meteors are fast and dangerous
	damage = 30.0
	base_speed = 180.0
	movement_pattern = "linear"
	
	# Apply random size variation
	var size_variation = randf_range(min_size_variation, max_size_variation)
	scale = Vector2(size_variation, size_variation)
	
	# Damage scales with size
	damage *= size_variation
	
	# Meteors always rotate, bigger ones rotate slower
	rotation_speed = randf_range(20.0, 90.0) / size_variation
	rotation_speed *= -1 if randf() < 0.5 else 1  # Random direction
	
	# Setup flame particles if they exist
	if flame_particles and flaming_trail:
		flame_particles.emitting = true
