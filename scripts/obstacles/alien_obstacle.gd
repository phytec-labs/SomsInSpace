# alien_obstacle.gd
extends Obstacle
class_name AlienObstacle
@export var spread_pattern: bool = true  # Should aliens fire in a spread pattern?

func _ready() -> void:
	super._ready()
	# Planes are slower but wider
	damage = 15.0
	base_speed = 80.0
	movement_pattern = "linear"
	rotation_speed = 0.0

# Override shoot function to play attack animation
func shoot() -> void:
	if not projectile_scene or not is_active:
		return

	_play_attack_animation()
	super.shoot()

func _play_attack_animation() -> void:
	if not animated_sprite:
		return

	# Play attack animation if available
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")

	# Connect to animation finished signal if not already connected
	if not animated_sprite.animation_finished.is_connected(_on_attack_animation_finished):
		animated_sprite.animation_finished.connect(_on_attack_animation_finished)

# Aliens fire from every gun point at once
func _select_gun_points() -> Array:
	return gun_points

# Aliens fire in a random spread instead of aiming, if spread_pattern is set
func _aim_direction(from_position: Vector2) -> Vector2:
	if spread_pattern:
		var spread = rng.randf_range(-0.3, 0.3)
		return Vector2.DOWN.rotated(spread)
	return super._aim_direction(from_position)

# Return to idle animation after attack finishes
func _on_attack_animation_finished() -> void:
	if animated_sprite and animated_sprite.animation == "attack":
		animated_sprite.play("idle")
