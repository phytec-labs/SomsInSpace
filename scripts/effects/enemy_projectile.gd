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
# speed / lifetime as authored in the scene. A spawner may override them for
# one flight (e.g. the seeker orb's slow burst ring) by setting them before
# initialize(); _despawn() restores them, so pooled instances reused by other
# shooters always fly as authored.
var _authored_speed: float = -1.0
var _authored_lifetime: float = -1.0
# Near-miss already awarded for this flight (reset in initialize(), i.e. on
# every pool acquire)
var _grazed: bool = false

# Player hurtbox (CollisionArea, layer 1) | player GrazeArea (layer 16)
const PLAYER_MASK := 1 | 16

# Every enemy projectile (any scene using this script) is in this group; the
# screen-clear bomb (main_level.gd detonate_bomb()) removes those on screen
const GROUP := &"enemy_projectile"

func _ready() -> void:
	_authored_speed = speed
	_authored_lifetime = lifetime
	add_to_group(GROUP)
	# Set collision to look for player
	collision_layer = 4  # Layer for enemy projectiles
	collision_mask = PLAYER_MASK  # Player hurtbox + graze sensor

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
	_grazed = false
	set_process(true)
	show()
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	# Rotate sprite to face direction
	rotation = direction.angle() + PI/2

func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return

	# Near miss: passing through the player's GrazeArea awards a graze once
	# per flight. The shot is NOT absorbed: it flies on and can still hit.
	if area.is_in_group("graze"):
		if not _grazed:
			var grazer = area.get_parent()
			var can_graze = grazer != null and grazer.has_method("can_graze") and grazer.can_graze()
			if can_graze:
				_grazed = true
				var level = get_tree().get_first_node_in_group("level")
				if level and level.has_method("award_graze"):
					level.award_graze(global_position)
		return

	# Check if we hit the player
	if area.get_parent() is CharacterBody2D:
		var player = area.get_parent()

		# Invulnerable (blinking) or dead player: absorb the shot without damage
		var invulnerable = ("is_blinking" in player and player.is_blinking) or \
			("is_dead" in player and player.is_dead)
		var shielded = player.has_method("is_shielded") and player.is_shielded()

		# Shielded (even while blinking): the shot meets the sphere edge,
		# update_health absorbs it there (pop + ripple, no damage)
		if shielded:
			var level = get_tree().get_first_node_in_group("level")
			if level and level.has_method("update_health"):
				level.update_health(-damage, global_position)
		elif not invulnerable:
			# Update player health and trigger hit animation
			var level = get_tree().get_first_node_in_group("level")
			if level and level.has_method("update_health"):
				level.update_health(-damage, global_position)

			# Start player blinking (invulnerability)
			if player.has_method("start_blink"):
				player.start_blink()

		# Destroy the projectile
		_despawn()

# Remove this shot now (screen-clear bomb); no-op if already despawned
func clear() -> void:
	_despawn()

func _despawn() -> void:
	if not is_active:
		return
	is_active = false
	if _authored_speed >= 0.0:
		speed = _authored_speed
		lifetime = _authored_lifetime
	ObjectPool.release(self)
