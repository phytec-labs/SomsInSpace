# projectile.gd
# Player projectile. Pooled via the ObjectPool autoload: never queue_free()d,
# it is released back to the pool on hit, lifetime expiry, or leaving the screen.
extends Area2D
class_name Projectile

# Impact sparks on non-lethal hits (kills show the obstacle's explosion)
const HIT_SPARK_SCENE := preload("res://scenes/effects/hit_spark.tscn")
const HitSparkScript := preload("res://scripts/effects/hit_spark.gd")

@export var speed: float = 500.0
@export var damage: float = 10.0
@export var lifetime: float = 2.0
## Spin while flying (round shots). Off = the sprite keeps facing `direction`
## (streak-shaped shots such as the tier-3 spread laser).
@export var spin: bool = true

var direction: Vector2 = Vector2.UP
var is_active: bool = false

var _time_left: float = 0.0
var _spin_tween: Tween

func _ready() -> void:
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

func initialize(spawn_position: Vector2, projectile_direction: Vector2 = Vector2.UP) -> void:
	position = spawn_position
	direction = projectile_direction.normalized()
	is_active = true
	_time_left = lifetime
	set_process(true)
	show()
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	# Face the flight direction (the sprite is authored pointing up, so
	# Vector2.UP -> rotation 0; angled shots are rotated to match)
	if _spin_tween:
		_spin_tween.kill()
		_spin_tween = null
	var base_rotation := direction.angle() + PI / 2.0
	rotation = base_rotation

	# Simple rotation animation, restarted on every spawn
	if spin:
		_spin_tween = create_tween()
		_spin_tween.tween_property(self, "rotation", base_rotation + PI * 4, lifetime)
		_spin_tween.set_ease(Tween.EASE_IN_OUT)

func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return

	# Check if we hit an obstacle directly (Area2D) or need to get its parent
	var obstacle = null
	if area is Obstacle:
		obstacle = area
	elif area.get_parent() is Obstacle:
		obstacle = area.get_parent()

	if obstacle and obstacle.is_active:
		# Deal damage to obstacle using the dedicated take_damage method
		# (intentionally NOT using handle_player_collision here)
		obstacle.take_damage(damage)
		# Survived the hit: sparks where the shot landed (capped, see
		# hit_spark.gd MAX_LIVE)
		if obstacle.is_active and obstacle.health > 0.0:
			_spawn_hit_spark()
		_despawn()

func _spawn_hit_spark() -> void:
	if not HitSparkScript.can_spawn():
		return
	var parent = get_parent()
	if parent == null:
		return
	var spark = ObjectPool.acquire(HIT_SPARK_SCENE, parent)
	if spark:
		spark.burst(global_position)

func _despawn() -> void:
	if not is_active:
		return
	is_active = false
	if _spin_tween:
		_spin_tween.kill()
		_spin_tween = null
	ObjectPool.release(self)
