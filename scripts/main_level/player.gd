# player.gd
extends CharacterBody2D

# Export variables
@export var speed: float = 300.0
@export var touch_offset: float = 100.0
@export var stopping_distance: float = 10
@export var smoothing_speed: float = 5.0
@export var blink_duration: float = 2.0  # Duration of invulnerability
@export var blink_frequency: float = 0.1  # How fast to toggle visibility
@export var projectile_scene: PackedScene
@export var fire_cooldown: float = 0.2  # Time between shots
@export var projectile_offset: float = -30.0  # Offset from player position (negative = in front)

# Node references
@onready var ship_sprite: Sprite2D = $Ship
@onready var som_sprite: Sprite2D = $SoM
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var area: Area2D = $CollisionArea
@onready var main_thruster: CPUParticles2D = $MainThruster
@onready var left_thruster: CPUParticles2D = $LeftThruster
@onready var right_thruster: CPUParticles2D = $RightThruster
@onready var up_thruster: CPUParticles2D = $UpThruster
@onready var down_thruster: CPUParticles2D = $DownThruster

# State variables
var can_move: bool = false
var initial_position: Vector2
var target_position: Vector2
var is_touch_active: bool = false
var last_input_time: float = 0.0
var input_throttle: float = 1.0/60.0
var previous_velocity: Vector2 = Vector2.ZERO
var can_fire: bool = true
var cooldown_timer: Timer
var is_dead: bool = false

# Damage blink variables
var is_blinking: bool = false
var blink_timer: float = 0.0
var blink_toggle_timer: float = 0.0
var is_sprite_visible: bool = true

func _ready() -> void:
	initial_position = position
	target_position = position

	assert(collision_polygon != null, "CollisionPolygon2D node not found")
	assert(area != null, "CollisionArea node not found")

	area.collision_layer = 1
	area.collision_mask = 2

	# Set up cooldown timer for firing
	cooldown_timer = Timer.new()
	cooldown_timer.one_shot = true
	cooldown_timer.wait_time = fire_cooldown
	cooldown_timer.timeout.connect(_on_fire_cooldown_timeout)
	add_child(cooldown_timer)

	disable_movement()

func _process(delta: float) -> void:
	if is_blinking:
		process_blink(delta)

func process_blink(delta: float) -> void:
	blink_timer += delta
	blink_toggle_timer += delta

	# Toggle visibility based on frequency
	if blink_toggle_timer >= blink_frequency:
		blink_toggle_timer = 0.0
		is_sprite_visible = !is_sprite_visible
		update_sprite_visibility(is_sprite_visible)

	# End blinking after duration
	if blink_timer >= blink_duration:
		end_blink()

func start_blink() -> void:
	is_blinking = true
	blink_timer = 0.0
	blink_toggle_timer = 0.0
	area.collision_mask = 0  # Disable collisions with obstacles

func end_blink() -> void:
	is_blinking = false
	area.collision_mask = 2  # Re-enable collisions with obstacles
	update_sprite_visibility(true)  # Ensure sprite is visible

func update_sprite_visibility(visible: bool) -> void:
	# If player is dead, sprites should remain hidden
	if is_dead:
		if ship_sprite:
			ship_sprite.visible = false
		if som_sprite:
			som_sprite.visible = false
		return
	
	# Normal visibility toggling for blinking when not dead
	if ship_sprite:
		ship_sprite.visible = visible
	if som_sprite:
		som_sprite.visible = visible

func _input(event: InputEvent) -> void:
	if not can_move:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_input_time < input_throttle:
		return

	# Handle firing inputs
	if event is InputEventScreenTouch:
		# If this is a second finger touch, fire
		if event.pressed and event.index > 0:
			fire_projectile()
		# Regular movement for primary touch
		else:
			is_touch_active = event.pressed
			if is_touch_active:
				update_target_position(event.position)
				last_input_time = current_time
	elif event is InputEventScreenDrag and is_touch_active:
		update_target_position(event.position)
		last_input_time = current_time
	elif event is InputEventMouseButton:
		# Right-click to fire
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			fire_projectile()
		# Left-click for movement
		elif event.button_index == MOUSE_BUTTON_LEFT:
			is_touch_active = event.pressed
			if is_touch_active:
				update_target_position(event.position)
				last_input_time = current_time
	elif event is InputEventMouseMotion and is_touch_active:
		update_target_position(event.position)
		last_input_time = current_time
	# Space key to fire
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		fire_projectile()

