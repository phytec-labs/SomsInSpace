# jet_obstacle.gd
extends Obstacle
class_name JetObstacle

@export var thruster_particle_color: Color = Color(0.7, 0.7, 1.0)
@export var thruster_size: float = 0.8
@onready var thruster_particles: CPUParticles2D = $ThrusterParticles if has_node("ThrusterParticles") else null

func _ready() -> void:
	super._ready()
	# Jets are fast with moderate damage
	damage = 20.0
	base_speed = 150.0
	movement_pattern = "sine"
	pattern_amplitude = 80.0
	pattern_frequency = 0.8

	# Load the projectile scene if it's not already set
	if not projectile_scene:
		projectile_scene = load("res://scenes/effects/enemy_projectile_1.tscn")
		
	# Setup thruster particles if they exist
	if thruster_particles:
		thruster_particles.emitting = true
		# Set custom color
		if thruster_particles.has_method("set_color"):
			thruster_particles.set_color(thruster_particle_color)

	#print("JetObstacle after setup: can_shoot=" + str(can_shoot) + 
	#	  ", cooldown=" + str(shoot_cooldown) + 
	#	  ", chance=" + str(shoot_chance))
# Override initialize to set up jet-specific behavior
func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	
	# Jets should face downward and move in their facing direction
	rotation_degrees = 180.0
	
	# Start thruster particles
	if thruster_particles:
		thruster_particles.emitting = true

# Override handle_player_collision for jet-specific effects
func handle_player_collision() -> void:
	super.handle_player_collision()
	
	# Could add explosion effect specific to jets here
	if thruster_particles:
		thruster_particles.emitting = false

# Override shoot function for more specialized behavior
func shoot() -> void:
	if not projectile_scene or not is_active:
		return
	
	# Decide how many gun points to use (1-2 randomly)
	var num_guns = rng.randi_range(1, min(2, gun_points.size()))
	
	# Randomly select which gun points to use
	var selected_guns = []
	var available_guns = gun_points.duplicate()
	for i in range(num_guns):
		if available_guns.is_empty():
			break
			
		var index = rng.randi() % available_guns.size()
		selected_guns.append(available_guns[index])
		available_guns.remove_at(index)
	
	# Create projectiles from selected gun points
	for gun_point in selected_guns:
		var projectile = projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		
		var spawn_position = gun_point.global_position
		
		# Default direction is straight down
		var direction = Vector2.DOWN
		
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
