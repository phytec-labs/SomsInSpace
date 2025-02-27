# explosion_manager.gd
extends Node2D

# Explosion types enum
enum ExplosionType {
	SMALL,
	MEDIUM,
	LARGE,
	ENERGY
}

# Pooled explosions
var explosion_pools = {}

# Preload explosion scene
@onready var explosion_scene = preload("res://scenes/effects/explosion.tscn")

func _ready() -> void:
	# Initialize pools
	for type in ExplosionType.values():
		explosion_pools[type] = []

# Create explosion at given position with given type
func create_explosion(position: Vector2, type: ExplosionType = ExplosionType.MEDIUM) -> void:
	var explosion = get_explosion_from_pool(type)
	if not explosion:
		explosion = explosion_scene.instantiate()
		add_child(explosion)

	explosion.position = position
	explosion.set_explosion_type(type)
	explosion.start()

# Get explosion from pool or return null if empty
func get_explosion_from_pool(type: ExplosionType) -> Node2D:
	if explosion_pools[type].size() > 0:
		return explosion_pools[type].pop_back()
	return null

# Return explosion to pool
func return_to_pool(explosion: Node2D, type: ExplosionType) -> void:
	explosion_pools[type].append(explosion)
