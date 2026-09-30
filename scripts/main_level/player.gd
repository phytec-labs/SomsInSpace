# player.gd
extends CharacterBody2D

# Preloaded (not referenced by class_name) so this works even before the
# editor has rebuilt the global class cache.
const ShipDefinitionScript := preload("res://scripts/data/ship_definition.gd")

# Export variables
@export var speed: float = 300.0
@export var touch_offset: float = 100.0
@export var stopping_distance: float = 10
@export var smoothing_speed: float = 5.0
@export var blink_duration: float = 2.0  # Duration of invulnerability
@export var blink_frequency: float = 0.1  # How fast to toggle visibility

# Node references
@onready var ship_sprite: Sprite2D = $Ship
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var area: Area2D = $CollisionArea
@onready var main_thruster: CPUParticles2D = $MainThruster
@onready var main_thruster2: CPUParticles2D = $MainThruster2
@onready var left_thruster: CPUParticles2D = $LeftThruster
@onready var right_thruster: CPUParticles2D = $RightThruster
@onready var up_thruster: CPUParticles2D = $UpThruster
@onready var down_thruster: CPUParticles2D = $DownThruster
@onready var fire_audio_player: AudioStreamPlayer2D = $ProjectileAudioPlayer

# State variables
var can_move: bool = false
var initial_position: Vector2
var target_position: Vector2
var is_touch_active: bool = false
var last_input_time: float = 0.0
var input_throttle: float = 1.0/60.0
var previous_velocity: Vector2 = Vector2.ZERO
var can_fire: bool = true
var cooldown_time_remaining: float = 0.0
var is_dead: bool = false
var is_firing: bool = false  # New variable to track if fire button is held down

# Damage blink variables
var is_blinking: bool = false
var blink_timer: float = 0.0
var blink_toggle_timer: float = 0.0
var is_sprite_visible: bool = true

# Weapon tiers:
#   1 = center gun
#   2 = center + left + right (straight)
#   3 = tier 2 + two angled shots (±spread_angle_degrees) from the side guns
signal weapon_tier_changed(tier: int)
var weapon_tier: int = 1
@export var max_weapon_tier: int = 3
@export var fire_cooldown: float = 0.2  # Time between shots (current tier; see tier_fire_cooldowns)
## Fire cooldown per weapon tier (index = tier - 1).
@export var tier_fire_cooldowns: Array[float] = [0.2, 0.2, 0.15]
## Angle (degrees from straight up) of the tier-3 angled side shots.
@export var spread_angle_degrees: float = 18.0
@export var fire_sound: AudioStream  # Export variable for the firing sound
@export var projectile_scene: PackedScene
## Side guns (tier 2+); falls back to projectile_scene.
@export var upgraded_projectile_scene: PackedScene
## Angled tier-3 shots; falls back to projectile_scene.
@export var spread_projectile_scene: PackedScene

# Selected ship (see apply_ship)
var ship_definition: ShipDefinitionScript = null
## Multiplies the damage of every projectile this ship fires.
var damage_scale: float = 1.0
# tier_fire_cooldowns as authored, before the ship's fire_cooldown_scale
var _base_tier_fire_cooldowns: Array[float] = []

# External velocity (e.g. an enemy tractor beam) for the current physics
# frame; see add_external_velocity()
var _external_velocity: Vector2 = Vector2.ZERO

const UPGRADE_FLASH_COLOR := Color(1, 0.5, 1)  # Pink (tier 2)
const MAX_TIER_FLASH_COLOR := Color(0.4, 1, 1)  # Cyan (tier 3)

# Gunpoint references
@onready var center_gunpoint = $Gunpoints/CenterGunpoint
@onready var left_gunpoint = $Gunpoints/LeftGunpoint
@onready var right_gunpoint = $Gunpoints/RightGunpoint

func _ready() -> void:
	initial_position = position
	target_position = position

	assert(collision_polygon != null, "CollisionPolygon2D node not found")
	assert(area != null, "CollisionArea node not found")

	# Make sure fire_audio_player has the sound assigned if available
	if fire_audio_player and fire_sound:
		fire_audio_player.stream = fire_sound

	# Initialize shooting as ready
	can_fire = true
	cooldown_time_remaining = 0.0

	add_to_group("player")

	if _base_tier_fire_cooldowns.is_empty():
		_base_tier_fire_cooldowns = tier_fire_cooldowns.duplicate()

	set_weapon_tier(weapon_tier, false)

	disable_movement()

