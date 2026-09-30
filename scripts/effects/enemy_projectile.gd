# enemy_projectile.gd
# Enemy projectile. Pooled via the ObjectPool autoload: never queue_free()d,
# it is released back to the pool on hit, lifetime expiry, or leaving the screen.
extends Area2D

@export var speed: float = 300.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.DOWN
var is_active: bool = false

var _time_left: float = 0.0

func _ready() -> void:
	# Set collision to look for player
	collision_layer = 4  # Layer for enemy projectiles
	collision_mask = 1   # Layer for player

	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if not is_active:
		return

	# Move the projectile
	position += direction * speed * delta

	# Lifetime countdown
	_time_left -= delta
	if _time_left <= 0.0:
		_despawn()
		return

	# Check if off-screen
	var viewport_rect = get_viewport_rect()
	var margin = 50.0
	if (position.y < -margin or
		position.y > viewport_rect.size.y + margin or
		position.x < -margin or
		position.x > viewport_rect.size.x + margin):
		_despawn()

func initialize(spawn_position: Vector2, projectile_direction: Vector2 = Vector2.DOWN) -> void:
	position = spawn_position
	direction = projectile_direction.normalized()
	is_active = true
	_time_left = lifetime
	set_process(true)
	show()
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	# Rotate sprite to face direction
	rotation = direction.angle() + PI/2

func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return

	# Debug print to verify the collision is detected
	print("Enemy projectile hit: ", area.name)

	# Check if we hit the player
	if area.get_parent() is CharacterBody2D:
		var player = area.get_parent()

		# Invulnerable (blinking) or dead player: absorb the shot without damage
		var invulnerable = ("is_blinking" in player and player.is_blinking) or \
			("is_dead" in player and player.is_dead)

		if not invulnerable:
			# Update player health and trigger hit animation
			var level = get_tree().get_first_node_in_group("level")
			if level and level.has_method("update_health"):
				level.update_health(-damage)

			# Start player blinking (invulnerability)
			if player.has_method("start_blink"):
				player.start_blink()

		# Destroy the projectile
		_despawn()

func _despawn() -> void:
	if not is_active:
		return
	is_active = false
	ObjectPool.release(self)
