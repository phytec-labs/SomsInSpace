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
# Near-miss sensor (layer 16, group "graze"): enemy projectiles (mask 1|16)
# award a graze when they pass through it. Only monitorable while the ship is
# controllable and vulnerable (see _update_graze_area()).
@onready var graze_area: Area2D = get_node_or_null("GrazeArea")
# Shield bubble (shown while shielded; see activate_shield()). Its child
# "Dome" Sprite2D (sprites/shield_dome_1.png, 634x634 full sphere, at 0.5258,
# at (0, -6): within 5 local px of the ships' visible center (y -10.8 for
# all three after visual_scale / visual_offset_y); sphere radius 126 local
# px, ~17 px outside the farthest corner of the ships' visible bounding box
# (~127x169 local), ~10 px outside it at the -5% pulse) uses
# shaders/shield_bubble.gdshader (faded interior, rim glow). The pulse / hit
# pop / warning blink drive ShieldRing's scale, modulate and visibility; the
# shader multiplies by modulate last, so they apply on top of the look.
@onready var shield_ring: Node2D = get_node_or_null("ShieldRing")
# Procedural look (shield_style = Procedural): sibling "Field" ColorRect,
# 324x324 at (-162, -168), i.e. centered on the Dome's (0, -6), with
# shaders/shield_procedural.gdshader (edge_radius 0.78 of the half-size =
# the same 126 local px sphere radius; the halo fits inside the quad).
@onready var shield_dome: CanvasItem = get_node_or_null("ShieldRing/Dome")
@onready var shield_field: Control = get_node_or_null("ShieldRing/Field")
# While shielded the hit area is the shield circle: CollisionArea/ShieldShape
# (CircleShape2D at the ShieldRing center (0, -6)) is enabled next to the hull
# polygon (which stays enabled and lies inside it), so enemies, enemy shots,
# pickups and the UFO beam meet the drawn sphere edge. Disabled whenever the
# shield is off (end_shield(): timeout, die, fly_to, reset, scene start).
@onready var shield_shape: CollisionShape2D = get_node_or_null("CollisionArea/ShieldShape")
## Radius (local px) of the shield hit circle: the drawn sphere edge, the same
## for both looks (Dome rim 0.378 x 634 x 0.5258 = 126; Field edge_radius
## 0.78 x 162 = 126). ~101 px on screen at the level's 0.8 player scale.
@export var shield_hit_radius: float = 126.0

# Emitted when a fly_to() tween reaches its target
signal arrived
var _fly_tween: Tween
var is_flying: bool = false
# Scale as placed in the level (0.8); fly_to(end_scale) shrinks the ship for
# the victory landing, reset_position() restores it
var _base_scale: Vector2 = Vector2.ONE

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

# Shield bubble (shield pickup): absorbs damaging hits (main_level.gd checks
# is_shielded()) for shield_time_left seconds. Accumulator timers in
# _process(), so it freezes while the tree is paused.
## Last seconds of the shield in which the ring blinks as a warning
@export var shield_warning_time: float = 2.0
const SHIELD_PULSE_SPEED := 6.0        # rad/s of the ring's scale/alpha pulse
const SHIELD_PULSE_SCALE := 0.05       # +-5% scale
const SHIELD_BLINK_RATE := 8.0         # Toggles per second in the warning time
const SHIELD_FLASH_TIME := 0.15        # Bright pop when a hit is absorbed
const SHIELD_FLASH_SCALE := 0.18
const SHIELD_FLASH_COLOR := Color(2.2, 2.2, 2.2, 1.0)
var shield_time_left: float = 0.0
var shield_duration: float = 0.0       # Length of the current shield (HUD bar)
var shield_hits_absorbed: int = 0      # Observability (tests / tuning)
var _shield_anim_time: float = 0.0
var _shield_flash_left: float = 0.0

