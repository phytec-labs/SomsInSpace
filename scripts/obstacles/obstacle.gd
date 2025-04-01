# obstacle.gd
extends GameObject
class_name Obstacle

# Base obstacle properties
@export var damage: float = 10.0
@export var base_speed: float = 100.0
@export var health: float = 10.0  # Default health value
@export var explosion_scene: PackedScene = preload("res://scenes/effects/obstacle_explosion.tscn")
# Shooting properties
@export var can_shoot: bool = false
@export var projectile_scene: PackedScene= preload("res://scenes/effects/enemy_projectile_1.tscn")
@export var shoot_cooldown: float = 2.0  # Time between shots
@export var projectile_speed: float = 200.0
@export var shoot_chance: float = 0.01  # Chance to shoot per frame
# Audio properties
@export var shoot_sound: AudioStream = preload("res://audio/retro-laser-1.mp3")
@export var explosion_sound: AudioStream = preload("res://audio/small-explosion-1.mp3")
@export var sound_pitch_variation: float = 0.2

# Movement pattern variables
var movement_pattern: String = "linear"  # linear, sine, zigzag
var pattern_amplitude: float = 50.0   # How far it moves side to side
var pattern_frequency: float = 1.0    # How fast it moves side to side
var pattern_time: float = 0.0        # Time tracker for movement patterns

# Formation variables
var is_formation_member: bool = false  # Is part of a formation?
var formation_id: int = -1            # Unique ID for the formation
var formation_offset: Vector2 = Vector2.ZERO  # Offset from formation center
var formation_local_position: Vector2 = Vector2.ZERO  # Local position in formation

var viewport_center_x: float = 0.0
var move_toward_center: bool = false
var center_pull_strength: float = 0.5  # How strongly to pull toward the center (0.5 = gentle, 2.0 = aggressive)

var use_formation_movement: bool = false  # Flag to indicate if object uses formation-based movement

# Shooting variables
var time_since_last_shot: float = 0.0
var rng = RandomNumberGenerator.new()
var gun_points = []

var shoot_audio_player: AudioStreamPlayer2D
var explosion_audio_player: AudioStreamPlayer2D

# Optional rotation
@export var rotation_speed: float = 0.0  # Degrees per second

# Initial position tracking for patterns
var initial_x: float = 0.0

func _ready() -> void:
	super._ready()

	# Initialize audio players
	# Shooting sound player
	shoot_audio_player = AudioStreamPlayer2D.new()
	shoot_audio_player.name = "ShootAudioPlayer"
	add_child(shoot_audio_player)
	if shoot_sound:
		shoot_audio_player.stream = shoot_sound

	# Explosion sound player
	explosion_audio_player = AudioStreamPlayer2D.new()
	explosion_audio_player.name = "ExplosionAudioPlayer"
	add_child(explosion_audio_player)
	if explosion_sound:
		explosion_audio_player.stream = explosion_sound

	# Find all gun point nodes
	for child in get_children():
		if child is Node2D and "GunPoint" in child.name:
			gun_points.append(child)

	# If no gun points found, use the obstacle's position as default
	if gun_points.is_empty():
		# Create a virtual gun point at the center
		var default_point = Node2D.new()
		default_point.name = "DefaultGunPoint"
		default_point.position = Vector2.ZERO
		add_child(default_point)
		gun_points.append(default_point)

func _process(delta: float) -> void:
	if not is_active:
		return

	# If this obstacle is part of a formation and uses formation movement,
	# don't process individual movement - the formation manager will position it
	if is_formation_member and use_formation_movement:
		# Still update rotation if set
		if rotation_speed != 0:
			rotation_degrees += rotation_speed * delta
			
		 # Handle shooting if enabled
		if can_shoot and projectile_scene:
			time_since_last_shot += delta
			if time_since_last_shot >= shoot_cooldown:
				# Random chance to shoot
				if rng.randf() < shoot_chance:
					shoot()
					time_since_last_shot = 0.0

		return

	# Rest of the original movement code for non-formation objects
	pattern_time += delta

	# Calculate movement based on pattern
	var velocity = Vector2.ZERO

	# Base vertical movement (always move down)
	velocity.y = base_speed * speed_multiplier

	# Add horizontal movement based on pattern for non-formation members
	match movement_pattern:
		"linear":
			# If coming from the sides, add horizontal movement toward center
			if move_toward_center:
				var direction_to_center = sign(viewport_center_x - position.x)
				velocity.x = base_speed * speed_multiplier * center_pull_strength * direction_to_center

		"sine":
			# Calculate sine offset
			var sin_offset = sin(pattern_time * pattern_frequency) * pattern_amplitude
			# Calculate horizontal velocity from sine
			var sine_velocity = cos(pattern_time * pattern_frequency) * pattern_amplitude * pattern_frequency

			# For side-spawned objects, add center-pulling to velocity
			if move_toward_center:
				var direction_to_center = sign(viewport_center_x - position.x)
				velocity.x = sine_velocity + (base_speed * speed_multiplier * center_pull_strength * 0.5 * direction_to_center)
				# Apply the sine offset to position
				position.x = position.x + (sine_velocity * delta)
			else:
				# For normal sine wave movement, apply traditional formula
				velocity.x = sine_velocity
				position.x = initial_x + sin_offset

		"zigzag":
			# Sharp zigzag movement
			var zigzag = sign(sin(pattern_time * pattern_frequency * PI))
			velocity.x = zigzag * pattern_amplitude * pattern_frequency

			# Add center-pulling component if side-spawned
			if move_toward_center:
				var direction_to_center = sign(viewport_center_x - position.x)
				velocity.x += base_speed * speed_multiplier * center_pull_strength * 0.3 * direction_to_center

	# Apply vertical movement
	position.y += velocity.y * delta

	# Apply horizontal movement if using linear, zigzag or side-spawned
	if movement_pattern == "linear" or movement_pattern == "zigzag" or move_toward_center:
		# Don't apply velocity for sine unless side-spawned
		if movement_pattern != "sine" or move_toward_center:
			position.x += velocity.x * delta

	 # Handle shooting if enabled
	if can_shoot and projectile_scene:
		time_since_last_shot += delta
		if time_since_last_shot >= shoot_cooldown:
			# Random chance to shoot
			if rng.randf() < shoot_chance:
				shoot()
				time_since_last_shot = 0.0

	# Apply rotation if set
	if rotation_speed != 0:
		rotation_degrees += rotation_speed * delta

	# Check if off-screen
	check_if_offscreen()

