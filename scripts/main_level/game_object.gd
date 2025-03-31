# game_object.gd
extends Area2D
class_name GameObject

# Export variables for easy configuration in editor
@export var points: int = 0  # Positive for collectibles, negative for obstacles
@export var speed_multiplier: float = 1.0  # Allows for varying speeds
@export var animation_speed: float = 1.0  # For animated sprites

# Signals
signal object_collected
signal object_hit
signal screen_exited

# Node references
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
@onready var collision_shape: CollisionShape2D = $CollisionShape2D if has_node("CollisionShape2D") else null
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D if has_node("CollisionPolygon2D") else null

# Object state
var is_active: bool = false
var is_being_collected: bool = false  # Prevent multiple collisions during collection

func _ready() -> void:
	# Set up collision properties
	collision_layer = 2  # Layer 2 for game objects
	collision_mask = 1   # Layer 1 for player

	# We only need area_entered since we're using Area2D for the player too
	area_entered.connect(_on_area_entered)
	
	# Verify we have at least one collision node
	if not collision_shape and not collision_polygon:
		push_error("GameObject " + name + " requires either a CollisionShape2D or CollisionPolygon2D child node!")
	
	# Verify we have at least one visual node
	if not sprite and not animated_sprite:
		push_warning("GameObject " + name + " has no Sprite2D or AnimatedSprite2D child node!")
	
	# Configure animated sprite if it exists
	if animated_sprite:
		animated_sprite.speed_scale = animation_speed

func _process(delta: float) -> void:
	if is_active:
		# Check if off-screen
		check_if_offscreen()

func check_if_offscreen() -> void:
	# Get viewport rect and add margins
	var viewport_rect = get_viewport_rect()
	var margin = 100.0
	
	# Check if object has moved completely off screen
	if (position.y > viewport_rect.size.y + margin or  # Below screen
		position.y < -margin * 2 or                   # Far above screen
		position.x > viewport_rect.size.x + margin or  # Right of screen
		position.x < -margin):                        # Left of screen
			
		print(name + " exited screen at " + str(position))
		emit_signal("screen_exited")

func initialize(spawn_position: Vector2) -> void:
	position = spawn_position
	is_active = true
	is_being_collected = false
	show()
	
	# Handle visuals
	if sprite:
		sprite.show()
	if animated_sprite:
		animated_sprite.show()
		animated_sprite.play()
		
	# Enable collisions
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if collision_polygon:
		collision_polygon.set_deferred("disabled", false)

func deactivate() -> void:
	is_active = false
	
	# Handle visuals
	if sprite:
		sprite.hide()
	if animated_sprite:
		animated_sprite.stop()
		animated_sprite.hide()
		
	# Disable collisions
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if collision_polygon:
		collision_polygon.set_deferred("disabled", true)
		
	hide()

func _on_area_entered(_area: Area2D) -> void:
	if not is_active or is_being_collected:
		return

	# Since we're using collision layers/masks, any area entering
	# must be the player's collision area
	call_deferred("handle_player_collision")

func handle_player_collision() -> void:
	if is_being_collected:
		return

	is_being_collected = true

	# Hide visual and disable collisions immediately
	if sprite:
		sprite.hide()
	if animated_sprite:
		animated_sprite.stop()
		animated_sprite.hide()
		
	# Disable collisions
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if collision_polygon:
		collision_polygon.set_deferred("disabled", true)

	# Emit appropriate signal based on points value
	if points >= 0:
		print("Object collected: " + name + " - Points: " + str(points))
		emit_signal("object_collected")
	else:
		print("Object hit: " + name)
		emit_signal("object_hit")

	# Finally deactivate the object
	deactivate()

# Optional: Methods to control animation
func set_animation_speed(speed: float) -> void:
	animation_speed = speed
	if animated_sprite:
		animated_sprite.speed_scale = speed

func play_animation(anim_name: String = "default") -> void:
	if animated_sprite and animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)

func stop_animation() -> void:
	if animated_sprite:
		animated_sprite.stop()
