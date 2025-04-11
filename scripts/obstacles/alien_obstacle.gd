# plane_obstacle.gd
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
		
		# Default direction is straight down
		var direction = Vector2.DOWN
		
		if spread_pattern:
			# Aliens fire in a spread pattern
			var spread = rng.randf_range(-0.3, 0.3)
			direction = direction.rotated(spread)
		else:
			# Find the player
			var player = get_tree().get_first_node_in_group("player")
			if player:
				# Calculate direction to player
				var player_direction = (player.global_position - spawn_position).normalized()
				
				# Limit the angle to max_aim_angle from straight down
				var down_angle = Vector2.DOWN.angle()
				var player_angle = player_direction.angle()
				var angle_diff = rad_to_deg(absf(wrapf(player_angle - down_angle, -PI, PI)))
				
				if angle_diff <= max_aim_angle:
					# Player is within aiming cone, use player direction
					direction = player_direction
				else:
					# Player is outside aiming cone, use clamped direction
					var sign_diff = sign(wrapf(player_angle - down_angle, -PI, PI))
					var clamped_angle = down_angle + sign_diff * deg_to_rad(max_aim_angle)
					direction = Vector2.from_angle(clamped_angle)
		
		# Apply accuracy variation
		if accuracy < 1.0:
			var max_deviation = (1.0 - accuracy) * PI * 0.5  # Scale to reasonable range
			var deviation = rng.randf_range(-max_deviation, max_deviation)
			direction = direction.rotated(deviation)
		
		# Initialize projectile
		if projectile.has_method("initialize"):
			projectile.initialize(spawn_position, direction)
			
		if shoot_audio_player and shoot_audio_player.stream:
			shoot_audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
			shoot_audio_player.play()
	
	# Randomize next cooldown
	shoot_cooldown = max(0.5, 2.0 + rng.randf_range(-cooldown_variation, cooldown_variation))

# Return to idle animation after attack finishes
func _on_attack_animation_finished() -> void:
	var animated_sprite = $AnimatedSprite2D
	if animated_sprite and animated_sprite.animation == "attack":
		animated_sprite.play("idle")
