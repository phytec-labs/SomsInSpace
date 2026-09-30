# hit_spark.gd
# Small one-shot burst of sparks where a player shot hits an enemy without
# killing it (projectile.gd; kills show the explosion instead). Pooled via the
# ObjectPool autoload: acquire it under the level, call burst(), and it
# releases itself back to the pool once its particles are gone.
#
# At most MAX_LIVE are alive at once (can_spawn()); extra hits in a dense
# volley simply get no sparks.
#
# Pause-safe: the release countdown is accumulated in _process().
#
# PLACEHOLDER_ART: scenes/effects/hit_spark.tscn draws untextured
# CPUParticles2D squares (white -> yellow -> transparent). A 2-3 frame spark
# sheet (~64x64 per frame, additive-friendly white/yellow star) would replace
# them: assign it as `texture` with a CanvasItemMaterial using
# particles_animation (like obstacle_explosion.tscn).
extends CPUParticles2D

const MAX_LIVE: int = 20

# Sparks currently bursting (in the tree, not yet exited)
static var live_count: int = 0

var _time_left: float = 0.0
var _counted: bool = false

static func can_spawn() -> bool:
	return live_count < MAX_LIVE

func _ready() -> void:
	one_shot = true
	emitting = false

## Burst at `at` (global position)
func burst(at: Vector2) -> void:
	global_position = at
	if not _counted:
		_counted = true
		live_count += 1
	restart()
	emitting = true
	# A little slack so the last particles finish fading
	_time_left = lifetime + 0.05
	set_process(true)

func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		set_process(false)
		emitting = false
		ObjectPool.release(self)

# Released (the pool detaches it) or freed with the level
func _exit_tree() -> void:
	if _counted:
		_counted = false
		live_count -= 1
