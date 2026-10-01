# blimp_obstacle.gd
# Atmosphere mini-boss: a big armoured blimp that descends slowly with a
# gentle side-to-side drift and fires aimed shots from its three gondola
# turret mounts (GunPoint1..3, left/center/right), one mount per shot in a
# ping-pong cycle. Survives ramming (the player takes contact damage, rate
# limited like the boss) and drops one energy collectible, one health cell
# and one missile upgrade when shot down.
#
# Missiles: besides the guns, a pair of homing missiles
# (scenes/effects/enemy_missile.tscn: shootable, 2 laser hits) leaves the two
# side pods (GunPoint1 / GunPoint3) every missile_interval, the first pair
# first_missile_delay after the pods came on screen; each pair is telegraphed
# by a missile_telegraph_time flash at the pods (PodFlashLeft / PodFlashRight).
# At most max_live_missiles of its missiles fly at once (a pair launches only
# what fits; with no room the flash waits).
#
# Spawned once per atmosphere visit as the zone's mini-boss
# (ZoneDefinition.miniboss_scene in data/zones/atmosphere.tres): the
# WaveManager brings it in 2.5 s after the zone's weapon upgrade is collected
# (or at 18 s zone time) and holds new wave groups while it is alive (at
# most 8 s, ZoneDefinition.miniboss_hold_max_seconds).
# Pause-safe: all timing is accumulated in _process().
#
# Art: sprites/zeppelin_1.png (1024x393, the zeppelin cut from
# art_archive/masters/zeppelin_weapon_combined.png, drawn top-down with the
# nose to the right) on a Sprite2D rotated 90 deg so the nose points down at
# the player, scale 0.24 (~94x246 px on screen), untinted. Hull: vertical
# CapsuleShape2D r 40 / height 229 at (0, 5) (the side pods poke out ~7 px);
# wide enough that all three tier-2 shots of a ship centered under it land
# (the wing guns sit at about +-30 px on screen). GunPoint1/3 sit on the
# forward side pods (x -+41, y 28), GunPoint2 on the gondola's front cockpit
# (0, 40).
extends Obstacle
class_name BlimpObstacle

@export_group("Blimp Tuning")
## Seconds between aimed shots (each from the next turret mount)
@export var shot_interval: float = 1.4
# The first shot comes Obstacle.first_shot_delay after spawning (0.8 s in
# blimp_obstacle.tscn), once the turret mount is on screen.
# Health: the scene's base (270) times the zone's enemy_health_multiplier
# (atmosphere 2.0 -> 540), applied by the SpawnManager like any obstacle.
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
## Missile upgrades dropped when shot down (always; in addition to the above)
@export var missile_drops: int = 1

@export_group("Blimp Missiles")
## Enemy missile scene (null = no missiles)
@export var missile_scene: PackedScene = preload("res://scenes/effects/enemy_missile.tscn")
## Seconds between missile pairs (launch to launch)
@export var missile_interval: float = 4.5
## Seconds the pods must have been on screen before the first pair
@export var first_missile_delay: float = 2.0
## Launch flash (telegraph) shown this long before each pair
@export var missile_telegraph_time: float = 0.35
## Most of this blimp's missiles alive at once
@export var max_live_missiles: int = 4
## Launch direction: this many degrees outward from straight down
@export var missile_launch_angle: float = 35.0
@export_group("")

## Read (duck-typed, via get()) by the attract-mode autopilot, which focuses
## its aim on a mini-boss while it is on screen
var is_miniboss: bool = true

var _shot_timer: float = 0.0
var _gun_step: int = 0
var _contact_timer: float = 0.0
# Missiles: seconds the pods have been on screen, when the next pair is due
# (in that clock), telegraph time left (> 0 = flashing), live missiles as
# [node, launch_count]
var _missile_clock: float = 0.0
var _next_missile_at: float = 0.0
var _missile_flash_left: float = 0.0
var _missiles: Array = []
var missiles_launched: int = 0  # Observability (tests / tuning)
@onready var _pod_left: Node2D = get_node_or_null("GunPoint1")
@onready var _pod_right: Node2D = get_node_or_null("GunPoint3")
@onready var _pod_flashes: Array = [get_node_or_null("PodFlashLeft"), get_node_or_null("PodFlashRight")]

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
	_missile_clock = 0.0
	_next_missile_at = first_missile_delay
	_missile_flash_left = 0.0
	_missiles.clear()
	_set_pod_flash(0.0)

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

	_update_missiles(delta)
	_update_contact(delta)
	check_if_offscreen()

