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
# Art: sprites/mine_1.png (512x512) on a Sprite2D at 0.103 (~52 px on
# screen, spike tips included); CircleShape2D r 16 over the body only. The
# "light" is a pulse of the sprite's modulate toward idle_light_color (slow);
# once armed it pulses fast toward armed_light_color. The hit flash material
# sits on the same sprite, so both work together.
extends Obstacle
class_name MineObstacle

@export_group("Mine Tuning")
## Player distance (px) that arms the mine
@export var trigger_radius: float = 120.0
## Seconds between arming and detonation
@export var fuse_time: float = 1.0
## Player distance (px) at detonation within which the player is hit
@export var blast_radius: float = 150.0
## Light pulse rates (half-cycles per second, i.e. on/off toggles): idle / armed
@export var idle_blink_rate: float = 1.5
@export var armed_blink_rate: float = 12.0
## Sprite modulate at the peak of an idle pulse (white = light off)
@export var idle_light_color: Color = Color(1.25, 0.8, 0.7, 1)
## Sprite modulate at the peak of an armed pulse
@export var armed_light_color: Color = Color(1.6, 0.45, 0.35, 1)

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
	_set_light(1.0)

# Mines always drift straight down
func set_movement_pattern(_pattern: String) -> void:
	movement_pattern = "linear"

func _process(delta: float) -> void:
	super._process(delta)
	if not is_active:
		return

	_blink_time += delta
	var rate = armed_blink_rate if is_armed else idle_blink_rate
	# Smooth pulse, 1 (lit) at _blink_time 0, one full cycle per two toggles
	_set_light(0.5 + 0.5 * cos(_blink_time * rate * PI))

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

# Light level 0 (off, plain sprite) .. 1 (peak of the pulse)
func _set_light(level: float) -> void:
	if sprite:
		var lit := armed_light_color if is_armed else idle_light_color
		sprite.modulate = Color.WHITE.lerp(lit, clampf(level, 0.0, 1.0))

func _get_player() -> Node2D:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	if player.has_method("is_alive") and not player.is_alive():
		return null
	if "is_dead" in player and player.is_dead:
		return null
	return player
