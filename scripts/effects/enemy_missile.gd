# enemy_missile.gd
# Zeppelin missile: a slow homing shot that can be shot down. Pooled via the
# ObjectPool autoload like every enemy projectile (never queue_free()d).
#
# It IS an enemy projectile (extends enemy_projectile.gd), so every existing
# rule applies unchanged: group "enemy_projectile" (the screen-clear bomb's
# clear() removes it, the attract autopilot dodges it), absorbed at the shield
# bubble's edge with the ripple, no damage while the player blinks or is dead,
# damage through level.update_health() (combo reset, optional tier loss,
# blink), grazes. On top of that:
#  - homing: it turns toward the player at up to turn_rate_degrees/s for the
#    first homing_time seconds, then keeps its heading (dodgeable)
#  - shootable: its root Area2D is also on projectile.gd SHOOTABLE_LAYER and in
#    SHOOTABLE_GROUP, so player lasers and missiles call take_damage(); it has
#    max_health (2 laser hits at 10 damage, 1 player missile) and when shot down
#    pops (small explosion) and awards shot_down_points through
#    level.award_kill_points(), i.e. as a kill: the combo applies and rises
# Timing is accumulated in _process(), so it freezes while paused.
#
# PLACEHOLDER_ART: scenes/effects/enemy_missile.tscn reuses the player's
# sidewinder (sprites/side_winder_missile_1.png, nose up = -y; the node rotates
# to face its velocity) on a Sprite2D at scale 0.1 (~50x17 px), tinted dark
# orange by the Sprite2D's self_modulate (the root's modulate is the hit
# flash), plus an untextured CPUParticles2D smoke trail from the nozzle
# (0, 24). Swap: a dedicated enemy missile render on the same canvas and
# orientation as side_winder_missile_1 (resize_art.gd entry like it), then
# self_modulate back to white; see docs/ART_SWAP_TRACKER.md.
extends "res://scripts/effects/enemy_projectile.gd"

const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")
const SHOOTABLE_LAYER := 32  # projectile.gd SHOOTABLE_LAYER
const SHOOTABLE_GROUP := &"shootable"
const HIT_FLASH_TIME := 0.08

## Max turn toward the player (degrees per second) while homing
@export var turn_rate_degrees: float = 110.0
## Seconds after launch during which it homes; afterwards it flies straight
@export var homing_time: float = 2.2
## Health against player shots (lasers deal 10 x the ship's damage_scale)
@export var max_health: float = 20.0
## Points for shooting it down (through award_kill_points: combo applies)
@export var shot_down_points: int = 5
## Despawn once this far outside the screen (it may curve out and back)
@export var offscreen_margin: float = 120.0

var health: float = 0.0
## Incremented on every launch: holders of a reference (the zeppelin's live
## missile count) compare it to tell "still my missile" from a pooled reuse
var launch_count: int = 0
# Seconds since launch
var age: float = 0.0
var _hit_flash_left: float = 0.0
@onready var _trail: CPUParticles2D = get_node_or_null("Trail")

# Observability (tests / tuning): missiles shot down by the player / that
# reached the player (subclasses keep their own counts via the hooks)
static var shot_down_total: int = 0
static var reached_player_total: int = 0

func _ready() -> void:
	super._ready()
	collision_layer = 4 | SHOOTABLE_LAYER
	add_to_group(SHOOTABLE_GROUP)

func initialize(spawn_position: Vector2, projectile_direction: Vector2 = Vector2.DOWN) -> void:
	super.initialize(spawn_position, projectile_direction)
	launch_count += 1
	health = max_health
	age = 0.0
	_hit_flash_left = 0.0
	modulate = Color.WHITE
	if _trail:
		_trail.restart()
		_trail.emitting = true

func _process(delta: float) -> void:
	if not is_active:
		return
	age += delta
	_steer(delta)
	position += direction * speed * delta
	rotation = direction.angle() + PI / 2.0
	_update_hit_flash(delta)

	_time_left -= delta
	if _time_left <= 0.0:
		_despawn()
		return
	var view := get_viewport_rect().size
	if position.y < -offscreen_margin or position.y > view.y + offscreen_margin \
			or position.x < -offscreen_margin or position.x > view.x + offscreen_margin:
		_despawn()

# Turn toward the player (limited rate) while homing
func _steer(delta: float) -> void:
	if age > homing_time:
		return
	var target := _homing_target()
	if not target.is_finite():
		return
	direction = turn_toward(direction, target - global_position, deg_to_rad(turn_rate_degrees) * delta)

# Global position to home on (INF = none: no player, or dead)
func _homing_target() -> Vector2:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.get("is_dead"):
		return Vector2.INF
	return player.global_position

## Rotate unit vector `from` toward `to` by at most `max_angle` radians
static func turn_toward(from: Vector2, to: Vector2, max_angle: float) -> Vector2:
	if to.length_squared() < 0.0001:
		return from
	var diff := wrapf(to.angle() - from.angle(), -PI, PI)
	return from.rotated(clampf(diff, -max_angle, max_angle)).normalized()

# Reached the player (hit, shield-absorbed or eaten by the blink): counted
func _on_area_entered(area: Area2D) -> void:
	var was_active := is_active
	super._on_area_entered(area)
	if was_active and not is_active:
		_on_reached_player()

# Hook for subclasses (observability)
func _on_reached_player() -> void:
	reached_player_total += 1

# Player laser / missile hit (projectile.gd, player_missile.gd)
func take_damage(amount: float) -> void:
	if not is_active:
		return
	health -= amount
	if health > 0.0:
		_hit_flash_left = HIT_FLASH_TIME
		modulate = Color(3.0, 3.0, 3.0)
		return
	_shot_down()

func _update_hit_flash(delta: float) -> void:
	if _hit_flash_left <= 0.0:
		return
	_hit_flash_left -= delta
	if _hit_flash_left <= 0.0:
		modulate = Color.WHITE

# Pop, points (as a kill, through the level), back to the pool
func _shot_down() -> void:
	_on_shot_down()
	_pop(0)
	var level = get_tree().get_first_node_in_group("level")
	if level and shot_down_points > 0 and level.has_method("award_kill_points"):
		level.award_kill_points(shot_down_points, self)
	_despawn()

# Hook for subclasses (observability)
func _on_shot_down() -> void:
	shot_down_total += 1

# Pooled explosion at this position (0 = SMALL, 3 = ENERGY)
func _pop(explosion_type: int) -> void:
	var scene_root = get_tree().current_scene
	var parent = scene_root if scene_root else get_parent()
	if parent == null:
		return
	var explosion = ObjectPool.acquire(EXPLOSION_SCENE, parent)
	if explosion:
		explosion.global_position = global_position
		explosion.set_explosion_type(explosion_type)
		explosion.start()

func _despawn() -> void:
	if not is_active:
		return
	if _trail:
		_trail.emitting = false
	modulate = Color.WHITE
	super._despawn()
