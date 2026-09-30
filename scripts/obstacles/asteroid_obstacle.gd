# asteroid_obstacle.gd
# Splitting asteroid. size_level 3 (large) -> 2 -> 1 (small). When shot down
# with size_level > 1 it breaks into split_count pieces of size_level - 1
# (spawned through SpawnManager.spawn_scene(), so they respect the obstacle
# cap) that fly apart horizontally. Ramming it or bombing it (bomb_kill(),
# suppress_splits) does not split it.
#
# Per-size stats live in the exported arrays below (index = size_level - 1).
# initialize() resets size_level to the scene's value and applies the size;
# set_size_level() re-applies it (used on split pieces after spawning).
#
# PLACEHOLDER_ART: scenes/obstacles/asteroid_obstacle.tscn Sprite2D uses
# sprites/meteor_1.png (scaled per size, no tint); swap the texture for the
# asteroid art (ideally one texture per size, see docs/ART_SWAP_TRACKER.md).
extends Obstacle
class_name AsteroidObstacle

## 3 = large, 2 = medium, 1 = small (value used by this scene's spawns)
@export_range(1, 3) var size_level: int = 3

@export_group("Per-Size Stats (index 0 = size 1)")
@export var size_scales: PackedFloat32Array = PackedFloat32Array([0.6, 1.0, 1.6])
@export var size_health: PackedFloat32Array = PackedFloat32Array([6.0, 15.0, 30.0])
@export var size_damage: PackedFloat32Array = PackedFloat32Array([10.0, 20.0, 30.0])
@export var size_points: PackedInt32Array = PackedInt32Array([-15, -30, -60])

@export_group("Splitting")
@export var split_count: int = 2
## Pieces spawn this far (px) left/right of the parent
@export var split_offset: float = 30.0
## Horizontal speed (px/s) the pieces fly apart with
@export var split_speed_x: float = 90.0
## Spin (deg/s) range, re-rolled per spawn; smaller pieces spin faster
@export var min_spin: float = 20.0
@export var max_spin: float = 60.0

## Extra horizontal velocity (px/s) applied on top of the movement pattern
## while not in a formation (set on split pieces, 0 otherwise)
var initial_velocity_x: float = 0.0

var _scene_size_level: int = 3
var _base_scale: Vector2 = Vector2.ONE
var _scene: PackedScene

func _ready() -> void:
	super._ready()
	_scene_size_level = size_level
	_base_scale = scale
	if not scene_file_path.is_empty():
		_scene = load(scene_file_path)

func initialize(spawn_position: Vector2) -> void:
	super.initialize(spawn_position)
	initial_velocity_x = 0.0
	# Pooled instances may have been a split piece last time
	set_size_level(_scene_size_level)

func set_size_level(level: int) -> void:
	size_level = clampi(level, 1, 3)
	var i = size_level - 1
	scale = _base_scale * _pick(size_scales, i, 1.0)
	# Per-size base health, times the zone multiplier of this spawn
	base_health = _pick(size_health, i, base_health)
	max_health = base_health * health_scale
	health = max_health
	damage = _pick(size_damage, i, damage)
	points = int(_pick(size_points, i, points))
	rotation_speed = randf_range(min_spin, max_spin) / _pick(size_scales, i, 1.0)
	rotation_speed *= -1.0 if randf() < 0.5 else 1.0

func _pick(values, index: int, fallback: float) -> float:
	return float(values[index]) if index < values.size() else fallback

func _process(delta: float) -> void:
	super._process(delta)
	if is_active and initial_velocity_x != 0.0 and not use_formation_movement:
		position.x += initial_velocity_x * delta

func take_damage(amount: float) -> void:
	if not is_active:
		return
	var level_before = size_level
	var split_position = position
	var spawn_manager = get_tree().get_first_node_in_group("spawn_manager")
	super.take_damage(amount)
	if not is_active and level_before > 1 and spawn_manager and _scene and not suppress_splits:
		# Deferred: we are usually inside a physics callback (projectile hit),
		# and this node is being returned to the pool (it may even be reused
		# as one of the pieces, so everything is passed by value)
		_spawn_pieces.call_deferred(spawn_manager, _scene, split_position, level_before - 1,
			split_count, split_offset, split_speed_x)

func _spawn_pieces(spawn_manager: Node, scene: PackedScene, at: Vector2, level: int,
		count: int, offset: float, speed_x: float) -> void:
	if not is_instance_valid(spawn_manager) or not spawn_manager.is_inside_tree():
		return
	for i in range(count):
		# -1 .. +1 across the pieces (left piece flies left, right piece right)
		var side = 0.0 if count <= 1 else lerpf(-1.0, 1.0, float(i) / float(count - 1))
		var piece = spawn_manager.spawn_scene(scene, at + Vector2(side * offset, 0.0))
		if piece == null:
			continue  # At the obstacle cap
		piece.set_movement_pattern("linear")
		piece.move_toward_center = false
		piece.set_size_level(level)
		piece.initial_velocity_x = side * speed_x
