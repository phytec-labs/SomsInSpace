# player_missile.gd
# Player's sidewinder missile (missile upgrade: player.gd activate_missiles()
# launches a pair from the wing guns every missile_interval while firing).
# Pooled via the ObjectPool autoload like the player's lasers: never
# queue_free()d, released on hit, lifetime expiry or leaving the screen.
#
# Flight: launched launch_speed px/s along the launch direction (the player
# angles the pair +-20 deg outward), accelerating to max_speed; homes on its
# target at up to turn_rate_degrees/s and always faces its velocity. Target
# (picked at launch, see _pick_target()): the boss or a mini-boss when one is
# on screen, else the nearest active obstacle or shootable enemy shot (enemy
# missile, seeker orb) above the ship. If the target dies or leaves, it
# retargets ONCE to the nearest; with no target it turns straight up.
#
# Hits: same layer / mask as the player's lasers (layer 8; mask 2 obstacles |
# 32 shootable shots). Obstacles take `damage` through take_damage(), so kill
# points, combo, hit flash / punch, health bar and loot all work as for
# lasers (x boss_damage_scale against the boss); shootable shots get
# take_damage() too. Impact: small explosion plus
# a hit spark (no extra shake: pairs every 0.55 s would shake constantly).
# `damage` is set by player.gd on every launch (scene value x damage_scale,
# like the lasers). Timing is accumulated in _process(): pause-safe.
#
# PLACEHOLDER_ART: scenes/effects/player_missile.tscn draws the missile with
# Polygon2D primitives (white/cyan body, blue fins, pointing up = -y) plus an
# untextured CPUParticles2D flame/smoke trail. Replace Body/Nose/Fins with a
# Sprite2D (64x160 px art facing up, shown at ~0.2 = 13x32 px; optional
# 3-frame flame as an AnimatedSprite2D at the tail), see
# docs/ART_SWAP_TRACKER.md.
extends Area2D

const EXPLOSION_SCENE := preload("res://scenes/effects/explosion.tscn")
const HIT_SPARK_SCENE := preload("res://scenes/effects/hit_spark.tscn")
const HitSparkScript := preload("res://scripts/effects/hit_spark.gd")
const SHOOTABLE_LAYER := 32  # projectile.gd SHOOTABLE_LAYER
const SHOOTABLE_GROUP := &"shootable"

## Speed at launch and top speed (px/s), and the acceleration between them
@export var launch_speed: float = 380.0
@export var max_speed: float = 720.0
@export var acceleration: float = 700.0
## Max turn toward the target (degrees per second)
@export var turn_rate_degrees: float = 260.0
## Damage per hit (x the ship's damage_scale, applied by player.gd)
@export var damage: float = 30.0
## Damage multiplier against a boss (an obstacle with a fight_started signal:
## the Alien Mothership; the zeppelin mini-boss takes full damage). Missiles
## always hit and prefer the boss, so at full damage 8 s of missiles would
## take most of its health (casual tier-3 bot: 19 s fight -> 7 s).
@export var boss_damage_scale: float = 0.5
## Seconds before it expires in flight
@export var lifetime: float = 2.5
## Despawn once this far outside the screen
@export var offscreen_margin: float = 80.0

var direction: Vector2 = Vector2.UP
var speed: float = 0.0
var is_active: bool = false
## Target to avoid at launch when another one exists (player.gd sets it on the
## second missile of a pair when the first one's target dies to one hit)
var avoid_target: Node2D = null
var target: Node2D = null
var _target_stamp: int = -1      # target's spawn_count / launch_count at pick
var _retargeted: bool = false
var _time_left: float = 0.0
@onready var _trail: CPUParticles2D = get_node_or_null("Trail")

# Observability (tests / tuning)
static var launched_total: int = 0
static var hits_total: int = 0
static var retargets_total: int = 0

func _ready() -> void:
	collision_layer = 8
	collision_mask = 2 | SHOOTABLE_LAYER
	area_entered.connect(_on_area_entered)

func initialize(spawn_position: Vector2, launch_direction: Vector2 = Vector2.UP) -> void:
	position = spawn_position
	direction = launch_direction.normalized()
	speed = launch_speed
	is_active = true
	_time_left = lifetime
	_retargeted = false
	rotation = direction.angle() + PI / 2.0
	set_process(true)
	show()
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	launched_total += 1
	_set_target(_pick_target(avoid_target))
	avoid_target = null
	if _trail:
		_trail.restart()
		_trail.emitting = true

