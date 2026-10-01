# blimp_obstacle.gd
# Atmosphere mini-boss: a big armoured blimp that descends slowly with a
# gentle side-to-side drift and fires aimed shots from its three gondola
# turret mounts (GunPoint1..3, left/center/right), one mount per shot in a
# ping-pong cycle. Survives ramming (the player takes contact damage, rate
# limited like the boss) and drops one energy collectible plus one health cell
# when shot down.
#
# Spawned once per atmosphere visit by a one_shot WaveGroup with
# scene_override (see data/zones/atmosphere.tres). Pause-safe: all timing is
# accumulated in _process().
#
# Art: sprites/zeppelin_1.png (1024x393, the zeppelin cut from
# art_archive/masters/zeppelin_weapon_combined.png, drawn top-down with the
# nose to the right) on a Sprite2D rotated 90 deg so the nose points down at
# the player, scale 0.18 (~69x184 px on screen), untinted. Hull: vertical
# CapsuleShape2D r 30 / height 172 at (0, 4) (the side pods poke out ~5 px).
# GunPoint1/3 sit on the forward side pods (x -+31, y 21), GunPoint2 on the
# gondola's front cockpit (0, 30).
extends Obstacle
class_name BlimpObstacle

@export_group("Blimp Tuning")
## Seconds between aimed shots (each from the next turret mount)
@export var shot_interval: float = 1.4
# The first shot comes Obstacle.first_shot_delay after spawning (0.8 s in
# blimp_obstacle.tscn), once the turret mount is on screen.
# Health: the scene's base (160) times the zone's enemy_health_multiplier
# (atmosphere 2.0 -> 320), applied by the SpawnManager like any obstacle.
## Side-to-side drift amplitude (px) and angular frequency (rad/s)
@export var drift_amplitude: float = 60.0
@export var drift_frequency: float = 0.5
## Keep the blimp's center at least this far from the screen sides
@export var side_margin: float = 80.0
## Seconds between contact hits while the player overlaps the blimp
@export var contact_hit_interval: float = 0.5
## Energy collectibles dropped when shot down
@export var collectible_drops: int = 1
## Health cells dropped when shot down (in addition to the energy)
@export var health_drops: int = 1

var _shot_timer: float = 0.0
var _gun_step: int = 0
var _contact_timer: float = 0.0

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	# Drift around a center that keeps the whole sway on screen
	var width = get_viewport_rect().size.x
	var margin = minf(drift_amplitude + side_margin, width / 2.0)
	initial_x = clampf(spawn_position.x, margin, width - margin)
	position.x = initial_x
	movement_pattern = "linear"
	move_toward_center = false
	_shot_timer = shot_interval - first_shot_delay
	_gun_step = 0
	_contact_timer = 0.0

# Flies on its own, never as part of a formation
func set_formation_data(_form_id: int, _form_offset: Vector2) -> void:
	pass

func set_use_formation_movement(_value: bool) -> void:
	use_formation_movement = false

func set_movement_pattern(_pattern: String) -> void:
	movement_pattern = "linear"

func _process(delta: float) -> void:
	if not is_active:
		return

	# (replaces Obstacle._process(), so run the hit flash / punch here)
	_update_hit_feedback(delta)

	pattern_time += delta
	position.y += base_speed * speed_multiplier * delta
	position.x = initial_x + sin(pattern_time * drift_frequency) * drift_amplitude

	_shot_timer += delta
	if _shot_timer >= shot_interval and projectile_scene and not gun_points.is_empty() \
			and _next_gun_point_on_screen():
		_shot_timer = 0.0
		_fire_from(_next_gun_point())

	_update_contact(delta)
	check_if_offscreen()

# Ping-pong over the turret mounts: L, C, R, C, L, ...
func _next_gun_point() -> Node2D:
	var n = gun_points.size()
	if n <= 1:
		return gun_points[0]
	var cycle = 2 * (n - 1)
	var step = _gun_step % cycle
	_gun_step += 1
	return gun_points[step if step < n else cycle - step]

# The mount the next shot uses is below the top edge (the blimp spawns
# above the screen and descends slowly; don't waste shots up there)
func _next_gun_point_on_screen() -> bool:
	return gun_points[get_next_gun_index()].global_position.y > 0.0

# Index (into gun_points) of the mount the next shot will use
func get_next_gun_index() -> int:
	var n = gun_points.size()
	if n <= 1:
		return 0
	var cycle = 2 * (n - 1)
	var step = _gun_step % cycle
	return step if step < n else cycle - step

# area_entered only fires once; keep hurting an overlapping player (the level
# ignores hits while the player is blinking)
func _update_contact(delta: float) -> void:
	_contact_timer = maxf(_contact_timer - delta, 0.0)
	if _contact_timer <= 0.0 and has_overlapping_areas():
		handle_player_collision()

# Ramming hurts the player but does not destroy the blimp
func handle_player_collision() -> void:
	if not is_active or _contact_timer > 0.0:
		return
	_contact_timer = contact_hit_interval
	emit_signal("object_hit")

func take_damage(amount: float) -> void:
	if not is_active:
		return
	var drop_position = position
	var spawn_manager = get_tree().get_first_node_in_group("spawn_manager")
	super.take_damage(amount)
	# Shot down this hit: drop loot (deferred: we may be inside a physics
	# callback, and this node is on its way back to the pool)
	if not is_active and spawn_manager and spawn_manager.has_method("spawn_collectible_at"):
		for i in range(collectible_drops):
			var offset = Vector2((float(i) - float(collectible_drops - 1) / 2.0) * 40.0, 0.0)
			spawn_manager.spawn_collectible_at.call_deferred(drop_position + offset)
		# Plus health cells (next to the energy, slightly lower)
		if health_drops > 0 and spawn_manager.has_method("get_pickup_scene"):
			var health_scene: PackedScene = spawn_manager.get_pickup_scene(&"health")
			# (null would fall back to an energy collectible: skip instead)
			for i in range(health_drops if health_scene else 0):
				var offset = Vector2((float(i) - float(health_drops - 1) / 2.0) * 50.0, 50.0)
				spawn_manager.spawn_collectible_at.call_deferred(drop_position + offset, health_scene)