## Player shield look: Sprite (ShieldRing/Dome, hex dome art) or Procedural
## (ShieldRing/Field, shader only). main_level.gd applies
## GameConfig.shield_style through set_shield_style().
@export_enum("Sprite", "Procedural") var shield_style: int = 1
const SHIELD_STYLE_SPRITE := 0
const SHIELD_STYLE_PROCEDURAL := 1
# Procedural hit ripple: seconds since the absorbed hit (accumulated in
# _process_shield, so it freezes while paused); the shader's hit_time uniform
# is only written while a ripple plays.
const SHIELD_RIPPLE_DURATION := 0.5    # Matches the shader's ripple_duration
const SHIELD_RIPPLE_IDLE := 100.0      # hit_time value meaning "no ripple"
var _shield_ripple_time: float = SHIELD_RIPPLE_IDLE

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
# Ship sprite scale / position as authored in the scene (0.125, origin),
# captured on the first apply_ship(); the ship's visual_scale and
# visual_offset_y are applied on top of these, so re-applying is idempotent
var _ship_base_scale: Vector2 = Vector2.ZERO
var _ship_base_position: Vector2 = Vector2.ZERO

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
	_base_scale = scale
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

	if graze_area:
		graze_area.add_to_group("graze")
	if shield_shape and shield_shape.shape is CircleShape2D:
		(shield_shape.shape as CircleShape2D).radius = shield_hit_radius
	set_shield_style(shield_style)
	end_shield()
	disable_movement()

# Applies a ShipDefinition: sprite texture/tint/size, speed, fire cooldowns
# and projectile damage. Idempotent (cooldowns and the sprite scale are
# derived from the authored values, not the current ones). Health is applied
# by main_level.gd.
func apply_ship(def: ShipDefinitionScript) -> void:
	if def == null:
		return
	ship_definition = def
	if def.texture and ship_sprite:
		ship_sprite.texture = def.texture
	if ship_sprite:
		ship_sprite.modulate = def.tint
		# Same visible height and center for every ship (see ShipDefinition)
		if _ship_base_scale == Vector2.ZERO:
			_ship_base_scale = ship_sprite.scale
			_ship_base_position = ship_sprite.position
		ship_sprite.scale = _ship_base_scale * def.visual_scale
		ship_sprite.position = _ship_base_position + Vector2(0.0, def.visual_offset_y)
	speed = def.speed
	damage_scale = def.damage_scale
	_apply_hardpoints(def)

	if _base_tier_fire_cooldowns.is_empty():
		_base_tier_fire_cooldowns = tier_fire_cooldowns.duplicate()
	var scaled: Array[float] = []
	for cooldown in _base_tier_fire_cooldowns:
		scaled.append(cooldown * def.fire_cooldown_scale)
	tier_fire_cooldowns = scaled
	# Refresh fire_cooldown for the current tier (no flash / signal)
	set_weapon_tier(weapon_tier, false)

# Gunpoints and thrusters from the ship's hardpoint offsets (x of each marker
# is kept unless the definition sets it; Up/Down thrusters are not moved)
func _apply_hardpoints(def: ShipDefinitionScript) -> void:
	if center_gunpoint:
		center_gunpoint.position.y = def.nose_offset_y
	if left_gunpoint:
		left_gunpoint.position = Vector2(-def.wing_gun_x, def.wing_gun_y)
	if right_gunpoint:
		right_gunpoint.position = Vector2(def.wing_gun_x, def.wing_gun_y)
	for thruster in [main_thruster, main_thruster2]:
		if thruster:
			thruster.position.y = def.engine_offset_y
	for thruster in [left_thruster, right_thruster]:
		if thruster:
			thruster.position.y = def.side_thruster_y

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
	if shield_time_left > 0.0:
		_process_shield(delta)

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
	_update_graze_area()

func end_blink() -> void:
	is_blinking = false
	area.collision_mask = 2  # Re-enable collisions with obstacles
	update_sprite_visibility(true)  # Ensure sprite is visible
	_update_graze_area()

# --- Shield ---

# Shield pickup: shielded for `duration` seconds (re-collecting refreshes the
# time to the full duration). No effect while dead.
func activate_shield(duration: float = 8.0) -> void:
	if is_dead or duration <= 0.0:
		return
	shield_duration = duration
	shield_time_left = duration
	_shield_anim_time = 0.0
	_shield_flash_left = 0.0
	_stop_shield_ripple()
	_update_shield_ring()
	_set_shield_hitbox(true)
	_update_graze_area()

