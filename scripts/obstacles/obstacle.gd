# obstacle.gd
extends GameObject
class_name Obstacle

# Emitted once when the obstacle is destroyed (shot down or rammed by the
# player), so the spawner can return it to its pool.
signal destroyed

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
@export var cooldown_variation: float = 1.0  # Adds/subtracts up to this amount from cooldown
@export_range(0.0, 1.0) var accuracy: float = 0.8  # 1.0 = perfect, 0.0 = completely random
@export_range(0.0, 90.0) var max_aim_angle: float = 30.0  # Maximum angle in degrees from straight down
## Seconds after spawning before an individually shooting obstacle may take
## its first shot (it still has to be on screen, and pass the shoot_chance
## roll). Formation fire patterns use WaveGroup.first_fire_delay instead.
@export var first_shot_delay: float = 0.5

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
# Set by FormationManager when the wave group runs a fire pattern (VOLLEY /
# RIPPLE / NONE): the per-frame shooting dice are skipped and the formation
# calls shoot() itself. Reset to false on every spawn.
var fire_controlled: bool = false

# Shooting variables
var time_since_last_shot: float = 0.0
var rng = RandomNumberGenerator.new()
var gun_points = []

var shoot_audio_player: AudioStreamPlayer2D

# Configured values captured on the first spawn (after subclass _ready() and
# scene overrides have been applied) so pooled instances can be reset.
var base_health: float = -1.0
# Health multiplier for this spawn, set by the SpawnManager before
# initialize() (ZoneDefinition.enemy_health_multiplier; 1.0 for bosses)
var health_scale: float = 1.0
# Full health of the current spawn: base_health * health_scale
var max_health: float = -1.0
var _base_rotation: float = 0.0

# Optional rotation
@export var rotation_speed: float = 0.0  # Degrees per second

# Initial position tracking for patterns
var initial_x: float = 0.0

func _ready() -> void:
	super._ready()

	# Set default points based on damage if points aren't already set
	# Points for obstacles should be negative (player earns positive points when destroying them)
	if points == 0:  # Only set if not already configured in editor
		points = -int(damage)  # Convert damage to points with negative value
		# Ensure minimum point value of -1
		if points == 0:
			points = -1
	
	# Remember the scene-configured rotation (e.g. planes/aliens face down)
	_base_rotation = rotation

	# Initialize with randomized cooldown
	_reset_shoot_cooldown()

	# Shooting sound player (the explosion sound uses a one-shot player created
	# on demand, see _play_explosion_sound())
	shoot_audio_player = AudioStreamPlayer2D.new()
	shoot_audio_player.name = "ShootAudioPlayer"
	add_child(shoot_audio_player)
	if shoot_sound:
		shoot_audio_player.stream = shoot_sound

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

		_process_shooting(delta)

		# Formations only move downward; release members once they pass the
		# bottom of the screen (side edges are ignored because formation
		# patterns can swing members briefly past them)
		_check_formation_offscreen()
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

	_process_shooting(delta)

	# Apply rotation if set
	if rotation_speed != 0:
		rotation_degrees += rotation_speed * delta

	# Check if off-screen
	check_if_offscreen()

func _process_shooting(delta: float) -> void:
	if fire_controlled or not (can_shoot and projectile_scene):
		return

	time_since_last_shot += delta
	# Hold fire while off screen (e.g. still flying in from above); the timer
	# keeps running so the first shot comes as soon as it is visible
	if time_since_last_shot >= shoot_cooldown and is_on_screen():
		# Random chance to shoot
		if rng.randf() < shoot_chance:
			shoot()
			time_since_last_shot = 0.0
			# Randomize next cooldown
			shoot_cooldown = max(0.5, shoot_cooldown + rng.randf_range(-cooldown_variation, cooldown_variation))

func _reset_shoot_cooldown() -> void:
	shoot_cooldown = max(1.0, 2.0 + rng.randf_range(-cooldown_variation, cooldown_variation))

# Inside the visible screen horizontally and below its top edge
func is_on_screen() -> bool:
	var size := get_viewport_rect().size
	return global_position.y > 0.0 and global_position.x >= 0.0 and global_position.x <= size.x

func _check_formation_offscreen() -> void:
	if has_exited_screen:
		return
	if position.y > get_viewport_rect().size.y + 100.0:
		has_exited_screen = true
		emit_signal("screen_exited")

func set_use_formation_movement(value: bool) -> void:
	use_formation_movement = value

# Called on every spawn, including when reused from the spawn manager's pool.
# Note: the formation manager calls set_formation_data() and
# set_use_formation_movement(true) AFTER this, so resetting formation state
# here is safe.
func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	initial_x = spawn_position.x
	pattern_time = 0.0

	# Restore health (base captured lazily on first spawn so subclass _ready()
	# changes and scene overrides of the exported value are respected), scaled
	# by the zone's multiplier for this spawn
	if base_health < 0.0:
		base_health = health
	max_health = base_health * health_scale
	health = max_health

	# Reset shooting state. The per-instance RNG is re-seeded from the global
	# one so a seeded run (tests) replays identically; gameplay is unchanged.
	rng.seed = randi()
	_reset_shoot_cooldown()
	# First shot first_shot_delay after spawning (once on screen), then the
	# usual randomized cooldown
	time_since_last_shot = shoot_cooldown - first_shot_delay

	# Reset orientation, then let subclasses re-roll per-spawn variation
	rotation = _base_rotation
	_randomize_on_spawn()

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
	is_formation_member = false
	use_formation_movement = false
	fire_controlled = false
	formation_id = -1
	formation_offset = Vector2.ZERO
	formation_local_position = Vector2.ZERO