# --- Missiles ---

func _update_missiles(delta: float) -> void:
	if missile_scene == null or _pod_left == null or _pod_right == null:
		return
	if _missile_flash_left > 0.0:
		_missile_flash_left -= delta
		if _missile_flash_left <= 0.0:
			_set_pod_flash(0.0)
			_launch_missile_pair()
		else:
			_set_pod_flash(_missile_flash_left / maxf(missile_telegraph_time, 0.001))
		return
	# The clock only runs while both pods are on screen
	if _pod_left.global_position.y <= 0.0 or _pod_right.global_position.y <= 0.0:
		return
	_missile_clock += delta
	if _missile_clock >= _next_missile_at - missile_telegraph_time:
		if get_live_missile_count() < max_live_missiles:
			_missile_flash_left = maxf(missile_telegraph_time, 0.001)
			_set_pod_flash(1.0)
		else:
			# No room: try again shortly (the flash always precedes a launch)
			_next_missile_at = _missile_clock + missile_telegraph_time + 0.25

func _launch_missile_pair() -> void:
	_next_missile_at = _missile_clock + missile_interval
	var room := max_live_missiles - get_live_missile_count()
	var angle := deg_to_rad(missile_launch_angle)
	var pods := [[_pod_left, Vector2.DOWN.rotated(angle)], [_pod_right, Vector2.DOWN.rotated(-angle)]]
	for pod in pods:
		if room <= 0:
			break
		var missile = ObjectPool.acquire(missile_scene, _get_effects_parent())
		if missile == null:
			continue
		missile.initialize(pod[0].global_position, pod[1])
		_missiles.append([missile, missile.launch_count])
		missiles_launched += 1
		room -= 1
	if shoot_audio_player and shoot_audio_player.stream:
		shoot_audio_player.pitch_scale = 0.7
		shoot_audio_player.play()

# This blimp's missiles still in flight (prunes popped / pooled ones)
func get_live_missile_count() -> int:
	for i in range(_missiles.size() - 1, -1, -1):
		var m = _missiles[i][0]
		if not is_instance_valid(m) or not m.is_active or m.launch_count != _missiles[i][1]:
			_missiles.remove_at(i)
	return _missiles.size()

## True while the launch telegraph is showing
func is_missile_telegraph_on() -> bool:
	return _missile_flash_left > 0.0

# Pod flash: 0 = hidden; else visible, pulsing brighter / larger toward the
# launch (amount runs 1 -> 0 over the telegraph)
func _set_pod_flash(amount: float) -> void:
	for flash in _pod_flashes:
		if flash == null:
			continue
		flash.visible = amount > 0.0
		if amount > 0.0:
			var t := 1.0 - amount
			var s := 0.6 + 0.8 * t
			flash.scale = Vector2(s, s)
			flash.modulate = Color(1.0, 1.0, 1.0, 0.55 + 0.45 * absf(sin(t * PI * 3.0)))

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

func deactivate() -> void:
	_missile_flash_left = 0.0
	_set_pod_flash(0.0)
	super.deactivate()

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
		# Plus the missile upgrade (above the energy, so it reaches the
		# player last and isn't hidden under the others)
		if missile_drops > 0 and spawn_manager.has_method("get_pickup_scene"):
			var missile_pickup: PackedScene = spawn_manager.get_pickup_scene(&"missile")
			for i in range(missile_drops if missile_pickup else 0):
				var offset = Vector2((float(i) - float(missile_drops - 1) / 2.0) * 50.0, -55.0)
				spawn_manager.spawn_collectible_at.call_deferred(drop_position + offset, missile_pickup)