# Shield circle hit area on/off. Deferred: shape changes are not allowed
# inside physics callbacks (the shield pickup is collected from one).
func _set_shield_hitbox(on: bool) -> void:
	if shield_shape:
		shield_shape.set_deferred("disabled", not on)

# Shows the Dome sprite (SHIELD_STYLE_SPRITE) or the procedural Field
# (SHIELD_STYLE_PROCEDURAL) under ShieldRing; everything else (pulse, pop,
# blink, end) animates ShieldRing itself, so it applies to either look.
func set_shield_style(style: int) -> void:
	shield_style = style
	var procedural := style == SHIELD_STYLE_PROCEDURAL and shield_field != null
	if shield_dome:
		shield_dome.visible = not procedural
	if shield_field:
		shield_field.visible = procedural
	_stop_shield_ripple()

func _is_procedural_shield() -> bool:
	return shield_field != null and shield_field.visible

func is_shielded() -> bool:
	return shield_time_left > 0.0 and not is_dead

# A damaging hit was absorbed (main_level.gd): brief pop, shield keeps going.
# `at` (global position of the shot / obstacle, if known) starts the
# procedural look's ripple there; without it the ripple starts at the top.
func shield_absorb_hit(at: Vector2 = Vector2.INF) -> void:
	if not is_shielded():
		return
	shield_hits_absorbed += 1
	_shield_flash_left = SHIELD_FLASH_TIME
	if _is_procedural_shield():
		_start_shield_ripple(at)
	_update_shield_ring()

# Ripple origin in the Field shader's p space ((UV - 0.5) * 2), clamped onto
# the sphere (a rammed obstacle's center is usually outside it)
func _start_shield_ripple(at: Vector2) -> void:
	var mat := shield_field.material as ShaderMaterial
	if mat == null:
		return
	# Uniform left at its shader default: may read back as null
	var er = mat.get_shader_parameter("edge_radius")
	var edge_radius: float = float(er) if er != null else 0.78
	var p := Vector2(0.0, -edge_radius)
	if at.is_finite():
		var local: Vector2 = shield_field.get_global_transform().affine_inverse() * at
		var size := shield_field.size
		if size.x > 0.0 and size.y > 0.0:
			p = (local / size - Vector2(0.5, 0.5)) * 2.0
			p = p.limit_length(edge_radius)
	mat.set_shader_parameter("hit_pos", p)
	_shield_ripple_time = 0.0
	mat.set_shader_parameter("hit_time", 0.0)

func _advance_shield_ripple(delta: float) -> void:
	if _shield_ripple_time >= SHIELD_RIPPLE_IDLE:
		return
	_shield_ripple_time += delta
	if _shield_ripple_time > SHIELD_RIPPLE_DURATION:
		_stop_shield_ripple()
	elif shield_field and shield_field.material:
		(shield_field.material as ShaderMaterial).set_shader_parameter("hit_time", _shield_ripple_time)

func _stop_shield_ripple() -> void:
	_shield_ripple_time = SHIELD_RIPPLE_IDLE
	if shield_field and shield_field.material is ShaderMaterial:
		(shield_field.material as ShaderMaterial).set_shader_parameter("hit_time", SHIELD_RIPPLE_IDLE)

# Shield off now (time out, death, end of run, scene reload)
func end_shield() -> void:
	shield_time_left = 0.0
	_shield_flash_left = 0.0
	if _shield_ripple_time < SHIELD_RIPPLE_IDLE:
		_stop_shield_ripple()
	# Back to the hull polygon only. Something overlapping just the circle
	# gets an area_exited (no hit); something already over the hull stays
	# overlapped (no new area_entered).
	_set_shield_hitbox(false)
	_update_graze_area()
	if shield_ring:
		shield_ring.visible = false
		shield_ring.scale = Vector2.ONE
		shield_ring.modulate = Color.WHITE

# Remaining shield time as a fraction of its duration (0 = off), for the HUD
func get_shield_fraction() -> float:
	if not is_shielded() or shield_duration <= 0.0:
		return 0.0
	return clampf(shield_time_left / shield_duration, 0.0, 1.0)

