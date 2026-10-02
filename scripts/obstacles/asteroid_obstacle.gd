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
# Art: one AnimatedSprite2D with sprites/asteroid.tres. Per size,
# size_animations lists the SpriteFrames animations to choose from (one
# picked at random per spawn): large = "large_1" or "large_2", two different
# rocks, each an 8-frame tumble (sprites/asteroid_large_sheet.png,
# asteroid_large_sheet_2.png) looping at large_tumble_fps from a random frame,
# forward or backward; medium = "medium", 8 different chunks
# (asteroid_chunks_sheet.png), and small = "small", 18 different shards
# (asteroid_shards_sheet.png), one random frame held. The node scale carries
# size_scales (collision follows it); the sprite scale per size
# (size_sprite_scales) compensates so the longest visible side is about
# 80 / 50 / 30 px. Split siblings get different frames. The code spin applies
# to every size. The health bar sits just under the rock at any spin angle
# (_sprite_half_extent() uses size_spin_reach_px, not the padded cell). New
# art (another rock, new pieces) = a new sheet plus its SpriteFrames
# animation, listed in size_animations; re-measure size_visible_px,
# size_sprite_scales and size_spin_reach_px for it. No script change. See
# docs/ART_SWAP_TRACKER.md.
extends Obstacle
class_name AsteroidObstacle

## 3 = large, 2 = medium, 1 = small (value used by this scene's spawns)
@export_range(1, 3) var size_level: int = 3

@export_group("Per-Size Stats (index 0 = size 1)")
@export var size_scales: PackedFloat32Array = PackedFloat32Array([0.6, 1.0, 1.6])
@export var size_health: PackedFloat32Array = PackedFloat32Array([6.0, 15.0, 30.0])
@export var size_damage: PackedFloat32Array = PackedFloat32Array([10.0, 20.0, 30.0])
@export var size_points: PackedInt32Array = PackedInt32Array([-15, -30, -60])

@export_group("Per-Size Art (index 0 = size 1)")
## SpriteFrames animations per size (in the AnimatedSprite2D's
## sprite_frames); each spawn picks one of its size's list at random
@export var size_animations: Array[PackedStringArray] = [
	PackedStringArray(["small"]),
	PackedStringArray(["medium"]),
	PackedStringArray(["large_1", "large_2"]),
]
## Mean longest visible side (alpha > 8) of the size's frames, in texture px
## (the art inside the padded sheet cells). Used for the health bar position
## and to fit size_sprite_scales; re-measure when a size's sheet changes.
@export var size_visible_px: PackedFloat32Array = PackedFloat32Array([91.7, 198.8, 198.1])
## AnimatedSprite2D scale per size, on top of the node's size_scales:
## size_visible_px times both scales gives about 30 / 50 / 80 px on screen
@export var size_sprite_scales: PackedFloat32Array = PackedFloat32Array([0.545, 0.252, 0.252])
## Spin reach per size, in texture px: the largest distance from the cell
## center (the spin center) to a visible pixel (alpha > 128), over all frames
## of the size (both large rocks for size 3). A radius, so it holds at every
## spin angle; it places the health bar (_sprite_half_extent()). Re-measure
## it with size_visible_px and size_sprite_scales when a size's sheet changes.
@export var size_spin_reach_px: PackedFloat32Array = PackedFloat32Array([58.8, 119.9, 114.8])
## Tumble speed (frames/s) of the large asteroid's animation. 0 = no
## animation: each large rock holds one random frame of its sheet.
@export var large_tumble_fps: float = 6.0

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

# `variant`: the frame of the size's animation to show (split pieces pass
# different ones); -1 = random
func set_size_level(level: int, variant: int = -1) -> void:
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
	_apply_size_art(variant)
	# Constant on-screen rim width for the new size (after the sprite scale)
	refresh_rim_width()

# Art for the current size_level: animation, frame, play state and sprite
# scale. Sets everything every time, so a pooled instance that was another
# size last time shows the right art.
func _apply_size_art(variant: int) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	var i = size_level - 1
	var choices := _size_animations(size_level)
	if choices.is_empty():
		return
	var anim := StringName(choices[randi() % choices.size()])
	var frames := animated_sprite.sprite_frames
	if not frames.has_animation(anim):
		push_warning("AsteroidObstacle: no animation '%s' for size %d" % [anim, size_level])
		return
	var count := frames.get_frame_count(anim)
	if count <= 0:
		return
	var frame := posmod(variant, count) if variant >= 0 else randi() % count
	var s := _pick(size_sprite_scales, i, absf(animated_sprite.scale.x))
	animated_sprite.scale = Vector2(s, s)
	if size_level == 3 and large_tumble_fps > 0.0 and count > 1:
		# Tumble: frames/s relative to the animation's own speed, random direction
		var anim_fps := frames.get_animation_speed(anim)
		var speed := large_tumble_fps / anim_fps if anim_fps > 0.0 else 1.0
		if randf() < 0.5:
			speed = -speed
		animated_sprite.play(anim, speed)
		animated_sprite.set_frame_and_progress(frame, 0.0)
	else:
		animated_sprite.stop()
		animated_sprite.animation = anim
		animated_sprite.frame = frame

func _size_animations(level: int) -> PackedStringArray:
	var i := level - 1
	if i >= 0 and i < size_animations.size() and not size_animations[i].is_empty():
		return size_animations[i]
	return PackedStringArray([animated_sprite.animation]) if animated_sprite else PackedStringArray()

# Number of different frames to hand out to split siblings of size `level`
# (the frame count of its first animation; sizes with one animation, the
# pieces, get all-different frames)
func get_variant_count(level: int) -> int:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return 1
	var choices := _size_animations(level)
	if choices.is_empty() or not animated_sprite.sprite_frames.has_animation(choices[0]):
		return 1
	return maxi(animated_sprite.sprite_frames.get_frame_count(choices[0]), 1)

# How far the rock reaches from its center at any spin angle, on screen (same
# units as Obstacle._sprite_half_extent(): node-local size times the resting
# node scale), so the health bar clears the spinning rock by health_bar_gap.
# The base version measures the whole sheet cell, padding included, which put
# the bar further below the rock than under other enemies.
func _sprite_half_extent() -> float:
	var i := size_level - 1
	if i < 0 or i >= size_spin_reach_px.size() or animated_sprite == null:
		return super._sprite_half_extent()
	var s := _hit_base_scale if _punch_time > 0.0 else scale
	return size_spin_reach_px[i] * absf(animated_sprite.scale.x) * absf(s.x)

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
	# A different look per piece (no identical twins side by side)
	var variants := range(get_variant_count(level))
	variants.shuffle()
	for i in range(count):
		# -1 .. +1 across the pieces (left piece flies left, right piece right)
		var side = 0.0 if count <= 1 else lerpf(-1.0, 1.0, float(i) / float(count - 1))
		var piece = spawn_manager.spawn_scene(scene, at + Vector2(side * offset, 0.0))
		if piece == null:
			continue  # At the obstacle cap
		piece.set_movement_pattern("linear")
		piece.move_toward_center = false
		piece.set_size_level(level, variants[i % variants.size()])
		piece.initial_velocity_x = side * speed_x