func update_target_position(input_position: Vector2) -> void:
	target_position = input_position
	target_position.y -= touch_offset

func _physics_process(delta: float) -> void:
	if not can_move:
		return

	var movement: Vector2 = Vector2.ZERO

	if is_touch_active:
		var distance = position.distance_to(target_position)
		if distance > stopping_distance:
			var direction = (target_position - position).normalized()
			movement = direction * speed
			velocity = velocity.lerp(movement, smoothing_speed * delta)
		else:
			velocity = velocity.lerp(Vector2.ZERO, smoothing_speed * delta)
	else:
		movement.x = Input.get_axis("ui_left", "ui_right")
		movement.y = Input.get_axis("ui_up", "ui_down")

		if movement.length() > 1.0:
			movement = movement.normalized()

		velocity = movement * speed

	# Update thrusters based on movement
	update_thrusters(velocity)

	move_and_slide()
	constrain_to_viewport()

	previous_velocity = velocity

func update_thrusters(current_velocity: Vector2) -> void:
	# Main thruster is always on when moving
	main_thruster.emitting = can_move

	# Update directional thrusters based on current velocity
	var threshold = 10.0  # Minimum velocity to trigger thrusters

	# Update individual thrusters
	left_thruster.emitting = current_velocity.x > threshold  # Moving right, fire left thruster
	right_thruster.emitting = current_velocity.x < -threshold  # Moving left, fire right thruster
	up_thruster.emitting = current_velocity.y > threshold  # Moving down, fire up thruster
	down_thruster.emitting = current_velocity.y < -threshold  # Moving up, fire down thruster

func constrain_to_viewport() -> void:
	var viewport_rect: Rect2 = get_viewport_rect()
	position.x = clamp(position.x, 0, viewport_rect.size.x)
	position.y = clamp(position.y, 0, viewport_rect.size.y)

func enable_movement() -> void:
	can_move = true
	is_touch_active = false
	target_position = position
	main_thruster.emitting = true

func disable_movement() -> void:
	can_move = false
	is_touch_active = false
	velocity = Vector2.ZERO

	# Stop all particle emitters
	main_thruster.emitting = false
	left_thruster.emitting = false
	right_thruster.emitting = false
	up_thruster.emitting = false
	down_thruster.emitting = false

func reset_position() -> void:
	position = initial_position
	target_position = initial_position
	velocity = Vector2.ZERO
	is_touch_active = false
	is_dead = false  # Reset the dead flag
	end_blink()  # Ensure blink effect is reset

func fire_projectile() -> void:
	if not can_fire or not can_move:
		print("Cannot fire: can_fire=", can_fire, ", can_move=", can_move)
		return

	if not projectile_scene:
		print("No projectile scene assigned to player!")
		return

	# Create projectile instance
	var projectile = projectile_scene.instantiate()
	get_parent().add_child(projectile)

	# Set projectile position (in front of the ship)
	var spawn_position = position + Vector2(0, projectile_offset)
	projectile.initialize(spawn_position, Vector2.UP)
	print("Fired projectile at position: ", spawn_position)

	# Start cooldown
	can_fire = false
	cooldown_timer.start()

func _on_fire_cooldown_timeout() -> void:
	can_fire = true

func die() -> void:
	# Set the dead flag to prevent blinking from showing the sprite
	is_dead = true
	
	# Hide all parts of the ship
	if ship_sprite:
		ship_sprite.visible = false
	if som_sprite:
		som_sprite.visible = false
	
	# Disable all thrusters
	main_thruster.emitting = false
	left_thruster.emitting = false
	right_thruster.emitting = false
	up_thruster.emitting = false
	down_thruster.emitting = false
	
	# Disable collisions
	area.collision_mask = 0
	
	# Stop movement
	can_move = false
	velocity = Vector2.ZERO