# Hook for per-spawn randomization (size, spin, ...). Called from initialize()
# after state has been reset; override in subclasses.
func _randomize_on_spawn() -> void:
	pass

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

func take_damage(damage: float) -> void:
	# Ignore hits after death (e.g. several projectiles in the same frame)
	if not is_active:
		return

	health -= damage

	if health <= 0:
		# Award the kill (x combo) before deactivating: the level marks this
		# spawn_count so its `destroyed` hook doesn't count the kill again
		_award_kill_points()

		# Create explosion effect
		create_explosion()

		# Deactivate the obstacle
		deactivate()
		emit_signal("destroyed")

# Kill points (obstacle points are negative; the player earns abs(points))
# through the level's combo multiplier. Call while still active, before
# emitting `destroyed`.
func _award_kill_points() -> void:
	var level = get_tree().get_first_node_in_group("level")
	if level == null:
		return
	if level.has_method("award_kill_points"):
		level.award_kill_points(abs(points), self)
	elif level.has_method("update_points"):
		level.update_points(abs(points))

func create_explosion() -> void:
	# Hide the sprite immediately
	if sprite:
		sprite.visible = false
	if animated_sprite:
		animated_sprite.visible = false

	_play_explosion_sound()

	var effects_parent = _get_effects_parent()

	# Get a (pooled) explosion if we have a scene
	if explosion_scene:
		var explosion = ObjectPool.acquire(explosion_scene, effects_parent)
		explosion.global_position = global_position

		# Set explosion type and start it
		explosion.set_explosion_type(1)  # Medium explosion
		explosion.start()
	else:
		# Fallback if no explosion scene - create a simple particle effect
		var particles = CPUParticles2D.new()
		effects_parent.add_child(particles)
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

# Plays the explosion sound on a one-shot player owned by the current scene,
# so it keeps playing after this obstacle is deactivated or reused
func _play_explosion_sound() -> void:
	if not explosion_sound:
		return

	var audio_player = AudioStreamPlayer2D.new()
	audio_player.stream = explosion_sound
	# Add pitch variation for more natural sound
	audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
	audio_player.finished.connect(audio_player.queue_free)
	_get_effects_parent().add_child(audio_player)
	audio_player.global_position = global_position
	audio_player.play()

# Projectiles, explosions and sounds live under the current scene
func _get_effects_parent() -> Node:
	var scene = get_tree().current_scene
	return scene if scene else get_parent()

func handle_player_collision() -> void:
	# Already destroyed (e.g. shot down in the same frame as the collision)
	if is_being_collected or not is_active:
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
	emit_signal("destroyed")

# Fire one volley now (public: formation fire patterns call it directly)
func shoot() -> void:
	if not projectile_scene or not is_active:
		return

	for gun_point in _select_gun_points():
		_fire_from(gun_point)

	# Randomize next cooldown
	shoot_cooldown = max(0.5, 2.0 + rng.randf_range(-cooldown_variation, cooldown_variation))

# Which gun points fire this volley. Base: one random gun point.
func _select_gun_points() -> Array:
	return [gun_points[rng.randi() % gun_points.size()]]

# Direction for a shot fired from from_position, before accuracy jitter.
# Base: aim at the player, clamped to max_aim_angle from straight down.
func _aim_direction(from_position: Vector2) -> Vector2:
	# Default direction is straight down
	var direction = Vector2.DOWN

	var player = get_tree().get_first_node_in_group("player")
	if player:
		# Calculate direction to player
		var player_direction = (player.global_position - from_position).normalized()

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

	return direction

# Random deviation based on accuracy (1.0 = perfect)
func _apply_accuracy(direction: Vector2) -> Vector2:
	if accuracy < 1.0:
		var max_deviation = (1.0 - accuracy) * PI * 0.5  # Scale to reasonable range
		var deviation = rng.randf_range(-max_deviation, max_deviation)
		direction = direction.rotated(deviation)
	return direction

# Spawn one (pooled) projectile from gun_point, aimed via _aim_direction()
# with accuracy jitter, and play the shoot sound
func _fire_from(gun_point: Node2D) -> void:
	_fire_from_direction(gun_point, _apply_accuracy(_aim_direction(gun_point.global_position)))

# Spawn one (pooled) projectile from gun_point travelling in an explicit
# direction (no aiming or jitter applied) and play the shoot sound
func _fire_from_direction(gun_point: Node2D, direction: Vector2) -> void:
	if not projectile_scene:
		return
	var projectile = ObjectPool.acquire(projectile_scene, _get_effects_parent())

	if projectile.has_method("initialize"):
		projectile.initialize(gun_point.global_position, direction)

	# Play shoot sound if available
	if shoot_audio_player and shoot_audio_player.stream:
		# Add pitch variation for more natural sound
		shoot_audio_player.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		shoot_audio_player.play()
