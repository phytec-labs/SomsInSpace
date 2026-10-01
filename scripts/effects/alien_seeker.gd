# alien_seeker.gd
# The Alien Mothership's own missile: a glowing seeker orb that snakes toward
# the player and, if not shot down in time, bursts into a slow bullet ring.
# Pooled via the ObjectPool autoload (never queue_free()d).
#
# Built on enemy_missile.gd, so it is an enemy projectile for every rule
# (group "enemy_projectile": bomb clear() and autopilot dodges; shield absorb
# with ripple; no damage while blinking / dead; damage via
# level.update_health(); grazes) and shootable (max_health 20 = 2 laser hits,
# 1 player missile; shot down = pop + shot_down_points as a kill, NO burst).
# Differences from the zeppelin missile:
#  - it homes for its whole flight (homing_time is ignored) on a hidden "base"
#    point, and the orb is drawn weave_amplitude * sin(2 pi weave_frequency t +
#    phase) px to the side of that point, perpendicular to the heading, so the
#    path snakes; the phase is random per orb
#  - fuse_time after launch it bursts: burst_count bullets of burst_scene in a
#    ring (random rotation) at burst_speed px/s (set per spawn; the bullet
#    restores its authored speed when pooled), plus an energy flash. It blinks
#    fast during the last tell_time seconds as the tell
#  - no smoke trail; the look is the procedural Glow (ColorRect +
#    shaders/alien_seeker.gdshader), no texture (code-only art)
# Timing is accumulated in _process(), so it freezes while paused.
extends "res://scripts/effects/enemy_missile.gd"

## Side-to-side weave (px) and its frequency (Hz)
@export var weave_amplitude: float = 45.0
@export var weave_frequency: float = 1.2
## Seconds from launch to the burst (if not shot down / absorbed first)
@export var fuse_time: float = 4.5
## Last seconds of the fuse in which the orb blinks fast (the tell)
@export var tell_time: float = 1.0
## Blink toggles per second during the tell
@export var tell_blink_rate: float = 14.0
## Burst ring: bullet scene, count and speed (px/s, set per spawn), lifetime
@export var burst_scene: PackedScene = preload("res://scenes/effects/enemy_projectile_3.tscn")
@export var burst_count: int = 6
@export var burst_speed: float = 160.0
@export var burst_lifetime: float = 6.0

const TELL_BRIGHT := Color(2.2, 2.2, 2.2, 1.0)
const TELL_DIM := Color(1.0, 1.0, 1.0, 0.35)

var _base_position: Vector2 = Vector2.ZERO
var _weave_phase: float = 0.0
var _rng := RandomNumberGenerator.new()

# Observability (tests / tuning)
static var burst_total: int = 0
static var orb_shot_down_total: int = 0
static var orb_reached_player_total: int = 0

func initialize(spawn_position: Vector2, projectile_direction: Vector2 = Vector2.DOWN) -> void:
	super.initialize(spawn_position, projectile_direction)
	# Re-seeded from the global RNG so seeded runs replay
	_rng.seed = randi()
	_weave_phase = _rng.randf() * TAU
	_base_position = spawn_position
	# Start on the weave curve's base (no jump on the first frame)
	position = _base_position + _weave_offset()
	_time_left = maxf(lifetime, fuse_time + 0.1)
	rotation = 0.0

func _process(delta: float) -> void:
	if not is_active:
		return
	age += delta
	# Home the base point (whole flight), then weave around it
	var target := _homing_target()
	if target.is_finite():
		direction = turn_toward(direction, target - _base_position,
			deg_to_rad(turn_rate_degrees) * delta)
	_base_position += direction * speed * delta
	position = _base_position + _weave_offset()
	_update_tell(delta)

	if age >= fuse_time:
		_burst()
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_despawn()
		return
	var view := get_viewport_rect().size
	if position.y < -offscreen_margin or position.y > view.y + offscreen_margin \
			or position.x < -offscreen_margin or position.x > view.x + offscreen_margin:
		_despawn()

# Sideways offset from the base point (perpendicular to the heading)
func _weave_offset() -> Vector2:
	var side := Vector2(-direction.y, direction.x)
	return side * weave_amplitude * sin(TAU * weave_frequency * age + _weave_phase)

## Current sideways distance from the homing base point (tests)
func get_weave_offset() -> float:
	return (position - _base_position).length()

# Hit flash, else the fast blink in the last tell_time seconds
func _update_tell(delta: float) -> void:
	if _hit_flash_left > 0.0:
		_update_hit_flash(delta)
		return
	if age >= fuse_time - tell_time:
		var on := int((age - (fuse_time - tell_time)) * tell_blink_rate) % 2 == 0
		modulate = TELL_BRIGHT if on else TELL_DIM
	elif modulate != Color.WHITE:
		modulate = Color.WHITE

func is_in_tell() -> bool:
	return is_active and age >= fuse_time - tell_time

# Fuse out: ring of slow bullets plus a flash, then back to the pool
func _burst() -> void:
	burst_total += 1
	_pop(3)
	var scene_root = get_tree().current_scene
	var parent = scene_root if scene_root else get_parent()
	var count := maxi(burst_count, 0)
	if burst_scene and parent and count > 0:
		var start := _rng.randf() * TAU
		for i in range(count):
			var bullet = ObjectPool.acquire(burst_scene, parent)
			if bullet == null:
				continue
			bullet.speed = burst_speed
			bullet.lifetime = burst_lifetime
			bullet.initialize(global_position, Vector2.RIGHT.rotated(start + TAU * float(i) / float(count)))
	_despawn()

func _on_shot_down() -> void:
	orb_shot_down_total += 1

func _on_reached_player() -> void:
	orb_reached_player_total += 1