func set_use_formation_movement(value: bool) -> void:
	use_formation_movement = value

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	initial_x = spawn_position.x
	pattern_time = 0.0

	# Get viewport center
	viewport_center_x = get_viewport_rect().size.x / 2.0

	# Determine if this is a side spawn and set inward movement flag
	var screen_edge_margin = 50.0
	if spawn_position.x < -screen_edge_margin:  # Left side spawn
		move_toward_center = true
	elif spawn_position.x > get_viewport_rect().size.x + screen_edge_margin:  # Right side spawn
		move_toward_center = true
	else:
		move_toward_center = false

	# Reset formation variables
	if not is_formation_member:
		formation_id = -1
		formation_offset = Vector2.ZERO

func set_movement_pattern(pattern: String) -> void:
	movement_pattern = pattern

func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = multiplier

func set_formation_member(is_member: bool) -> void:
	is_formation_member = is_member

# Set this obstacle as part of a formation
func set_formation_data(form_id: int, form_offset: Vector2) -> void:
	formation_id = form_id
	formation_offset = form_offset
	is_formation_member = true
	# Store local offset for patterns that might later be applied to the formation as a whole
	formation_local_position = formation_offset

func check_if_offscreen() -> void:
	var viewport_rect = get_viewport_rect()
	var margin = 100.0  # Margin beyond screen edges

	if (position.y > viewport_rect.size.y + margin or
		position.y < -margin * 2 or
		position.x > viewport_rect.size.x + margin or
		position.x < -margin):
		emit_signal("screen_exited")

func take_damage(damage: float) -> void:
	health -= damage

	if health <= 0:
		# Award points to the player before destroying
		var level = get_tree().get_first_node_in_group("level")
		if level and level.has_method("update_points"):
			# Convert negative points to positive for destroying
			var destroy_points = abs(points)
			level.update_points(destroy_points)

		# Create explosion effect
		create_explosion()

		# Deactivate the obstacle
		deactivate()

func create_explosion() -> void:
	# Hide the sprite immediately
	if sprite:
		sprite.visible = false
	if animated_sprite:
		animated_sprite.visible = false

	# Play explosion sound if available
	if explosion_audio_player and explosion_audio_player.stream:
		# Detach the audio player so it continues playing after the obstacle is gone
		remove_child(explosion_audio_player)
		get_parent().add_child(explosion_audio_player)

		# Position at the obstacle's last position
		explosion_audio_player.global_position = global_position

		# Add pitch variation for more natural sound
		explosion_audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		explosion_audio_player.play()

		# Set up auto-deletion after playing
		explosion_audio_player.finished.connect(explosion_audio_player.queue_free)

	# Instantiate explosion if we have a scene
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		# Add to the parent so it persists after obstacle is gone
		get_parent().add_child(explosion)
		explosion.global_position = global_position

		# Set explosion type and start it
		explosion.set_explosion_type(1)  # Medium explosion
		explosion.start()
	else:
		# Fallback if no explosion scene - create a simple particle effect
		var particles = CPUParticles2D.new()
		get_parent().add_child(particles)
		particles.global_position = global_position
		particles.amount = 20
		particles.lifetime = 0.5
		particles.explosiveness = 0.9
		particles.direction = Vector2(0, 0)
		particles.spread = 180
		particles.gravity = Vector2(0, 98)
		particles.initial_velocity_min = 50
		particles.initial_velocity_max = 100
		particles.scale_amount_min = 2
		particles.scale_amount_max = 4
		particles.emitting = true

		# Auto-free particles after emission
		var timer = Timer.new()
		particles.add_child(timer)
		timer.wait_time = 1.0
		timer.one_shot = true
		timer.timeout.connect(func(): particles.queue_free())
		timer.start()

func handle_player_collision() -> void:
	if is_being_collected:
		return

	is_being_collected = true

	# Create explosion before hiding the sprite
	create_explosion()

	# No need to manually hide sprite or disable collisions
	# since create_explosion() already does that

	# Emit signal for damage to player
	emit_signal("object_hit")

	# Finally deactivate the object
	deactivate()

func shoot() -> void:
	if not projectile_scene or not is_active:
		return

	# Choose which gun point to use (if there are multiple)
	var gun_point = gun_points[rng.randi() % gun_points.size()]

	# Create projectile
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	# Calculate global spawn position
	var spawn_position = gun_point.global_position

	# Find the player
	var player = get_tree().get_first_node_in_group("player")
	var direction = Vector2.DOWN  # Default direction if player not found

	if player:
		direction = (player.global_position - spawn_position).normalized()

	# Initialize the projectile
	if projectile.has_method("initialize"):
		projectile.initialize(spawn_position, direction)

	# Play shoot sound if available
	if shoot_audio_player and shoot_audio_player.stream:
		# Add pitch variation for more natural sound
		shoot_audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		shoot_audio_player.play()