# Applies a ShipDefinition: sprite texture/tint, speed, fire cooldowns and
# projectile damage. Idempotent (cooldowns are scaled from the authored
# values, not the current ones). Health is applied by main_level.gd.
func apply_ship(def: ShipDefinitionScript) -> void:
	if def == null:
		return
	ship_definition = def
	if def.texture and ship_sprite:
		ship_sprite.texture = def.texture
	if ship_sprite:
		ship_sprite.modulate = def.tint
	speed = def.speed
	damage_scale = def.damage_scale

	if _base_tier_fire_cooldowns.is_empty():
		_base_tier_fire_cooldowns = tier_fire_cooldowns.duplicate()
	var scaled: Array[float] = []
	for cooldown in _base_tier_fire_cooldowns:
		scaled.append(cooldown * def.fire_cooldown_scale)
	tier_fire_cooldowns = scaled
	# Refresh fire_cooldown for the current tier (no flash / signal)
	set_weapon_tier(weapon_tier, false)

# Contract for enemies (e.g. a tractor beam): adds `v` (px/s) on top of the
# input movement for the player's next physics step only (calls in the same
# frame accumulate; the sum is cleared after each step). Call it every
# physics frame the pull should last. Dropped while the ship can't move
# (countdown, dead, victory); nothing runs while the tree is paused.
func add_external_velocity(v: Vector2) -> void:
	_external_velocity += v

func is_alive() -> bool:
	return not is_dead

func _process(delta: float) -> void:
	if is_blinking:
		process_blink(delta)

	# Handle shooting cooldown
	if not can_fire:
		cooldown_time_remaining -= delta
		if cooldown_time_remaining <= 0:
			can_fire = true
			cooldown_time_remaining = 0.0
			
	# Check if we should fire while button is held down
	if is_firing and can_fire and can_move and not is_dead:
		fire_projectile()

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
		return

	# Normal visibility toggling for blinking when not dead
	if ship_sprite:
		ship_sprite.visible = visible

# Clears latched touch/fire state (e.g. on resume from pause, where the
# matching release events were delivered while the player was paused) so the
# ship never keeps firing or chasing an old touch point. Main thrusters are
# left as they are; directional thrusters stop until the ship moves again.
func reset_input_state() -> void:
	is_firing = false
	is_touch_active = false
	target_position = position
	_external_velocity = Vector2.ZERO
	left_thruster.emitting = false
	right_thruster.emitting = false
	up_thruster.emitting = false
	down_thruster.emitting = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED and is_node_ready():
		reset_input_state()

# Gameplay input. Uses _unhandled_input so taps consumed by the GUI (HUD pause
# button, pause menu, game over screen) never move the ship or fire.
func _unhandled_input(event: InputEvent) -> void:
	if not can_move:
		return

	# Handle firing inputs - track both press and release events
	if _is_fire_press_input(event):
		is_firing = true
		fire_projectile()  # Fire immediately when button is first pressed
		return
	elif _is_fire_release_input(event):
		is_firing = false
		return

	# Handle movement inputs with throttling
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_input_time < input_throttle:
		return

	if _is_movement_start_input(event):
		is_touch_active = true
		update_target_position(event.position)
		last_input_time = current_time
	elif _is_movement_update_input(event) and is_touch_active:
		update_target_position(event.position)
		last_input_time = current_time
	elif _is_movement_end_input(event):
		is_touch_active = false