func _process_shield(delta: float) -> void:
	shield_time_left -= delta
	_shield_anim_time += delta
	_shield_flash_left = maxf(_shield_flash_left - delta, 0.0)
	if shield_time_left <= 0.0 or is_dead:
		end_shield()
		return
	_advance_shield_ripple(delta)
	_update_shield_ring()

# Dome visuals from the shield state: pulse, hit flash, warning blink
func _update_shield_ring() -> void:
	if not shield_ring:
		return
	if not is_shielded():
		shield_ring.visible = false
		return
	var pulse := sin(_shield_anim_time * SHIELD_PULSE_SPEED)
	var ring_scale := 1.0 + pulse * SHIELD_PULSE_SCALE
	var color := Color(1, 1, 1, 0.75 + 0.25 * pulse)
	if _shield_flash_left > 0.0:
		var t := _shield_flash_left / SHIELD_FLASH_TIME
		ring_scale += SHIELD_FLASH_SCALE * t
		color = color.lerp(SHIELD_FLASH_COLOR, t)
	shield_ring.scale = Vector2(ring_scale, ring_scale)
	shield_ring.modulate = color
	# Blink in the warning time (a hit flash always shows)
	var warning := shield_time_left <= shield_warning_time
	shield_ring.visible = _shield_flash_left > 0.0 or not warning \
		or int(_shield_anim_time * SHIELD_BLINK_RATE) % 2 == 0

# Grazes only count while the ship is flying under player control and can be
# hit (not blinking / dead / countdown / victory / fly_to / shielded: the
# GrazeArea lies inside the shield circle, which eats the shot first).
# Deferred: this runs from physics callbacks (a projectile hit starts the
# blink).
func _update_graze_area() -> void:
	if graze_area:
		graze_area.set_deferred("monitorable", can_graze())

func can_graze() -> bool:
	return can_move and not is_blinking and not is_dead and not is_shielded()

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
	# The shield itself survives (this also runs on every unpause); only the
	# ring is re-synced so it is never left showing without a shield
	_update_shield_ring()
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
	_update_graze_area()

func disable_movement() -> void:
	can_move = false
	is_touch_active = false
	velocity = Vector2.ZERO
	_update_graze_area()

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
	scale = _base_scale
	end_blink()  # Ensure blink effect is reset
	end_shield()

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
	end_shield()

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
	if _fly_tween:
		_fly_tween.kill()
		_fly_tween = null
	is_flying = false
	_update_graze_area()

# Scripted flight (victory docking): tweens the ship to `target` (global) over
# `duration` seconds, ignoring player input, with the main thrusters on (plus
# the directional thruster opposite the travel direction). Thrusters go off and
# `arrived` is emitted on arrival. Input stays disabled afterwards.
# `end_scale` > 0 also shrinks the ship from its current scale to that uniform
# scale over the flight, mostly in the second half (reads as descending onto
# the landing pad); only a scene reload or reset_position() restores it.
func fly_to(target: Vector2, duration: float, end_scale: float = -1.0) -> void:
	if is_dead:
		return
	if _fly_tween:
		_fly_tween.kill()
	# Scripted flight (docking) is never shielded: no ring over the station
	end_shield()
	can_move = false
	is_firing = false
	is_touch_active = false
	velocity = Vector2.ZERO
	_external_velocity = Vector2.ZERO
	is_flying = true
	_update_graze_area()

	var travel := target - global_position
	main_thruster.emitting = true
	main_thruster2.emitting = true
	update_thrusters(travel)  # Directional thrusters for the travel direction
	main_thruster.emitting = true  # (update_thrusters ties these to can_move)
	main_thruster2.emitting = true

	var time := maxf(duration, 0.01)
	_fly_tween = create_tween()
	_fly_tween.tween_property(self, "global_position", target, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if end_scale > 0.0:
		_fly_tween.parallel().tween_property(self, "scale", Vector2(end_scale, end_scale), time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fly_tween.tween_callback(_on_fly_arrived)

func _on_fly_arrived() -> void:
	_fly_tween = null
	is_flying = false
	main_thruster.emitting = false
	main_thruster2.emitting = false
	left_thruster.emitting = false
	right_thruster.emitting = false
	up_thruster.emitting = false
	down_thruster.emitting = false
	arrived.emit()
