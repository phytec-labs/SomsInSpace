# meteor_obstacle.gd
extends Obstacle
class_name MeteorObstacle

@export var flaming_trail: bool = true
@export var min_size_variation: float = 0.7
@export var max_size_variation: float = 1.3
@onready var flame_particles: CPUParticles2D = $FlameParticles if has_node("FlameParticles") else null

# Unscaled values, captured once so per-spawn variation never compounds
var _base_damage: float = -1.0
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	super._ready()
	# Meteors are fast and dangerous
	damage = 30.0
	base_speed = 180.0
	movement_pattern = "linear"

	_base_scale = scale

	# Setup flame particles if they exist
	if flame_particles and flaming_trail:
		flame_particles.emitting = true

# Re-rolled on every spawn (including reuse from the pool)
func _randomize_on_spawn() -> void:
	if _base_damage < 0.0:
		_base_damage = damage

	# Apply random size variation
	var size_variation = randf_range(min_size_variation, max_size_variation)
	scale = _base_scale * size_variation

	# Damage scales with size
	damage = _base_damage * size_variation

	# Meteors always rotate, bigger ones rotate slower
	rotation_speed = randf_range(20.0, 90.0) / size_variation
	rotation_speed *= -1 if randf() < 0.5 else 1  # Random direction