func _process(delta: float) -> void:
	if not is_active:
		return
	if target != null and not _target_alive():
		target = null
		if not _retargeted:
			_retargeted = true
			retargets_total += 1
			_set_target(_pick_target(null))
	var want := Vector2.UP
	if target != null:
		want = target.global_position - global_position
	direction = _turn_toward(direction, want, deg_to_rad(turn_rate_degrees) * delta)
	speed = minf(speed + acceleration * delta, max_speed)
	position += direction * speed * delta
	rotation = direction.angle() + PI / 2.0

	_time_left -= delta
	if _time_left <= 0.0:
		_despawn()
		return
	var view := get_viewport_rect().size
	if position.y < -offscreen_margin or position.y > view.y + offscreen_margin \
			or position.x < -offscreen_margin or position.x > view.x + offscreen_margin:
		_despawn()

static func _turn_toward(from: Vector2, to: Vector2, max_angle: float) -> Vector2:
	if to.length_squared() < 0.0001:
		return from
	var diff := wrapf(to.angle() - from.angle(), -PI, PI)
	return from.rotated(clampf(diff, -max_angle, max_angle)).normalized()

func _set_target(node: Node2D) -> void:
	target = node
	_target_stamp = _stamp_of(node) if node else -1

# Pooled reuse is told apart by spawn_count (obstacles) / launch_count (shots)
static func _stamp_of(node: Node) -> int:
	if "spawn_count" in node:
		return int(node.spawn_count)
	if "launch_count" in node:
		return int(node.launch_count)
	return 0

func _target_alive() -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and target.visible \
		and bool(target.get("is_active")) and _stamp_of(target) == _target_stamp

## Target for a missile at this position: a boss / mini-boss on screen first,
## else the nearest active obstacle or shootable shot above this point
## (`avoid` is skipped when anything else qualifies). Null = none.
func _pick_target(avoid: Node2D) -> Node2D:
	var from := global_position
	var view := get_viewport_rect()
	var candidates: Array[Node2D] = []
	var priority: Node2D = null
	var spawn_manager = get_tree().get_first_node_in_group("spawn_manager")
	if spawn_manager and spawn_manager.has_method("get_live_objects"):
		for object in spawn_manager.get_live_objects():
			if not (object is Obstacle) or not object.is_active or not object.visible:
				continue
			if not view.has_point(object.global_position) or object.global_position.y >= from.y:
				continue
			# Boss (has a fight / phases) or mini-boss (blimp): preferred
			if object.has_signal("fight_started") or object.get("is_miniboss") == true:
				if object.has_signal("fight_started") and object.get("_fight_started") == false:
					continue  # Still flying in: shots are absorbed
				priority = object
			candidates.append(object)
	for shot in get_tree().get_nodes_in_group(SHOOTABLE_GROUP):
		if shot is Node2D and shot.get("is_active") and shot.visible \
				and view.has_point(shot.global_position) and shot.global_position.y < from.y:
			candidates.append(shot)
	if priority != null and priority != avoid:
		return priority
	var best: Node2D = null
	var best_d := INF
	var fallback: Node2D = null
	for node in candidates:
		var d := from.distance_squared_to(node.global_position)
		if node == avoid:
			fallback = node
			continue
		if d < best_d:
			best_d = d
			best = node
	return best if best != null else (priority if priority != null else fallback)

func _on_area_entered(area: Area2D) -> void:
	if not is_active:
		return
	var hit: Node = null
	if area is Obstacle:
		hit = area
	elif area.get_parent() is Obstacle:
		hit = area.get_parent()
	elif area.is_in_group(SHOOTABLE_GROUP) and area.has_method("take_damage"):
		hit = area
	if hit == null or not hit.get("is_active"):
		return
	hits_total += 1
	var amount := damage
	if hit.has_signal("fight_started"):
		amount *= boss_damage_scale
	hit.take_damage(amount)
	if hit.get("is_active"):
		_spawn_hit_spark()
	_explode()
	_despawn()

func _explode() -> void:
	var parent = get_parent()
	if parent == null:
		return
	var explosion = ObjectPool.acquire(EXPLOSION_SCENE, parent)
	if explosion:
		explosion.global_position = global_position
		explosion.set_explosion_type(0)  # SMALL
		explosion.start()

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
	target = null
	if _trail:
		_trail.emitting = false
	ObjectPool.release(self)
