# enemy_projectile.gd
extends Area2D

@export var speed: float = 300.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.DOWN
var is_active: bool = false

func _ready() -> void:
	# Set collision to look for player
	collision_layer = 4  # Layer for enemy projectiles
	collision_mask = 1   # Layer for player
	
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

func initialize(spawn_position: Vector2, projectile_direction: Vector2 = Vector2.DOWN) -> void:
	position = spawn_position
	direction = projectile_direction.normalized()
	is_active = true
	
	# Rotate sprite to face direction
	rotation = direction.angle() + PI/2

func _on_area_entered(area: Area2D) -> void:
	# Debug print to verify the collision is detected
	print("Enemy projectile hit: ", area.name)
	
	# Check if we hit the player
	var player = null
	if area.get_parent() is CharacterBody2D:
		player = area.get_parent()
		
		# Update player health and trigger hit animation
		var level = get_tree().get_first_node_in_group("level")
		if level and level.has_method("update_health"):
			level.update_health(-damage)
		
		# Start player blinking (invulnerability)
		if player.has_method("start_blink"):
			player.start_blink()
		
		# Destroy the projectile
		queue_free()

func _on_lifetime_timer_timeout() -> void:
	queue_free()
