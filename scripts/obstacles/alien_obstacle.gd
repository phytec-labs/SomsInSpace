# plane_obstacle.gd
extends Obstacle
class_name AlienObstacle

func _ready() -> void:
	super._ready()
	# Planes are slower but wider
	damage = 15.0
	base_speed = 80.0
	movement_pattern = "linear"
	rotation_speed = 0.0
	# Set shooting capabilities for aliens
	can_shoot = true
	shoot_cooldown = 2.0  # Aliens shoot less frequently
	shoot_chance = 0.5    # 50% chance to shoot when cooldown expired
	projectile_speed = 180.0

# Override shoot function for more specialized behavior
func shoot() -> void:
	if not projectile_scene or not is_active:
		return
	
	# Aliens always fire from all gun points at once
	for gun_point in gun_points:
		var projectile = projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		
		var spawn_position = gun_point.global_position
		
		# Aliens fire in a spread pattern rather than directly at player
		var base_direction = Vector2.DOWN
		var spread = rng.randf_range(-0.3, 0.3)  # Random angle spread
		var direction = base_direction.rotated(spread)
		
		# Initialize projectile
		if projectile.has_method("initialize"):
			projectile.initialize(spawn_position, direction)
