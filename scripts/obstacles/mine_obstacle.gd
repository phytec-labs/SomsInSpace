# mine_obstacle.gd
# Space mine. Drifts straight down with a slowly blinking light. When the
# player comes within trigger_radius it arms: the light blinks fast for
# fuse_time seconds, then the mine detonates (large explosion) and hurts the
# player if still within blast_radius. The hit goes through the object_hit
# signal -> level._on_object_hit(), so the usual blink invulnerability rules
# apply and `damage` is the amount dealt. Shooting it first defuses it
# (normal destruction, points awarded); ramming it is a normal contact hit.
#
# Pause-safe: all timing is accumulated in _process().
#
# PLACEHOLDER_ART: scenes/obstacles/mine_obstacle.tscn draws the mine with
# two Polygon2Ds under the (texture-less) Sprite2D: a dark grey octagon "Body"
# and a red "Light" whose visibility blinks. Replace with a 2-4 frame sprite
# sheet (light off/on) and drive the frame from _set_light().
extends Obstacle
class_name MineObstacle

@export_group("Mine Tuning")
## Player distance (px) that arms the mine
@export var trigger_radius: float = 120.0
## Seconds between arming and detonation
@export var fuse_time: float = 1.0
## Player distance (px) at detonation within which the player is hit
@export var blast_radius: float = 150.0
## Light blink rates (toggles per second): idle / armed
@export var idle_blink_rate: float = 1.5
@export var armed_blink_rate: float = 12.0

@onready var light: CanvasItem = get_node_or_null("Sprite2D/Light")

var is_armed: bool = false
var fuse_left: float = 0.0
var _blink_time: float = 0.0
# Observability for tests / debugging
var detonation_count: int = 0
var last_detonation_hit_player: bool = false

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	is_armed = false
	fuse_left = 0.0
	_blink_time = 0.0
	last_detonation_hit_player = false
	_set_light(true)

# Mines always drift straight down
func set_movement_pattern(_pattern: String) -> void:
	movement_pattern = "linear"

func _process(delta: float) -> void:
	super._process(delta)
	if not is_active:
		return

	_blink_time += delta
	var rate = armed_blink_rate if is_armed else idle_blink_rate
	_set_light(int(_blink_time * rate) % 2 == 0)

	if is_armed:
		fuse_left -= delta
		if fuse_left <= 0.0:
			detonate()
		return

	var player = _get_player()
	if player and global_position.distance_to(player.global_position) <= trigger_radius:
		arm()

func arm() -> void:
	if is_armed or not is_active:
		return
	is_armed = true
	fuse_left = fuse_time
	_blink_time = 0.0

func detonate() -> void:
	if not is_active:
		return
	detonation_count += 1

	var player = _get_player()
	last_detonation_hit_player = player != null \
		and global_position.distance_to(player.global_position) <= blast_radius

	_create_large_explosion()
	if last_detonation_hit_player:
		# Level applies `damage` unless the player is blinking / dead
		emit_signal("object_hit")

	deactivate()
	emit_signal("destroyed")

func _create_large_explosion() -> void:
	if sprite:
		sprite.visible = false
	_play_explosion_sound()
	if explosion_scene:
		var explosion = ObjectPool.acquire(explosion_scene, _get_effects_parent())
		explosion.global_position = global_position
		explosion.set_explosion_type(2)  # LARGE
		explosion.start()

func _set_light(on: bool) -> void:
	if light:
		light.visible = on

func _get_player() -> Node2D:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	if player.has_method("is_alive") and not player.is_alive():
		return null
	if "is_dead" in player and player.is_dead:
		return null
	return player
