# projectile.gd
extends Area2D
class_name Projectile

@export var speed: float = 500.0
@export var damage: float = 10.0
@export var lifetime: float = 2.0

var direction: Vector2 = Vector2.UP
var is_active: bool = false

func _ready() -> void:
	# Connect signals
	area_entered.connect(_on_area_entered)

	# Start the lifetime timer
	var timer = Timer.new()
	timer.name = "LifetimeTimer"
	timer.wait_time = lifetime
	timer.one_shot = true
	timer.timeout.connect(_on_lifetime_timer_timeout)
	add_child(timer)
	timer.start()

	# Add a simple rotation animation
	var tween = create_tween()
	tween.tween_property(self, "rotation", PI * 4, lifetime)
	tween.set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	# Move the projectile
	position += direction * speed * delta

	# Check if off-screen
	var viewport_rect = get_viewport_rect()
	var margin = 50.0
	if (position.y < -margin or
		position.y > viewport_rect.size.y + margin or
		position.x < -margin or
		position.x > viewport_rect.size.x + margin):
		queue_free()

func initialize(spawn_position: Vector2, projectile_direction: Vector2 = Vector2.UP) -> void:
	position = spawn_position
	direction = projectile_direction.normalized()
	is_active = true

func _on_area_entered(area: Area2D) -> void:
	# Check if we hit an obstacle directly (Area2D) or need to get its parent
	var obstacle = null
	if area is Obstacle:
		obstacle = area
	elif area.get_parent() is Obstacle:
		obstacle = area.get_parent()

	if obstacle:
		# Deal damage to obstacle using the dedicated take_damage method
		# This avoids the normal player collision handling
		if obstacle.has_method("take_damage"):
			obstacle.take_damage(damage)
		# Intentionally NOT using handle_player_collision here

		# Destroy the projectile
		queue_free()

func _on_lifetime_timer_timeout() -> void:
	queue_free()