# Helper function for firing inputs - PRESS
func _is_fire_press_input(event: InputEvent) -> bool:
	return (event is InputEventScreenTouch and event.pressed and event.index > 0) or \
		   (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or \
		   (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE)

# Helper function for firing inputs - RELEASE
func _is_fire_release_input(event: InputEvent) -> bool:
	return (event is InputEventScreenTouch and not event.pressed and event.index > 0) or \
		   (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or \
		   (event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE)

# Helper function for movement start
func _is_movement_start_input(event: InputEvent) -> bool:
	return (event is InputEventScreenTouch and event.index == 0 and event.pressed) or \
		   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)


# Helper function for movement updates (drags/motion)
func _is_movement_update_input(event: InputEvent) -> bool:
	return (event is InputEventScreenDrag) or \
		   (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

# Helper function for movement end
func _is_movement_end_input(event: InputEvent) -> bool:
	return (event is InputEventScreenTouch and event.index == 0 and not event.pressed) or \
		   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)

func update_target_position(input_position: Vector2) -> void:
	target_position = input_position
	target_position.y -= touch_offset

func _physics_process(delta: float) -> void:
	if not can_move:
		_external_velocity = Vector2.ZERO
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

	# External pull (tractor beam etc.) is added for this frame only and kept
	# out of `velocity` afterwards, so the input smoothing never inherits it
	var input_velocity := velocity
	velocity += _external_velocity
	_external_velocity = Vector2.ZERO
	move_and_slide()
	velocity = input_velocity
	constrain_to_viewport()

	previous_velocity = velocity

func update_thrusters(current_velocity: Vector2) -> void:
	# Main thruster is always on when moving
	main_thruster.emitting = can_move
	main_thruster2.emitting = can_move
	
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
	main_thruster2.emitting = true

func disable_movement() -> void:
	can_move = false
	is_touch_active = false
	velocity = Vector2.ZERO

	# Stop all particle emitters
	main_thruster.emitting = false
	main_thruster2.emitting = false
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

# Weapon upgrade pickup: one tier up, capped at max_weapon_tier
func upgrade_weapon() -> void:
	set_weapon_tier(weapon_tier + 1)

# Set the weapon tier (clamped to 1..max_weapon_tier); applies the tier's
# fire cooldown and side gun visibility. `flash` plays the upgrade flash when
# the tier went up.
func set_weapon_tier(tier: int, flash: bool = true) -> void:
	var old_tier := weapon_tier
	weapon_tier = clampi(tier, 1, maxi(max_weapon_tier, 1))

	if not tier_fire_cooldowns.is_empty():
		fire_cooldown = tier_fire_cooldowns[mini(weapon_tier, tier_fire_cooldowns.size()) - 1]

	# Side guns are shown from tier 2
	var sides_visible := weapon_tier >= 2
	if left_gunpoint:
		left_gunpoint.visible = sides_visible
	if right_gunpoint:
		right_gunpoint.visible = sides_visible

	if flash and weapon_tier > old_tier:
		var flash_color := MAX_TIER_FLASH_COLOR if weapon_tier >= 3 else UPGRADE_FLASH_COLOR
		var tween = create_tween()
		tween.tween_property(self, "modulate", flash_color, 0.3)
		tween.tween_property(self, "modulate", Color(1, 1, 1), 0.3)  # Back to normal

	if weapon_tier != old_tier:
		weapon_tier_changed.emit(weapon_tier)

func fire_projectile() -> void:
	if not can_fire or not can_move or is_dead:
		return

	if not projectile_scene:
		print("No projectile scene assigned to player!")
		return

	# Tier 1+: center gun
	_spawn_projectile(projectile_scene, center_gunpoint)

	# Tier 2+: straight shots from the side guns
	if weapon_tier >= 2:
		var side_scene := upgraded_projectile_scene if upgraded_projectile_scene else projectile_scene
		if left_gunpoint:
			_spawn_projectile(side_scene, left_gunpoint)
		if right_gunpoint:
			_spawn_projectile(side_scene, right_gunpoint)

	# Tier 3: angled shots from the side guns
	if weapon_tier >= 3:
		var spread_scene := spread_projectile_scene if spread_projectile_scene else projectile_scene
		var angle := deg_to_rad(spread_angle_degrees)
		if left_gunpoint:
			_spawn_projectile(spread_scene, left_gunpoint, Vector2.UP.rotated(-angle))
		if right_gunpoint:
			_spawn_projectile(spread_scene, right_gunpoint, Vector2.UP.rotated(angle))

	# Play firing sound
	if fire_audio_player and fire_audio_player.stream:
		fire_audio_player.pitch_scale = randf_range(1.0, 1.4)  # Random pitch variation
		fire_audio_player.play()

	# Start cooldown using the direct time tracking approach
	can_fire = false
	cooldown_time_remaining = fire_cooldown

# Get a pooled projectile under the current scene and launch it from gunpoint
func _spawn_projectile(scene: PackedScene, gunpoint: Node2D, direction: Vector2 = Vector2.UP) -> void:
	var parent = get_tree().current_scene if get_tree().current_scene else get_parent()
	var projectile = ObjectPool.acquire(scene, parent)
	# Damage is set on every spawn from the scene's authored value (kept as
	# meta on first use; pooled instances keep their last damage, so the
	# current value must never be scaled again)
	if not projectile.has_meta("base_damage"):
		projectile.set_meta("base_damage", projectile.damage)
	projectile.damage = float(projectile.get_meta("base_damage")) * damage_scale
	projectile.initialize(gunpoint.global_position, direction)

func _on_fire_cooldown_timeout() -> void:
	can_fire = true

func die() -> void:
	# Set the dead flag to prevent blinking from showing the sprite
	is_dead = true
	is_firing = false  # Make sure we stop firing when dead

	# Hide all parts of the ship
	if ship_sprite:
		ship_sprite.visible = false

	# Disable all thrusters
	main_thruster.emitting = false
	main_thruster2.emitting = false
	left_thruster.emitting = false
	right_thruster.emitting = false
	up_thruster.emitting = false
	down_thruster.emitting = false

	# Disable collisions
	area.collision_mask = 0

	# Stop movement
	can_move = false
	velocity = Vector2.ZERO
	_external_velocity = Vector2.ZERO
