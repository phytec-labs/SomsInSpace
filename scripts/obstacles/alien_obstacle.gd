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

# Override shoot function to play attack animation
func shoot() -> void:
	if not projectile_scene or not is_active:
		return
	
	# Play attack animation if we have an AnimatedSprite2D
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and animated_sprite.sprite_frames.has_animation("attack"):
		animated_sprite.play("attack")
		
		# Connect to animation finished signal if not already connected
		if not animated_sprite.is_connected("animation_finished", _on_attack_animation_finished):
			animated_sprite.animation_finished.connect(_on_attack_animation_finished)
	
	# Continue with normal shooting logic
	for gun_point in gun_points:
		var projectile = projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		
		var spawn_position = gun_point.global_position
		
		# Aliens fire in a spread pattern
		var base_direction = Vector2.DOWN
		var spread = rng.randf_range(-0.3, 0.3)
		var direction = base_direction.rotated(spread)
		
		# Initialize projectile
		if projectile.has_method("initialize"):
			projectile.initialize(spawn_position, direction)
			
		if shoot_audio_player and shoot_audio_player.stream:
			shoot_audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
			shoot_audio_player.play()

# Return to idle animation after attack finishes
func _on_attack_animation_finished() -> void:
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and animated_sprite.animation == "attack":
		animated_sprite.play("idle")
